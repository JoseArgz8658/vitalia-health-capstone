const request=require('supertest');
const {createApp}=require('../dist/app');
const {createReviewService,ReviewInputError,ReviewForbiddenError,ReviewNotFoundError,ReviewConflictError}=require('../dist/reviews/service');
const {createProcessingService}=require('../dist/processing/service');
const id='11111111-1111-4111-8111-111111111111',patientId='22222222-2222-4222-8222-222222222222',docId='33333333-3333-4333-8333-333333333333',processingId='44444444-4444-4444-8444-444444444444';
const account={id,role:'profesional'};
const extraction={examen:'Prueba ficticia',fecha:'29-09-2026',resultados:[{nombre:'Alfa',valor:'15,2',unidad:'g/dL',rango_referencia:'14,0–16,0 g/dL'}]};
function setup(){
 let active=true,saved=null,status='requires_review';const audit=[];
 const result={status:'requires_review',source:'pdf',method:'direct',reading:{status:'text_ready',text:'Texto ficticio',pageCount:1,incidents:[]},ocr:null,inputText:'Texto ficticio',
 ai:{status:'requires_review',raw:JSON.stringify(extraction),extraction,incidents:[],approved:false,model:'qwen3:4b-instruct',promptVersion:3,elapsedMs:1},approved:false};
 const query=jest.fn(async(sql,args)=>{
  if(sql.startsWith('SELECT x.id'))return {rows:active&&args[0]===id&&args[1]===patientId&&args[2]===docId?[{id:docId}]:[]};
  if(sql.startsWith('SELECT id,status,result'))return {rows:[{id:processingId,status,result}]};
  if(sql.startsWith('SELECT v.id'))return {rows:saved?[saved]:[]};
  if(sql.startsWith('INSERT INTO public.vitalia_professional_reviews')){
   if(saved)throw {code:'23505'};
   saved={id:args[0],processing_id:args[1],reviewer_id:args[5],reviewer_email:'r@example.com',original_extraction:JSON.parse(args[6]),reviewed_extraction:JSON.parse(args[7]),observations:args[8],created_at:new Date()};
   return {rows:[]};
  }
  if(sql.startsWith('INSERT INTO public.vitalia_professional_access_audit')){audit.push(args);return {rows:[]};}
  if(sql.startsWith('SELECT id FROM public.vitalia_documents'))return {rows:args[0]===docId&&args[1]===patientId?[{id:docId}]:[]};
  if(sql.startsWith('SELECT p.id'))return {rows:[{id:processingId,status,created_at:new Date(),started_at:null,finished_at:null}]};
  if(sql.startsWith('SELECT created_at FROM public.vitalia_professional_reviews'))return {rows:saved?[{created_at:saved.created_at}]:[]};
  throw new Error('Unexpected SQL');
 });
 const db={query,transaction:jest.fn(work=>work({query}))};
 return {db,service:createReviewService(db),result,revoke:()=>{active=false;},setStatus:s=>{status=s;},saved:()=>saved,audit};
}
const input=(overrides={})=>({processingId,extraction:structuredClone(extraction),observations:'',confirmedOriginal:true,...overrides});
test('aprueba copia humana sin modificar el resultado original y refleja estado al paciente',async()=>{
 const x=setup(),before=JSON.stringify(x.result);
 expect((await x.service.get(account,patientId,docId)).canReview).toBe(true);
 const saved=await x.service.approve(account,patientId,docId,input());
 expect(saved.approved).toBe(true);expect(saved.reviewerId).toBe(id);expect(saved.extraction).toEqual(extraction);
 expect(JSON.stringify(x.result)).toBe(before);expect(x.saved().original_extraction).toEqual(extraction);
 expect(x.db.query.mock.calls.some(([sql])=>/^UPDATE|^DELETE/.test(sql))).toBe(false);
 const patientState=await createProcessingService(x.db).get({id:patientId,role:'paciente'},docId);
 expect(patientState.reviewStatus).toBe('approved');expect(patientState.approved).toBe(false);expect(patientState.extraction).toBeUndefined();
});
test('corrección exige observaciones y conserva ambos valores',async()=>{
 const x=setup(),changed=structuredClone(extraction);changed.resultados[0].valor='15,3';
 await expect(x.service.approve(account,patientId,docId,input({extraction:changed}))).rejects.toBeInstanceOf(ReviewInputError);
 const saved=await x.service.approve(account,patientId,docId,input({extraction:changed,observations:'Cifra cotejada con el documento original.'}));
 expect(saved.extraction.resultados[0].valor).toBe('15,3');expect(x.saved().original_extraction.resultados[0].valor).toBe('15,2');
});
test('campos ausentes requieren explicación, no se convierten a cero',async()=>{
 const x=setup(),changed=structuredClone(extraction);changed.resultados[0].valor=null;
 await expect(x.service.approve(account,patientId,docId,input({extraction:changed}))).rejects.toBeInstanceOf(ReviewInputError);
 expect((await x.service.approve(account,patientId,docId,input({extraction:changed,observations:'Valor no legible en original.'}))).extraction.resultados[0].valor).toBeNull();
});
test.each(['31-11-2026','29-02-2027','2026-09-29'])('fecha inválida %s se rechaza antes de escribir',async fecha=>{
 const x=setup(),changed=structuredClone(extraction);changed.fecha=fecha;
 await expect(x.service.approve(account,patientId,docId,input({extraction:changed,observations:'Prueba'}))).rejects.toBeInstanceOf(ReviewInputError);expect(x.db.query).not.toHaveBeenCalled();
});
test('bisiesto válido y cero decimal se conservan',async()=>{
 const x=setup(),changed=structuredClone(extraction);changed.fecha='29-02-2028';changed.resultados[0].valor='0,00';
 const saved=await x.service.approve(account,patientId,docId,input({extraction:changed,observations:'Datos cotejados en documento ficticio.'}));expect(saved.extraction.fecha).toBe('29-02-2028');expect(saved.extraction.resultados[0].valor).toBe('0,00');
});
test.each([{confirmedOriginal:false},{approved:true},{reviewerId:id},{extraction:{...extraction,resultados:[]}},{observations:'a'.repeat(2001)}])('rechaza entrada incompleta o forjada %j',async overrides=>{
 const x=setup();await expect(x.service.approve(account,patientId,docId,input(overrides))).rejects.toBeInstanceOf(ReviewInputError);expect(x.db.query).not.toHaveBeenCalled();
});
test.each(['paciente','administrador'])('rol %s no consulta ni aprueba',async role=>{
 const x=setup();await expect(x.service.get({...account,role},patientId,docId)).rejects.toBeInstanceOf(ReviewForbiddenError);
 await expect(x.service.approve({...account,role},patientId,docId,input())).rejects.toBeInstanceOf(ReviewForbiddenError);expect(x.db.query).not.toHaveBeenCalled();
});
test('relación revocada y documento ajeno no aprueban',async()=>{
 const x=setup();x.revoke();await expect(x.service.approve(account,patientId,docId,input())).rejects.toBeInstanceOf(ReviewNotFoundError);
 const y=setup();await expect(y.service.approve(account,patientId,id,input())).rejects.toBeInstanceOf(ReviewNotFoundError);expect(y.saved()).toBeNull();
});
test('segunda revisión y otro procesamiento no sobrescriben',async()=>{
 const x=setup();await x.service.approve(account,patientId,docId,input());const snapshot=JSON.stringify(x.saved());
 await expect(x.service.approve(account,patientId,docId,input({observations:'Intento posterior'}))).rejects.toBeInstanceOf(ReviewConflictError);expect(JSON.stringify(x.saved())).toBe(snapshot);
 expect((await x.service.get(account,patientId,docId)).canReview).toBe(false);
 const y=setup();await expect(y.service.approve(account,patientId,docId,input({processingId:id}))).rejects.toBeInstanceOf(ReviewConflictError);
});
test.each(['queued','processing','rejected','failed'])('estado %s no se aprueba',async status=>{
 const x=setup();x.setStatus(status);await expect(x.service.approve(account,patientId,docId,input())).rejects.toBeInstanceOf(ReviewConflictError);expect(x.saved()).toBeNull();
});
test('bloquea procesamiento y auditoría identifica consulta',async()=>{
 const x=setup();await x.service.approve(account,patientId,docId,input());await x.service.get(account,patientId,docId);
 expect(x.db.query.mock.calls.some(([sql])=>sql.includes('FOR UPDATE'))).toBe(true);expect(x.db.query.mock.calls.some(([sql])=>sql.includes('FOR SHARE OF x,p,r,d'))).toBe(true);
 expect(x.audit[0].slice(1)).toEqual([id,patientId,docId,docId,processingId]);
});
test('HTTP requiere sesión, devuelve 201, conflicto 409 y no-store',async()=>{
 const x=setup(),app=createApp({find:async()=>account},undefined,undefined,undefined,undefined,undefined,x.service);
 const path=`/api/professional/patients/${patientId}/documents/${docId}/review`;
 expect((await request(app).post(path).send(input())).status).toBe(401);
 const first=await request(app).post(path).set('Authorization','Bearer '+'a'.repeat(64)).send(input());expect(first.status).toBe(201);expect(first.headers['cache-control']).toBe('no-store');
 expect((await request(app).post(path).set('Authorization','Bearer '+'a'.repeat(64)).send(input())).status).toBe(409);
});
