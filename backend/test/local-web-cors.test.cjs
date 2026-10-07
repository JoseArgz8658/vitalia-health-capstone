const request = require('supertest');
const { createApp } = require('../dist/app');
describe('origen local de Flutter', () => {
  test('permite preflight con Authorization', async () => {
    const response = await request(createApp()).options('/api/auth/me')
      .set('Origin', 'http://localhost:5173')
      .set('Access-Control-Request-Method', 'GET')
      .set('Access-Control-Request-Headers', 'authorization,content-type');
    expect(response.status).toBe(204);
    expect(response.headers['access-control-allow-origin']).toBe('http://localhost:5173');
  });
  test('rechaza un origen diferente', async () => {
    expect((await request(createApp()).get('/api/health')
      .set('Origin', 'https://example.com')).status).toBe(403);
  });
  test('rechaza métodos y cabeceras no permitidos', async () => {
    expect((await request(createApp()).options('/api/auth/me')
      .set('Origin', 'http://localhost:5173')
      .set('Access-Control-Request-Method', 'DELETE')).status).toBe(403);
    expect((await request(createApp()).options('/api/auth/me')
      .set('Origin', 'http://localhost:5173')
      .set('Access-Control-Request-Method', 'GET')
      .set('Access-Control-Request-Headers', 'x-extra')).status).toBe(403);
  });
  test('conserva clientes sin Origin', async () => {
    expect((await request(createApp()).get('/api/health')).status).toBe(200);
  });
});
