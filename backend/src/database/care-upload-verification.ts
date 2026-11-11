import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {createCredentialVerificationService} from '../professional-credentials/service';
import {createCareCatalogService} from '../care/catalog';
import {createCareUploadService} from '../care/upload';
import {createDocumentService} from '../documents/service';
import {createProfessionalService} from '../professional/service';
import {createReviewService} from '../reviews/service';

export async function verifyCareUpload(client:Pick<PoolClient,'query'>):Promise<number>{
 let begun=false,checks=0;
 const check=(ok:boolean)=>{if(!ok)throw new Error('Comprobación de carga con atención incorrecta.');checks++;};
 try{
  await client.query('BEGIN');begun=true;
  if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['021_care_upload'])).rows.length)throw new Error('Falta migración 021.');
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
  const uploaded=await documents.upload(patient,file);check(objects.size===1);
  const persisted=(await client.query('SELECT * FROM public.vitalia_care_contacts WHERE document_id=$1',[uploaded.id])).rows[0];
  check(persisted.phone===input.phone&&persisted.email===ctx.email);
  check(persisted.residence_commune_code===otherCommune&&persisted.consultation_commune_code===commune);
  check((await client.query('SELECT responsible_membership_id,branch_id FROM public.vitalia_exam_care WHERE document_id=$1',[uploaded.id])).rows[0].responsible_membership_id===member);
  check((await care.context(patient)).street===input.street);
  check((await care.context(patient)).preferredCommuneCode===commune);
  check((await care.context(patient)).residenceCommuneCode===otherCommune);
  check((await client.query('SELECT care_flow FROM public.vitalia_documents WHERE id=$1',[uploaded.id])).rows[0].care_flow===true);
  // El flujo heredado no puede abrir estos documentos, aunque exista asignación de paciente.
  await client.query('INSERT INTO public.vitalia_patient_assignments(id,patient_id,professional_id,created_by,updated_by) VALUES($1,$2,$3,$4,$4)',[randomUUID(),patient.id,professional,admin.id]);
  const clinician={id:professional,role:'profesional'} as AccountSummary,legacy=createProfessionalService(db,storage),reviews=createReviewService(db);
  check((await legacy.list(clinician,patient.id)).length===0);
  try{await legacy.extraction(clinician,patient.id,uploaded.id);check(false);}catch(e){check((e as Error).constructor.name==='ProfessionalNotFoundError');}
  try{await reviews.get(clinician,patient.id,uploaded.id);check(false);}catch(e){check((e as Error).constructor.name==='ReviewNotFoundError');}
  await denied(()=>documents.upload(patient,file),409); // revisión del perfil obsoleta
  const updated=await care.context(patient),next={...input,profileRevision:updated.revision,saveProfile:false,street:'Otra calle ficticia'};
  const second=await documents.upload(patient,{...file,metadata:{...file.metadata,care:JSON.stringify(next)}});
  check((await care.context(patient)).street===input.street);
  check((await client.query('SELECT street FROM public.vitalia_care_contacts WHERE document_id=$1',[second.id])).rows[0].street===next.street);
  const previousObjects=objects.size;
  // Cambio entre preflight y confirmación: revierte DB y compensa el objeto.
  const changingStorage={...storage,put:async(key:string,body:Buffer)=>{await storage.put(key,body);await client.query('UPDATE public.vitalia_clinic_memberships SET active=false WHERE id=$1',[member]);}};
  await denied(()=>createDocumentService(db,changingStorage,care).upload(patient,{...file,metadata:{...file.metadata,care:JSON.stringify(next)}}),409);
  check(objects.size===previousObjects);
  check((await client.query("SELECT count(*)::int AS n FROM public.vitalia_documents WHERE patient_id=$1 AND status='stored'",[patient.id])).rows[0].n===2);
  await client.query('UPDATE public.vitalia_clinic_memberships SET active=true WHERE id=$1',[member]);
  await client.query('SAVEPOINT immutable_contact');let blocked=false;
  try{await client.query('UPDATE public.vitalia_care_contacts SET phone=$2 WHERE document_id=$1',[uploaded.id,'+56911111111']);}catch{blocked=true;}
  await client.query('ROLLBACK TO SAVEPOINT immutable_contact');await client.query('RELEASE SAVEPOINT immutable_contact');check(blocked);
  const beforeFailure=await care.context(patient);
  const refusing={...db,transaction:async(fn:(tx:Pick<PoolClient,'query'>)=>Promise<unknown>)=>db.transaction(tx=>fn({query:async(sql:unknown,args:unknown)=>{
   if(String(sql).includes('INSERT INTO public.vitalia_care_contacts'))throw {code:'42501'};
   return tx.query(sql as string,args as unknown[]);
  }} as Pick<PoolClient,'query'>))} as DocumentDatabase;
  await denied(()=>createDocumentService(refusing,storage,care).upload(patient,{...file,metadata:{...file.metadata,care:JSON.stringify({...next,profileRevision:beforeFailure.revision,saveProfile:true,street:'No debe persistir'})}}),503);
  check((await care.context(patient)).street===input.street);
  check(objects.size===previousObjects);
  check((await client.query('SELECT count(*)::int AS n FROM public.vitalia_care_contacts WHERE patient_id=$1',[patient.id])).rows[0].n===2);
  await client.query('SAVEPOINT no_downgrade');blocked=false;
  try{await client.query('UPDATE public.vitalia_documents SET care_flow=false WHERE id=$1',[uploaded.id]);}catch{blocked=true;}
  await client.query('ROLLBACK TO SAVEPOINT no_downgrade');await client.query('RELEASE SAVEPOINT no_downgrade');check(blocked);
  const {care:unused,...oldMetadata}=file.metadata;
  const old=await createDocumentService(db,storage).upload(patient,{...file,metadata:oldMetadata});
  check((await legacy.list(clinician,patient.id)).length===1);
  await client.query('SAVEPOINT no_orphan');blocked=false;
  try{await client.query('UPDATE public.vitalia_documents SET care_flow=true WHERE id=$1',[old.id]);await client.query('SET CONSTRAINTS ALL IMMEDIATE');}catch{blocked=true;}
  await client.query('ROLLBACK TO SAVEPOINT no_orphan');await client.query('RELEASE SAVEPOINT no_orphan');check(blocked);
  await client.query('SET CONSTRAINTS ALL IMMEDIATE');check(true);
  return checks;
 }finally{if(begun)await client.query('ROLLBACK');}
}
