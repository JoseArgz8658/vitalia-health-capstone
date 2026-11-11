import {createCareHistoryService} from '../care/history';
import {createCareInboxService} from '../care/inbox';
import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {createCredentialVerificationService} from '../professional-credentials/service';
import {createCareCatalogService} from '../care/catalog';
import {createCareUploadService} from '../care/upload';
import {createDocumentService} from '../documents/service';

export async function verifyCareReferral(client:Pick<PoolClient,'query'>):Promise<number>{
 let begun=false,checks=0;
 const check=(ok:boolean)=>{if(!ok)throw new Error('Comprobación de derivación incorrecta.');checks++;};
 try{
  await client.query('BEGIN');begun=true;
  if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['024_clinic_referrals'])).rows.length)throw new Error('Falta migración 024.');
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
  await inbox.begin(actor,careId,{expectedRevision:0});
  const targets=[] as {account:string;person:string;member:string;clinic:string;branch:string}[];
  for(let i=0;i<2;i++){
   const target={account:randomUUID(),person:randomUUID(),member:randomUUID(),clinic:i===0?clinic:randomUUID(),branch:randomUUID()};targets.push(target);
   await client.query("INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login','profesional')",[target.account,target.account+'@example.invalid']);
   if(i===1)await client.query("INSERT INTO public.vitalia_clinics(id,name) VALUES($1,'Otra clínica sintética')",[target.clinic]);
   await client.query("INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname) VALUES($1,$2,'Destino','Sintético')",[target.person,target.account]);
   await client.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1)',[target.person]);
   await client.query('INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id,active) VALUES($1,$2,$3,true)',[target.member,target.clinic,target.person]);
   await client.query("INSERT INTO public.vitalia_branches(id,clinic_id,commune_code,name,street,address_number) VALUES($1,$2,$3,'Destino ficticio','Calle ficticia','123')",[target.branch,target.clinic,commune]);
   await client.query('INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)',[target.clinic,target.branch,target.member]);
   await client.query('INSERT INTO public.vitalia_membership_specialties(clinic_id,membership_id,specialty_id) VALUES($1,$2,$3)',[target.clinic,target.member,specialty]);
   const request=randomUUID();await credentials.request(admin,target.clinic,target.member,{requestId:request,expectedRevision:0,registrationReference:'SYNTHETIC',supportingReference:'Evidencia exclusivamente sintética'});
   await credentials.decide(admin,target.clinic,target.member,request,{requestId:randomUUID(),expectedRevision:0,decision:'verified',sourceReference:'Fuente sintética',checkedAt:new Date(Date.now()-60000).toISOString(),reason:'Prueba sintética de derivación',confirmed:true});
  }
  const [target,outside]=targets,recipient={id:target.account,role:'profesional'} as AccountSummary;
  const history=createCareHistoryService(db),before=await history.get(patient,uploaded.id,{});check(before.items.length===1);
  await denied(()=>history.get({...patient,id:outside.account},uploaded.id,{}),404);
  const options=await inbox.referralOptions(actor,careId,{});check(options.items.length===1);
  check(options.items[0].membershipId===target.member&&options.expectedRevision===1);
  check(!JSON.stringify(options).includes(input.phone));
  const requestId=randomUUID(),body={requestId,expectedRevision:1,membershipId:target.member,branchId:target.branch,specialtyId:specialty,reason:'Continuidad de revisión exclusivamente sintética',confirmed:true};
  await denied(()=>inbox.refer(patient,careId,body),403);await denied(()=>inbox.refer(admin,careId,body),403);
  await denied(()=>inbox.refer(recipient,careId,body),404);
  await denied(()=>inbox.refer(actor,careId,{...body,confirmed:false}),400);
  await denied(()=>inbox.refer(actor,careId,{...body,expectedRevision:0}),409);
  await denied(()=>inbox.refer(actor,careId,{...body,membershipId:member,branchId:branch}),409);
  await denied(()=>inbox.refer(actor,careId,{...body,membershipId:outside.member,branchId:outside.branch}),409);
  await client.query('UPDATE public.vitalia_clinic_memberships SET active=false WHERE id=$1',[target.member]);
  check((await inbox.referralOptions(actor,careId,{})).items.length===0);
  await denied(()=>inbox.refer(actor,careId,body),409);
  await client.query('UPDATE public.vitalia_clinic_memberships SET active=true WHERE id=$1',[target.member]);
  const failing={...db,transaction:async(fn:(tx:Pick<PoolClient,'query'>)=>Promise<unknown>)=>db.transaction(tx=>fn({query:async(sql:unknown,args:unknown)=>{
   const value=await tx.query(sql as string,args as unknown[]);if(String(sql).includes('INSERT INTO public.vitalia_exam_referrals'))throw {code:'42501'};return value;
  }} as Pick<PoolClient,'query'>))} as DocumentDatabase;
  await denied(()=>createCareInboxService(failing,reader).refer(actor,careId,body),503);
  check((await inbox.details(actor,careId)).care.status==='active');
  check((await client.query('SELECT id FROM public.vitalia_exam_care WHERE document_id=$1',[uploaded.id])).rows.length===1);
  check((await client.query('SELECT id FROM public.vitalia_exam_referrals WHERE source_care_id=$1',[careId])).rows.length===0);
  check((await inbox.refer(actor,careId,body)).referred);
  check((await inbox.refer(actor,careId,body)).replayed);
  await denied(()=>inbox.refer(actor,careId,{...body,reason:'Otro motivo sintético'}),409);
  await denied(()=>inbox.refer(actor,careId,{...body,requestId:randomUUID()}),404);
  await denied(()=>inbox.details(actor,careId),404);await denied(()=>inbox.download(actor,careId),404);check(reads===0);
  const incoming=await inbox.details(recipient,requestId);check(incoming.care.status==='requested');
  check(incoming.contact.phone===input.phone);check(incoming.referral?.reason===body.reason);
  check((await inbox.list(recipient,{})).items.length===1);check((await inbox.list(actor,{})).items.length===0);
  check((await history.get(patient,uploaded.id,{})).items.length===2);
  check((await history.get(patient,uploaded.id,{})).items.some(x=>x.referralReason===body.reason));
  check((await client.query('SELECT care_id FROM public.vitalia_care_contacts WHERE document_id=$1',[uploaded.id])).rows.length===1);
  await inbox.begin(recipient,requestId,{expectedRevision:0});
  const back={...body,requestId:randomUUID(),membershipId:member,branchId:branch,expectedRevision:1,reason:'Retorno sintético de continuidad'};
  await inbox.refer(recipient,requestId,back);
  check((await history.get(patient,uploaded.id,{})).items.length===3);
  check((await inbox.details(actor,back.requestId)).care.status==='requested');
  await denied(()=>inbox.details(recipient,requestId),404);
  check((await client.query("SELECT id FROM public.vitalia_exam_care WHERE document_id=$1 AND status IN ('requested','active')",[uploaded.id])).rows.length===1);
  check((await client.query('SELECT id FROM public.vitalia_document_processing WHERE document_id=$1',[uploaded.id])).rows.length===0);
  await client.query('SET CONSTRAINTS ALL IMMEDIATE');check(true);
  return checks;
 }finally{if(begun)await client.query('ROLLBACK');}
}
