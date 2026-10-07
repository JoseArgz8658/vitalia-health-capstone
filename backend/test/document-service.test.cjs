const { createDocumentService } = require('../dist/documents/service');
const account = { id: '11111111-1111-4111-8111-111111111111', role: 'paciente' };
const pdf = Buffer.from('%PDF-1.4\nsynthetic\n%%EOF');
const incoming = { metadata: { examName: 'Sintético', examType: 'Laboratorio', examDate: '2026-01-01' },
  name: 'sintetico.pdf', contentType: 'application/pdf', body: pdf };
function fixture(failCommit = false) {
  let saved;
  const db = {
    query: jest.fn(async (sql, values) => {
      if (sql.includes('INSERT INTO public.vitalia_documents')) {
        saved = { id: values[0], exam_name: values[2], exam_type: values[3], exam_date: values[4],
          original_name: values[5], content_type: values[6], size_bytes: values[7],
          created_at: new Date(), storage_key: values[8], status: 'pending' };
        return { rows: [] };
      }
      if (sql.includes("SET status = 'stored'")) { saved.status = 'stored'; return { rows: [{ id: saved.id }] }; }
      if (sql.includes("SET status = 'failed'")) { saved.status = 'failed'; return { rows: [] }; }
      if (sql.includes('SELECT storage_key')) return { rows: [{ storage_key: saved.storage_key }] };
      if (sql.includes('FROM public.vitalia_documents')) return { rows: saved?.status === 'stored' ? [saved] : [] };
      return { rows: [] };
    }),
    transaction: async work => {
      const status = saved?.status;
      try {
        const value = await work(db);
        if (failCommit) throw new Error('commit fallido');
        return value;
      } catch (error) { if (saved) saved.status = status; throw error; }
    },
  };
  const storage = { put: jest.fn().mockResolvedValue(undefined),
    read: jest.fn().mockResolvedValue(pdf), remove: jest.fn().mockResolvedValue(undefined) };
  return { db, storage, service: createDocumentService(db, storage), state: () => saved };
}
test('upload confirmado registra auditoría y devuelve resumen sin clave S3', async () => {
  const f = fixture();
  const item = await f.service.upload(account, incoming);
  expect(f.state().status).toBe('stored');
  expect(item.storageKey).toBeUndefined();
  expect(f.db.query.mock.calls.some(c => c[0].includes('vitalia_document_audit') && c[1][2] === 'upload')).toBe(true);
});
test('fallo S3 marca failed, intenta limpieza y no confirma documento', async () => {
  const f = fixture();
  f.storage.put.mockRejectedValue(new Error('S3 caído'));
  await expect(f.service.upload(account, incoming)).rejects.toThrow('S3 caído');
  expect(f.state().status).toBe('failed');
  expect(f.storage.remove).toHaveBeenCalledTimes(1);
  expect(f.db.query.mock.calls.some(c => c[0].includes("SET status = 'stored'"))).toBe(false);
});
test('fallo al confirmar PostgreSQL compensa el objeto', async () => {
  const f = fixture(true);
  await expect(f.service.upload(account, incoming)).rejects.toThrow('commit fallido');
  expect(f.state().status).toBe('failed');
  expect(f.storage.remove).toHaveBeenCalledTimes(1);
});
test('archivo falso y metadatos con rol no escriben en DB o S3', async () => {
  const f = fixture();
  await expect(f.service.upload(account, { ...incoming, body: Buffer.from('no es PDF') })).rejects.toThrow();
  await expect(f.service.upload(account, { ...incoming, metadata: { ...incoming.metadata, role: 'administrador' } })).rejects.toThrow();
  expect(f.db.query).not.toHaveBeenCalled();
  expect(f.storage.put).not.toHaveBeenCalled();
});
test('documento no encontrado nunca consulta S3', async () => {
  const f = fixture();
  await expect(f.service.download(account, '22222222-2222-4222-8222-222222222222')).rejects.toThrow();
  expect(f.storage.read).not.toHaveBeenCalled();
});
