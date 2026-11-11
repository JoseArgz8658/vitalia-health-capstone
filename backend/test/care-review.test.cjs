const request=require('supertest'),express=require('express');
const {createCareInboxService}=require('../dist/care/inbox');
const {createCareInboxRouter}=require('../dist/care/inbox-router');
const {reviewedExtractionValid}=require('../dist/reviews/validation');
const {verifyCareReview}=require('../dist/database/care-review-verification');
const id='11111111-1111-4111-8111-111111111111',a={id,role:'profesional'},token='a'.repeat(64);
const extraction={examen:'Examen sintético',fecha:'01-01-2026',resultados:[{nombre:'Glucosa',valor:'90',unidad:'mg/dL',rango_referencia:'70-100'}]};
const body={processingId:id,extraction,observations:'',confirmedOriginal:true,expectedRevision:1};
test.each(['paciente','administrador'])('%s no consulta ni aprueba revisión',async role=>{
 const transaction=jest.fn(),s=createCareInboxService({transaction},{});
 await expect(s.review({...a,role},id)).rejects.toMatchObject({status:403});await expect(s.approve({...a,role},id,body)).rejects.toMatchObject({status:403});expect(transaction).not.toHaveBeenCalled();
});
test.each([{confirmedOriginal:false},{expectedRevision:'1'},{expectedRevision:-1},{patientId:id},{reviewerId:id},{extraction:{...extraction,diagnostico:'inventado'}},{processingId:'x'}])('rechaza cuerpo alterado %j',async extra=>{
 const transaction=jest.fn();await expect(createCareInboxService({transaction},{}).approve(a,id,{...body,...extra})).rejects.toMatchObject({status:400});expect(transaction).not.toHaveBeenCalled();
});
test('observaciones obligatorias para corrección o dato ausente, sin convertirlo en cero',()=>{
 const corrected={...extraction,resultados:[{...extraction.resultados[0],valor:'91'}]},missing={...extraction,resultados:[{...extraction.resultados[0],valor:null}]};
 expect(reviewedExtractionValid(extraction,extraction,'')).toBe(true);
 expect(reviewedExtractionValid(corrected,extraction,'')).toBe(false);expect(reviewedExtractionValid(corrected,extraction,'Cotejo sintético')).toBe(true);
 expect(reviewedExtractionValid(missing,extraction,'')).toBe(false);expect(reviewedExtractionValid(missing,extraction,'Ausente en original')).toBe(true);
});
test.each(['31-02-2026','2026-01-01'])('fecha inválida %s se rechaza incluso con observación',fecha=>{
 expect(reviewedExtractionValid({...extraction,fecha},extraction,'Cotejado')).toBe(false);
});
test('sin resultados no permite aprobación',()=>{expect(reviewedExtractionValid({...extraction,resultados:[]},extraction,'No extraídos')).toBe(false);});
test('informe ampliado no se elimina durante revisión',()=>{
 expect(reviewedExtractionValid(extraction,{...extraction,informe:{}},'Cotejado')).toBe(false);
});
test('lectura ajena no consulta procesamiento ni auditoría',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(createCareInboxService({transaction:fn=>fn({query})},{}).review(a,id)).rejects.toMatchObject({status:404});expect(query).toHaveBeenCalledTimes(1);
});
test.each(['42P01','42703','42501'])('esquema/permiso %s no devuelve extracción parcial',async code=>{
 await expect(createCareInboxService({transaction:async()=>{throw {code};}},{}).review(a,id)).rejects.toMatchObject({status:503});
});
function app(user=a){const s={review:jest.fn(async()=>({canReview:false})),approve:jest.fn(async()=>({approved:true}))},x=express();x.use(express.json());x.use('/api/care-inbox',createCareInboxRouter({find:async()=>user},s));return {app:x,s};}
test.each([null,{...a,role:'paciente'},{...a,role:'administrador'}])('ruta de revisión exige sesión/rol %j',async user=>{
 const f=app(user);expect((await request(f.app).get(`/api/care-inbox/${id}/review`).set('Authorization','Bearer '+token)).status).toBe(user?403:401);expect(f.s.review).not.toHaveBeenCalled();
});
test('lectura y aprobación usan identidad de sesión y no-store',async()=>{
 const f=app();let r=await request(f.app).get(`/api/care-inbox/${id}/review`).set('Authorization','Bearer '+token);expect(r.status).toBe(200);expect(r.headers['cache-control']).toBe('no-store');expect(f.s.review).toHaveBeenCalledWith(a,id);
 r=await request(f.app).post(`/api/care-inbox/${id}/review`).set('Authorization','Bearer '+token).send(body);expect(r.status).toBe(201);expect(f.s.approve).toHaveBeenCalledWith(a,id,body);
});
test('query con otra identidad no llega al servicio',async()=>{
 const f=app();expect((await request(f.app).post(`/api/care-inbox/${id}/review?patientId=${id}`).set('Authorization','Bearer '+token).send(body)).status).toBe(400);expect(f.s.approve).not.toHaveBeenCalled();
});
test('verificador exige 023 y revierte sin insertar',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(verifyCareReview({query})).rejects.toThrow('Falta migración 023.');expect(query.mock.calls.at(-1)[0]).toBe('ROLLBACK');expect(query.mock.calls.some(([s])=>s.startsWith('INSERT'))).toBe(false);
});
test.each(['migrate-care-review','verify-care-review'])('CLI %s no expone secretos',file=>{
 const {spawnSync}=require('node:child_process'),r=spawnSync(process.execPath,[`dist/database/${file}.js`],{cwd:process.cwd(),encoding:'utf8',env:{...process.env,PGPORT:'inválido',PGPASSWORD:'no-exponer-clave'}});expect(r.status).toBe(1);expect(r.stderr).not.toContain('no-exponer-clave');
});
