import {isDeepStrictEqual} from 'node:util';
import {createReviewService} from '../reviews/service';
import {createExplanationService} from '../explanations/service';
import {createExamAssistantService} from '../exam-assistant/service';
import {createProcessingService} from '../processing/service';
import {createCareInboxService} from '../care/inbox';
import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {createCredentialVerificationService} from '../professional-credentials/service';
import {createCareCatalogService} from '../care/catalog';
import {createCareUploadService} from '../care/upload';
import {createDocumentService} from '../documents/service';

export async function verifyCareReview(client:Pick<PoolClient,'query'>):Promise<number>{
 let begun=false,checks=0;
 const check=(ok:boolean)=>{if(!ok)throw new Error('Comprobación de revisión incorrecta.');checks++;};
 try{
  await client.query('BEGIN');begun=true;
  if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['023_care_review_registry'])).rows.length)throw new Error('Falta migración 023.');
  const patient={id:randomUUID(),role:'paciente'} as AccountSummary,admin={id:randomUUID(),role:'administrador'} as AccountSummary;
  const professional=randomUUID(),person=randomUUID(),member=randomUUID(),clinic=randomUUID(),branch=randomUUID(),otherBranch=randomUUID(),specialty=randomUUID();
  // Código numérico compatible con el filtro, elegido dentro de una transacción que se revierte.
  const candidates=await client.query<{code:string}>(`SELECT lpad(n::text,5,'0') AS code FROM generate_series(90000,99999) n
   WHERE NOT EXISTS(SELECT 1 FROM public.vitalia_communes WHERE code=lpad(n::text,5,'0')) LIMIT 2`);
  if(candidates.rows.length!==2)throw new Error('No hay códigos sintéticos disponibles.');
  const [commune,otherCommune]=candidates.rows.map(x=>x.code),region='T'+randomUUID().slice(0,8),province='T'+randomUUID().slice(0,8);
  await client.query('INSERT INTO public.vitalia_regions(code,name) VALUES($1,$2)',[region,'Región sintética']);
  await client.query('INSERT INTO public.vitalia_provinces(code,region_code,name) VALUES($1,$2,$3)',[province,region,'Provincia sintética']);
  for(const code of [commune,otherCommune])await client.query('INSERT INTO public.vitalia_communes(code,province_code,name) VALUES($1,$2,$3)',[code,province,'Comuna sintética']);
  for(const [id,role] of [[patient.id,'paciente'],[admin.id,'administrador'],[professional,'profesional']])await client.query("INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login',$3)",[id,id+'@example.invalid',role]);
  await client.query("INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname,phone) VALUES($1,$2,'Profesional','Sintético','+56900000000')",[person,professional]);
  await client.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1)',[person]);
  await client.query("INSERT INTO public.vitalia_clinics(id,name) VALUES($1,'Clínica sintética')",[clinic]);
  for(const [id,code]of [[branch,commune],[otherBranch,otherCommune]])await client.query("INSERT INTO public.vitalia_branches(id,clinic_id,commune_code,name,street,address_number) VALUES($1,$2,$3,'Sucursal sintética','Calle ficticia','S/N')",[id,clinic,code]);
  await client.query('INSERT INTO public.vitalia_specialties(id,name) VALUES($1,$2)',[specialty,'Especialidad sintética '+specialty]);
  await client.query('INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id,active) VALUES($1,$2,$3,true)',[member,clinic,person]);
  await client.query('INSERT INTO public.vitalia_membership_specialties(clinic_id,membership_id,specialty_id) VALUES($1,$2,$3)',[clinic,member,specialty]);
  for(const id of [branch,otherBranch])await client.query('INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)',[clinic,id,member]);
  const catalog=createCareCatalogService(client),read=(extra={})=>catalog.list(patient,{communeCode:commune,...extra});
  check((await read()).items.length===0);
  const db={query:client.query.bind(client),transaction:async fn=>{
   await client.query('SAVEPOINT care_upload_work');
   try{const result=await fn(client);await client.query('RELEASE SAVEPOINT care_upload_work');return result;}
   catch(e){await client.query('ROLLBACK TO SAVEPOINT care_upload_work');await client.query('RELEASE SAVEPOINT care_upload_work');throw e;}
  }} as DocumentDatabase;
  const credentials=createCredentialVerificationService(db),req=randomUUID();
  await credentials.request(admin,clinic,member,{requestId:req,expectedRevision:0,registrationReference:'SYNTHETIC',supportingReference:'Respaldo exclusivamente sintético'});
  await credentials.decide(admin,clinic,member,req,{requestId:randomUUID(),expectedRevision:0,decision:'verified',sourceReference:'Fuente sintética',checkedAt:new Date(Date.now()-10000).toISOString(),reason:'Prueba de catálogo exclusivamente sintética',confirmed:true});
  await client.query("INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname,preferred_commune_code) VALUES($1,$2,'Paciente','Sintético',$3)",[randomUUID(),patient.id,commune]);
  const care=createCareUploadService(db),objects=new Map<string,Buffer>();
  const storage={put:async(key:string,body:Buffer)=>{objects.set(key,body);},remove:async(key:string)=>{objects.delete(key);},read:async(key:string)=>objects.get(key)!};
  const documents=createDocumentService(db,storage,care);
  const ctx=await care.context(patient);check(ctx.email===patient.id+'@example.invalid');check(ctx.street===null);
  const input={clinicId:clinic,branchId:branch,membershipId:member,specialtyId:specialty,residenceCommuneCode:otherCommune,consultationCommuneCode:commune,street:'Calle ficticia',addressNumber:'S/N',phone:'+56900000000',confirmed:true,saveProfile:true,profileRevision:ctx.revision};
  const file={name:'sintetico.pdf',contentType:'application/pdf',body:Buffer.from('%PDF-1.4\nsynthetic\n%%EOF'),metadata:{examName:'Examen sintético',examType:'Laboratorio',examDate:'2026-01-01',care:JSON.stringify(input)}};
  async function denied(fn:()=>Promise<unknown>,status:number){let actual=0;try{await fn();}catch(e){actual=(e as {status:number}).status;}check(actual===status);}
  await denied(()=>documents.upload(patient,{...file,metadata:{...file.metadata,care:undefined}}),400);
  await denied(()=>documents.upload(patient,{...file,metadata:{...file.metadata,care:JSON.stringify({...input,email:'otra@example.invalid'})}}),400);
  check(objects.size===0);
  await denied(()=>care.context(admin),403);
  await denied(()=>documents.upload(patient,{...file,metadata:{...file.metadata,care:JSON.stringify({...input,consultationCommuneCode:otherCommune})}}),409);
  const uploaded=await documents.upload(patient,file);
  const actor={id:professional,role:'profesional'} as AccountSummary;
  let reads=0;
  const reader={read:async(key:string)=>{reads++;return storage.read(key);}};
  const inbox=createCareInboxService(db,reader);
  const list=await inbox.list(actor,{});check(list.items.length===1);
  const careId=list.items[0].id;
  check(!JSON.stringify(list).includes(input.phone));
  check(!(await inbox.review(actor,careId)).canReview);
  await inbox.begin(actor,careId,{expectedRevision:0});
  check((await inbox.review(actor,careId)).processingStatus==='not_requested');
  const extraction={examen:'Examen sintético',fecha:'01-01-2026',resultados:[{nombre:'Glucosa',valor:'90',unidad:'mg/dL',rango_referencia:'70-100'}]};
  const text='Texto exclusivamente sintético';
  const result={status:'requires_review',source:'pdf',method:'direct',reading:{status:'text_ready',text,pageCount:1,incidents:[]},ocr:null,inputText:text,
   ai:{status:'requires_review',raw:JSON.stringify(extraction),extraction,incidents:[],approved:false,model:'synthetic',promptVersion:3,elapsedMs:0},approved:false};
  const processing=randomUUID();
  await client.query("INSERT INTO public.vitalia_document_processing(id,document_id,status,model,prompt_version,result,started_at,finished_at) VALUES($1,$2,'requires_review','synthetic',3,$3::jsonb,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",[processing,uploaded.id,JSON.stringify(result)]);
  const pending=await inbox.review(actor,careId);check(pending.canReview&&pending.expectedRevision===1);
  check(isDeepStrictEqual(pending.originalExtraction,extraction));check(pending.sourceText===text);
  const reviewed={...extraction,resultados:[{...extraction.resultados[0],valor:'91'}]};
  const body={processingId:processing,extraction:reviewed,observations:'Corrección exclusivamente sintética cotejada en el documento ficticio',confirmedOriginal:true,expectedRevision:1};
  await denied(()=>inbox.approve(patient,careId,body),403);await denied(()=>inbox.approve(admin,careId,body),403);
  const otherId=randomUUID();await client.query("INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login','profesional')",[otherId,otherId+'@example.invalid']);
  const other={id:otherId,role:'profesional'} as AccountSummary;
  await denied(()=>inbox.review(other,careId),404);await denied(()=>inbox.approve(other,careId,body),404);
  await denied(()=>inbox.approve(actor,careId,{...body,observations:''}),400);
  await denied(()=>inbox.approve(actor,careId,{...body,confirmedOriginal:false}),400);
  await denied(()=>inbox.approve(actor,careId,{...body,extraction:{...extraction,fecha:'31-02-2026'}}),400);
  await denied(()=>inbox.approve(actor,careId,{...body,processingId:randomUUID()}),409);
  await denied(()=>inbox.approve(actor,careId,{...body,expectedRevision:0}),409);
  const failing={...db,transaction:async(fn:(tx:Pick<PoolClient,'query'>)=>Promise<unknown>)=>db.transaction(tx=>fn({query:async(sql:unknown,args:unknown)=>{
   const value=await tx.query(sql as string,args as unknown[]);if(String(sql).includes("SET status='completed'"))throw {code:'42501'};return value;
  }} as Pick<PoolClient,'query'>))} as DocumentDatabase;
  await denied(()=>createCareInboxService(failing,reader).approve(actor,careId,body),503);
  check((await client.query('SELECT id FROM public.vitalia_care_reviews WHERE care_id=$1',[careId])).rows.length===0);
  check((await client.query('SELECT id FROM public.vitalia_approved_review_refs WHERE document_id=$1',[uploaded.id])).rows.length===0);
  check((await inbox.details(actor,careId)).care.status==='active');
  const saved=await inbox.approve(actor,careId,body);check(saved.approved&&saved.extraction.resultados[0].valor==='91');
  check((await inbox.approve(actor,careId,body)).id===saved.id);
  check((await client.query('SELECT id FROM public.vitalia_care_reviews WHERE care_id=$1',[careId])).rows.length===1);
  check((await inbox.details(actor,careId)).care.status==='completed');
  check((await inbox.review(actor,careId)).review?.id===saved.id);
  await denied(()=>inbox.approve(actor,careId,{...body,observations:'Otro fundamento sintético'}),409);
  check((await client.query("SELECT result#>>'{ai,extraction,resultados,0,valor}' AS v FROM public.vitalia_document_processing WHERE id=$1",[processing])).rows[0].v==='90');
  const original=(await client.query('SELECT original_extraction FROM public.vitalia_care_reviews WHERE care_id=$1',[careId])).rows[0].original_extraction;
  check(isDeepStrictEqual(original,extraction));
  const patientReview=await createReviewService(db).getPatient(patient,uploaded.id);
  check(patientReview.review?.extraction.resultados[0].valor==='91');
  const educational=createExplanationService(db,async()=>{throw new Error('No debe invocar modelos');});
  const explanation=await educational.get(patient,uploaded.id);check(explanation.status==='not_requested'&&explanation.reviewId===saved.id);
  const assistant=createExamAssistantService(db,async()=>{throw new Error('No debe invocar modelos');});
  check((await assistant.get(patient,uploaded.id)).reviewId===saved.id);
  const thread=randomUUID();await client.query('INSERT INTO public.vitalia_exam_assistant_threads(id,review_id,document_id,patient_id,review_snapshot) VALUES($1,$2,$3,$4,$5::jsonb)',[thread,saved.id,uploaded.id,patient.id,JSON.stringify(reviewed)]);
  check((await assistant.get(patient,uploaded.id)).status==='available');
  check((await createProcessingService(client).get(patient,uploaded.id)).reviewStatus==='approved');
  await client.query('SAVEPOINT immutable_review');let blocked=false;
  try{await client.query("UPDATE public.vitalia_care_reviews SET observations='Cambio' WHERE id=$1",[saved.id]);}catch{blocked=true;}
  await client.query('ROLLBACK TO SAVEPOINT immutable_review');await client.query('RELEASE SAVEPOINT immutable_review');check(blocked);
  await client.query('SAVEPOINT immutable_ref');blocked=false;
  try{await client.query('DELETE FROM public.vitalia_approved_review_refs WHERE id=$1',[saved.id]);}catch{blocked=true;}
  await client.query('ROLLBACK TO SAVEPOINT immutable_ref');await client.query('RELEASE SAVEPOINT immutable_ref');check(blocked);
  await client.query('UPDATE public.vitalia_clinic_memberships SET active=false WHERE id=$1',[member]);
  await denied(()=>inbox.review(actor,careId),404);
  check((await createReviewService(db).getPatient(patient,uploaded.id)).review?.approved===true);
  check((await client.query('SELECT id FROM public.vitalia_patient_assignments WHERE patient_id=$1',[patient.id])).rows.length===0);
  await client.query('UPDATE public.vitalia_clinic_memberships SET active=true WHERE id=$1',[member]);
  // Un documento histórico sigue utilizando la revisión anterior, sin copiarla al circuito nuevo.
  const {care:unused,...legacyMetadata}=file.metadata;
  const historical=await createDocumentService(db,storage).upload(patient,{...file,metadata:legacyMetadata});
  const oldProcessing=randomUUID();
  await client.query("INSERT INTO public.vitalia_document_processing(id,document_id,status,model,prompt_version,result,started_at,finished_at) VALUES($1,$2,'requires_review','synthetic',3,$3::jsonb,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",[oldProcessing,historical.id,JSON.stringify(result)]);
  await client.query('INSERT INTO public.vitalia_patient_assignments(id,patient_id,professional_id,created_by,updated_by) VALUES($1,$2,$3,$4,$4)',[randomUUID(),patient.id,professional,admin.id]);
  const oldSaved=await createReviewService(db).approve(actor,patient.id,historical.id,{processingId:oldProcessing,extraction,observations:'',confirmedOriginal:true});
  check((await client.query('SELECT legacy_review_id FROM public.vitalia_approved_review_refs WHERE id=$1',[oldSaved.id])).rows[0].legacy_review_id===oldSaved.id);
  check((await educational.get(patient,historical.id)).reviewId===oldSaved.id);
  check((await assistant.get(patient,historical.id)).reviewId===oldSaved.id);
  const wrongPatient={id:otherId,role:'paciente'} as AccountSummary;
  try{await createReviewService(db).getPatient(wrongPatient,uploaded.id);check(false);}catch(e){check((e as Error).constructor.name==='ReviewNotFoundError');}
  await denied(()=>educational.get(wrongPatient,uploaded.id).catch(e=>{if((e as Error).constructor.name==='ExplanationNotFoundError')throw {status:404};throw e;}),404);
  check((await client.query('SELECT id FROM public.vitalia_care_reviews WHERE document_id=$1',[historical.id])).rows.length===0);
  return checks;
 }finally{if(begun)await client.query('ROLLBACK');}
}
