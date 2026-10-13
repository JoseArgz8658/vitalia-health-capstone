import { randomUUID } from 'node:crypto';
import { type Pool, type PoolClient } from 'pg';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { hashPassword, verifyPassword } from '../auth/password';
import { insertPatientAccount, findAccountCredentialsByEmail } from '../accounts/repository';

// Prueba real con datos sintéticos que se revierte sin dejar una cuenta permanente.
async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let started = false;
  let failed = false;
  try {
    const email = 'prueba-' + randomUUID() + '@example.invalid';
    const password = randomUUID();
    const hash = await hashPassword(password);
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    await client.query('BEGIN');
    started = true;
    const account = await insertPatientAccount(client, email, hash);
    const credentials = await findAccountCredentialsByEmail(client, email);
    if (account.role !== 'paciente' || 'passwordHash' in account
      || !credentials || credentials.id !== account.id
      || !(await verifyPassword(password, credentials.passwordHash))
      || await verifyPassword(password + '-incorrecta', credentials.passwordHash)) {
      throw new Error('Verificación de persistencia inválida.');
    }
    await client.query('ROLLBACK');
    started = false;
    if (await findAccountCredentialsByEmail(client, email)) throw new Error('La prueba no fue revertida.');
    console.info('Persistencia de cuentas correcta. La cuenta sintética fue revertida.');
  } catch {
    failed = true;
    process.exitCode = 1;
    console.error('No se pudo verificar la persistencia. Revisa conexión y migración; no compartas credenciales.');
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
