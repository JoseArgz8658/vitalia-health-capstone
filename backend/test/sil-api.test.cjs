const request=require('supertest');
const {createApp}=require('../dist/app');
const id='22222222-2222-4222-8222-222222222222';
const patientId='33333333-3333-4333-8333-333333333333';
const token='a'.repeat(64);
const sample={id,orderId:id,barcode:'LAB-DEMO-001'};
const service={
 createOrder:jest.fn().mockResolvedValue({id,status:'registered'}),
 registerSample:jest.fn().mockResolvedValue(sample),
 recordResults:jest.fn().mockResolvedValue({orderId:id,status:'results_recorded',count:1,synthetic:true}),
 getOrder:jest.fn().mockResolvedValue({order:{id,status:'registered'},sample:null,results:[]}),
};
function app(role='administrador',hasSession=true) {
 const auth={find:jest.fn().mockResolvedValue(hasSession?
  {id:'11111111-1111-4111-8111-111111111111',role}:null)};
 // SilServices es el último parámetro de createApp.
 return createApp(auth,...Array(17).fill(undefined),service);
}
const bearer={Authorization:'Bearer '+token};
beforeEach(()=>jest.clearAllMocks());
test('acceso al SIL exige sesión válida',async()=>{
 expect((await request(app()).post('/api/sil/orders').send({patientId,examCode:'hemograma'})).status).toBe(401);
 expect((await request(app('administrador',false)).post('/api/sil/orders')
  .set(bearer).send({patientId,examCode:'hemograma'})).status).toBe(401);
 expect(service.createOrder).not.toHaveBeenCalled();
});
test.each(['paciente','profesional'])('%s no puede registrar órdenes',async role=>{
 expect((await request(app(role)).post('/api/sil/orders').set(bearer)
  .send({patientId,examCode:'hemograma'})).status).toBe(403);
 expect(service.createOrder).not.toHaveBeenCalled();
});
test('administrador crea orden de hemograma sintético',async()=>{
 const res=await request(app()).post('/api/sil/orders').set(bearer)
  .send({patientId,examCode:'hemograma'});
 expect(res.status).toBe(201);
 expect(service.createOrder).toHaveBeenCalledWith(patientId,'11111111-1111-4111-8111-111111111111');
});
test('no admite adjudicar roles ni exámenes no soportados',async()=>{
 for(const value of [
  {patientId,examCode:'hemograma',role:'administrador'},
  {patientId,examCode:'perfil_lipidico'},
  {patientId:'no-es-uuid',examCode:'hemograma'},
 ]) {
  const res=await request(app()).post('/api/sil/orders').set(bearer).send(value);
  expect(res.status).toBe(400);
 }
 expect(service.createOrder).not.toHaveBeenCalled();
});
test('registrar muestra requiere código válido',async()=>{
 const res=await request(app()).post('/api/sil/orders/'+id+'/sample').set(bearer)
  .send({barcode:'LAB-DEMO-001'});
 expect(res.status).toBe(201);
 expect(service.registerSample).toHaveBeenCalledWith(id,'LAB-DEMO-001');
 expect((await request(app()).post('/api/sil/orders/'+id+'/sample').set(bearer)
  .send({barcode:'abc/def'})).status).toBe(400);
});
test('resultados numéricos sintéticos válidos',async()=>{
 const results=[{analyte:'Hemoglobina',numericValue:13.2,unit:'g/dL',
  referenceMin:12,referenceMax:16}];
 const res=await request(app()).post('/api/sil/orders/'+id+'/results').set(bearer).send({results});
 expect(res.status).toBe(201);
 expect(service.recordResults).toHaveBeenCalledWith(id,results);
});
test('rechaza analitos repetidos, valores inválidos y rangos invertidos',async()=>{
 for(const results of [
  [{analyte:'H',numericValue:'14',unit:'g/dL'}],
  [{analyte:'H',numericValue:14,unit:'g/dL',referenceMin:16,referenceMax:12}],
  [{analyte:'H',numericValue:14,unit:'g/dL'},{analyte:'h',numericValue:14,unit:'g/dL'}],
 ]) expect((await request(app()).post('/api/sil/orders/'+id+'/results')
   .set(bearer).send({results})).status).toBe(400);
 expect(service.recordResults).not.toHaveBeenCalled();
});
test('consulta admin ve estado y no expone datos a paciente',async()=>{
 expect((await request(app()).get('/api/sil/orders/'+id).set(bearer)).status).toBe(200);
 expect((await request(app('paciente')).get('/api/sil/orders/'+id).set(bearer)).status).toBe(403);
});
