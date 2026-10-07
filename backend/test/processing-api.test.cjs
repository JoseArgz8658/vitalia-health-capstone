const request=require('supertest');
const {createApp}=require('../dist/app');
const {createProcessingService}=require('../dist/processing/service');
const token='a'.repeat(64),id='22222222-2222-4222-8222-222222222222';
const account={id:'11111111-1111-4111-8111-111111111111',role:'paciente'};
function setup(user=account){
 let job=null;
 const query=jest.fn(async(sql,args)=>{
  if(sql.startsWith('SELECT id FROM'))return {rows:args[0]===id&&args[1]===account.id?[{id}]:[]};
  if(sql.startsWith('INSERT INTO')){if(job)return {rows:[]};job={id:args[0],status:'queued',created_at:new Date(),started_at:null,finished_at:null};return {rows:[{id:job.id}]};}
  if(sql.startsWith('SELECT created_at FROM public.vitalia_professional_reviews'))return {rows:[]};
  if(sql.startsWith('SELECT p.id'))return {rows:job?[job]:[]};
  throw new Error('unexpected SQL');
 });
 return {app:createApp({find:async()=>user},undefined,undefined,createProcessingService({query})),query,setJob:value=>{job=value;}};
}
const api=(app,method='get',doc=id)=>request(app)[method](`/api/documents/${doc}/processing`).set('Authorization',`Bearer ${token}`);
test('sin token o sesión no consulta datos',async()=>{
 const x=setup();expect((await request(x.app).get(`/api/documents/${id}/processing`)).status).toBe(401);expect(x.query).not.toHaveBeenCalled();
 const y=setup(null);expect((await api(y.app)).status).toBe(401);expect(y.query).not.toHaveBeenCalled();
});
test.each(['profesional','administrador'])('rol %s no solicita ni consulta',async role=>{
 const x=setup({...account,role});for(const method of ['get','post'])expect((await api(x.app,method)).status).toBe(403);expect(x.query).not.toHaveBeenCalled();
});
test('documento ajeno e inexistente responden 404 sin reserva',async()=>{
 for(const [x,doc] of [[setup({...account,id:'33333333-3333-4333-8333-333333333333'}),id],[setup(),'44444444-4444-4444-8444-444444444444']]){
  for(const method of ['get','post'])expect((await api(x.app,method,doc)).status).toBe(404);
  expect(x.query.mock.calls.some(([sql])=>sql.startsWith('INSERT'))).toBe(false);
 }
});
test('UUID inválido no consulta PostgreSQL',async()=>{const x=setup();expect((await api(x.app,'get','bad')).status).toBe(404);expect(x.query).not.toHaveBeenCalled();});
test('consulta inicial solo lee y responde no-store',async()=>{
 const x=setup(),r=await api(x.app);expect(r.status).toBe(200);expect(r.headers['cache-control']).toBe('no-store');expect(r.body.processing.status).toBe('not_requested');expect(x.query.mock.calls.every(([sql])=>sql.startsWith('SELECT'))).toBe(true);
});
test('solicitudes concurrentes crean un único trabajo',async()=>{
 const x=setup(),results=await Promise.all([api(x.app,'post').send({}),api(x.app,'post').send({})]);
 expect(results.map(r=>r.status).sort()).toEqual([200,202]);for(const r of results)expect(r.body.processing.status).toBe('queued');
 expect(x.query.mock.calls.filter(([sql])=>sql.startsWith('INSERT')).every(([sql,args])=>sql.includes('ON CONFLICT')&&args[2]===account.id)).toBe(true);
});
test.each(['processing','requires_review','rejected','failed'])('estado %s no se reinicia ni expone contenido',async status=>{
 const x=setup();x.setJob({id,status,created_at:new Date(),started_at:null,finished_at:null,result:{raw:'secreto'},model:'modelo'});
 const r=await api(x.app,'post').send({});expect(r.status).toBe(200);expect(r.body.processing.status).toBe(status);
 expect(Object.keys(r.body.processing).sort()).toEqual(['approved','createdAt','finishedAt','reviewStatus','reviewedAt','startedAt','status']);expect(r.body.processing.approved).toBe(false);
});
test.each([{patientId:account.id},{model:'evil'},{approved:true}])('rechaza campos del servidor %j',async body=>{
 const x=setup();expect((await api(x.app,'post').send(body)).status).toBe(400);expect(x.query).not.toHaveBeenCalled();
});
test('fallo DB no expone detalles',async()=>{
 const services=createProcessingService({query:async()=>{throw new Error('password secreto');}});
 const r=await api(createApp({find:async()=>account},undefined,undefined,services));expect(r.status).toBe(500);expect(JSON.stringify(r.body)).not.toContain('secreto');
});
