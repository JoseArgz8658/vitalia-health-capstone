const request=require('supertest');
const {createApp}=require('../dist/app');
const {createSilMainService,SilMainAccessDenied}=require('../dist/sil/main-service');

const token='b'.repeat(64);
const bearer={Authorization:'Bearer '+token};
const lab='11111111-1111-4111-8111-111111111111';
const patient='22222222-2222-4222-8222-222222222222';
const order='33333333-3333-4333-8333-333333333333';
const report='44444444-4444-4444-8444-444444444444';
const operator='55555555-5555-4555-8555-555555555555';

function demo(role='operador_laboratorio',authenticated=true){
  const service={
    laboratoriesFor:jest.fn().mockResolvedValue({laboratories:[]}),
    createLaboratory:jest.fn().mockResolvedValue({laboratory:{id:lab}}),
    setReviewPermission:jest.fn().mockResolvedValue({membership:{canReviewReports:true}}),
    reportForReview:jest.fn().mockResolvedValue({fileName:'revision.pdf',bytes:Buffer.from('%PDF-1.4')}),
    grantStaff:jest.fn().mockResolvedValue({membership:{labId:lab}}),
    associatePatient:jest.fn().mockResolvedValue({patientId:patient,linked:true}),
    createOrder:jest.fn().mockResolvedValue({order:{id:order}}),
    listOrders:jest.fn().mockResolvedValue({orders:[]}),
    attachReport:jest.fn().mockResolvedValue({report:{id:report}}),
    publishReport:jest.fn().mockResolvedValue({publication:{orderId:order}}),
    patientProfile:jest.fn().mockResolvedValue({profile:{hasProfile:false}}),
    patientReports:jest.fn().mockResolvedValue({reports:[]}),
    downloadPatientReport:jest.fn().mockResolvedValue({
      fileName:'informe.pdf',bytes:Buffer.from('%PDF-1.4\narchivo')}),
    getPatientReportOverview:jest.fn().mockResolvedValue({reports:[],statistics:[]}),
    askPatientReport:jest.fn().mockResolvedValue({answer:'Ayuda general',source:'catalogo'}),
  };
  const auth={find:jest.fn().mockResolvedValue(authenticated
    ?{id:operator,role,email:'operador@example.invalid'}:null)};
  // createApp(auth,...register..sil(18 posiciones),silMain)
  const application=createApp(auth,...Array(18).fill(undefined),service);
  return {application,service};
}
let previous;
beforeEach(()=>{
  previous=process.env.VITALIA_SIL_MAIN_MODE;
  process.env.VITALIA_SIL_MAIN_MODE='YES';
});
afterEach(()=>{
  if(previous===undefined)delete process.env.VITALIA_SIL_MAIN_MODE;
  else process.env.VITALIA_SIL_MAIN_MODE=previous;
  jest.clearAllMocks();
});

test('sin habilitar MAIN_MODE la API no se monta',async()=>{
  delete process.env.VITALIA_SIL_MAIN_MODE;
  const {application}=demo();
  const r=await request(application).get('/api/sil/main/labs').set(bearer);
  expect(r.status).toBe(404);
});
test('ninguna ruta principal acepta acceso anónimo',async()=>{
  const {application}=demo('administrador',false);
  for(const url of ['/api/sil/main/labs','/api/sil/main/patient/reports']){
    expect((await request(application).get(url).set(bearer)).status).toBe(401);
  }
});
test('paciente no puede crear laboratorios ni órdenes ajenas',async()=>{
  const {application,service}=demo('paciente');
  expect((await request(application).post('/api/sil/main/labs')
    .set(bearer).send({displayName:'Laboratorio privado'})).status).toBe(403);
  expect((await request(application).post('/api/sil/main/labs/'+lab+'/orders')
    .set(bearer).send({patientId:patient,examCodes:['glicemia']})).status).toBe(403);
  expect(service.createOrder).not.toHaveBeenCalled();
});
test('solo administrador habilita un laboratorio o personal',async()=>{
  const {application,service}=demo('administrador');
  expect((await request(application).post('/api/sil/main/labs')
    .set(bearer).send({displayName:'Laboratorio privado'})).status).toBe(201);
  expect(service.createLaboratory).toHaveBeenCalledWith('Laboratorio privado',operator);
  expect((await request(application).post('/api/sil/main/labs/'+lab+'/staff')
    .set(bearer).send({accountId:patient})).status).toBe(201);
  expect(service.grantStaff).toHaveBeenCalledWith(lab,patient,operator);
  expect((await request(application).post('/api/sil/main/labs/'+lab+'/staff')
    .set(bearer).send({accountId:patient,kind:'validator'})).status).toBe(400);
});
test('orden principal exige paciente y prestaciones válidas',async()=>{
  const {application,service}=demo();
  expect((await request(application).post('/api/sil/main/labs/'+lab+'/orders')
    .set(bearer).send({patientId:patient,examCodes:['glicemia']})).status).toBe(201);
  expect(service.createOrder).toHaveBeenCalledWith(lab,patient,['glicemia'],operator);
  for(const body of [
    {patientId:patient,examCodes:['glicemia','glicemia']},
    {patientId:patient,examCodes:['glicemia'],labId:lab},
    {patientId:'x',examCodes:['glicemia']},
  ])expect((await request(application).post('/api/sil/main/labs/'+lab+'/orders')
    .set(bearer).send(body)).status).toBe(400);
});
test('solo administración puede conceder o retirar el permiso por laboratorio',async()=>{
  const path='/api/sil/main/labs/'+lab+'/staff/review-permission';
  const admin=demo('administrador');
  const staff=demo();
  for(const enabled of [true,false]){
    const body={accountId:patient,enabled};
    expect((await request(admin.application).post(path).set(bearer).send(body)).status).toBe(200);
    expect(admin.service.setReviewPermission).toHaveBeenLastCalledWith(lab,patient,operator,enabled);
    expect((await request(staff.application).post(path).set(bearer).send(body)).status).toBe(403);
  }
  expect(staff.service.setReviewPermission).not.toHaveBeenCalled();
});

test('revisión y publicación requieren sesión de operador y permiso del servicio',async()=>{
  const prefix='/api/sil/main/labs/'+lab+'/orders/'+order+'/report';
  const body={operatorReviewConfirmed:true};
  for(const role of ['profesional','administrador','paciente']){
    const other=demo(role);
    expect((await request(other.application).get(prefix+'/file').set(bearer)).status).toBe(403);
    expect((await request(other.application).post(prefix+'/publish').set(bearer).send(body)).status).toBe(403);
    expect(other.service.publishReport).not.toHaveBeenCalled();
  }
  const {application,service}=demo();
  expect((await request(application).get(prefix+'/file').set(bearer)).status).toBe(200);
  expect(service.reportForReview).toHaveBeenCalledWith(lab,order,operator);
  expect((await request(application).post(prefix+'/publish').set(bearer)
    .send({operatorReviewConfirmed:false})).status).toBe(400);
  expect((await request(application).post(prefix+'/publish').set(bearer).send(body)).status).toBe(201);
  expect(service.publishReport).toHaveBeenCalledWith(lab,order,operator);
  service.publishReport.mockRejectedValueOnce(new SilMainAccessDenied());
  expect((await request(application).post(prefix+'/publish').set(bearer).send(body)).status).toBe(403);
});
test('informes del paciente pertenecen a su cuenta y no aceptan id externo',async()=>{
  const {application,service}=demo('paciente');
  expect((await request(application).get('/api/sil/main/patient/reports')
    .set(bearer)).status).toBe(200);
  expect(service.patientReports).toHaveBeenCalledWith(operator);
  expect((await request(application).get('/api/sil/main/patient/reports/'+report+'/file')
    .set(bearer)).status).toBe(200);
  expect(service.downloadPatientReport).toHaveBeenCalledWith(operator,report);
  expect((await request(application).get('/api/sil/main/patient/reports/not-a-uuid/file')
    .set(bearer)).status).toBe(404);
});
test('comparación y chat exigen un paciente autenticado',async()=>{
  const patientApp=demo('paciente');
  expect((await request(patientApp.application).post('/api/sil/main/patient/reports/overview')
    .set(bearer).send({reportIds:[report]})).status).toBe(200);
  expect((await request(patientApp.application).post('/api/sil/main/patient/reports/'+report+'/chat')
    .set(bearer).send({question:'¿Qué mide el examen?'})).status).toBe(200);
  expect((await request(demo('operador_laboratorio').application)
    .post('/api/sil/main/patient/reports/overview')
    .set(bearer).send({reportIds:[report]})).status).toBe(403);
});
test('consulta de informes principales está filtrada por paciente y laboratorio activo',async()=>{
  const query=jest.fn().mockResolvedValue({rows:[]});
  const main=createSilMainService({query});
  await main.patientReports(patient);
  const [sql,values]=query.mock.calls[0];
  expect(sql).toMatch(/p\.active/);
  expect(sql).toMatch(/l\.active/);
  expect(sql).toMatch(/r\.patient_id=\$1/);
  expect(sql).toMatch(/report_published/);
  expect(values).toEqual([patient]);
});
