import { createHash } from 'node:crypto';
import { type PoolClient } from 'pg';

// Permite migraciones nuevas sin reescribir la migración de cuentas ya aplicada.
export async function applyAdditionalMigration(
  client: Pick<PoolClient, 'query'>, version: string, sql: string, prerequisite: string,
): Promise<'applied' | 'unchanged'> {
  const checksum = createHash('sha256').update(sql.replace(/\r\n/g, '\n')).digest('hex');
  let started = false;
  try {
    await client.query('BEGIN');
    started = true;
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', ['vitalia-health-migrations']);
    const base = await client.query(
      'SELECT version FROM public.vitalia_schema_migrations WHERE version = $1', [prerequisite],
    );
    if (base.rows.length !== 1) throw new Error('Falta la migración previa.');
    const previous = await client.query<{ checksum: string }>(
      'SELECT checksum FROM public.vitalia_schema_migrations WHERE version = $1', [version],
    );
    if (previous.rows.length) {
      if (previous.rows[0].checksum !== checksum) throw new Error('Migración aplicada con otra huella.');
      await client.query('COMMIT');
      return 'unchanged';
    }
    await client.query(sql);
    await client.query(
      'INSERT INTO public.vitalia_schema_migrations (version, checksum) VALUES ($1, $2)',
      [version, checksum],
    );
    await client.query('COMMIT');
    return 'applied';
  } catch (error) {
    if (started) { try { await client.query('ROLLBACK'); } catch { /* Descartar cliente fallido. */ } }
    throw error;
  }
}
