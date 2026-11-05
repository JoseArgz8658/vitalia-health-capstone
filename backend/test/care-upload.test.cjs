const request=require('supertest');
const {createCareUploadService,CareUploadError}=require('../dist/care/upload');
const {createCareUploadRouter}=require('../dist/care/upload-router');
const {createDocumentService}=require('../dist/documents/service');
const {verifyCareUpload}=require('../dist/database/care-upload-verification');
const express=require('express');
const id='11111111-1111-4111-8111-111111111111',account={id,role:'paciente'},token='a'.repeat(64);
const value={clinicId:id,branchId:id,membershipId:id,specialtyId:id,residenceCommuneCode:'13125',consultationCommuneCode:'13101',street:'Calle sintética',addressNumber:'S/N',phone:'+56912345678',confirmed:true,saveProfile:true,profileRevision:'synthetic'};
test.each([{phone:''},{phone:'123'},{confirmed:false},{email:'otro@example.invalid'},{patientId:id},{saveProfile:'true'},
 {profileRevision:''},{branchId:'x'},{residenceCommuneCode:'Quilicura'},{street:''},{addressNumber:''},{consultationCommuneCode:['13125']}])('entrada de atención inválida %j',extra=>{
 expect(()=>createCareUploadService({}).parse({...value,...extra})).toThrow(CareUploadError);
});
test('entrada multipart debe ser JSON válido y cerrado',()=>{
 const service=createCareUploadService({});expect(()=>service.parse('{')).toThrow(CareUploadError);expect(()=>service.parse(undefined)).toThrow(CareUploadError);
 expect(service.parse(JSON.stringify(value))).toEqual(value);
});
test.each(['profesional','administrador'])('%s no precarga ni adjunta atención',async role=>{
 const transaction=jest.fn(),service=createCareUploadService({transaction});
 await expect(service.context({...account,role})).rejects.toMatchObject({status:403});
 await expect(service.preflight({...account,role},value)).rejects.toMatchObject({status:403});
 expect(transaction).not.toHaveBeenCalled();
});
test('sin persona requiere completar perfil y no escribe',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(createCareUploadService({transaction:fn=>fn({query})}).context(account)).rejects.toMatchObject({status:409,code:'CARE_PROFILE_REQUIRED'});
 expect(query.mock.calls.some(([s])=>s.startsWith('INSERT'))).toBe(false);
});
test.each(['42P01','42703','42501'])('contexto traduce esquema/permisos %s',async code=>{
 await expect(createCareUploadService({transaction:async()=>{throw {code};}}).context(account)).rejects.toMatchObject({status:503});
});
test('perfil modificado detiene preflight antes de selección',async()=>{
 const query=jest.fn(async()=>({rows:[{revision:'new'}]}));await expect(createCareUploadService({transaction:fn=>fn({query})}).preflight(account,value)).rejects.toMatchObject({status:409,code:'CARE_PROFILE_CHANGED'});expect(query).toHaveBeenCalledTimes(1);
});
const incoming={name:'synthetic.pdf',contentType:'application/pdf',body:Buffer.from('%PDF-1.4\nsynthetic\n%%EOF'),metadata:{examName:'Sintético',examType:'Laboratorio',examDate:'2026-01-01',care:JSON.stringify(value)}};
test('preflight rechazado no reserva ni escribe S3',async()=>{
 const query=jest.fn(),put=jest.fn(),care={parse:()=>value,preflight:async()=>{throw new CareUploadError(409,'CARE_SELECTION_CHANGED');}};
 await expect(createDocumentService({query},{put},care).upload(account,incoming)).rejects.toMatchObject({status:409});expect(query).not.toHaveBeenCalled();expect(put).not.toHaveBeenCalled();
});
function fixture(){
 let saved;
 const query=jest.fn(async(sql,args)=>{
  if(sql.includes('INSERT INTO public.vitalia_documents')){saved={id:args[0],exam_name:args[2],exam_type:args[3],exam_date:args[4],original_name:args[5],content_type:args[6],size_bytes:args[7],created_at:new Date(),status:'pending'};return {rows:[]};}
  if(sql.includes("SET status = 'stored'")){saved.status='stored';return {rows:[{id:saved.id}]};}
  if(sql.includes("SET status = 'failed'")){saved.status='failed';return {rows:[]};}
  if(sql.includes('FROM public.vitalia_documents'))return {rows:[saved]};return {rows:[]};
 });
 const transaction=async fn=>{const previous=saved?{...saved}:null;try{return await fn({query});}catch(e){saved=previous;throw e;}};
 const storage={put:jest.fn(async()=>{}),remove:jest.fn(async()=>{})},care={parse:()=>value,preflight:jest.fn(async()=>{}),attach:jest.fn(async()=>{})};
 return {query,storage,care,service:createDocumentService({query,transaction},storage,care),state:()=>saved};
}
test('atención se confirma junto con documento y auditoría',async()=>{
 const f=fixture();await f.service.upload(account,incoming);expect(f.care.attach).toHaveBeenCalledWith(expect.anything(),account,expect.any(String),value);expect(f.state().status).toBe('stored');
});
test('fallo en atención compensa S3 y deja reserva fallida',async()=>{
 const f=fixture();f.care.attach.mockRejectedValue(new CareUploadError(409,'CARE_SELECTION_CHANGED'));
 await expect(f.service.upload(account,incoming)).rejects.toMatchObject({status:409});expect(f.storage.remove).toHaveBeenCalledTimes(1);expect(f.state().status).toBe('failed');
});
function app(a){const service={context:jest.fn(async()=>({email:'test@example.invalid'}))},x=express();x.use('/api/care',createCareUploadRouter({find:async()=>a},service));return {app:x,service};}
test('contexto exige sesión, no cachea ni admite identidad por query',async()=>{
 const x=app(account);expect((await request(x.app).get('/api/care/context')).status).toBe(401);
 const good=await request(x.app).get('/api/care/context').set('Authorization','Bearer '+token);expect(good.status).toBe(200);expect(good.headers['cache-control']).toBe('no-store');expect(x.service.context).toHaveBeenCalledWith(account);
 expect((await request(x.app).get('/api/care/context?patientId='+id).set('Authorization','Bearer '+token)).status).toBe(400);
});
test('sin 021 el verificador revierte y no inserta',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(verifyCareUpload({query})).rejects.toThrow('Falta migración 021.');expect(query.mock.calls.at(-1)[0]).toBe('ROLLBACK');expect(query.mock.calls.some(([s])=>s.startsWith('INSERT'))).toBe(false);
});
test('verificador sin conexión no ejecuta rollback',async()=>{
 const query=jest.fn().mockRejectedValue(new Error('Sin conexión'));await expect(verifyCareUpload({query})).rejects.toThrow('Sin conexión');expect(query).toHaveBeenCalledTimes(1);
});
test.each(['migrate-care-upload','verify-care-upload'])('CLI %s no imprime secretos',file=>{
 const {spawnSync}=require('node:child_process'),r=spawnSync(process.execPath,[`dist/database/${file}.js`],{cwd:process.cwd(),encoding:'utf8',env:{...process.env,PGPORT:'inválido',PGPASSWORD:'no-exponer-esta-clave'}});
 expect(r.status).toBe(1);expect(r.stderr).not.toContain('no-exponer-esta-clave');
});
