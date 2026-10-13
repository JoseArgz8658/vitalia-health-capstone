import { randomUUID } from 'node:crypto';
import { type Pool, type PoolClient } from 'pg';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { insertPatientAccount } from '../accounts/repository';
import { hashPassword } from '../auth/password';
import { createCredentialAuthenticator } from '../auth/credentials';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let started = false;
  let failed = false;
  try {
    const email = 'credenciales-' + randomUUID() + '@example.invalid';
    const password = randomUUID();
    const hash = await hashPassword(password);
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    const authenticate = await createCredentialAuthenticator(client);
    await client.query('BEGIN');
    started = true;
    const saved = await insertPatientAccount(client, email, hash);
    const valid = await authenticate({ email, password });
    const wrong = await authenticate({ email, password: password + '-incorrecta' });
    const missing = await authenticate({ email: 'ausente-' + randomUUID() + '@example.invalid', password });
    if (!valid || valid.id !== saved.id || valid.role !== 'paciente'
      || 'passwordHash' in valid || wrong !== null || missing !== null) {
      throw new Error('Comprobación de credenciales inválida.');
    }
    await client.query('ROLLBACK');
    started = false;
    if (await authenticate({ email, password })) throw new Error('La cuenta de prueba no fue revertida.');
    console.info('Comprobación de credenciales correcta. La cuenta sintética fue revertida.');
  } catch {
    failed = true;
    process.exitCode = 1;
    console.error('No se pudo verificar credenciales. Revisa PostgreSQL y la migración de cuentas.');
  } finally {
    if (client && started) {
      try { await client.query('ROLLBACK'); }
      catch { failed = true; process.exitCode = 1; }
    }
    client?.release(failed);
    if (pool) {
      try { await pool.end(); }
      catch { process.exitCode = 1; console.error('No se pudo cerrar la conexión PostgreSQL.'); }
    }
  }
}
void main();
