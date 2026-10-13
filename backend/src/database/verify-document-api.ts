import { randomUUID } from 'node:crypto';
import { type Server } from 'node:http';
import { type Pool, type PoolClient } from 'pg';
import { type S3Client } from '@aws-sdk/client-s3';
import { createApp } from '../app';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { readStorageConfig } from '../storage/config';
import { createStorageClient, checkPrivateBucket } from '../storage/s3';
import { createDocumentService, type DocumentDatabase } from '../documents/service';
import { s3DocumentStorage } from '../documents/storage-adapter';
import { hashPassword } from '../auth/password';
import { insertPatientAccount } from '../accounts/repository';
import { issueSession, findSessionAccount, revokeSession } from '../auth/sessions';

function syntheticPdf(): Buffer {
  const stream = 'BT /F1 12 Tf 40 100 Td (Vitalia synthetic test) Tj ET';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ' + Buffer.byteLength(stream) + ' >>\nstream\n' + stream + '\nendstream',
  ];
  let content = '%PDF-1.4\n';
  const offsets = [0];
  objects.forEach((object, index) => {
    offsets.push(Buffer.byteLength(content));
    content += (index + 1) + ' 0 obj\n' + object + '\nendobj\n';
  });
  const xref = Buffer.byteLength(content);
  content += 'xref\n0 6\n0000000000 65535 f \n';
  content += offsets.slice(1).map(offset => String(offset).padStart(10, '0') + ' 00000 n \n').join('');
  content += 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF\n';
  return Buffer.from(content);
}
async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let storageClient: S3Client | undefined;
  let server: Server | undefined;
  let started = false;
  let failed = false;
  const keys = new Set<string>();
  let remove: ((key: string) => Promise<void>) | undefined;
  try {
    const config = readStorageConfig(process.env);
    storageClient = createStorageClient(config);
    await checkPrivateBucket(storageClient, config);
    const storage = s3DocumentStorage(storageClient, config);
    remove = storage.remove;
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    const dbClient = client;
    await client.query('BEGIN'); started = true;
    const db: DocumentDatabase = {
      query: client.query.bind(client) as Pool['query'],
      async transaction<T>(work: (db: Pick<Pool, 'query'>) => Promise<T>) {
        await dbClient.query('SAVEPOINT document_api_test');
        try {
          const result = await work(dbClient);
          await dbClient.query('RELEASE SAVEPOINT document_api_test');
          return result;
        } catch (error) {
          await dbClient.query('ROLLBACK TO SAVEPOINT document_api_test');
          throw error;
        }
      },
    };
    const documents = createDocumentService(db, {
      ...storage,
      async put(key, body, contentType) {
        keys.add(key);
        await storage.put(key, body, contentType);
      },
    });
    const hash = await hashPassword(randomUUID());
    const a = await insertPatientAccount(client, randomUUID() + '@example.invalid', hash);
    const b = await insertPatientAccount(client, randomUUID() + '@example.invalid', hash);
    const tokenA = (await issueSession(client, a.id)).token;
    const tokenB = (await issueSession(client, b.id)).token;
    server = createApp({
      authenticate: async () => null,
      issue: id => issueSession(dbClient, id),
      find: token => findSessionAccount(dbClient, token),
      revoke: token => revokeSession(dbClient, token),
    }, undefined, documents).listen(0, '127.0.0.1');
    const activeServer = server;
    await new Promise<void>((resolve, reject) => {
      activeServer.once('listening', resolve); activeServer.once('error', reject);
    });
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('Dirección inválida.');
    const base = 'http://127.0.0.1:' + address.port + '/api/documents';
    const authorized = (token: string) => ({ Authorization: 'Bearer ' + token });
    if ((await fetch(base)).status !== 401) throw new Error('Acceso sin sesión.');
    const pdf = syntheticPdf();
    const form = new FormData();
    form.append('examName', 'Examen sintético');
    form.append('examType', 'Laboratorio');
    form.append('examDate', '2026-01-01');
    form.append('file', new Blob([new Uint8Array(pdf)], { type: 'application/pdf' }), 'sintetico.pdf');
    const uploaded = await fetch(base, { method: 'POST', headers: authorized(tokenA), body: form });
    if (uploaded.status !== 201) throw new Error('Carga fallida.');
    const result = await uploaded.json() as { document: { id: string } };
    const id = result.document.id;
    const listA = await fetch(base, { headers: authorized(tokenA) });
    const listB = await fetch(base, { headers: authorized(tokenB) });
    const itemsA = await listA.json() as { documents: Array<{ id: string }> };
    const itemsB = await listB.json() as { documents: unknown[] };
    if (itemsA.documents.length !== 1 || itemsA.documents[0].id !== id ||
        itemsB.documents.length !== 0) throw new Error('Aislamiento de listado inválido.');
    const denied = await fetch(base + '/' + id + '/file', { headers: authorized(tokenB) });
    if (denied.status !== 404) throw new Error('Descarga ajena permitida.');
    const download = await fetch(base + '/' + id + '/file', { headers: authorized(tokenA) });
    if (download.status !== 200 || !Buffer.from(await download.arrayBuffer()).equals(pdf)) {
      throw new Error('Descarga inválida.');
    }
    const events = await client.query<{ action: string }>(
      'SELECT action FROM public.vitalia_document_audit WHERE account_id = $1 ORDER BY id', [a.id]);
    if (events.rows.map(row => row.action).join(',') !== 'upload,list,download') throw new Error('Auditoría inválida.');
  } catch {
    failed = true; process.exitCode = 1;
    console.error('No se pudo verificar la API de documentos. Revisa PostgreSQL, S3 y migración de auditoría.');
  } finally {
    if (server) {
      server.closeAllConnections();
      await new Promise<void>(resolve => server!.close(() => resolve()));
    }
    if (started && client) {
      try { await client.query('ROLLBACK'); }
      catch { failed = true; process.exitCode = 1; console.error('No se confirmó reversión PostgreSQL.'); }
    }
    // Solo claves aleatorias creadas por esta ejecución; nunca borra documentos existentes.
    if (remove) {
      for (const key of keys) {
        try { await remove(key); }
        catch {
          failed = true; process.exitCode = 1;
          console.error('No se confirmó limpieza del objeto sintético en S3. Clave:', key);
        }
      }
    }
    client?.release(failed);
    if (pool) { try { await pool.end(); } catch { failed = true; process.exitCode = 1; } }
    storageClient?.destroy();
  }
  if (!failed) console.info('API de documentos correcta: carga, listado, descarga y aislamiento. Datos sintéticos revertidos y objeto S3 eliminado.');
}
void main();
