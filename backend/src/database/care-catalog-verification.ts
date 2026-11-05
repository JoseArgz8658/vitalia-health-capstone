import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {createCredentialVerificationService} from '../professional-credentials/service';
import {createCareCatalogService} from '../care/catalog';

export async function verifyCareCatalog(client:Pick<PoolClient,'query'>):Promise<number>{
 let begun=false,checks=0;
 const check=(ok:boolean)=>{if(!ok)throw new Error('Comprobación de catálogo incorrecta.');checks++;};
 try{
  await client.query('BEGIN');begun=true;
  if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['020_professional_credentials'])).rows.length)throw new Error('Falta migración 020.');
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
  const db={query:client.query.bind(client),transaction:async fn=>fn(client)} as DocumentDatabase;
  const credentials=createCredentialVerificationService(db),req=randomUUID();
  await credentials.request(admin,clinic,member,{requestId:req,expectedRevision:0,registrationReference:'SYNTHETIC',supportingReference:'Respaldo exclusivamente sintético'});
  await credentials.decide(admin,clinic,member,req,{requestId:randomUUID(),expectedRevision:0,decision:'verified',sourceReference:'Fuente sintética',checkedAt:new Date(Date.now()-10000).toISOString(),reason:'Prueba de catálogo exclusivamente sintética',confirmed:true});
  const result=await read(),option=result.items[0];check(result.items.length===1);check(result.nextOffset===null);
  check(option.membershipId===member&&option.branchId===branch&&option.specialtyId===specialty&&option.clinicId===clinic);
  check(option.professionalName==='Profesional Sintético');
  check(Object.keys(option).sort().join(',')===['clinicId','clinicName','branchId','branchName','communeCode','street','addressNumber','specialtyId','specialtyName','membershipId','professionalName'].sort().join(','));
  check((await read({communeCode:otherCommune})).items[0]?.branchId===otherBranch);
  check((await read({branchId:otherBranch})).items.length===0);
  check((await read({clinicId:randomUUID()})).items.length===0);
  check((await read({specialtyId:randomUUID()})).items.length===0);
  check((await read({clinicId:clinic,branchId:branch,specialtyId:specialty})).items.length===1);
  // Cada cambio se revierte con savepoint: aislamiento de clínica/sucursal/rol/credencial.
  for(const [sql,args]of [
   ['UPDATE public.vitalia_clinics SET active=false WHERE id=$1',[clinic]],
   ['UPDATE public.vitalia_branches SET active=false WHERE id=$1',[branch]],
   ['UPDATE public.vitalia_clinic_memberships SET active=false WHERE id=$1',[member]],
   ['UPDATE public.vitalia_specialties SET active=false WHERE id=$1',[specialty]],
   ["UPDATE public.vitalia_account_roles SET active=false WHERE account_id=$1 AND role_code='profesional'",[professional]],
   ["UPDATE public.vitalia_professional_profiles SET verification_status='rejected' WHERE person_id=$1",[person]],
   ['UPDATE public.vitalia_professional_profiles SET verification_request_id=NULL WHERE person_id=$1',[person]],
   ["UPDATE public.vitalia_professional_profiles SET registration_reference='ALTERADA' WHERE person_id=$1",[person]],
   ['UPDATE public.vitalia_professional_profiles SET verification_revision=verification_revision+1 WHERE person_id=$1',[person]],
   ['DELETE FROM public.vitalia_membership_specialties WHERE membership_id=$1',[member]],
   ['DELETE FROM public.vitalia_branch_memberships WHERE membership_id=$1 AND branch_id=$2',[member,branch]],
  ] as [string,unknown[]][]){
   await client.query('SAVEPOINT catalog_case');await client.query(sql,args);check((await read()).items.length===0);
   await client.query('ROLLBACK TO SAVEPOINT catalog_case');await client.query('RELEASE SAVEPOINT catalog_case');
  }
  check((await read()).items.length===1);
  check((await client.query('SELECT id FROM public.vitalia_exam_care WHERE patient_id=$1',[patient.id])).rows.length===0);
  check((await client.query('SELECT id FROM public.vitalia_patient_assignments WHERE patient_id=$1',[patient.id])).rows.length===0);
  // Más de una página: ninguna opción se pierde por un límite silencioso.
  for(let i=0;i<31;i++){
   const id=randomUUID();
   await client.query("INSERT INTO public.vitalia_branches(id,clinic_id,commune_code,name,street,address_number) VALUES($1,$2,$3,$4,'Calle ficticia','S/N')",[id,clinic,commune,'Sucursal paginada '+String(i).padStart(2,'0')]);
   await client.query('INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)',[clinic,id,member]);
  }
  const first=await read(),last=await read({offset:first.nextOffset});
  check(first.items.length===30&&first.nextOffset===30);
  check(last.items.length===2&&last.nextOffset===null);
  check(new Set([...first.items,...last.items].map(x=>x.branchId)).size===32);
  return checks;
 }finally{if(begun)await client.query('ROLLBACK');}
}
