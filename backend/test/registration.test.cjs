const { createPatientRegistrar, RegistrationInputError, RegistrationBusyError } = require('../dist/auth/registration');
const { verifyPassword } = require('../dist/auth/password');
jest.setTimeout(20000);
const input = { email: 'Paciente@Example.cl', password: 'Contraseña-sintética-2026!' };
const row = { id: 'sintetico', email: 'paciente@example.cl', role_code: 'paciente', created_at: new Date() };
let db, register;
beforeEach(() => {
  db = { query: jest.fn().mockResolvedValue({ rows: [row] }) };
  register = createPatientRegistrar(db);
});

test('guarda correo normalizado, hash válido y rol paciente', async () => {
  await expect(register(input)).resolves.toBeUndefined();
  const [sql, values] = db.query.mock.calls[0];
  expect(values[1]).toBe('paciente@example.cl');
  expect(values[2]).not.toBe(input.password);
  expect(await verifyPassword(input.password, values[2])).toBe(true);
  expect(sql).toContain("'paciente'");
  expect(sql).not.toContain(input.password);
});

test('rechaza correo inválido, contraseña corta y campos de rol antes de consultar la base', async () => {
  for (const value of [null, {}, { ...input, email: 'inválido' },
    { ...input, password: '12345678901' }, { ...input, role: 'administrador' },
    { ...input, password: '🔒'.repeat(257) }]) {
    await expect(register(value)).rejects.toBeInstanceOf(RegistrationInputError);
  }
  expect(db.query).not.toHaveBeenCalled();
});

test('cuenta caracteres Unicode y no unidades UTF-16', async () => {
  await expect(register({ ...input, password: '🔒'.repeat(6) })).rejects.toBeInstanceOf(RegistrationInputError);
  await expect(register({ ...input, password: '🔒'.repeat(12) })).resolves.toBeUndefined();
});

test('admite exactamente doce caracteres sin exigir símbolos', async () => {
  await expect(register({ ...input, password: 'abcdefghijkl' })).resolves.toBeUndefined();
});

test('conserva espacios en la contraseña sin recortarla', async () => {
  const password = '  contraseña-larga  ';
  await register({ ...input, password });
  const hash = db.query.mock.calls[0][1][2];
  expect(await verifyPassword(password, hash)).toBe(true);
  expect(await verifyPassword(password.trim(), hash)).toBe(false);
});

test('correo duplicado no cambia la cuenta ni genera un error que revele su existencia', async () => {
  db.query.mockRejectedValue({ code: '23505', constraint: 'vitalia_accounts_email_key' });
  await expect(register(input)).resolves.toBeUndefined();
  expect(db.query.mock.calls[0][0]).toContain('INSERT INTO');
  expect(db.query.mock.calls[0][0]).not.toContain('UPDATE');
});

test('fallos internos se propagan y el servicio queda disponible para el siguiente intento', async () => {
  const error = new Error('fallo sintético');
  db.query.mockRejectedValueOnce(error);
  await expect(register(input)).rejects.toBe(error);
  await expect(register(input)).resolves.toBeUndefined();
});

test('rechaza un registro concurrente sin iniciar otro cálculo', async () => {
  const first = register(input);
  await expect(register(input)).rejects.toBeInstanceOf(RegistrationBusyError);
  await first;
  expect(db.query).toHaveBeenCalledTimes(1);
});
