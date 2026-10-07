import { type Pool } from 'pg';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { checkDatabaseAvailability } from './availability';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  try {
    pool = createDatabasePool(readDatabaseConfig(process.env));
    await checkDatabaseAvailability(pool);
    console.info('Conexión con PostgreSQL correcta.');
  } catch {
    console.error('No se pudo comprobar PostgreSQL. Revisa el servicio y las variables PG en .env.');
    process.exitCode = 1;
  } finally {
    if (pool) {
      try { await pool.end(); }
      catch {
        console.error('No se pudo cerrar la conexión con PostgreSQL.');
        process.exitCode = 1;
      }
    }
  }
}
void main();
