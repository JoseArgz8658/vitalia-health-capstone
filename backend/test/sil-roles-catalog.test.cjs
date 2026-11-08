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
    listOrders: jest.fn(async () => ({orders: []})),
    findPatientByEmail: jest.fn(async (email) => ({id: patientId, email})),
    createOrder: jest.fn(async (_patient,_actor,codes) => ({
      id:actorId,status:'registered',examCodes:codes,
    })),
    registerSample: jest.fn(async () => ({id: actorId})),
    recordResults: jest.fn(async () => ({orderId:actorId,status:'results_recorded'})),
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
