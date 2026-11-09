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

function setup(role, options) {
  const auth = {
    find: jest.fn(async () => ({
      id: actorId, email: 'usuario@example.invalid',
      role, createdAt: new Date(),
    })),
  };
  const service = {
    catalog: jest.fn(async () => ({exams: []})),
    branches: jest.fn(async () => ({branches:[{code:'perez-vitacura',
      branchName:'Vitacura',laboratoryName:'Laboratorio Pérez (ficticio)'}]})),
    patientProfileDemo: jest.fn(async () => ({patient:{id:patientId,
      email:'paciente.sil@example.invalid',syntheticIdentifier:'DEMO-0001'}})),
    savePatientProfileDemo: jest.fn(async () => ({patient:{id:patientId,
      email:'paciente.sil@example.invalid',syntheticIdentifier:'DEMO-0001'}})),
    summary: jest.fn(async () => ({summary:{total:2,pendingSample:1,pendingResults:1,pendingReview:0,patients:1}})),
    listOrders: jest.fn(async () => ({orders: []})),
    findPatientByEmail: jest.fn(async (email) => ({id: patientId, email})),
    createOrder: jest.fn(async (_patient,_actor,codes) => ({
      id:actorId,status:'registered',examCodes:codes,
    })),
    registerSample: jest.fn(async () => ({id: actorId})),
    recordResults: jest.fn(async () => ({orderId:actorId,status:'results_recorded'})),
    recordManualResults: jest.fn(async () => ({orderId:actorId,status:'results_recorded'})),
    previewMedicalRequest: jest.fn(async()=>({
      state:'requires_operator_review',confirmed:false,previewToken:actorId,
      suggestedExams:[{code:'glicemia',name:'Glicemia'}],
    })),
    downloadMedicalRequest: jest.fn(async()=>({
      fileName:'solicitud-demo.pdf',bytes:Buffer.from('%PDF-1.4\\n%%EOF'),
    })),
    confirmMedicalRequest: jest.fn(async()=>({
      order:{id:actorId,orderNumber:'VH-000125',status:'registered'},
      requestId:patientId,
    })),
    previewResultsFile: jest.fn(async()=>({
      state:'ready',items:[],warnings:[],generatedBy:'ai_draft',confirmed:false,
      previewToken:actorId,
    })),
    simulateAnalyzer: jest.fn(async () => ({orderId:actorId,count:9})),
    getOrder: jest.fn(async () => ({order:{id:actorId},exams:[],results:[]})),
    reviewOrder: jest.fn(async (_order,_actor,decision) => ({orderId:actorId,decision})),
    attachExternalReport: jest.fn(async () => ({id:actorId,status:'report_attached'})),
    publishExternalReport: jest.fn(async () => ({status:'report_published'})),
    listPatientReports: jest.fn(async () => ({reports:[{id:actorId}]})),
    askPatientReport: jest.fn(async () => ({answer:'Concepto educativo de prueba.',source:'catalogo',approved:false})),
    downloadPatientReport: jest.fn(async () => ({
      fileName:'informe.pdf',bytes:Buffer.from('%PDF-1.4\\n%%EOF'),
    })),
  };
  const app = express();
  app.use(express.json());
  app.use('/api/sil', createSilRouter(auth,service,options));
  return {app,service};
}
function authorized(req) {
  return req.set('Authorization','Bearer '+token);
}

describe('SIL: permisos y catálogo multiprestación', () => {
  test('recepción de solicitudes requiere operador y controles de ingreso',async()=>{
    const operator=setup('operador_laboratorio');
    const file=Buffer.from('%PDF-1.4\nsolicitud ficticia\n%%EOF');
    const preview=await authorized(request(operator.app)
      .post('/api/sil/medical-requests/preview')
      .set('Content-Type','application/pdf')
      .set('x-request-patient-email','paciente.sil@example.invalid')
      .set('x-request-filename','solicitud.pdf')
      .send(file)).expect(200);
    expect(preview.body.preview.confirmed).toBe(false);
    expect(operator.service.previewMedicalRequest).toHaveBeenCalledWith(
      actorId,'paciente.sil@example.invalid','solicitud.pdf',expect.any(Buffer));
    const payload={
      previewToken:actorId,patientId,branchCode:'perez-las-condes',
      examCodes:['glicemia','hba1c'],
      documentReference:'SOL-DEMO-01',
      prescriberName:'Profesional Ficticio',
      requestDate:'2026-11-01',verified:true,
    };
    await authorized(request(operator.app)
      .post('/api/sil/medical-requests/confirm')
      .send(payload)).expect(201);
    expect(operator.service.confirmMedicalRequest).toHaveBeenCalledWith(
      actorId,payload);
    await authorized(request(operator.app)
      .post('/api/sil/medical-requests/confirm')
      .send({...payload,verified:false})).expect(400);
    await authorized(request(operator.app)
      .post('/api/sil/medical-requests/confirm')
      .send({...payload,examCodes:['glicemia','glicemia']})).expect(400);
    await authorized(request(operator.app)
      .post('/api/sil/medical-requests/confirm')
      .send({...payload,role:'admin'})).expect(400);
    await authorized(request(operator.app)
      .post('/api/sil/medical-requests/preview')
      .send({email:'paciente.sil@example.invalid'})).expect(400);
    for(const role of ['paciente','administrador','validador_laboratorio']){
      const restricted=setup(role);
      await authorized(request(restricted.app)
        .post('/api/sil/medical-requests/confirm')
        .send(payload)).expect(403);
      await authorized(request(restricted.app)
        .post('/api/sil/medical-requests/preview')
        .set('Content-Type','application/pdf')
        .set('x-request-patient-email','paciente.sil@example.invalid')
        .set('x-request-filename','solicitud.pdf')
        .send(file)).expect(403);
      expect(restricted.service.confirmMedicalRequest).not.toHaveBeenCalled();
    }
  });
  test('solo operador puede consultar el PDF original de solicitud',async()=>{
    const file='/api/sil/orders/'+actorId+'/medical-request/file';
    const operator=setup('operador_laboratorio');
    const response=await authorized(request(operator.app).get(file)).expect(200);
    expect(response.headers['content-type']).toMatch(/application\/pdf/);
    expect(response.headers['cache-control']).toContain('no-store');
    expect(operator.service.downloadMedicalRequest).toHaveBeenCalledWith(actorId,actorId);
    for(const role of ['paciente','administrador','validador_laboratorio']){
      const denied=setup(role);
      await authorized(request(denied.app).get(file)).expect(403);
      expect(denied.service.downloadMedicalRequest).not.toHaveBeenCalled();
    }
  });
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
  test('solo operador carga PDF a vista previa sin persistir resultados',async()=>{
    const operator=setup('operador_laboratorio');
    const payload=Buffer.from('%PDF-1.4\\n%%EOF');
    const path='/api/sil/orders/'+actorId+'/results/preview';
    const response=await authorized(request(operator.app).post(path)
      .set('Content-Type','application/pdf')).send(payload).expect(200);
    expect(response.body.preview.confirmed).toBe(false);
    expect(operator.service.previewResultsFile).toHaveBeenCalledWith(
      actorId,expect.any(Buffer),actorId);
    expect(operator.service.recordManualResults).not.toHaveBeenCalled();
    await authorized(request(operator.app).post(path)
      .send({fileName:'fake.pdf'})).expect(400);
    const validator=setup('validador_laboratorio');
    await authorized(request(validator.app).post(path)
      .set('Content-Type','application/pdf')).send(payload).expect(403);
    const patient=setup('paciente');
    await authorized(request(patient.app).post(path)
      .set('Content-Type','application/pdf')).send(payload).expect(403);
    const results=[{examCode:'glicemia',analyte:'Glucosa',numericValue:91}];
    await authorized(request(operator.app).post('/api/sil/orders/'+actorId+'/results')
      .send({results,previewToken:actorId})).expect(201);
    expect(operator.service.recordManualResults).toHaveBeenLastCalledWith(
      actorId,results,actorId,actorId);
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
  test('el rol retirado, el operador sin permiso y el administrador no pueden revisar',async () => {
    for(const role of ['validador_laboratorio','operador_laboratorio','administrador']){
      const {app,service}=setup(role);
      await authorized(request(app).post('/api/sil/orders/'+actorId+'/review'))
        .send({decision:'approve'}).expect(403);
      expect(service.reviewOrder).not.toHaveBeenCalled();
    }
    await authorized(request(setup('validador_laboratorio').app)
      .get('/api/sil/orders')).expect(403);
  });
  test('solo el operador autorizado puede revisar en el entorno demo',async () => {
    const reviewPath='/api/sil/orders/'+actorId+'/review';
    const approved=setup('operador_laboratorio',{demoReviewOperatorId:actorId});
    const other=setup('operador_laboratorio',{demoReviewOperatorId:patientId});
    const granted=await authorized(request(approved.app).get('/api/sil/summary')).expect(200);
    expect(granted.body.permissions.reviewResults).toBe(true);
    await authorized(request(approved.app).post(reviewPath))
      .send({decision:'return',note:'Cotejar los valores del documento.'}).expect(201);
    expect(approved.service.reviewOrder).toHaveBeenCalledWith(
      actorId,actorId,'return','Cotejar los valores del documento.');
    await authorized(request(other.app).post(reviewPath)).send({decision:'approve'}).expect(403);
    expect(other.service.reviewOrder).not.toHaveBeenCalled();
    const previous=process.env.VITALIA_SIL_DEMO;
    try {
      delete process.env.VITALIA_SIL_DEMO;
      const denied=await authorized(request(approved.app).get('/api/sil/summary')).expect(200);
      expect(denied.body.permissions.reviewResults).toBe(false);
      await authorized(request(approved.app).post(reviewPath)).send({decision:'approve'}).expect(403);
    } finally {
      process.env.VITALIA_SIL_DEMO=previous;
    }
  });
  test('devolución requiere motivo suficiente y rechaza parámetros extra',async () => {
    const {app,service}=setup('operador_laboratorio',{demoReviewOperatorId:actorId});
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
  test('el operador usa solo sucursales y fichas sintéticas',async () => {
    const operator=setup('operador_laboratorio');
    const branches=await authorized(request(operator.app)
      .get('/api/sil/branches')).expect(200);
    expect(branches.body.branches[0].code).toBe('perez-vitacura');
    await authorized(request(operator.app)
      .get('/api/sil/patients/profile')
      .query({email:'paciente.sil@example.invalid'})).expect(200);
    const demo={
      email:'paciente.sil@example.invalid',
      syntheticIdentifier:'DEMO-0001',
      givenNames:'Paciente Ficticio',
      familyNames:'Prueba',
      birthDate:'1990-01-01',
      sexForReference:'not_specified',
      contactPhoneDemo:'000000000',
      syntheticConfirmed:true,
    };
    await authorized(request(operator.app)
      .post('/api/sil/patients/profile')).send(demo).expect(200);
    expect(operator.service.savePatientProfileDemo).toHaveBeenCalled();
    const {syntheticIdentifier,...withoutId}=demo;
    await authorized(request(operator.app)
      .post('/api/sil/patients/profile')).send(withoutId).expect(200);
    await authorized(request(operator.app)
      .post('/api/sil/patients/profile'))
      .send({...demo,email:'persona@gmail.com'}).expect(400);
    await authorized(request(operator.app)
      .post('/api/sil/patients/profile'))
      .send({...demo,syntheticIdentifier:'11111111-1'}).expect(400);
    await authorized(request(operator.app)
      .post('/api/sil/patients/profile'))
      .send({...demo,syntheticConfirmed:false}).expect(400);
    await authorized(request(setup('validador_laboratorio').app)
      .post('/api/sil/patients/profile')).send(demo).expect(403);
    await authorized(request(setup('paciente').app)
      .get('/api/sil/patients/profile')
      .query({email:'paciente.sil@example.invalid'})).expect(403);
  });
  test('operador incorpora informe PDF externo y lo publica con confirmación',async () => {
    const {app,service}=setup('operador_laboratorio');
    const pdf=Buffer.from('%PDF-1.4\\n%%EOF');
    const res=await authorized(request(app).post('/api/sil/orders/'+actorId+'/report'))
      .set('Content-Type','application/pdf')
      .set('x-report-filename','informe.pdf')
      .set('x-report-branch-code','perez-vitacura')
      .set('x-report-authorized-professional','Profesional Ficticio')
      .set('x-report-patient-identifier','DEMO-0001')
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
      .set('x-report-branch-code','perez-vitacura')
      .set('x-report-authorized-professional','Profesional Ficticio')
      .set('x-report-patient-identifier','DEMO-0001')
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
  test('paciente consulta IA solo sobre su informe publicado con sesión',async () => {
    const patient=setup('paciente');
    const path='/api/sil/patient/reports/'+actorId+'/chat';
    const answer=await authorized(request(patient.app).post(path))
      .send({question:'¿Qué es la glicemia?'}).expect(200);
    expect(answer.body.response.answer).toContain('educativo');
    expect(patient.service.askPatientReport).toHaveBeenCalledWith(
      actorId,actorId,'¿Qué es la glicemia?');
    await authorized(request(patient.app).post(path))
      .send({question:'a'}).expect(400);
    await authorized(request(patient.app).post(path))
      .send({question:'¿Qué es la glicemia?',patientId}).expect(400);
    await authorized(request(setup('operador_laboratorio').app).post(path))
      .send({question:'¿Qué es la glicemia?'}).expect(403);
    await request(patient.app).post(path)
      .send({question:'¿Qué es la glicemia?'}).expect(401);
  });
  test('se requiere token de sesión para consultar',async () => {
    const {app}=setup('operador_laboratorio');
    await request(app).get('/api/sil/catalog').expect(401);
  });
});
