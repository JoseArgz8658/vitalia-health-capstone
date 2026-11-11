const express=require('express'),request=require('supertest');
const {createInstitutionRouter}=require('../dist/institutions/router');
const {createInstitutionService,clinicInput,branchInput}=require('../dist/institutions/service');
const admin={id:'11111111-1111-4111-8111-111111111111',role:'administrador'};
const id='22222222-2222-4222-8222-222222222222';
const clinic={requestId:id,name:'Clínica ficticia',contactPhone:null};
const branch={...clinic,communeCode:'13125',street:'Calle ficticia',addressNumber:'S/N',floor:null,unit:null};
const bearer='Bearer '+'a'.repeat(64);
function app(account=admin){const a=express();a.use(express.json());const s={list:jest.fn(async()=>[]),branches:jest.fn(async()=>[]),create:jest.fn(async()=>({item:{id},created:true})),createBranch:jest.fn(async()=>({item:{id},created:true})),territories:jest.fn(async()=>({regions:[],provinces:[],communes:[]}))};a.use('/api/institutions',createInstitutionRouter({find:async()=>account},s));return {a,s};}
test.each(['paciente','profesional'])('API deniega todas las operaciones al rol %s',async role=>{
 const {a,s}=app({...admin,role});
 for(const [method,url]of [['get','/api/institutions'],['post','/api/institutions'],['get',`/api/institutions/${id}/branches`],['post',`/api/institutions/${id}/branches`],['get','/api/institutions/territories']])expect((await request(a)[method](url).set('Authorization',bearer).send({})).status).toBe(403);
 expect(s.list).not.toHaveBeenCalled();expect(s.createBranch).not.toHaveBeenCalled();
});
test('API exige sesión, identidad de sesión y no-store',async()=>{
 const {a,s}=app();expect((await request(a).get('/api/institutions')).status).toBe(401);
 const r=await request(a).post('/api/institutions').set('Authorization',bearer).send(clinic);expect(r.status).toBe(201);expect(r.headers['cache-control']).toBe('no-store');expect(s.create).toHaveBeenCalledWith(admin,clinic);
});
test.each(['?patientId=other','?limit=999','?offset=-1'])('listado rechaza parámetros %s',async q=>{
 const {a,s}=app();expect((await request(a).get('/api/institutions'+q).set('Authorization',bearer)).status).toBe(400);expect(s.list).not.toHaveBeenCalled();
});
test('API pasa el alcance de clínica de la ruta y nunca ofrece exámenes',async()=>{
 const {a,s}=app();expect((await request(a).post(`/api/institutions/${id}/branches`).set('Authorization',bearer).send(branch)).status).toBe(201);expect(s.createBranch).toHaveBeenCalledWith(admin,id,branch);
 expect((await request(a).get('/api/institutions/exams').set('Authorization',bearer)).status).toBe(404);
});
test.each([{actorId:admin.id},{active:false},{clinicalRole:'jefe_clinico'},{patientId:id},{name:' '},{contactPhone:''}])('clínica rechaza datos no autorizados %j',extra=>expect(clinicInput.safeParse({...clinic,...extra}).success).toBe(false));
test.each([{clinicId:id},{communeCode:'1312'},{floor:''},{street:''},{addressNumber:''},{unit:' '.repeat(10)}])('sucursal rechaza %j',extra=>expect(branchInput.safeParse({...branch,...extra}).success).toBe(false));
test('opcionales nulos y número S/N se conservan',()=>expect(branchInput.parse(branch)).toEqual(branch));
test.each(['paciente','profesional'])('servicio deniega operaciones antes de acceder a DB: %s',async role=>{
 const db={query:jest.fn(),transaction:jest.fn()},s=createInstitutionService(db),a={...admin,role};
 for(const work of [()=>s.list(a),()=>s.create(a,clinic),()=>s.branches(a,id),()=>s.createBranch(a,id,branch),()=>s.territories(a)])await expect(work()).rejects.toMatchObject({status:403});expect(db.query).not.toHaveBeenCalled();expect(db.transaction).not.toHaveBeenCalled();
});
test('creación y auditoría pertenecen a la misma transacción',async()=>{
 const query=jest.fn(async(sql)=>({rows:sql.startsWith('INSERT INTO public.vitalia_clinics')?[{id}]:sql.startsWith('SELECT id,name')?[{id,name:clinic.name,contactPhone:null,active:true}]:[]}));
 const transaction=jest.fn(fn=>fn({query}));const s=createInstitutionService({query:jest.fn(),transaction});expect((await s.create(admin,clinic)).created).toBe(true);
 expect(transaction).toHaveBeenCalledTimes(1);expect(query.mock.calls.some(([sql,args])=>sql.includes('vitalia_institution_audit')&&args[1]===admin.id)).toBe(true);
});
test('reintento coincidente no duplica auditoría y uno diferente devuelve conflicto',async()=>{
 const query=jest.fn(async(sql)=>({rows:sql.startsWith('SELECT id,name')?[{id,name:clinic.name,contactPhone:null,active:true}]:[]}));const s=createInstitutionService({transaction:fn=>fn({query})});
 expect((await s.create(admin,clinic)).created).toBe(false);expect(query.mock.calls.some(([sql])=>sql.includes('INSERT INTO public.vitalia_institution_audit'))).toBe(false);
 await expect(s.create(admin,{...clinic,name:'Distinta'})).rejects.toMatchObject({status:409});
});
test('sucursal en clínica inactiva se rechaza antes de escribir',async()=>{
 const query=jest.fn(async sql=>({rows:sql.startsWith('SELECT id,active')?[{id,active:false}]:[]}));const s=createInstitutionService({transaction:fn=>fn({query})});await expect(s.createBranch(admin,id,branch)).rejects.toMatchObject({status:409});expect(query.mock.calls.some(([sql])=>sql.startsWith('INSERT'))).toBe(false);
});
test('auditoría fallida impide informar creación aceptada',async()=>{
 const query=async sql=>{if(sql.includes('INSERT INTO public.vitalia_institution_audit'))throw {code:'42501'};return {rows:sql.startsWith('INSERT INTO public.vitalia_clinics')?[{id}]:sql.startsWith('SELECT id,name')?[{id,name:clinic.name,contactPhone:null}]:[]};};
 await expect(createInstitutionService({transaction:fn=>fn({query})}).create(admin,clinic)).rejects.toMatchObject({status:503});
});
