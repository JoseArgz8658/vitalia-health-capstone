import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { type Pool, type PoolClient } from 'pg';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { applyAdditionalMigration } from './additional-migration';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let failed = false;
  try {
    const sql = await readFile(resolve(__dirname, '../../database/migrations/005_document_cleanup.sql'), 'utf8');
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    const result = await applyAdditionalMigration(client, '005_document_cleanup', sql, '004_document_audit');
    console.info(result === 'applied' ? 'Migración de recuperación de documentos aplicada.'
      : 'La migración de recuperación de documentos ya estaba aplicada.');
  } catch {
    failed = true; process.exitCode = 1;
    console.error('No se pudo migrar recuperación. Revisa PostgreSQL y la migración de auditoría.');
  } finally {
    client?.release(failed);
    if (pool) { try { await pool.end(); } catch { process.exitCode = 1; } }
  }
}
void main();
