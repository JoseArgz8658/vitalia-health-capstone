'use strict';
const express=require('express');
const request=require('supertest');
const {createSilPatientRecoveryRouterDemo}=require('../dist/sil/patient-recovery-router-demo');
const {SilRecoveryRejected}=require('../dist/sil/patient-recovery-demo');
const {createRegistrationRouter}=require('../dist/auth/registration-router');
const {createPatientRegistrar}=require('../dist/auth/registration');

const email='persona@example.invalid';
const recoveryKey='a'.repeat(43);
const password='una-clave-sintetica-nueva';
const previous=process.env.VITALIA_SIL_DEMO;
beforeEach(()=>{process.env.VITALIA_SIL_DEMO='YES';});
afterEach(()=>{
  if(previous===undefined)delete process.env.VITALIA_SIL_DEMO;
  else process.env.VITALIA_SIL_DEMO=previous;
});

function setup(role='paciente'){
  const account={id:'00000000-0000-4000-8000-000000000001',role,email};
  const auth={find:jest.fn(async()=>account)};
  const recovery={
    generate:jest.fn(async()=>({recoveryKey})),
    recover:jest.fn(async()=>{}),
  };
  const app=express();
  app.use(express.json());
  app.use('/recovery',createSilPatientRecoveryRouterDemo(auth,recovery));
  return {app,recovery,account,auth};
}
test('solo la sesión de paciente emite una clave tras volver a presentar su contraseña',async()=>{
  const headers={Authorization:'Bearer '+'a'.repeat(64)};
  const patient=setup();
  await request(patient.app).post('/recovery/key').send({currentPassword:password}).expect(401);
  await request(setup('operador_laboratorio').app).post('/recovery/key').set(headers)
    .send({currentPassword:password}).expect(403);
  await request(patient.app).post('/recovery/key').set(headers)
    .send({currentPassword:password,email:'otra@example.invalid'}).expect(400);
  const response=await request(patient.app).post('/recovery/key').set(headers)
    .send({currentPassword:password}).expect(201);
  expect(response.headers['cache-control']).toBe('no-store');
  expect(response.body).toEqual({recoveryKey});
  expect(patient.recovery.generate).toHaveBeenCalledTimes(1);
  expect(patient.recovery.generate).toHaveBeenCalledWith(patient.account,password);
});

test('recuperación pública valida el dominio y responde igual ante claves rechazadas',async()=>{
  const {app,recovery,auth}=setup();
  const payload={email,recoveryKey,password};
  await request(app).post('/recovery/complete').send({...payload,email:'otro@example.com'}).expect(400);
  recovery.recover.mockRejectedValueOnce(new SilRecoveryRejected());
  const rejected=await request(app).post('/recovery/complete').send(payload).expect(422);
  expect(rejected.body).toEqual({error:{code:'RECOVERY_REJECTED'}});
  await request(app).post('/recovery/complete').send(payload).expect(204);
  expect(auth.find).not.toHaveBeenCalled();
  delete process.env.VITALIA_SIL_DEMO;
  await request(app).post('/recovery/complete').send(payload).expect(404);
  expect(recovery.recover).toHaveBeenCalledTimes(2);
});

test('registro local solo crea pacientes ficticios y nunca vincula fichas',async()=>{
  const db={query:jest.fn(async(_sql,args)=>({rows:[{
    id:args[0],email:args[1],role_code:'paciente',created_at:new Date(),
  }]}))};
  const app=express();
  app.use(express.json());
  app.use(createRegistrationRouter(createPatientRegistrar(db,{demoOnly:true})));
  await request(app).post('/register').send({email:'otro@example.com',password}).expect(400);
  await request(app).post('/register').send({email,password,role:'operador_laboratorio'}).expect(400);
  await request(app).post('/register').send({email,password}).expect(202);
  expect(db.query).toHaveBeenCalledTimes(1);
  expect(db.query.mock.calls[0][0]).toMatch(/INSERT INTO public.vitalia_accounts/i);
  expect(db.query.mock.calls[0][1]).not.toContain(password);
});
