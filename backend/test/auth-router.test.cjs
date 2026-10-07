const request = require('supertest');
const { createApp } = require('../dist/app');
const { CredentialCheckBusyError } = require('../dist/auth/credentials');
const token = 'a'.repeat(64);
const user = { id: 'sintetico', email: 'paciente@example.cl', role: 'paciente',
  createdAt: new Date('2026-01-01T00:00:00Z'), passwordHash: 'no-exponer' };
const body = { email: user.email, password: 'sintética' };
let auth, app;
beforeEach(() => {
  auth = {
    authenticate: jest.fn().mockResolvedValue(user),
    issue: jest.fn().mockResolvedValue({ token, expiresAt: new Date('2026-01-01T00:30:00Z') }),
    find: jest.fn().mockResolvedValue(user),
    revoke: jest.fn().mockResolvedValue(undefined),
  };
  app = createApp(auth);
});

test('login correcto entrega sesión sin hash y prohíbe caché', async () => {
  const response = await request(app).post('/api/auth/login').send(body);
  expect(response.status).toBe(200);
  expect(response.body.token).toBe(token);
  expect(response.body.user).not.toHaveProperty('passwordHash');
  expect(response.headers['cache-control']).toBe('no-store');
  expect(auth.issue).toHaveBeenCalledWith(user.id);
});

test('credenciales incorrectas no generan sesión', async () => {
  auth.authenticate.mockResolvedValue(null);
  const response = await request(app).post('/api/auth/login').send(body);
  expect(response.status).toBe(401);
  expect(response.body.error.code).toBe('INVALID_CREDENTIALS');
  expect(auth.issue).not.toHaveBeenCalled();
});

test('cálculo ocupado responde de forma controlada', async () => {
  auth.authenticate.mockRejectedValue(new CredentialCheckBusyError());
  const response = await request(app).post('/api/auth/login').send(body);
  expect(response.status).toBe(503);
  expect(response.headers['retry-after']).toBe('1');
  expect(auth.issue).not.toHaveBeenCalled();
});

test('fallo interno no expone detalles de base ni credenciales', async () => {
  auth.authenticate.mockRejectedValue(new Error('contraseña-secreta-y-SQL'));
  const response = await request(app).post('/api/auth/login').send(body);
  expect(response.status).toBe(500);
  expect(response.body.error.code).toBe('INTERNAL_ERROR');
  expect(JSON.stringify(response.body)).not.toContain('secreta');
});

test('me exige un bearer válido antes de consultar la sesión', async () => {
  for (const header of ['', 'Bearer inválido', 'Basic ' + token]) {
    const req = request(app).get('/api/auth/me');
    if (header) req.set('Authorization', header);
    expect((await req).status).toBe(401);
  }
  expect(auth.find).not.toHaveBeenCalled();
});

test('me devuelve el rol del servicio sin hashes ni tokens', async () => {
  auth.find.mockResolvedValue({ ...user, role: 'profesional' });
  const response = await request(app).get('/api/auth/me').set('Authorization', 'Bearer ' + token);
  expect(response.status).toBe(200);
  expect(response.body.user.role).toBe('profesional');
  expect(response.body.user).not.toHaveProperty('passwordHash');
  expect(response.body).not.toHaveProperty('token');
});

test('una sesión expirada o desconocida devuelve 401', async () => {
  auth.find.mockResolvedValue(null);
  const response = await request(app).get('/api/auth/me').set('Authorization', 'Bearer ' + token);
  expect(response.status).toBe(401);
  expect(JSON.stringify(response.body)).not.toContain(token);
});

test('logout revoca la sesión y el acceso siguiente deja de ser válido', async () => {
  auth.revoke.mockImplementation(async () => { auth.find.mockResolvedValue(null); });
  const response = await request(app).post('/api/auth/logout').set('Authorization', 'Bearer ' + token);
  expect(response.status).toBe(204);
  expect(auth.revoke).toHaveBeenCalledWith(token);
  expect((await request(app).get('/api/auth/me').set('Authorization', 'Bearer ' + token)).status).toBe(401);
  expect((await request(app).post('/api/auth/logout')).status).toBe(401);
});

test('limita intentos aunque el cliente cambie X-Forwarded-For', async () => {
  auth.authenticate.mockResolvedValue(null);
  for (let i = 0; i < 10; i++) {
    expect((await request(app).post('/api/auth/login')
      .set('X-Forwarded-For', '192.0.2.' + i).send(body)).status).toBe(401);
  }
  const response = await request(app).post('/api/auth/login').send(body);
  expect(response.status).toBe(429);
  expect(response.headers['retry-after']).toBe('900');
  expect(auth.authenticate).toHaveBeenCalledTimes(10);
});
