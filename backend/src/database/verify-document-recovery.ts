import { randomUUID } from 'node:crypto';
import { type Pool, type PoolClient } from 'pg';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { hashPassword } from '../auth/password';
import { insertPatientAccount } from '../accounts/repository';
import { reserveDocument, completeDocument } from '../documents/repository';
import { applyRecovery } from '../documents/recovery';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let started = false;
  let failed = false;
  try {
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    await client.query('BEGIN'); started = true;
    const account = await insertPatientAccount(client, randomUUID() + '@example.invalid',
      await hashPassword(randomUUID()));
    const input = { examName: 'Examen sintético', examType: 'Laboratorio', examDate: '2026-01-01',
      originalName: 'sintetico.pdf', contentType: 'application/pdf', sizeBytes: 100 };
    const old = await reserveDocument(client, account, input);
    const recent = await reserveDocument(client, account, input);
    const stored = await reserveDocument(client, account, input);
    await completeDocument(client, account, stored.id);
    await client.query(`UPDATE public.vitalia_documents
      SET created_at = CURRENT_TIMESTAMP - INTERVAL '2 hours' WHERE id = ANY($1::uuid[])`,
      [[old.id, stored.id]]);
    const removed: string[] = [];
    // Solo estos IDs sintéticos. El borrado de S3 se simula; no accede a AWS.
    const ids = [old.id, recent.id, stored.id];
    const result = await applyRecovery(client, async key => { removed.push(key); }, ids);
    if (result.cleaned !== 1 || result.failed !== 0 ||
      removed.join(',') !== old.storageKey) throw new Error('Recuperación inválida.');
    const states = await client.query<{ id: string; status: string }>(
      'SELECT id, status FROM public.vitalia_documents WHERE id = ANY($1::uuid[])', [ids]);
    const status = new Map(states.rows.map(row => [row.id, row.status]));
    if (status.get(old.id) !== 'failed' || status.get(recent.id) !== 'pending' ||
        status.get(stored.id) !== 'stored') throw new Error('Estados inválidos.');
    const repeated = await applyRecovery(client, async () => { throw new Error('No debe repetir.'); }, ids);
    if (repeated.candidates !== 0) throw new Error('Limpieza repetida.');
    await client.query('ROLLBACK'); started = false;
    const leftovers = await client.query('SELECT id FROM public.vitalia_documents WHERE id = ANY($1::uuid[])', [ids]);
    if (leftovers.rows.length) throw new Error('Reversión inválida.');
    console.info('Recuperación de documentos correcta. Borrado S3 simulado y datos sintéticos revertidos.');
  } catch {
    failed = true; process.exitCode = 1;
    console.error('No se pudo verificar recuperación. Revisa PostgreSQL y la migración de recuperación.');
  } finally {
    if (started && client) {
      try { await client.query('ROLLBACK'); } catch { failed = true; process.exitCode = 1; }
    }
    client?.release(failed);
    if (pool) { try { await pool.end(); } catch { process.exitCode = 1; } }
  }
}
void main();
