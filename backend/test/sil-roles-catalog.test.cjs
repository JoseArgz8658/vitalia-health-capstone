'use strict';
const express = require('express');
const request = require('supertest');
const {createSilRouter} = require('../dist/sil/router');

const token = 'a'.repeat(64);
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
  test('se requiere token de sesión para consultar',async () => {
    const {app}=setup('operador_laboratorio');
    await request(app).get('/api/sil/catalog').expect(401);
  });
});
