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
    const sql = await readFile(resolve(__dirname, '../../database/migrations/004_document_audit.sql'), 'utf8');
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    const result = await applyAdditionalMigration(client, '004_document_audit', sql, '003_documents');
    console.info(result === 'applied' ? 'Migración de auditoría de documentos aplicada.'
      : 'La migración de auditoría de documentos ya estaba aplicada.');
  } catch {
    failed = true; process.exitCode = 1;
    console.error('No se pudo migrar auditoría. Revisa PostgreSQL y la migración previa de documentos.');
  } finally {
    client?.release(failed);
    if (pool) { try { await pool.end(); } catch { process.exitCode = 1; } }
  }
}
void main();
