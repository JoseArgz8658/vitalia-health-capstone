'use strict';
const express = require('express');
const request = require('supertest');
const {createSilRouter} = require('../dist/sil/router');

const token = 'a'.repeat(64);
const previousDemo = process.env.VITALIA_SIL_DEMO;
beforeAll(() => { process.env.VITALIA_SIL_DEMO = 'YES'; });
afterAll(() => {
  if(previousDemo === undefined) delete process.env.VITALIA_SIL_DEMO;
  else process.env.VITALIA_SIL_DEMO=previousDemo;
});
const patientId = '11111111-1111-4111-8111-111111111111';
const actorId = '22222222-2222-4222-8222-222222222222';

function setup(role) {
  const auth = {
    find: jest.fn(async () => ({
      id: actorId, email: 'usuario@example.invalid',
      role, createdAt: new Date(),
    })),
  };
  const service = {
    catalog: jest.fn(async () => ({exams: []})),
    summary: jest.fn(async () => ({summary:{total:2,pendingSample:1,pendingResults:1,pendingReview:0,patients:1}})),
    listOrders: jest.fn(async () => ({orders: []})),
    findPatientByEmail: jest.fn(async (email) => ({id: patientId, email})),
    createOrder: jest.fn(async (_patient,_actor,codes) => ({
      id:actorId,status:'registered',examCodes:codes,
    })),
    registerSample: jest.fn(async () => ({id: actorId})),
    recordResults: jest.fn(async () => ({orderId:actorId,status:'results_recorded'})),
    recordManualResults: jest.fn(async () => ({orderId:actorId,status:'results_recorded'})),
    simulateAnalyzer: jest.fn(async () => ({orderId:actorId,count:9})),
    getOrder: jest.fn(async () => ({order:{id:actorId},exams:[],results:[]})),
    reviewOrder: jest.fn(async (_order,_actor,decision) => ({orderId:actorId,decision})),
    attachExternalReport: jest.fn(async () => ({id:actorId,status:'report_attached'})),
    publishExternalReport: jest.fn(async () => ({status:'report_published'})),
    listPatientReports: jest.fn(async () => ({reports:[{id:actorId}]})),
    downloadPatientReport: jest.fn(async () => ({
      fileName:'informe.pdf',bytes:Buffer.from('%PDF-1.4\\n%%EOF'),
    })),
  };
  const app = express();
  app.use(express.json());
  app.use('/api/sil', createSilRouter(auth,service));
  return {app,service};
}
function authorized(req) {
  return req.set('Authorization','Bearer '+token);
}

describe('SIL: permisos y catálogo multiprestación', () => {
  test('operador recibe indicadores globales y listado filtrado',async () => {
    const {app,service}=setup('operador_laboratorio');
    const summary=await authorized(request(app).get('/api/sil/summary')).expect(200);
    expect(summary.body.summary.total).toBe(2);
    await authorized(request(app).get('/api/sil/orders')
      .query({limit:10,offset:0,status:'registered',search:'paciente@example.invalid'}))
      .expect(200);
    expect(service.listOrders).toHaveBeenCalledWith(10,0,'registered','paciente@example.invalid');
  });
  test('rechaza filtros arbitrarios y estados desconocidos',async () => {
    const {app,service}=setup('operador_laboratorio');
    await authorized(request(app).get('/api/sil/orders')
      .query({status:'published'})).expect(400);
    await authorized(request(app).get('/api/sil/orders')
      .query({unknown:'value'})).expect(400);
    await authorized(request(app).get('/api/sil/orders')
      .query({limit:10000})).expect(400);
    expect(service.listOrders).not.toHaveBeenCalled();
  });
  test('administrador consulta catálogo pero no registra órdenes',async () => {
    const {app,service}=setup('administrador');
    await authorized(request(app).get('/api/sil/catalog')).expect(200);
    await authorized(request(app).post('/api/sil/orders'))
      .send({patientId,examCodes:['hemograma']}).expect(403);
    expect(service.createOrder).not.toHaveBeenCalled();
  });
  test('operador registra una orden con dos exámenes y paciente por correo',async () => {
    const {app,service}=setup('operador_laboratorio');
    await authorized(request(app).get('/api/sil/patients')
      .query({email:'paciente@example.invalid'})).expect(200);
    expect(service.findPatientByEmail).toHaveBeenCalledWith('paciente@example.invalid');
    await authorized(request(app).post('/api/sil/orders'))
      .send({patientId,examCodes:['hemograma','perfil_lipidico']}).expect(201);
    expect(service.createOrder).toHaveBeenCalledWith(patientId,actorId,
      ['hemograma','perfil_lipidico']);
  });
  test('recepción de tubo requiere código permitido y registra actor',async () => {
    const {app,service}=setup('operador_laboratorio');
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/sample'))
      .send({barcode:'EDTA-0001',containerCode:'edta'}).expect(201);
    expect(service.registerSample).toHaveBeenCalledWith(
      actorId,'EDTA-0001','edta',actorId,undefined);
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/sample'))
      .send({barcode:'BAD-0001',containerCode:'historical'}).expect(400);
  });
  test('solo operador puede registrar valores manuales sin unidades suministradas',async () => {
    const {app,service}=setup('operador_laboratorio');
    const results=[{examCode:'hemograma',analyte:'Hemoglobina',numericValue:13.2}];
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/results'))
      .send({results}).expect(201);
    expect(service.recordManualResults).toHaveBeenCalledWith(actorId,results,actorId);
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/results'))
      .send({results:[{...results[0],unit:'g/dL'}]}).expect(400);
    expect(service.recordManualResults).toHaveBeenCalledTimes(1);
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/results'))
      .send({results:[{...results[0],numericValue:NaN}]}).expect(400);
  });
  test('operador no puede duplicar prestaciones',async () => {
    const {app,service}=setup('operador_laboratorio');
    await authorized(request(app).post('/api/sil/orders'))
      .send({patientId,examCodes:['hemograma','hemograma']}).expect(400);
    expect(service.createOrder).not.toHaveBeenCalled();
  });
  test('paciente no accede a datos de laboratorio',async () => {
    const {app}=setup('paciente');
    await authorized(request(app).get('/api/sil/catalog')).expect(403);
    await authorized(request(app).get('/api/sil/orders')).expect(403);
  });
  test('responsable de validación consulta pero no procesa',async () => {
    const {app,service}=setup('validador_laboratorio');
    await authorized(request(app).get('/api/sil/orders')).expect(200);
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/simulate'))
      .send({}).expect(403);
    expect(service.simulateAnalyzer).not.toHaveBeenCalled();
  });
  test('solo validador puede aprobar o devolver una orden',async () => {
    const review={decision:'approve',note:'Valores comprobados en revisión interna.'};
    const validator=setup('validador_laboratorio');
    await authorized(request(validator.app).post('/api/sil/orders/'+actorId+'/review'))
      .send(review).expect(201);
    expect(validator.service.reviewOrder).toHaveBeenCalledWith(
      actorId,actorId,'approve',review.note);

    const operator=setup('operador_laboratorio');
    await authorized(request(operator.app).post('/api/sil/orders/'+actorId+'/review'))
      .send(review).expect(403);
    const admin=setup('administrador');
    await authorized(request(admin.app).post('/api/sil/orders/'+actorId+'/review'))
      .send(review).expect(403);
    expect(operator.service.reviewOrder).not.toHaveBeenCalled();
    expect(admin.service.reviewOrder).not.toHaveBeenCalled();
    await authorized(request(validator.app).post('/api/sil/orders/'+actorId+'/sample'))
      .send({barcode:'TUBO-0001',containerCode:'edta'}).expect(403);
  });
  test('devolución requiere motivo suficiente y rechaza parámetros extra',async () => {
    const {app,service}=setup('validador_laboratorio');
    for(const payload of [
      {decision:'return',note:''},
      {decision:'return',note:'muy corto'},
      {decision:'unknown',note:'Razón extensa'},
      {decision:'approve',note:'ok',overrideStatus:'review_approved'},
    ]) {
      await authorized(request(app).post('/api/sil/orders/'+actorId+'/review'))
        .send(payload).expect(400);
    }
    expect(service.reviewOrder).not.toHaveBeenCalled();
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/review'))
      .send({decision:'return',note:'Revisar valores del hemograma.'}).expect(201);
    expect(service.reviewOrder).toHaveBeenCalledWith(
      actorId,actorId,'return','Revisar valores del hemograma.');
  });
  test('operador incorpora informe PDF externo y lo publica con confirmación',async () => {
    const {app,service}=setup('operador_laboratorio');
    const pdf=Buffer.from('%PDF-1.4\\n%%EOF');
    const res=await authorized(request(app).post('/api/sil/orders/'+actorId+'/report'))
      .set('Content-Type','application/pdf')
      .set('x-report-filename','informe.pdf')
      .set('x-report-issuer','Laboratorio ejemplo')
      .set('x-report-authorization-ref','LAB-REFERENCIA-01')
      .set('x-report-authorized-at','2026-11-01T12:00:00Z')
      .set('x-report-patient-confirmed','true')
      .set('x-report-externally-authorized','true')
      .send(pdf).expect(201);
    expect(res.body.report.status).toBe('report_attached');
    expect(service.attachExternalReport).toHaveBeenCalled();
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/report/publish'))
      .send({}).expect(201);
    expect(service.publishExternalReport).toHaveBeenCalledWith(actorId,actorId);
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/report/publish'))
      .send({clinicalAuthorization:true}).expect(400);
  });
  test('PDF externo exige autorización, asociación y permisos',async () => {
    const payload=Buffer.from('%PDF-1.4\\n%%EOF');
    const {app,service}=setup('operador_laboratorio');
    await authorized(request(app).post('/api/sil/orders/'+actorId+'/report'))
      .set('Content-Type','application/pdf')
      .set('x-report-filename','informe.pdf')
      .set('x-report-issuer','Laboratorio ejemplo')
      .set('x-report-authorization-ref','REF-01')
      .set('x-report-authorized-at','2026-11-01')
      .set('x-report-externally-authorized','true')
      .send(payload).expect(400);
    expect(service.attachExternalReport).not.toHaveBeenCalled();
    await authorized(request(setup('validador_laboratorio').app)
      .post('/api/sil/orders/'+actorId+'/report/publish'))
      .send({}).expect(403);
  });
  test('solo paciente puede consultar sus informes y descargar archivo',async () => {
    const patient=setup('paciente');
    const listed=await authorized(request(patient.app)
      .get('/api/sil/patient/reports')).expect(200);
    expect(listed.body.reports.length).toBe(1);
    const downloaded=await authorized(request(patient.app)
      .get('/api/sil/patient/reports/'+actorId+'/file')).expect(200);
    expect(downloaded.headers['content-type']).toContain('application/pdf');
    expect(patient.service.downloadPatientReport).toHaveBeenCalledWith(actorId,actorId);
    await authorized(request(setup('administrador').app)
      .get('/api/sil/patient/reports')).expect(403);
    await authorized(request(patient.app).get('/api/sil/orders')).expect(403);
  });
  test('se requiere token de sesión para consultar',async () => {
    const {app}=setup('operador_laboratorio');
    await request(app).get('/api/sil/catalog').expect(401);
  });
});
