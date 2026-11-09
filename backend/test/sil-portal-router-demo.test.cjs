'use strict';
const express=require('express');
const request=require('supertest');
const {createSilPortalRouterDemo}=require('../dist/sil/portal-router-demo');
const operatorId='11111111-1111-4111-8111-111111111111';
const patientId='22222222-2222-4222-8222-222222222222';
const token='a'.repeat(64);
const authHeader={Authorization:'Bearer '+token};
const previousDemo=process.env.VITALIA_SIL_DEMO;
const previousMailbox=process.env.VITALIA_SIL_DEV_MAILBOX;
beforeEach(()=>{
  process.env.VITALIA_SIL_DEMO='YES';
  process.env.VITALIA_SIL_DEV_MAILBOX='YES';
});
afterEach(()=>{
  if(previousDemo===undefined)delete process.env.VITALIA_SIL_DEMO;
  else process.env.VITALIA_SIL_DEMO=previousDemo;
  if(previousMailbox===undefined)delete process.env.VITALIA_SIL_DEV_MAILBOX;
  else process.env.VITALIA_SIL_DEV_MAILBOX=previousMailbox;
});
function setup(role='operador_laboratorio'){
 const portal={
  provision:jest.fn(async()=>({patient:{id:patientId},portalStatus:'pending'})),
  status:jest.fn(async()=>({patient:{id:patientId},canInvite:true})),
  invite:jest.fn(async()=>({invitation:{id:patientId,delivery:'simulated_outbox'},
    handoffCode:'x'.repeat(12)})),
  demoMailbox:jest.fn(()=>({emailCode:'y'.repeat(12)})),
  activate:jest.fn(async()=>({activated:true,loginRequired:true})),
 };
 const auth={find:jest.fn(async()=>({id:operatorId,role}))};
 const app=express();
 app.use(express.json());
 app.use('/api/sil',createSilPortalRouterDemo(auth,portal));
 return {app,portal,auth};
}
const patient={
 email:'nuevo@example.invalid',givenNames:'Paciente',familyNames:'Ficticio',
 birthDate:'1990-01-01',sexForReference:'not_specified',syntheticConfirmed:true,
};

test('solo operador puede dar de alta cuenta sintética pendiente',async()=>{
 const {app,portal}=setup();
 const good=await request(app).post('/api/sil/portal/patients')
   .set(authHeader).send(patient);
 expect(good.status).toBe(201);
 expect(good.body.portalStatus).toBe('pending');
 expect(portal.provision).toHaveBeenCalledWith(
  expect.objectContaining({email:'nuevo@example.invalid'}),operatorId);
 for(const bad of [
  {...patient,email:'someone@gmail.com'},
  {...patient,role:'administrador'},
  {...patient,syntheticConfirmed:false},
  {...patient,birthDate:'not-a-date'},
 ]) {
  const r=await request(app).post('/api/sil/portal/patients')
    .set(authHeader).send(bad);
  expect(r.status).toBe(400);
 }
 expect(portal.provision).toHaveBeenCalledTimes(1);
});

test.each(['administrador','paciente','profesional'])(
 '%s no puede consultar destinatarios ni emitir invitaciones',
 async role=>{
 const {app,portal}=setup(role);
 const get=await request(app).get('/api/sil/portal/patients/'+patientId)
    .set(authHeader);
 const post=await request(app)
    .post('/api/sil/portal/patients/'+patientId+'/invitations')
    .set(authHeader).send({contactConfirmed:true,identityChecked:true});
 expect(get.status).toBe(403);
 expect(post.status).toBe(403);
 expect(portal.invite).not.toHaveBeenCalled();
});

test('la invitación exige dos confirmaciones expresas',async()=>{
 const {app,portal}=setup();
 const path='/api/sil/portal/patients/'+patientId+'/invitations';
 for(const value of [
   {},
   {contactConfirmed:true,identityChecked:false},
   {contactConfirmed:false,identityChecked:true},
   {contactConfirmed:true,identityChecked:true,email:'otro@example.invalid'},
 ]) {
  const res=await request(app).post(path).set(authHeader).send(value);
  expect(res.status).toBe(400);
 }
 expect(portal.invite).not.toHaveBeenCalled();
 const result=await request(app).post(path).set(authHeader)
  .send({contactConfirmed:true,identityChecked:true});
 expect(result.status).toBe(201);
 expect(portal.invite).toHaveBeenCalledWith(patientId,operatorId,
  {contactConfirmed:true,identityChecked:true});
 expect(result.body).not.toHaveProperty('emailCode');
 expect(result.body.handoffCode).toHaveLength(24);
});

test('activación pública exige códigos, nueva clave y confirmación',async()=>{
 const {app,portal}=setup();
 const valid={email:'nuevo@example.invalid',emailCode:'a'.repeat(12),
   handoffCode:'b'.repeat(12),password:'UnaClaveLargaUnica2026',
   confirmedDetails:true};
 for(const invalid of [
  {...valid,confirmedDetails:false},
  {...valid,password:'corta'},
  {...valid,handoffCode:'bad'},
  {...valid,role:'administrador'},
 ]) {
  const res=await request(app).post('/api/sil/portal/activate').send(invalid);
  expect(res.status).toBe(400);
 }
 expect(portal.activate).not.toHaveBeenCalled();
 const accepted=await request(app).post('/api/sil/portal/activate').send(valid);
 expect(accepted.status).toBe(200);
 expect(accepted.body.activated).toBe(true);
});

test('sin DEMO ni buzón explícito, no existe la activación pública',async()=>{
 const {app,portal}=setup();
 delete process.env.VITALIA_SIL_DEMO;
 const r=await request(app).post('/api/sil/portal/activate')
  .send({email:'nuevo@example.invalid'});
 expect(r.status).toBe(404);
 expect(portal.activate).not.toHaveBeenCalled();
 process.env.VITALIA_SIL_DEMO='YES';
 delete process.env.VITALIA_SIL_DEV_MAILBOX;
 const mailbox=await request(app).get('/api/sil/portal/demo-mailbox')
  .query({email:'nuevo@example.invalid'});
 expect(mailbox.status).toBe(404);
 expect(portal.demoMailbox).not.toHaveBeenCalled();
});

test('el portal DEMO no intercepta órdenes, informes ni rutas SIL existentes',async()=>{
 const {app}=setup();
 app.get('/api/sil/patient/reports',(_req,res)=>res.json({reports:[]}));
 app.get('/api/sil/orders',(_req,res)=>res.json({orders:[]}));
 const reports=await request(app).get('/api/sil/patient/reports');
 const orders=await request(app).get('/api/sil/orders');
 expect(reports.status).toBe(200);
 expect(orders.status).toBe(200);
 expect(reports.body).toEqual({reports:[]});
 expect(orders.body).toEqual({orders:[]});
});
