const { reserveDocument, completeDocument, listPatientDocuments, findPatientDocument } = require('../dist/documents/repository');
const patient = { id: '11111111-1111-4111-8111-111111111111', role: 'paciente' };
const id = '22222222-2222-4222-8222-222222222222';
const input = { examName: 'Examen ficticio', examType: 'Laboratorio', examDate: '2026-01-01',
  originalName: 'examen.pdf', contentType: 'application/pdf', sizeBytes: 512 };
test('reserva usa propietario de identidad y clave independiente del nombre', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
  const result = await reserveDocument(db, patient, input);
  expect(db.query.mock.calls[0][1][1]).toBe(patient.id);
  expect(result.storageKey).toBe('patients/' + patient.id + '/documents/' + result.id);
  expect(result.storageKey).not.toContain('examen.pdf');
});
test('rechaza propietario o rol enviado como metadato', async () => {
  const db = { query: jest.fn() };
  await expect(reserveDocument(db, patient, { ...input, patientId: id })).rejects.toThrow();
  expect(db.query).not.toHaveBeenCalled();
});
test('rechaza fecha inexistente, archivo demasiado grande y ruta en nombre', async () => {
  const db = { query: jest.fn() };
  for (const extra of [{ examDate: '2026-02-30' }, { sizeBytes: 10485761 },
    { originalName: '../examen.pdf' }, { contentType: 'application/javascript' }]) {
    await expect(reserveDocument(db, patient, { ...input, ...extra })).rejects.toThrow();
  }
  expect(db.query).not.toHaveBeenCalled();
});
test('lista filtra por propietario y documentos almacenados', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
  expect(await listPatientDocuments(db, patient)).toEqual([]);
  expect(db.query.mock.calls[0][0]).toContain("patient_id = $1 AND status = 'stored'");
  expect(db.query.mock.calls[0][1]).toEqual([patient.id, 20, 0]);
});
test('detalle ajeno o inexistente no devuelve datos', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
  expect(await findPatientDocument(db, patient, id)).toBeNull();
  expect(db.query.mock.calls[0][1]).toEqual([id, patient.id]);
});
test('confirmación está restringida al propietario y estado pendiente', async () => {
  const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
  expect(await completeDocument(db, patient, id)).toBe(false);
  expect(db.query.mock.calls[0][0]).toContain("patient_id = $2 AND status = 'pending'");
});
test('rechaza profesional y paginación inválida', async () => {
  const db = { query: jest.fn() };
  await expect(listPatientDocuments(db, { ...patient, role: 'profesional' })).rejects.toThrow();
  await expect(listPatientDocuments(db, patient, 101)).rejects.toThrow();
  expect(db.query).not.toHaveBeenCalled();
});
