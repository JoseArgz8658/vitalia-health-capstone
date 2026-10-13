import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { type Server } from 'node:http';
import { type Pool, type PoolClient } from 'pg';
import { createApp } from '../app';
import { createPatientRegistrar } from '../auth/registration';
import { createCredentialAuthenticator } from '../auth/credentials';
import { issueSession, findSessionAccount, revokeSession } from '../auth/sessions';
import { findAccountCredentialsByEmail } from '../accounts/repository';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let server: Server | undefined;
  let started = false;
  let failed = false;
  try {
    const email = 'registro-' + randomUUID() + '@example.invalid';
    const password = randomUUID();
    const otherPassword = randomUUID();
    pool = createDatabasePool(readDatabaseConfig(process.env));
    const database = await pool.connect();
    client = database;
    const authenticate = await createCredentialAuthenticator(database);
    const register = createPatientRegistrar(database);
    await database.query('BEGIN');
    started = true;
    server = createApp({
      authenticate,
      issue: id => issueSession(database, id),
      find: token => findSessionAccount(database, token),
      revoke: token => revokeSession(database, token),
    }, register).listen(0, '127.0.0.1');
    await once(server, 'listening');
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('Servidor de prueba inválido.');
    const base = 'http://127.0.0.1:' + address.port + '/api/auth';
    const post = (path: string, body: unknown) => fetch(base + path, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    if ((await post('/register', { email, password: 'corta' })).status !== 400
      || (await post('/register', { email, password, role: 'administrador' })).status !== 400
      || await findAccountCredentialsByEmail(database, email)) {
      throw new Error('Registro inválido aceptado.');
    }
    const response = await post('/register', { email: ' ' + email.toUpperCase() + ' ', password });
    if (response.status !== 202) throw new Error('Registro fallido.');
    const firstBody = await response.json();
    if ('token' in firstBody || 'user' in firstBody) throw new Error('Registro expuso identidad o sesión.');
    const account = await findAccountCredentialsByEmail(database, email);
    if (!account || account.role !== 'paciente') throw new Error('Cuenta no creada como paciente.');

    // Un duplicado provoca un error SQL; el savepoint permite conservar la transacción de prueba.
    await database.query('SAVEPOINT duplicate_registration');
    const duplicate = await post('/register', { email, password: otherPassword });
    const duplicateBody = await duplicate.json();
    await database.query('ROLLBACK TO SAVEPOINT duplicate_registration');
    await database.query('RELEASE SAVEPOINT duplicate_registration');
    if (duplicate.status !== 202 || JSON.stringify(duplicateBody) !== JSON.stringify(firstBody)) {
      throw new Error('Respuesta de duplicado distinta.');
    }
    const unchanged = await findAccountCredentialsByEmail(database, email);
    if (!unchanged || unchanged.id !== account.id || unchanged.passwordHash !== account.passwordHash) {
      throw new Error('Una cuenta existente fue cambiada.');
    }
    if ((await post('/login', { email, password: otherPassword })).status !== 401) {
      throw new Error('Contraseña de duplicado aceptada.');
    }
    const login = await post('/login', { email, password });
    if (login.status !== 200) throw new Error('No se pudo acceder con la cuenta registrada.');
    const session = await login.json();
    if (session.user.role !== 'paciente' || session.user.id !== account.id) throw new Error('Identidad incorrecta.');
    const headers = { Authorization: 'Bearer ' + session.token };
    if ((await fetch(base + '/me', { headers })).status !== 200
      || (await fetch(base + '/logout', { method: 'POST', headers })).status !== 204) {
      throw new Error('Sesión de registro inválida.');
    }
    await database.query('ROLLBACK');
    started = false;
    if (await findAccountCredentialsByEmail(database, email)) throw new Error('Cuenta de prueba no revertida.');
    const sessions = await database.query('SELECT token_hash FROM public.vitalia_sessions WHERE account_id = $1', [account.id]);
    if (sessions.rows.length) throw new Error('Sesiones de prueba no revertidas.');
    console.info('Registro de pacientes correcto: validación, duplicados y acceso. Datos sintéticos revertidos.');
  } catch {
    failed = true;
    process.exitCode = 1;
    console.error('No se pudo verificar el registro. Revisa PostgreSQL y las migraciones; no compartas contraseñas ni tokens.');
  } finally {
    if (server?.listening) {
      const current = server;
      current.closeAllConnections();
      await new Promise<void>(resolve => current.close(() => resolve()));
    }
    if (client && started) {
      try { await client.query('ROLLBACK'); }
      catch { failed = true; process.exitCode = 1; }
    }
    client?.release(failed);
    if (pool) {
      try { await pool.end(); }
      catch { process.exitCode = 1; console.error('No se pudo cerrar PostgreSQL.'); }
    }
  }
}
void main();
