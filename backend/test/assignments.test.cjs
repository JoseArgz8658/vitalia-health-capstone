const request=require('supertest');
const {createApp}=require('../dist/app');
const {createAssignmentService,AssignmentForbiddenError,AssignmentInputError,AssignmentNotFoundError}=require('../dist/assignments/service');
const {applyAdditionalMigration}=require('../dist/database/additional-migration');
const fs=require('node:fs');
const id='11111111-1111-4111-8111-111111111111',pid='22222222-2222-4222-8222-222222222222',rid='33333333-3333-4333-8333-333333333333';
const admin={id,role:'administrador'},professional={id:rid,role:'profesional'},patient={id:pid,role:'paciente'};
const input={patientEmail:'p@example.com',professionalEmail:'r@example.com'};
function setup(){
 let row=null;const audit=[];
 const query=jest.fn(async(sql,args)=>{
  if(sql.startsWith('SELECT id,role_code'))return {rows:[{id:pid,role_code:'paciente'},{id:rid,role_code:'profesional'}]};
  if(sql.startsWith('INSERT INTO public.vitalia_patient_assignments')){
   if(row?.active)return {rows:[]};
   if(!row)row={id:args[0],active:true,patient_email:input.patientEmail,professional_email:input.professionalEmail,created_at:new Date(),updated_at:new Date(),deactivated_at:null};
   row.active=true;row.deactivated_at=null;return {rows:[{id:row.id}]};
  }
  if(sql.startsWith('INSERT INTO public.vitalia_assignment_audit')){audit.push({actor:args[2],action:sql.includes("'activate'")?'activate':'deactivate'});return {rows:[]};}
  if(sql.startsWith('UPDATE public.vitalia_patient_assignments')){
   if(!row||row.id!==args[0]||!row.active)return {rows:[]};row.active=false;row.deactivated_at=new Date();return {rows:[{id:row.id}]};
  }
  if(sql.startsWith('SELECT p.id,p.email'))return {rows:row?.active&&args[0]===rid?[{id:pid,email:input.patientEmail,assignment_id:row.id}]:[]};
  if(sql.startsWith('SELECT x.id'))return {rows:row?[row]:[]};
  throw new Error('unexpected SQL');
 });
 const db={query,transaction:jest.fn(work=>work({query}))};
 return {service:createAssignmentService(db),db,audit};
}
function app(service,user=admin){return createApp({find:async()=>user},undefined,undefined,undefined,service);}
const call=(app,method='get',path='/api/assignments')=>request(app)[method](path).set('Authorization','Bearer '+'a'.repeat(64));
test('crea, no duplica, desactiva y reactiva con auditoría solo al cambiar',async()=>{
 const x=setup(),first=await x.service.assign(admin,input);expect(first.changed).toBe(true);
 expect((await x.service.assign(admin,input)).changed).toBe(false);
 expect((await x.service.listProfessional(professional))[0].id).toBe(pid);
 expect(await x.service.listProfessional({...professional,id})).toEqual([]);
 expect((await x.service.deactivate(admin,first.assignment.id)).assignment.active).toBe(false);
 expect(await x.service.listProfessional(professional)).toEqual([]);
 expect((await x.service.deactivate(admin,first.assignment.id)).changed).toBe(false);
 const again=await x.service.assign(admin,input);expect(again.assignment.id).toBe(first.assignment.id);
 expect(x.audit).toEqual([{actor:id,action:'activate'},{actor:id,action:'deactivate'},{actor:id,action:'activate'}]);
 expect(x.db.transaction).toHaveBeenCalledTimes(5);
});
test.each([patient,professional])('no administrador no puede modificar %j',async account=>{
 const x=setup();await expect(x.service.assign(account,input)).rejects.toBeInstanceOf(AssignmentForbiddenError);
 await expect(x.service.deactivate(account,id)).rejects.toBeInstanceOf(AssignmentForbiddenError);expect(x.db.query).not.toHaveBeenCalled();
});
test('no profesional no recibe lista profesional',async()=>{const x=setup();await expect(x.service.listProfessional(admin)).rejects.toBeInstanceOf(AssignmentForbiddenError);expect(x.db.query).not.toHaveBeenCalled();});
test.each([{...input,patientId:pid},{...input,createdBy:id},{...input,patientEmail:'bad'}])('rechaza datos extra e inválidos %j',async body=>{
 const x=setup();await expect(x.service.assign(admin,body)).rejects.toBeInstanceOf(AssignmentInputError);expect(x.db.query).not.toHaveBeenCalled();
});
test('cuentas con roles incorrectos o inexistentes no insertan',async()=>{
 const db={query:jest.fn().mockResolvedValue({rows:[]})};db.transaction=work=>work(db);
 await expect(createAssignmentService(db).assign(admin,input)).rejects.toBeInstanceOf(AssignmentNotFoundError);expect(db.query).toHaveBeenCalledTimes(1);
});
test('SQL parametriza correos y usa roles, propiedad y restricción única',async()=>{
 const x=setup();await x.service.assign(admin,input);await x.service.listProfessional(professional);
 const lookup=x.db.query.mock.calls[0];expect(lookup[0]).toContain("role_code='paciente'");expect(lookup[0]).toContain("role_code='profesional'");expect(lookup[1]).toEqual(Object.values(input));
 expect(x.db.query.mock.calls.find(([sql])=>sql.startsWith('INSERT'))[0]).toContain('ON CONFLICT(professional_id,patient_id)');
 const query=x.db.query.mock.calls.at(-1);expect(query[0]).toContain('x.professional_id=$1 AND x.active=true');expect(query[1]).toEqual([rid,20,0]);
});
test('fallo de auditoría falla la transacción en vez de declarar éxito',async()=>{
 const x=setup(),original=x.db.query.getMockImplementation();x.db.query.mockImplementation((sql,args)=>sql.startsWith('INSERT INTO public.vitalia_assignment_audit')?Promise.reject(new Error('audit failed')):original(sql,args));
 await expect(x.service.assign(admin,input)).rejects.toThrow('audit failed');
});
test('sin sesión y paciente no reciben listas',async()=>{
 const x=setup();expect((await call(app(x.service,null))).status).toBe(401);expect((await call(app(x.service,patient))).status).toBe(403);expect(x.db.query).not.toHaveBeenCalled();
});
test('HTTP admin activa y profesional recibe solo pacientes',async()=>{
 const x=setup(),created=await call(app(x.service),'post').send(input);expect(created.status).toBe(201);
 expect((await call(app(x.service),'post').send(input)).status).toBe(200);
 const res=await call(app(x.service,professional));expect(res.body).toEqual({patients:[{id:pid,email:input.patientEmail,assignmentId:created.body.assignment.id}]});expect(res.headers['cache-control']).toBe('no-store');
 expect((await call(app(x.service,professional),'post').send(input)).status).toBe(403);
 expect((await call(app(x.service),'post',`/api/assignments/${created.body.assignment.id}/deactivate`).send({})).status).toBe(200);
});
test('paginación extra y solicitud forjada no llegan a SQL',async()=>{
 const x=setup();expect((await call(app(x.service),'get','/api/assignments?professionalId='+rid)).status).toBe(400);
 expect((await call(app(x.service),'post').send({...input,role:'administrador'})).status).toBe(400);
 expect((await call(app(x.service),'post','/api/assignments/invalid/deactivate').send({})).status).toBe(404);expect(x.db.query).not.toHaveBeenCalled();
});
test('migración 007 usa tablas nuevas, referencias, auditoría y requisito 006',async()=>{
 const sql=fs.readFileSync('database/migrations/007_patient_assignments.sql','utf8');expect(sql).toContain('UNIQUE(professional_id,patient_id)');expect(sql).toContain('vitalia_assignment_audit');expect(sql).not.toMatch(/DROP|ALTER/);
 const db={query:jest.fn(async text=>({rows:text.startsWith('SELECT version')?[{version:'006_document_processing'}]:[]}))};
 expect(await applyAdditionalMigration(db,'007_patient_assignments',sql,'006_document_processing')).toBe('applied');expect(db.query).toHaveBeenCalledWith(sql);
});
