const { createHash } = require('node:crypto');
const { applyAdditionalMigration } = require('../dist/database/additional-migration');
const sql = 'CREATE TABLE ficticia (id uuid);';
function client(base = true, checksum) {
  return { query: jest.fn(async text => {
    if (text.startsWith('SELECT version')) return { rows: base ? [{ version: '001_accounts' }] : [] };
    if (text.startsWith('SELECT checksum')) return { rows: checksum ? [{ checksum }] : [] };
    return { rows: [] };
  }) };
}
test('aplica una migración nueva después de comprobar su requisito', async () => {
  const db = client();
  expect(await applyAdditionalMigration(db, '002_sessions', sql, '001_accounts')).toBe('applied');
  expect(db.query).toHaveBeenCalledWith(sql);
  expect(db.query.mock.calls.at(-1)[0]).toBe('COMMIT');
});
test('no aplica sesiones si falta la migración de cuentas', async () => {
  const db = client(false);
  await expect(applyAdditionalMigration(db, '002_sessions', sql, '001_accounts')).rejects.toThrow();
  expect(db.query).not.toHaveBeenCalledWith(sql);
  expect(db.query.mock.calls.at(-1)[0]).toBe('ROLLBACK');
});
test('una migración ya aplicada no repite el DDL', async () => {
  const db = client(true, createHash('sha256').update(sql).digest('hex'));
  expect(await applyAdditionalMigration(db, '002_sessions', sql, '001_accounts')).toBe('unchanged');
  expect(db.query).not.toHaveBeenCalledWith(sql);
});
test('una huella distinta revierte sin tocar el DDL existente', async () => {
  const db = client(true, 'otra');
  await expect(applyAdditionalMigration(db, '002_sessions', sql, '001_accounts')).rejects.toThrow();
  expect(db.query).not.toHaveBeenCalledWith(sql);
  expect(db.query.mock.calls.at(-1)[0]).toBe('ROLLBACK');
});
