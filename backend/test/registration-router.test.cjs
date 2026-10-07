const request = require('supertest');
const { createApp } = require('../dist/app');
const { RegistrationInputError, RegistrationBusyError } = require('../dist/auth/registration');
const input = { email: 'paciente@example.cl', password: 'contraseña-sintética' };
let register, app;
beforeEach(() => {
  register = jest.fn().mockResolvedValue(undefined);
  app = createApp(undefined, register);
});

test('registro procesado responde sin identidad, contraseña o sesión', async () => {
  const response = await request(app).post('/api/auth/register').send(input);
  expect(response.status).toBe(202);
  expect(response.body).toEqual({ message: 'Solicitud de registro procesada.' });
  expect(response.headers['cache-control']).toBe('no-store');
  expect(JSON.stringify(response.body)).not.toContain(input.email);
  expect(response.body).not.toHaveProperty('token');
  expect(register).toHaveBeenCalledWith(input);
});

test('un error de validación da 400 sin reflejar la entrada', async () => {
  register.mockRejectedValue(new RegistrationInputError());
  const response = await request(app).post('/api/auth/register').send({ ...input, role: 'administrador' });
  expect(response.status).toBe(400);
  expect(response.body.error.code).toBe('INVALID_REGISTRATION');
  expect(JSON.stringify(response.body)).not.toContain(input.password);
});

test('registro ocupado da 503 y permite reintentar', async () => {
  register.mockRejectedValue(new RegistrationBusyError());
  const response = await request(app).post('/api/auth/register').send(input);
  expect(response.status).toBe(503);
  expect(response.headers['retry-after']).toBe('1');
});

test('errores internos responden de forma genérica', async () => {
  register.mockRejectedValue(new Error('datos-secretos-y-SQL'));
  const response = await request(app).post('/api/auth/register').send(input);
  expect(response.status).toBe(500);
  expect(response.body.error.code).toBe('INTERNAL_ERROR');
  expect(JSON.stringify(response.body)).not.toContain('secretos');
});

test('la ruta limita diez peticiones por dirección y conserva el 404 anterior', async () => {
  for (let i = 0; i < 10; i++) {
    expect((await request(app).post('/api/auth/register').send(input)).status).toBe(202);
  }
  expect((await request(app).post('/api/auth/register').send(input)).status).toBe(429);
  expect(register).toHaveBeenCalledTimes(10);
  expect((await request(app).get('/ruta-inexistente')).status).toBe(404);
});
