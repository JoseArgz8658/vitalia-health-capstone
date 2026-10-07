const { hashPassword } = require('../dist/auth/password');
const { createCredentialAuthenticator, CredentialCheckBusyError } = require('../dist/auth/credentials');
jest.setTimeout(20000);
const password = '  Contraseña-sintética-2026!  ';
const input = { email: 'paciente@example.cl', password };
let account, authenticate;
const db = { query: jest.fn() };

beforeAll(async () => {
  account = { id: 'ficticio', email: input.email, role_code: 'paciente',
    created_at: new Date('2026-01-01T00:00:00Z'), password_hash: await hashPassword(password) };
  authenticate = await createCredentialAuthenticator(db);
});
beforeEach(() => db.query.mockReset().mockResolvedValue({ rows: [account] }));

test('credenciales correctas devuelven solo un resumen de la cuenta', async () => {
  const result = await authenticate({ ...input, email: ' PACIENTE@EXAMPLE.CL ' });
  expect(result).toEqual({ id: account.id, email: account.email,
    role: 'paciente', createdAt: account.created_at });
  expect(result).not.toHaveProperty('passwordHash');
  expect(result).not.toHaveProperty('password_hash');
  expect(result).not.toHaveProperty('token');
});

test('una contraseña incorrecta no acredita la identidad', async () => {
  expect(await authenticate({ ...input, password: 'incorrecta' })).toBeNull();
});

test('una cuenta desconocida devuelve el mismo resultado que una contraseña incorrecta', async () => {
  db.query.mockResolvedValue({ rows: [] });
  expect(await authenticate(input)).toBeNull();
});

test('rechaza entradas inválidas o campos adicionales antes de consultar datos', async () => {
  for (const value of [null, {}, { ...input, role: 'administrador' },
    { ...input, email: "' OR 1=1 --" }, { ...input, password: '' },
    { ...input, password: '🔒'.repeat(257) }]) {
    expect(await authenticate(value)).toBeNull();
  }
  expect(db.query).not.toHaveBeenCalled();
});

test('no elimina los espacios de una contraseña', async () => {
  expect(await authenticate({ ...input, password: password.trim() })).toBeNull();
});

test('un fallo de base se propaga y libera el control para la siguiente comprobación', async () => {
  const error = new Error('fallo interno sintético');
  db.query.mockRejectedValueOnce(error);
  await expect(authenticate(input)).rejects.toBe(error);
  expect(await authenticate(input)).not.toBeNull();
});

test('rechaza cálculos concurrentes y vuelve a aceptar después de finalizar', async () => {
  let release;
  db.query.mockImplementationOnce(() => new Promise(resolve => { release = resolve; }));
  const first = authenticate(input);
  await expect(authenticate(input)).rejects.toBeInstanceOf(CredentialCheckBusyError);
  release({ rows: [account] });
  expect(await first).not.toBeNull();
  expect(await authenticate(input)).not.toBeNull();
});
