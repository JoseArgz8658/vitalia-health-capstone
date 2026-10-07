const { previewRecovery, applyRecovery } = require('../dist/documents/recovery');
const row = { id: '22222222-2222-4222-8222-222222222222',
  patient_id: '11111111-1111-4111-8111-111111111111' };
row.storage_key = 'patients/' + row.patient_id + '/documents/' + row.id;
function fixture({ locked = true, rows = [row], claim = true, logFails = false } = {}) {
  const query = jest.fn(async sql => {
    if (sql.includes('pg_try_advisory_lock')) return { rows: [{ locked }] };
    if (sql.includes('FROM public.vitalia_documents d')) return { rows };
    if (sql.includes('UPDATE public.vitalia_documents')) return { rows: claim ? [{ id: row.id }] : [] };
    if (logFails && sql.includes('INSERT INTO public.vitalia_document_cleanup')) throw new Error('DB falló');
    return { rows: [] };
  });
  return { query };
}
test('preview solo consulta estados incompletos antiguos y no limpiados', async () => {
  const db = fixture();
  expect(await previewRecovery(db)).toEqual([row]);
  expect(db.query).toHaveBeenCalledTimes(1);
  const sql = db.query.mock.calls[0][0];
  expect(sql).toContain("d.status IN ('pending', 'failed')");
  expect(sql).toContain("INTERVAL '1 hour'");
  expect(sql).toContain('c.document_id IS NULL');
});
test('limpieza registra éxito y libera bloqueo', async () => {
  const db = fixture(); const remove = jest.fn().mockResolvedValue();
  expect(await applyRecovery(db, remove)).toEqual({ candidates: 1, cleaned: 1, skipped: 0, failed: 0 });
  expect(remove).toHaveBeenCalledWith(row.storage_key);
  expect(db.query.mock.calls.some(c => c[0].includes('INSERT INTO public.vitalia_document_cleanup'))).toBe(true);
  expect(db.query.mock.calls.at(-1)[0]).toContain('pg_advisory_unlock');
});
test('documento confirmado entre consulta y limpieza no se borra', async () => {
  const db = fixture({ claim: false }); const remove = jest.fn();
  expect((await applyRecovery(db, remove)).skipped).toBe(1);
  expect(remove).not.toHaveBeenCalled();
});
test('clave arbitraria no se borra ni cambia estado', async () => {
  const db = fixture({ rows: [{ ...row, storage_key: 'otro/objeto' }] }); const remove = jest.fn();
  expect((await applyRecovery(db, remove)).failed).toBe(1);
  expect(remove).not.toHaveBeenCalled();
  expect(db.query.mock.calls.some(c => c[0].includes('UPDATE'))).toBe(false);
});
test('fallo S3 no registra limpieza y permite reintento', async () => {
  const db = fixture(); const remove = jest.fn().mockRejectedValue(new Error('S3 caído'));
  expect((await applyRecovery(db, remove)).failed).toBe(1);
  expect(db.query.mock.calls.some(c => c[0].includes('INSERT INTO public.vitalia_document_cleanup'))).toBe(false);
  expect(db.query.mock.calls.at(-1)[0]).toContain('pg_advisory_unlock');
});
test('otro proceso bloquea la recuperación sin borrar objetos', async () => {
  const db = fixture({ locked: false }); const remove = jest.fn();
  await expect(applyRecovery(db, remove)).rejects.toThrow();
  expect(remove).not.toHaveBeenCalled();
});
test('fallo de registro no afirma limpieza completada', async () => {
  const db = fixture({ logFails: true });
  expect((await applyRecovery(db, jest.fn().mockResolvedValue())).failed).toBe(1);
});
