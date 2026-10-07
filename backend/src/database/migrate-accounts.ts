import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { type Pool, type PoolClient } from 'pg';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { applyAccountsMigration } from './accounts-migration';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let failed = false;
  try {
    const sql = await readFile(resolve(__dirname, '../../database/migrations/001_accounts.sql'), 'utf8');
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    const result = await applyAccountsMigration(client, sql);
    console.info(result === 'applied' ? 'Migración de cuentas aplicada.' : 'La migración de cuentas ya estaba aplicada.');
  } catch {
    failed = true;
    process.exitCode = 1;
    console.error('No se pudo aplicar la migración. Revisa PostgreSQL, permisos y el archivo de migración; no borres tablas para reintentar.');
  } finally {
    client?.release(failed);
    if (pool) {
      try { await pool.end(); }
      catch { process.exitCode = 1; console.error('No se pudo cerrar la conexión PostgreSQL.'); }
    }
  }
}
void main();
