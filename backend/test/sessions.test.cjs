const { createHash } = require('node:crypto');
const { issueSession, findSessionAccount, revokeSession } = require('../dist/auth/sessions');
const token = 'a'.repeat(64);
const hash = createHash('sha256').update(token).digest('hex');

test('cada sesión usa un token diferente y almacena solo su huella', async () => {
  const expires = new Date('2026-01-01T00:30:00Z');
  const db = { query: jest.fn().mockResolvedValue({ rows: [{ expires_at: expires }] }) };
  const first = await issueSession(db, 'cuenta');
  const second = await issueSession(db, 'cuenta');
  expect(first.token).not.toBe(second.token);
  expect(first.token).toMatch(/^[a-f0-9]{64}$/);
  expect(first.expiresAt).toBe(expires);
  const [sql, values] = db.query.mock.calls[0];
  expect(values).toEqual([createHash('sha256').update(first.token).digest('hex'), 'cuenta']);
  expect(sql).not.toContain(first.token);
  expect(sql).toContain("INTERVAL '30 minutes'");
});

test('consulta la huella y el rol actual, sin devolver campos sensibles', async () => {
  const row = { id: 'cuenta', email: 'sintetico@example.cl', role_code: 'profesional',
    created_at: new Date(), password_hash: 'no-devolver', token_hash: hash };
  const db = { query: jest.fn().mockResolvedValue({ rows: [row] }) };
  const result = await findSessionAccount(db, token);
  expect(result.role).toBe('profesional');
  expect(result).not.toHaveProperty('password_hash');
  expect(result).not.toHaveProperty('token_hash');
  expect(db.query.mock.calls[0][1]).toEqual([hash]);
  expect(db.query.mock.calls[0][0]).toContain('s.expires_at > CURRENT_TIMESTAMP');
});

test('un token malformado no consulta ni elimina datos', async () => {
  const db = { query: jest.fn() };
  expect(await findSessionAccount(db, 'inválido')).toBeNull();
  await revokeSession(db, 'inválido');
  expect(db.query).not.toHaveBeenCalled();
});

test('una sesión no encontrada no acredita identidad', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
  expect(await findSessionAccount(db, token)).toBeNull();
});

test('cerrar sesión elimina por huella y no por token original', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
  await revokeSession(db, token);
  expect(db.query).toHaveBeenCalledWith(
    'DELETE FROM public.vitalia_sessions WHERE token_hash = $1', [hash]);
});
