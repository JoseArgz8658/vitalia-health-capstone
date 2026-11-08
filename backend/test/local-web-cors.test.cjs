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
  test('permite preflight del PDF únicamente en SIL demo', async () => {
    const old = process.env.VITALIA_SIL_DEMO;
    const url='/api/sil/orders/11111111-1111-4111-8111-111111111111/report';
    const headers=[
      'authorization','content-type','x-report-filename',
      'x-report-branch-code','x-report-authorized-professional',
      'x-report-patient-identifier','x-report-authorization-ref',
      'x-report-authorized-at','x-report-patient-confirmed',
      'x-report-externally-authorized',
    ].join(',');
    try {
      process.env.VITALIA_SIL_DEMO='YES';
      const response=await request(createApp()).options(url)
        .set('Origin','http://localhost:5173')
        .set('Access-Control-Request-Method','POST')
        .set('Access-Control-Request-Headers',headers);
      expect(response.status).toBe(204);
      expect(response.headers['access-control-allow-headers'])
        .toContain('x-report-patient-identifier');
      // No se autoriza la misma lista de cabeceras a rutas distintas.
      expect((await request(createApp()).options('/api/auth/login')
        .set('Origin','http://localhost:5173')
        .set('Access-Control-Request-Method','POST')
        .set('Access-Control-Request-Headers',headers)).status).toBe(403);
      expect((await request(createApp()).options(url)
        .set('Origin','http://localhost:5173')
        .set('Access-Control-Request-Method','POST')
        .set('Access-Control-Request-Headers',headers+',x-unknown')).status).toBe(403);
      process.env.VITALIA_SIL_DEMO='NO';
      expect((await request(createApp()).options(url)
        .set('Origin','http://localhost:5173')
        .set('Access-Control-Request-Method','POST')
        .set('Access-Control-Request-Headers',headers)).status).toBe(403);
    } finally {
      if(old===undefined)delete process.env.VITALIA_SIL_DEMO;
      else process.env.VITALIA_SIL_DEMO=old;
    }
  });
  test('la recepción de solicitudes permite solo sus encabezados en demo', async()=>{
    const old=process.env.VITALIA_SIL_DEMO;
    const path='/api/sil/medical-requests/preview';
    const headers='authorization,content-type,x-request-patient-email,x-request-filename';
    try{
      process.env.VITALIA_SIL_DEMO='YES';
      const ok=await request(createApp()).options(path)
        .set('Origin','http://localhost:5173')
        .set('Access-Control-Request-Method','POST')
        .set('Access-Control-Request-Headers',headers);
      expect(ok.status).toBe(204);
      expect(ok.headers['access-control-allow-headers'])
        .toContain('x-request-patient-email');
      expect((await request(createApp()).options('/api/auth/me')
        .set('Origin','http://localhost:5173')
        .set('Access-Control-Request-Method','POST')
        .set('Access-Control-Request-Headers',headers)).status).toBe(403);
      process.env.VITALIA_SIL_DEMO='NO';
      expect((await request(createApp()).options(path)
        .set('Origin','http://localhost:5173')
        .set('Access-Control-Request-Method','POST')
        .set('Access-Control-Request-Headers',headers)).status).toBe(403);
    }finally{
      if(old===undefined)delete process.env.VITALIA_SIL_DEMO;
      else process.env.VITALIA_SIL_DEMO=old;
    }
  });
  test('conserva clientes sin Origin', async () => {
    expect((await request(createApp()).get('/api/health')).status).toBe(200);
  });
});
