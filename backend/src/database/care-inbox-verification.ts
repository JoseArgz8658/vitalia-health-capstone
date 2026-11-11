import {createCareInboxService} from '../care/inbox';
import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {createCredentialVerificationService} from '../professional-credentials/service';
import {createCareCatalogService} from '../care/catalog';
import {createCareUploadService} from '../care/upload';
import {createDocumentService} from '../documents/service';

export async function verifyCareInbox(client:Pick<PoolClient,'query'>):Promise<number>{
 let begun=false,checks=0;
 const check=(ok:boolean)=>{if(!ok)throw new Error('Comprobación de bandeja incorrecta.');checks++;};
 try{
  await client.query('BEGIN');begun=true;
  if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['022_care_inbox'])).rows.length)throw new Error('Falta migración 022.');
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
  const detail=await inbox.details(actor,careId);
  check(detail.contact.phone===input.phone&&detail.contact.email===ctx.email);
  check(detail.care.document.id===uploaded.id&&detail.care.status==='requested');
  const otherId=randomUUID(),otherPerson=randomUUID(),otherMember=randomUUID();
  await client.query("INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login','profesional')",[otherId,otherId+'@example.invalid']);
  await client.query("INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname) VALUES($1,$2,'Jefatura','Sintética')",[otherPerson,otherId]);
  await client.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1)',[otherPerson]);
  await client.query("INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id,clinical_role,active) VALUES($1,$2,$3,'jefe_clinico',true)",[otherMember,clinic,otherPerson]);
  const outsider={id:otherId,role:'profesional'} as AccountSummary;
  check((await inbox.list(outsider,{})).items.length===0);
  await denied(()=>inbox.details(outsider,careId),404);
  await denied(()=>inbox.download(outsider,careId),404);check(reads===0);
  await denied(()=>inbox.begin(outsider,careId,{expectedRevision:0}),404);
  await denied(()=>inbox.list(admin,{}),403);await denied(()=>inbox.details(patient,careId),403);
  // Una asignación general de paciente tampoco amplía el acceso de otra jefatura.
  await client.query('INSERT INTO public.vitalia_patient_assignments(id,patient_id,professional_id,created_by,updated_by) VALUES($1,$2,$3,$4,$4)',[randomUUID(),patient.id,otherId,admin.id]);
  await denied(()=>inbox.details(outsider,careId),404);
  await denied(()=>inbox.begin(actor,careId,{expectedRevision:99}),409);
  const failing={...db,transaction:async(fn:(tx:Pick<PoolClient,'query'>)=>Promise<unknown>)=>db.transaction(tx=>fn({query:async(sql:unknown,args:unknown)=>{
   const result=await tx.query(sql as string,args as unknown[]);
   if(String(sql).startsWith('UPDATE public.vitalia_exam_care'))throw {code:'42501'};
   return result;
  }} as Pick<PoolClient,'query'>))} as DocumentDatabase;
  await denied(()=>createCareInboxService(failing,reader).begin(actor,careId,{expectedRevision:0}),503);
  check((await inbox.details(actor,careId)).care.status==='requested');
  check((await client.query("SELECT id FROM public.vitalia_care_audit WHERE care_id=$1 AND action='active'",[careId])).rows.length===0);
  check((await inbox.begin(actor,careId,{expectedRevision:0})).started);
  check((await inbox.begin(actor,careId,{expectedRevision:0})).replayed);
  const active=await inbox.details(actor,careId);check(active.care.status==='active'&&active.care.revision===1);
  check((await client.query("SELECT id FROM public.vitalia_care_audit WHERE care_id=$1 AND action='active'",[careId])).rows.length===1);
  const downloaded=await inbox.download(actor,careId);check(downloaded.body.equals(file.body));check(reads===1);
  check((await client.query("SELECT id FROM public.vitalia_care_access_audit WHERE care_id=$1 AND action='download'",[careId])).rows.length===1);
  for(const [sql,args]of [
    ['UPDATE public.vitalia_clinic_memberships SET active=false WHERE id=$1',[member]],
    ['UPDATE public.vitalia_clinics SET active=false WHERE id=$1',[clinic]],
    ['UPDATE public.vitalia_branches SET active=false WHERE id=$1',[branch]],
    ['UPDATE public.vitalia_specialties SET active=false WHERE id=$1',[specialty]],
    ["UPDATE public.vitalia_professional_profiles SET registration_reference='ALTERADA' WHERE person_id=$1",[person]],
    ["UPDATE public.vitalia_account_roles SET active=false WHERE account_id=$1 AND role_code='profesional'",[professional]],
    ['DELETE FROM public.vitalia_membership_specialties WHERE membership_id=$1',[member]],
  ] as [string,unknown[]][]){
   await client.query('SAVEPOINT disabled_care');await client.query(sql,args);
   check((await inbox.list(actor,{})).items.length===0);await denied(()=>inbox.details(actor,careId),404);
   await client.query('ROLLBACK TO SAVEPOINT disabled_care');await client.query('RELEASE SAVEPOINT disabled_care');
  }
  const beforeRace=reads;
  const raced=createCareInboxService(db,{read:async(key:string)=>{const body=await reader.read(key);await client.query('UPDATE public.vitalia_clinic_memberships SET active=false WHERE id=$1',[member]);return body;}});
  await denied(()=>raced.download(actor,careId),404);check(reads===beforeRace+1);
  check((await client.query("SELECT id FROM public.vitalia_care_access_audit WHERE care_id=$1 AND action='download'",[careId])).rows.length===1);
  await client.query('UPDATE public.vitalia_clinic_memberships SET active=true WHERE id=$1',[member]);
  await client.query('SAVEPOINT immutable_access');let blocked=false;
  try{await client.query("UPDATE public.vitalia_care_access_audit SET action='view' WHERE care_id=$1",[careId]);}catch{blocked=true;}
  await client.query('ROLLBACK TO SAVEPOINT immutable_access');await client.query('RELEASE SAVEPOINT immutable_access');check(blocked);
  await client.query("UPDATE public.vitalia_exam_care SET status='cancelled',updated_by=$2,revision=revision+1 WHERE id=$1",[careId,patient.id]);
  check((await inbox.list(actor,{})).items.length===0);await denied(()=>inbox.details(actor,careId),404);
  check((await client.query('SELECT id FROM public.vitalia_document_processing WHERE document_id=$1',[uploaded.id])).rows.length===0);
  return checks;
 }finally{if(begun)await client.query('ROLLBACK');}
}
