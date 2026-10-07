const { createLoginAttemptLimiter } = require('../dist/auth/login-limit');
test('limita diez intentos y permite nuevamente al terminar la ventana', () => {
  let now = 0;
  const allow = createLoginAttemptLimiter(() => now);
  for (let i = 0; i < 10; i++) expect(allow('direccion')).toBe(true);
  expect(allow('direccion')).toBe(false);
  now = 15 * 60 * 1000;
  expect(allow('direccion')).toBe(true);
});
test('separa direcciones dentro del mismo proceso', () => {
  const allow = createLoginAttemptLimiter(() => 0);
  for (let i = 0; i < 10; i++) allow('primera');
  expect(allow('primera')).toBe(false);
  expect(allow('segunda')).toBe(true);
});
test('limita la memoria y recupera capacidad al caducar entradas', () => {
  let now = 0;
  const allow = createLoginAttemptLimiter(() => now);
  for (let i = 0; i < 1000; i++) expect(allow('direccion-' + i)).toBe(true);
  expect(allow('otra')).toBe(false);
  now = 15 * 60 * 1000;
  expect(allow('otra')).toBe(true);
});
