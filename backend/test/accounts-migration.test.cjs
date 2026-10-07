const { createHash } = require('node:crypto');
const { applyAccountsMigration } = require('../dist/database/accounts-migration');
const sql = 'CREATE TABLE tabla_ficticia (id uuid PRIMARY KEY);';
const checksum = createHash('sha256').update(sql).digest('hex');
function clientWith(rows = []) {
  return { query: jest.fn(async (query) => {
    if (query.startsWith('SELECT checksum')) return { rows };
    return { rows: [] };
  }) };
}

test('registra una nueva migración y confirma la misma transacción', async () => {
  const client = clientWith();
  expect(await applyAccountsMigration(client, sql)).toBe('applied');
  expect(client.query.mock.calls[0][0]).toBe('BEGIN');
  expect(client.query).toHaveBeenCalledWith(sql);
  expect(client.query).toHaveBeenCalledWith(
    'INSERT INTO public.vitalia_schema_migrations (version, checksum) VALUES ($1, $2)',
    ['001_accounts', checksum]);
  expect(client.query.mock.calls.at(-1)[0]).toBe('COMMIT');
});

test('una migración ya aplicada con el mismo hash no vuelve a ejecutar DDL', async () => {
  const client = clientWith([{ checksum }]);
  expect(await applyAccountsMigration(client, sql)).toBe('unchanged');
  expect(client.query).not.toHaveBeenCalledWith(sql);
  expect(client.query.mock.calls.at(-1)[0]).toBe('COMMIT');
});

test('cambiar una migración aplicada provoca rechazo y rollback', async () => {
  const client = clientWith([{ checksum: 'otro' }]);
  await expect(applyAccountsMigration(client, sql)).rejects.toThrow();
  expect(client.query).not.toHaveBeenCalledWith(sql);
  expect(client.query.mock.calls.at(-1)[0]).toBe('ROLLBACK');
});

test('un fallo del DDL revierte sin registrar la migración', async () => {
  const client = clientWith();
  client.query.mockImplementation(async (query) => {
    if (query === sql) throw new Error('fallo DDL');
    return { rows: [] };
  });
  await expect(applyAccountsMigration(client, sql)).rejects.toThrow('fallo DDL');
  expect(client.query.mock.calls.some(([q]) => q.startsWith('INSERT INTO'))).toBe(false);
  expect(client.query.mock.calls.at(-1)[0]).toBe('ROLLBACK');
});

test('si BEGIN falla no intenta una transacción inexistente', async () => {
  const client = { query: jest.fn().mockRejectedValue(new Error('sin conexión')) };
  await expect(applyAccountsMigration(client, sql)).rejects.toThrow('sin conexión');
  expect(client.query).toHaveBeenCalledTimes(1);
});

test('un fallo de rollback no oculta el error original', async () => {
  const original = new Error('DDL original');
  const client = clientWith();
  client.query.mockImplementation(async (query) => {
    if (query === sql) throw original;
    if (query === 'ROLLBACK') throw new Error('conexión cerrada');
    return { rows: [] };
  });
  await expect(applyAccountsMigration(client, sql)).rejects.toBe(original);
});

test('la huella de la migración es estable entre saltos LF y CRLF', async () => {
  const lf = '-- ejemplo\n' + sql + '\n';
  const canonicalChecksum = createHash('sha256').update(lf).digest('hex');
  const client = clientWith([{ checksum: canonicalChecksum }]);
  expect(await applyAccountsMigration(client, lf.replace(/\n/g, '\r\n'))).toBe('unchanged');
});
