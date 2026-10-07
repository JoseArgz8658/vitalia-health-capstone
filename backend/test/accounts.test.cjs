const {
  insertPatientAccount, findAccountCredentialsByEmail, DuplicateEmailError,
} = require('../dist/accounts/repository');
const hash = 'scrypt-v1$' + 'a'.repeat(32) + '$' + 'b'.repeat(128);
const row = { id: 'ficticio', email: 'paciente@example.cl',
  role_code: 'paciente', created_at: new Date('2026-01-01T00:00:00Z'), password_hash: hash };

test('inserta paciente con correo normalizado y devuelve un resumen sin hash', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [row] }) };
  const result = await insertPatientAccount(db, ' Paciente@Example.cl ', hash);
  const [sql, values] = db.query.mock.calls[0];
  expect(sql).toContain("VALUES ($1, $2, $3, 'paciente')");
  expect(values[0]).toMatch(/^[a-f0-9-]{36}$/);
  expect(values.slice(1)).toEqual(['paciente@example.cl', hash]);
  expect(sql).not.toContain(hash);
  expect(result).toEqual({ id: row.id, email: row.email, role: 'paciente', createdAt: row.created_at });
  expect(result).not.toHaveProperty('passwordHash');
  expect(result).not.toHaveProperty('password_hash');
});

test('rechaza correo o hash inválido antes de consultar PostgreSQL', async () => {
  const db = { query: jest.fn() };
  await expect(insertPatientAccount(db, 'inválido', hash)).rejects.toThrow();
  await expect(insertPatientAccount(db, 'paciente@example.cl', 'texto-plano')).rejects.toThrow();
  expect(db.query).not.toHaveBeenCalled();
});

test('un correo duplicado se convierte en error interno identificable', async () => {
  const db = { query: jest.fn().mockRejectedValue({
    code: '23505', constraint: 'vitalia_accounts_email_key', detail: 'dato sensible',
  }) };
  await expect(insertPatientAccount(db, row.email, hash)).rejects.toBeInstanceOf(DuplicateEmailError);
  await expect(insertPatientAccount(db, row.email, hash)).rejects.toThrow('El correo ya está registrado.');
});

test('otros errores de base no se confunden con correo duplicado', async () => {
  const error = new Error('error interno');
  error.code = '23505';
  error.constraint = 'otra_restricción';
  const db = { query: jest.fn().mockRejectedValue(error) };
  await expect(insertPatientAccount(db, row.email, hash)).rejects.toBe(error);
});

test('consulta con parámetros preserva apóstrofes válidos sin concatenarlos al SQL', async () => {
  const email = "o'connor@example.cl";
  const db = { query: jest.fn().mockResolvedValue({ rows: [{ ...row, email }] }) };
  const result = await findAccountCredentialsByEmail(db, email);
  const [sql, values] = db.query.mock.calls[0];
  expect(sql).toContain('WHERE email = $1');
  expect(sql).not.toContain(email);
  expect(values).toEqual([email]);
  expect(result.passwordHash).toBe(hash);
});

test('una cuenta inexistente devuelve null', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
  expect(await findAccountCredentialsByEmail(db, row.email)).toBeNull();
});

test('rechaza una entrada de inyección que no es correo válido', async () => {
  const db = { query: jest.fn() };
  await expect(findAccountCredentialsByEmail(db, "' OR 1=1 --")).rejects.toThrow();
  expect(db.query).not.toHaveBeenCalled();
});

test('no acepta una cuenta sin hash almacenado', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [{ ...row, password_hash: null }] }) };
  await expect(findAccountCredentialsByEmail(db, row.email)).rejects.toThrow();
});
