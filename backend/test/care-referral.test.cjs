const request=require('supertest'),express=require('express');
const {createCareInboxService}=require('../dist/care/inbox');
const {createCareInboxRouter}=require('../dist/care/inbox-router');
const {createCareHistoryService}=require('../dist/care/history');
const {createCareHistoryRouter}=require('../dist/care/history-router');
const {verifyCareReferral}=require('../dist/database/care-referral-verification');
const id='11111111-1111-4111-8111-111111111111',a={id,role:'profesional'},token='a'.repeat(64);
const body={requestId:id,expectedRevision:0,membershipId:id,branchId:id,specialtyId:id,reason:'Derivación sintética',confirmed:true};
test.each(['paciente','administrador'])('%s no deriva ni consulta destinatarios',async role=>{
 const transaction=jest.fn(),s=createCareInboxService({transaction},{}),user={...a,role};
 await expect(s.referralOptions(user,id,{})).rejects.toMatchObject({status:403});await expect(s.refer(user,id,body)).rejects.toMatchObject({status:403});expect(transaction).not.toHaveBeenCalled();
});
test.each([{confirmed:false},{requestId:'x'},{expectedRevision:-1},{reason:'x'},{clinicId:id},{patientId:id},{actorId:id},{membershipId:'x'}])('rechaza cuerpo inválido %j',async extra=>{
 const transaction=jest.fn();await expect(createCareInboxService({transaction},{}).refer(a,id,{...body,...extra})).rejects.toMatchObject({status:400});expect(transaction).not.toHaveBeenCalled();
});
test.each([{offset:'-1'},{clinicId:id},{offset:['0']},{offset:'1.5'}])('destinatarios rechazan filtros de otro ámbito %j',async input=>{
 const transaction=jest.fn();await expect(createCareInboxService({transaction},{}).referralOptions(a,id,input)).rejects.toMatchObject({status:400});expect(transaction).not.toHaveBeenCalled();
});
test('seguimiento exige propiedad antes de consultar atenciones',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(createCareHistoryService({transaction:fn=>fn({query})}).get({...a,role:'paciente'},id,{})).rejects.toMatchObject({status:404});expect(query).toHaveBeenCalledTimes(1);expect(query.mock.calls[0][1]).toEqual([id,id]);
});
test.each(['profesional','administrador'])('%s no consulta seguimiento como paciente',async role=>{
 const transaction=jest.fn();await expect(createCareHistoryService({transaction}).get({...a,role},id,{})).rejects.toMatchObject({status:403});expect(transaction).not.toHaveBeenCalled();
});
test('seguimiento paginado sin exposición del teléfono',async()=>{
 const query=jest.fn(async sql=>sql.startsWith('SELECT id')?{rows:[{id}]}:{rows:Array.from({length:31},()=>({id,status:'requested'}))});
 const result=await createCareHistoryService({transaction:fn=>fn({query})}).get({...a,role:'paciente'},id,{});expect(result.items).toHaveLength(30);expect(result.nextOffset).toBe(30);expect(JSON.stringify(result)).not.toContain('phone');
});
function app(user=a){const s={referralOptions:jest.fn(async()=>({items:[]})),refer:jest.fn(async()=>({referred:true}))},x=express();x.use(express.json());x.use('/api/care-inbox',createCareInboxRouter({find:async()=>user},s));return {app:x,s};}
test.each([null,{...a,role:'paciente'},{...a,role:'administrador'}])('ruta de derivación exige sesión/rol %j',async user=>{
 const f=app(user);expect((await request(f.app).post(`/api/care-inbox/${id}/referrals`).set('Authorization','Bearer '+token).send(body)).status).toBe(user?403:401);expect(f.s.refer).not.toHaveBeenCalled();
});
test('API deriva con actor autenticado, sin identidad por query',async()=>{
 const f=app();let r=await request(f.app).post(`/api/care-inbox/${id}/referrals`).set('Authorization','Bearer '+token).send(body);expect(r.status).toBe(201);expect(r.headers['cache-control']).toBe('no-store');expect(f.s.refer).toHaveBeenCalledWith(a,id,body);
 r=await request(f.app).post(`/api/care-inbox/${id}/referrals?actorId=${id}`).set('Authorization','Bearer '+token).send(body);expect(r.status).toBe(400);expect(f.s.refer).toHaveBeenCalledTimes(1);
});
test('ruta de seguimiento solo lectura con sesión',async()=>{
 const s={get:jest.fn(async()=>({items:[]}))},x=express();x.use('/api/documents',createCareHistoryRouter({find:async()=>({...a,role:'paciente'})},s));
 expect((await request(x).get(`/api/documents/${id}/care`)).status).toBe(401);
 const r=await request(x).get(`/api/documents/${id}/care`).set('Authorization','Bearer '+token);expect(r.status).toBe(200);expect(r.headers['cache-control']).toBe('no-store');expect(s.get).toHaveBeenCalledWith({...a,role:'paciente'},id,{});
 expect((await request(x).post(`/api/documents/${id}/care`).set('Authorization','Bearer '+token)).status).toBe(404);
});
test('verificador requiere 024 y revierte sin insertar',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(verifyCareReferral({query})).rejects.toThrow('Falta migración 024.');expect(query.mock.calls.at(-1)[0]).toBe('ROLLBACK');expect(query.mock.calls.some(([s])=>s.startsWith('INSERT'))).toBe(false);
});
test.each(['migrate-care-referral','verify-care-referral'])('CLI %s no muestra secretos',file=>{
 const {spawnSync}=require('node:child_process'),r=spawnSync(process.execPath,[`dist/database/${file}.js`],{cwd:process.cwd(),encoding:'utf8',env:{...process.env,PGPORT:'inválido',PGPASSWORD:'no-exponer-clave'}});expect(r.status).toBe(1);expect(r.stderr).not.toContain('no-exponer-clave');
});
