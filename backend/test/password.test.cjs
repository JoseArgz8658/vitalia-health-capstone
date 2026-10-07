const { hashPassword, verifyPassword } = require('../dist/auth/password.js');

jest.setTimeout(20000);

test('la misma contraseña genera hashes distintos y ambos son verificables', async () => {
  const password = 'Ejemplo-sintético-2026!';
  const first = await hashPassword(password);
  const second = await hashPassword(password);
  expect(first).not.toBe(second);
  expect(first).not.toContain(password);
  expect(await verifyPassword(password, first)).toBe(true);
  expect(await verifyPassword(password, second)).toBe(true);
});

test('una contraseña incorrecta no coincide', async () => {
  const hash = await hashPassword('Contraseña-sintética!');
  expect(await verifyPassword('otra contraseña', hash)).toBe(false);
});

test('preserva espacios y caracteres Unicode sin transformar la contraseña', async () => {
  const hash = await hashPassword('  áé🔒 Contraseña  ');
  expect(await verifyPassword('  áé🔒 Contraseña  ', hash)).toBe(true);
  expect(await verifyPassword('áé🔒 Contraseña', hash)).toBe(false);
});

test('rechaza hashes malformados y versiones no admitidas', async () => {
  for (const value of ['', 'texto', 'scrypt-v2$00$00',
    'scrypt-v1$' + '0'.repeat(32) + '$' + '0'.repeat(127),
    'scrypt-v1$' + 'g'.repeat(32) + '$' + '0'.repeat(128),
    'scrypt-v1$' + '0'.repeat(32) + '$' + '0'.repeat(128) + '$extra']) {
    expect(await verifyPassword('Ejemplo!', value)).toBe(false);
  }
});

test('aplica el límite técnico en bytes sin truncar contraseñas', async () => {
  const oversized = '🔒'.repeat(257);
  await expect(hashPassword('')).rejects.toThrow();
  await expect(hashPassword(oversized)).rejects.toThrow();
  expect(await verifyPassword(oversized, 'texto')).toBe(false);
  const atLimit = 'a'.repeat(1024);
  const hash = await hashPassword(atLimit);
  expect(await verifyPassword(atLimit, hash)).toBe(true);
});
