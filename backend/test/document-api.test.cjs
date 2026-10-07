const request = require('supertest');
const { createApp } = require('../dist/app');
const { identifyDocument } = require('../dist/documents/file-validation');
const { DocumentNotFoundError } = require('../dist/documents/service');
const token = 'a'.repeat(64);
const account = { id: '11111111-1111-4111-8111-111111111111', role: 'paciente' };
const id = '22222222-2222-4222-8222-222222222222';
const pdf = Buffer.from('%PDF-1.4\nsynthetic\n%%EOF');
function setup(user = account) {
  const services = { upload: jest.fn().mockResolvedValue({ id }),
    list: jest.fn().mockResolvedValue([]),
    download: jest.fn().mockResolvedValue({ item: { contentType: 'application/pdf',
      originalName: 'sintetico.pdf' }, body: pdf }) };
  const auth = { find: jest.fn().mockResolvedValue(user) };
  return { app: createApp(auth, undefined, services), services, auth };
}
test('sin sesión no recibe archivo ni llama al servicio', async () => {
  const { app, services } = setup();
  expect((await request(app).post('/api/documents')
    .attach('file', pdf, 'sintetico.pdf')).status).toBe(401);
  expect(services.upload).not.toHaveBeenCalled();
});
test('sesión inexistente devuelve 401', async () => {
  const { app, services } = setup(null);
  expect((await request(app).get('/api/documents').set('Authorization', 'Bearer ' + token)).status).toBe(401);
  expect(services.list).not.toHaveBeenCalled();
});
test('rol profesional no obtiene acceso de paciente', async () => {
  const { app, services } = setup({ ...account, role: 'profesional' });
  expect((await request(app).get('/api/documents').set('Authorization', 'Bearer ' + token)).status).toBe(403);
  expect(services.list).not.toHaveBeenCalled();
});
test('multipart entrega identidad de sesión y metadatos al servicio', async () => {
  const { app, services } = setup();
  const res = await request(app).post('/api/documents').set('Authorization', 'Bearer ' + token)
    .field('examName', 'Examen sintético').field('examType', 'Laboratorio').field('examDate', '2026-01-01')
    .attach('file', pdf, { filename: 'sintetico.pdf', contentType: 'application/pdf' });
  expect(res.status).toBe(201);
  expect(services.upload.mock.calls[0][0]).toEqual(account);
  expect(services.upload.mock.calls[0][1].body).toEqual(pdf);
});
test('archivo ausente o campo de archivo equivocado devuelve 400', async () => {
  for (const field of [null, 'otro']) {
    const { app, services } = setup();
    let req = request(app).post('/api/documents').set('Authorization', 'Bearer ' + token);
    req = field ? req.attach(field, pdf, 'sintetico.pdf') : req.field('examName', 'sintético');
    expect((await req).status).toBe(400);
    expect(services.upload).not.toHaveBeenCalled();
  }
});
test('tamaño superior a 10 MiB devuelve 413', async () => {
  const { app, services } = setup();
  expect((await request(app).post('/api/documents').set('Authorization', 'Bearer ' + token)
    .attach('file', Buffer.alloc(10 * 1024 * 1024 + 1), 'grande.pdf')).status).toBe(413);
  expect(services.upload).not.toHaveBeenCalled();
});
test('paginación inválida rechazada', async () => {
  const { app, services } = setup();
  expect((await request(app).get('/api/documents?limit=101').set('Authorization', 'Bearer ' + token)).status).toBe(400);
  expect(services.list).not.toHaveBeenCalled();
});
test('download ajeno devuelve respuesta neutral y no contenido', async () => {
  const { app, services } = setup();
  services.download.mockRejectedValue(new DocumentNotFoundError());
  const res = await request(app).get('/api/documents/' + id + '/file').set('Authorization', 'Bearer ' + token);
  expect(res.status).toBe(404);
  expect(res.body.error.message).toBe('Documento no disponible.');
});
test('download es adjunto, no cacheable y nosniff', async () => {
  const { app } = setup();
  const res = await request(app).get('/api/documents/' + id + '/file').set('Authorization', 'Bearer ' + token);
  expect(res.status).toBe(200);
  expect(res.headers['content-disposition']).toContain('attachment');
  expect(res.headers['cache-control']).toBe('no-store');
  expect(res.headers['x-content-type-options']).toBe('nosniff');
});
test('firmas, MIME y extensión deben coincidir', () => {
  expect(identifyDocument(pdf, 'application/pdf', 'sintetico.pdf')).toBe('application/pdf');
  expect(() => identifyDocument(Buffer.from('texto'), 'application/pdf', 'falso.pdf')).toThrow();
  expect(() => identifyDocument(pdf, 'image/png', 'sintetico.png')).toThrow();
  expect(() => identifyDocument(pdf, 'application/pdf', 'sintetico.html')).toThrow();
});
