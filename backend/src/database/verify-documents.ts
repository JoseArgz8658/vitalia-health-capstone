import { randomUUID } from 'node:crypto';
import { type Pool, type PoolClient } from 'pg';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { hashPassword } from '../auth/password';
import { insertPatientAccount } from '../accounts/repository';
import { reserveDocument, completeDocument, listPatientDocuments, findPatientDocument } from '../documents/repository';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let started = false;
  let failed = false;
  try {
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    await client.query('BEGIN'); started = true;
    const hash = await hashPassword(randomUUID());
    const a = await insertPatientAccount(client, randomUUID() + '@example.invalid', hash);
    const b = await insertPatientAccount(client, randomUUID() + '@example.invalid', hash);
    const reserved = await reserveDocument(client, a, {
      examName: 'Examen sintético', examType: 'Laboratorio', examDate: '2026-01-01',
      originalName: 'sintetico.pdf', contentType: 'application/pdf', sizeBytes: 100,
    });
    if ((await listPatientDocuments(client, a)).length !== 0) throw new Error('Reserva visible.');
    if (await completeDocument(client, b, reserved.id)) throw new Error('Confirmación ajena.');
    // Prueba exclusiva de metadatos: no afirma haber subido un objeto real a S3.
    if (!await completeDocument(client, a, reserved.id)) throw new Error('Confirmación fallida.');
    if ((await listPatientDocuments(client, a)).length !== 1 ||
        (await listPatientDocuments(client, b)).length !== 0 ||
        await findPatientDocument(client, b, reserved.id) ||
        !(await findPatientDocument(client, a, reserved.id))) throw new Error('Aislamiento inválido.');
    await client.query('ROLLBACK'); started = false;
    const check = await client.query('SELECT id FROM public.vitalia_documents WHERE id = $1', [reserved.id]);
    if (check.rows.length) throw new Error('Reversión fallida.');
    console.info('Metadatos y aislamiento de documentos correctos. Datos sintéticos revertidos.');
  } catch {
    failed = true; process.exitCode = 1;
    console.error('No se pudieron verificar documentos. Revisa PostgreSQL y la migración de documentos.');
  } finally {
    if (started && client) {
      try { await client.query('ROLLBACK'); } catch { failed = true; process.exitCode = 1; }
    }
    client?.release(failed);
    if (pool) { try { await pool.end(); } catch { process.exitCode = 1; } }
  }
}
void main();
