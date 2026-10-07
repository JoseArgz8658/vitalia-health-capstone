const { spawnSync } = require('node:child_process');
const { readDatabaseConfig } = require('../dist/database/config');
const { createDatabasePool } = require('../dist/database/pool');
const { checkDatabaseAvailability } = require('../dist/database/availability');
const valid = { PGDATABASE: 'vitalia_test', PGUSER: 'usuario_test', PGPASSWORD: 'solo-sintético' };

test('configuración local omite variables ajenas y aplica valores por defecto', () => {
  expect(readDatabaseConfig({ ...valid, TOKEN: 'no-usar' })).toEqual({
    host: '127.0.0.1', port: 5432, database: 'vitalia_test',
    user: 'usuario_test', password: 'solo-sintético',
  });
});

test('rechaza puertos inválidos y servidores remotos en esta fase local', () => {
  for (const PGPORT of ['abc', '0', '65536', '1.5', '']) {
    expect(() => readDatabaseConfig({ ...valid, PGPORT })).toThrow();
  }
  expect(() => readDatabaseConfig({ ...valid, PGHOST: 'servidor-remoto.example' })).toThrow();
});

test('rechaza campos requeridos ausentes sin reflejar credenciales', () => {
  for (const key of ['PGDATABASE', 'PGUSER', 'PGPASSWORD']) {
    const env = { ...valid };
    delete env[key];
    expect(() => readDatabaseConfig(env)).toThrow(
      'Configuración PostgreSQL inválida. Revisa las variables PG en .env.');
  }
});

test('un error de conexión inactiva genera un mensaje sin detalles sensibles', async () => {
  const log = jest.spyOn(console, 'error').mockImplementation(() => {});
  const pool = createDatabasePool(readDatabaseConfig(valid));
  try {
    pool.emit('error', new Error('contraseña-y-host-sensibles'));
    expect(log).toHaveBeenCalledWith('Se perdió una conexión inactiva con PostgreSQL.');
    expect(JSON.stringify(log.mock.calls)).not.toContain('sensibles');
  } finally {
    await pool.end();
    log.mockRestore();
  }
});

test('disponibilidad ejecuta únicamente una consulta de lectura', async () => {
  const pool = { query: jest.fn().mockResolvedValue({ rows: [{ connection_ok: 1 }] }) };
  await expect(checkDatabaseAvailability(pool)).resolves.toBeUndefined();
  expect(pool.query).toHaveBeenCalledWith('SELECT 1 AS connection_ok');
});

test('una respuesta inesperada o un fallo de consulta no indica disponibilidad', async () => {
  for (const rows of [[], [{ connection_ok: 0 }]]) {
    await expect(checkDatabaseAvailability({
      query: jest.fn().mockResolvedValue({ rows }),
    })).rejects.toThrow();
  }
  await expect(checkDatabaseAvailability({
    query: jest.fn().mockRejectedValue(new Error('fallo de consulta')),
  })).rejects.toThrow();
});

test('la comprobación CLI falla de forma controlada sin configuración válida', () => {
  const result = spawnSync(process.execPath, ['dist/database/check.js'], {
    cwd: process.cwd(), encoding: 'utf8',
    env: { ...process.env, ...valid, PGPORT: 'inválido' },
  });
  expect(result.status).toBe(1);
  expect(result.stdout).toBe('');
  expect(result.stderr).toContain('No se pudo comprobar PostgreSQL.');
  expect(result.stderr).not.toContain('solo-sintético');
  expect(result.stderr).not.toContain('usuario_test');
});
