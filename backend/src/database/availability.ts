import { type Pool } from 'pg';

// Comprueba una consulta real sin crear tablas ni leer datos personales.
export async function checkDatabaseAvailability(pool: Pick<Pool, 'query'>): Promise<void> {
  const result = await pool.query<{ connection_ok: number }>('SELECT 1 AS connection_ok');
  if (result.rows.length !== 1 || result.rows[0].connection_ok !== 1) {
    throw new Error('PostgreSQL devolvió una comprobación inesperada.');
  }
}
