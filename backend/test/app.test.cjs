const request = require('supertest');
const { createApp } = require('../dist/app');
const { readConfig } = require('../dist/config');

test('health devuelve únicamente estado y servicio', async () => {
  const response = await request(createApp()).get('/api/health');
  expect(response.status).toBe(200);
  expect(response.body).toEqual({ status: 'ok', service: 'vitalia-api' });
  expect(response.headers['x-powered-by']).toBeUndefined();
});
test('ruta desconocida no expone detalles internos', async () => {
  const response = await request(createApp()).get('/api/patients');
  expect(response.status).toBe(404);
  expect(response.body).toEqual({ error: { code: 'NOT_FOUND', message: 'Recurso no disponible.' } });
});
test('JSON inválido responde controladamente sin reflejar entrada', async () => {
  const response = await request(createApp()).post('/api/login')
    .set('Content-Type', 'application/json').send('{"clave":');
  expect(response.status).toBe(400);
  expect(response.body.error.code).toBe('INVALID_JSON');
  expect(JSON.stringify(response.body)).not.toContain('clave');
});
test('rechaza cuerpo excesivo', async () => {
  const response = await request(createApp()).post('/api/login')
    .send({ value: 'x'.repeat(40000) });
  expect(response.status).toBe(413);
});
test('puerto inválido es rechazado y configuración omite datos ajenos', () => {
  expect(() => readConfig({ PORT: 'abc' })).toThrow();
  expect(readConfig({ TOKEN: 'ficticio' })).toEqual({ PORT: 3000, HOST: '127.0.0.1' });
});
