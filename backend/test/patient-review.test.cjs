const request=require('supertest');
const {createApp}=require('../dist/app');
const {createReviewService,ReviewForbiddenError,ReviewNotFoundError}=require('../dist/reviews/service');
const id='22222222-2222-4222-8222-222222222222',doc='33333333-3333-4333-8333-333333333333';
const account={id,role:'paciente'};
const extraction={examen:'Ficticio',fecha:'29-09-2026',resultados:[{nombre:'Alfa',valor:'0,00',unidad:null,rango_referencia:null}]};
function setup({owned=true,review=true}={}){
 const query=jest.fn(async(sql,args)=>{
  expect(args).toEqual([doc,id]);
  if(sql.startsWith('SELECT id FROM public.vitalia_documents')){
   expect(sql).toContain("status='stored'");expect(sql).toContain('patient_id=$2');
   return {rows:owned?[{id:doc}]:[]};
  }
  expect(sql).toContain('v.patient_id=$2 AND v.approved=true');
  expect(sql).not.toContain('original_extraction');
  return {rows:review?[{reviewed_extraction:extraction,observations:'Valor cotejado.',created_at:new Date('2026-10-01T18:00:00Z'),original_extraction:{secret:'hidden'},reviewer_email:'hidden@example.com'}]:[]};
 });
 const service=createReviewService({query,transaction:work=>work({query})});return {query,service};
}
test('solo entrega copia aprobada, observaciones y fecha; conserva cero y null',async()=>{
 const x=setup();const result=await x.service.getPatient(account,doc);
 expect(result.review).toEqual({extraction,observations:'Valor cotejado.',reviewedAt:new Date('2026-10-01T18:00:00Z'),approved:true});
 expect(x.query).toHaveBeenCalledTimes(2);expect(JSON.stringify(result)).not.toContain('hidden');
});
test('documento propio sin aprobación no expone extracción pendiente',async()=>{
 expect(await setup({review:false}).service.getPatient(account,doc)).toEqual({review:null});
});
test('documento ajeno o no almacenado falla antes de leer revisión',async()=>{
 const x=setup({owned:false});await expect(x.service.getPatient(account,doc)).rejects.toBeInstanceOf(ReviewNotFoundError);expect(x.query).toHaveBeenCalledTimes(1);
});
test.each(['profesional','administrador'])('rol %s no consulta como paciente',async role=>{
 const x=setup();await expect(x.service.getPatient({...account,role},doc)).rejects.toBeInstanceOf(ReviewForbiddenError);expect(x.query).not.toHaveBeenCalled();
});
test('identificador malformado falla antes de SQL',async()=>{
 const x=setup();await expect(x.service.getPatient(account,"' OR 1=1")).rejects.toBeInstanceOf(ReviewNotFoundError);expect(x.query).not.toHaveBeenCalled();
});
test('HTTP requiere sesión, rechaza otros roles y query, no permite POST',async()=>{
 const x=setup(),token='a'.repeat(64);let role='paciente';
 const app=createApp({find:async()=>({...account,role})},undefined,undefined,undefined,undefined,undefined,x.service);
 const path=`/api/documents/${doc}/review`,get=()=>request(app).get(path).set('Authorization',`Bearer ${token}`);
 expect((await request(app).get(path)).status).toBe(401);
 const ok=await get();expect(ok.status).toBe(200);expect(ok.headers['cache-control']).toBe('no-store');expect(ok.body.review.extraction).toEqual(extraction);
 role='administrador';expect((await get()).status).toBe(403);role='paciente';
 expect((await request(app).get(path+'?patientId=otro').set('Authorization',`Bearer ${token}`)).status).toBe(400);
 expect((await request(app).post(path).set('Authorization',`Bearer ${token}`).send({approved:true})).status).toBe(404);
});
test('HTTP documento ajeno responde 404 sin filtrar revisión',async()=>{
 const x=setup({owned:false});const app=createApp({find:async()=>account},undefined,undefined,undefined,undefined,undefined,x.service);
 const res=await request(app).get(`/api/documents/${doc}/review`).set('Authorization','Bearer '+'a'.repeat(64));
 expect(res.status).toBe(404);expect(res.body.review).toBeUndefined();expect(x.query).toHaveBeenCalledTimes(1);
});
