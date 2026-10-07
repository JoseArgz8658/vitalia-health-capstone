import { createHash } from 'node:crypto';
import { type PoolClient } from 'pg';

const VERSION = '001_accounts';

// Una transacción protege la migración y su registro; no altera migraciones ya aplicadas.
export async function applyAccountsMigration(
  client: Pick<PoolClient, 'query'>, sql: string,
): Promise<'applied' | 'unchanged'> {
  // El mismo archivo mantiene su huella en Windows (CRLF) y Linux (LF).
  const checksum = createHash('sha256').update(sql.replace(/\r\n/g, '\n')).digest('hex');
  let started = false;
  try {
    await client.query('BEGIN');
    started = true;
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', ['vitalia-health-migrations']);
    await client.query(`CREATE TABLE IF NOT EXISTS public.vitalia_schema_migrations (
      version text PRIMARY KEY, checksum text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`);
    const previous = await client.query<{ checksum: string }>(
      'SELECT checksum FROM public.vitalia_schema_migrations WHERE version = $1', [VERSION],
    );
    if (previous.rows.length > 0) {
      if (previous.rows[0].checksum !== checksum) {
        throw new Error('La migración aplicada no coincide con el archivo actual.');
      }
      await client.query('COMMIT');
      return 'unchanged';
    }
    await client.query(sql);
    await client.query(
      'INSERT INTO public.vitalia_schema_migrations (version, checksum) VALUES ($1, $2)',
      [VERSION, checksum],
    );
    await client.query('COMMIT');
    return 'applied';
  } catch (error) {
    if (started) {
      try { await client.query('ROLLBACK'); } catch { /* El CLI descarta la conexión fallida. */ }
    }
    throw error;
  }
}
