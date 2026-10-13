import { randomUUID, createHash } from 'node:crypto';
import { once } from 'node:events';
import { type Server } from 'node:http';
import { type Pool, type PoolClient } from 'pg';
import { createApp } from '../app';
import { hashPassword } from '../auth/password';
import { createCredentialAuthenticator } from '../auth/credentials';
import { issueSession, findSessionAccount, revokeSession } from '../auth/sessions';
import { insertPatientAccount } from '../accounts/repository';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let server: Server | undefined;
  let started = false;
  let failed = false;
  try {
    const email = 'sesiones-' + randomUUID() + '@example.invalid';
    const password = randomUUID();
    const passwordHash = await hashPassword(password);
    pool = createDatabasePool(readDatabaseConfig(process.env));
    const database = await pool.connect();
    client = database;
    const authenticate = await createCredentialAuthenticator(database);
    await database.query('BEGIN');
    started = true;
    const saved = await insertPatientAccount(database, email, passwordHash);
    server = createApp({
      authenticate,
      issue: id => issueSession(database, id),
      find: token => findSessionAccount(database, token),
      revoke: token => revokeSession(database, token),
    }).listen(0, '127.0.0.1');
    await once(server, 'listening');
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('Servidor de prueba inválido.');
    const base = 'http://127.0.0.1:' + address.port + '/api/auth';
    const login = (value: string) => fetch(base + '/login', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: value }),
    });
    if ((await fetch(base + '/me')).status !== 401) throw new Error('Acceso sin sesión.');
    if ((await login(password + '-incorrecta')).status !== 401) throw new Error('Credenciales incorrectas aceptadas.');
    const response = await login(password);
    if (response.status !== 200) throw new Error('Inicio de sesión fallido.');
    const grant = await response.json();
    if (grant.user.id !== saved.id || grant.user.role !== 'paciente'
      || 'passwordHash' in grant.user || !/^[a-f0-9]{64}$/.test(grant.token)) throw new Error('Respuesta inválida.');
    const headers = { Authorization: 'Bearer ' + grant.token };
    if ((await fetch(base + '/me', { headers })).status !== 200) throw new Error('Sesión no reconocida.');
    const stored = await database.query<{ token_hash: string }>(
      'SELECT token_hash FROM public.vitalia_sessions WHERE account_id = $1', [saved.id],
    );
    if (stored.rows.length !== 1 || stored.rows[0].token_hash !== createHash('sha256').update(grant.token).digest('hex')) {
      throw new Error('Persistencia de token inválida.');
    }
    if ((await fetch(base + '/logout', { method: 'POST', headers })).status !== 204) throw new Error('Cierre fallido.');
    if ((await fetch(base + '/me', { headers })).status !== 401) throw new Error('Sesión revocada aceptada.');
    const renewedResponse = await login(password);
    if (renewedResponse.status !== 200) throw new Error('Segundo acceso fallido.');
    const renewed = await renewedResponse.json();
    if (renewed.token === grant.token) throw new Error('Token reutilizado.');
    await database.query(
      `UPDATE public.vitalia_sessions
       SET created_at = CURRENT_TIMESTAMP - INTERVAL '2 hours',
           expires_at = CURRENT_TIMESTAMP - INTERVAL '1 hour'
       WHERE account_id = $1`, [saved.id],
    );
    if ((await fetch(base + '/me', { headers: { Authorization: 'Bearer ' + renewed.token } })).status !== 401) {
      throw new Error('Sesión expirada aceptada.');
    }
    await database.query('ROLLBACK');
    started = false;
    const remaining = await database.query('SELECT id FROM public.vitalia_accounts WHERE id = $1', [saved.id]);
    const sessions = await database.query('SELECT token_hash FROM public.vitalia_sessions WHERE account_id = $1', [saved.id]);
    if (remaining.rows.length || sessions.rows.length) throw new Error('Prueba no revertida.');
    console.info('API de acceso correcta: login, sesión, expiración y logout. Datos sintéticos revertidos.');
  } catch {
    failed = true;
    process.exitCode = 1;
    console.error('No se pudo verificar la API de acceso. Revisa PostgreSQL y ambas migraciones; no compartas credenciales ni tokens.');
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
