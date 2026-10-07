const request=require('supertest');
const {createApp}=require('../dist/app');
const {createProfessionalService,ProfessionalNotFoundError,ProfessionalForbiddenError}=require('../dist/professional/service');
const id='11111111-1111-4111-8111-111111111111',patientId='22222222-2222-4222-8222-222222222222',docId='33333333-3333-4333-8333-333333333333';
const account={id,role:'profesional'};
const body=Buffer.from('%PDF-1.4\nDocumento ficticio\n%%EOF');
function setup(){
 let active=true;const audit=[];
 const row={id:docId,exam_name:'Prueba',exam_type:'Laboratorio',exam_date:'2026-09-29',original_name:'sintetico.pdf',content_type:'application/pdf',size_bytes:body.length,created_at:new Date(),storage_key:`patients/${patientId}/documents/${docId}`};
 let result={status:'requires_review',source:'pdf',method:'direct',reading:{status:'text_ready',text:'Texto ficticio',pageCount:1,incidents:[]},ocr:null,inputText:'Texto ficticio',ai:{status:'requires_review',raw:'no exponer raw',extraction:{examen:'Prueba',fecha:'29-09-2026',resultados:[]},incidents:[],approved:false,model:'qwen3:4b-instruct',promptVersion:3,elapsedMs:1},approved:false};
 const query=jest.fn(async(sql,args)=>{
  if(sql.startsWith('SELECT x.id'))return {rows:active&&args[0]===id&&args[1]===patientId?[{id:'44444444-4444-4444-8444-444444444444'}]:[]};
  if(sql.startsWith('SELECT id,status,result'))return {rows:result===null?[]:[{id:'55555555-5555-4555-8555-555555555555',status:result.status==='service_error'?'failed':result.status,result}]};
  if(sql.startsWith('SELECT id,exam_name'))return {rows:sql.includes('WHERE id=')?(args[0]===docId&&args[1]===patientId?[row]:[]):[row]};
  if(sql.startsWith('INSERT INTO public.vitalia_professional_access_audit')){audit.push(args);return {rows:[]};}
  throw new Error('unexpected SQL');
 });
 const db={query,transaction:jest.fn(work=>work({query}))};
 const storage={read:jest.fn().mockResolvedValue(body)};
 return {service:createProfessionalService(db,storage),db,storage,audit,row,revoke:()=>{active=false;},setResult:r=>{result=r;}};
}
function app(x,user=account){return createApp({find:async()=>user},undefined,undefined,undefined,undefined,x.service);}
const url=(suffix='')=>`/api/professional/patients/${patientId}/documents${suffix}`;
const get=(app,path=url())=>request(app).get(path).set('Authorization','Bearer '+'a'.repeat(64));
test('historial autorizado filtra paciente y registra actor sin exponer clave',async()=>{
 const x=setup(),items=await x.service.list(account,patientId);expect(items[0].id).toBe(docId);expect(JSON.stringify(items)).not.toContain('storage_key');
 expect(x.audit[0].slice(1)).toEqual([id,patientId,'44444444-4444-4444-8444-444444444444','list',null,null]);
 const lock=x.db.query.mock.calls[0];expect(lock[0]).toContain('FOR SHARE OF x,p,r');expect(lock[1]).toEqual([id,patientId]);
});
test('extracción conserva datos y texto sin aprobación ni respuesta cruda',async()=>{
 const x=setup(),view=await x.service.extraction(account,patientId,docId);
 expect(view.processing.status).toBe('requires_review');expect(view.processing.extraction.fecha).toBe('29-09-2026');expect(view.processing.sourceText).toBe('Texto ficticio');expect(view.processing.approved).toBe(false);
 expect(JSON.stringify(view)).not.toContain('no exponer raw');expect(JSON.stringify(view)).not.toContain('storage_key');expect(x.audit[0][4]).toBe('view_extraction');
});
test('sin trabajo devuelve no solicitado sin inventar extracción',async()=>{
 const x=setup();x.setResult(null);const value=await x.service.extraction(account,patientId,docId);expect(value.processing.status).toBe('not_requested');expect(value.processing.extraction).toBeNull();
});
test.each(['paciente','administrador'])('rol %s no llega a DB o S3',async role=>{
 const x=setup();await expect(x.service.list({...account,role},patientId)).rejects.toBeInstanceOf(ProfessionalForbiddenError);expect(x.db.query).not.toHaveBeenCalled();expect(x.storage.read).not.toHaveBeenCalled();
});
test('no asignado o desactivado no lista, consulta ni descarga',async()=>{
 for(const revoke of [true,false]){const x=setup();if(revoke)x.revoke();const actor=revoke?account:{...account,id:docId};
  for(const call of [()=>x.service.list(actor,patientId),()=>x.service.extraction(actor,patientId,docId),()=>x.service.download(actor,patientId,docId)])await expect(call()).rejects.toBeInstanceOf(ProfessionalNotFoundError);
  expect(x.storage.read).not.toHaveBeenCalled();expect(x.audit).toHaveLength(0);
 }
});
test('documento ajeno/no guardado no se descarga',async()=>{
 const x=setup();await expect(x.service.download(account,patientId,id)).rejects.toBeInstanceOf(ProfessionalNotFoundError);expect(x.storage.read).not.toHaveBeenCalled();expect(x.audit).toHaveLength(0);
});
test('descarga original valida objeto y vuelve a autorizar después de S3',async()=>{
 const x=setup(),file=await x.service.download(account,patientId,docId);expect(file.body).toEqual(body);expect(x.storage.read).toHaveBeenCalledWith(x.row.storage_key);
 expect(x.db.query.mock.calls.filter(([sql])=>sql.startsWith('SELECT x.id'))).toHaveLength(2);expect(x.audit[0][4]).toBe('download');
});
test('revocación durante S3 impide entregar y no registra descarga exitosa',async()=>{
 const x=setup();x.storage.read.mockImplementation(async()=>{x.revoke();return body;});
 await expect(x.service.download(account,patientId,docId)).rejects.toBeInstanceOf(ProfessionalNotFoundError);expect(x.audit).toHaveLength(0);
});
test('clave ajena, tamaño y firma incorrectos no entregan archivo',async()=>{
 for(const mode of ['key','size','signature']){
  const x=setup();if(mode==='key')x.row.storage_key='patients/otro/documento';
  if(mode==='size')x.storage.read.mockResolvedValue(Buffer.from('bad'));
  if(mode==='signature')x.storage.read.mockResolvedValue(Buffer.alloc(body.length));
  await expect(x.service.download(account,patientId,docId)).rejects.toThrow();expect(x.audit).toHaveLength(0);
 }
});
test('auditoría fallida y resultado inválido no se aceptan',async()=>{
 const x=setup(),original=x.db.query.getMockImplementation();x.db.query.mockImplementation((sql,args)=>sql.startsWith('INSERT')?Promise.reject(new Error('audit')):original(sql,args));
 await expect(x.service.list(account,patientId)).rejects.toThrow('audit');
 const y=setup();y.setResult({approved:true});await expect(y.service.extraction(account,patientId,docId)).rejects.toThrow();expect(y.audit).toHaveLength(0);
});
test('HTTP sesión, rol, asignación y cabeceras de descarga',async()=>{
 const x=setup();expect((await request(app(x)).get(url())).status).toBe(401);expect((await get(app(x,{...account,role:'administrador'}))).status).toBe(403);
 const res=await get(app(x),url('/'+docId+'/file'));expect(res.status).toBe(200);expect(res.headers['cache-control']).toBe('no-store');expect(res.headers['content-disposition']).toContain('attachment');expect(res.headers['x-content-type-options']).toBe('nosniff');
 x.revoke();expect((await get(app(x))).status).toBe(404);
});
test('HTTP entrada forjada, UUID inválido y escritura rechazados',async()=>{
 const x=setup();expect((await get(app(x),url('?professionalId='+id))).status).toBe(400);
 expect((await get(app(x),url('/bad/extraction'))).status).toBe(404);
 expect((await request(app(x)).post(url('/'+docId+'/extraction')).set('Authorization','Bearer '+'a'.repeat(64)).send({approved:true})).status).toBe(404);expect(x.db.query).not.toHaveBeenCalled();
});
