const {createSilService}=require('../dist/sil/service');

test('listado DEMO: consulta paginada, literal y parametrizada',async()=>{
 const db={
  query:jest.fn()
   .mockResolvedValueOnce({rows:[{total:100}]})
   .mockResolvedValueOnce({rows:[{
    id:'11111111-1111-4111-8111-111111111111',
    email:'ana@example.invalid',syntheticIdentifier:'DEMO-ANA001',
    givenNames:'Ana',familyNames:'Prueba',
    orderCount:2,lastOrderNumber:'VH-000032',
   }]}),
 };
 const service=createSilService(db);
 const result=await service.listPatientsDemo(
  20,40,'Ana%_','complete','with','female','recent');
 expect(result).toEqual({
  total:100,limit:20,offset:40,patients:[expect.objectContaining({
   email:'ana@example.invalid',orderCount:2,
  })],
 });
 expect(db.query).toHaveBeenCalledTimes(2);
 const count=db.query.mock.calls[0];
 const page=db.query.mock.calls[1];
 expect(count[1]).toEqual(['ana%_','female']);
 expect(page[1]).toEqual(['ana%_','female',20,40]);
 expect(count[0]).toContain('POSITION(');
 expect(page[0]).toContain('LIMIT $3 OFFSET $4');
 expect(page[0]).toContain('COALESCE(last_order."lastOrderAt"');
 expect(page[0]).toContain('p.patient_id IS NOT NULL');
 expect(page[0]).toContain('EXISTS (SELECT 1 FROM public.vitalia_sil_orders');
 expect(page[0]).not.toContain('Ana%_');
 expect(page[0]).toContain("a.email LIKE '%@example.invalid'");
});

test('sin filtros la consulta se mantiene restringida a pacientes sintéticos',async()=>{
 const db={query:jest.fn()
  .mockResolvedValueOnce({rows:[{total:0}]})
  .mockResolvedValueOnce({rows:[]})};
 const result=await createSilService(db).listPatientsDemo();
 expect(result.total).toBe(0);
 const sql=db.query.mock.calls.map(call=>call[0]).join('\n');
 expect(sql).toContain("a.role_code='paciente'");
 expect(sql).toContain("a.email LIKE '%@example.invalid'");
 expect(db.query.mock.calls[1][1]).toEqual([20,0]);
});
