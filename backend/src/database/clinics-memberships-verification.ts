import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
type Client=Pick<PoolClient,'query'>;
// Una conexión exclusiva y datos ficticios; incluso una comprobación fallida revierte.
export async function verifyClinicsMemberships(client:Client):Promise<number>{
 let started=false,checks=0;
 const assert=(ok:boolean)=>{if(!ok)throw new Error('Comprobación institucional incorrecta.');checks++;};
 async function rejected(sql:string,values:unknown[],code:string){
  await client.query('SAVEPOINT invalid_clinic_input');let error:unknown;
  try{await client.query(sql,values);}catch(e){error=e;}
  await client.query('ROLLBACK TO SAVEPOINT invalid_clinic_input');
  await client.query('RELEASE SAVEPOINT invalid_clinic_input');
  assert((error as {code?:string})?.code===code);
 }
 try{
  await client.query('BEGIN');started=true;
  const version=await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['013_clinics_memberships']);
  if(version.rows.length!==1)throw new Error('Falta migración 013.');
  const clinic=randomUUID(),otherClinic=randomUUID(),branch=randomUUID(),otherBranch=randomUUID();
  const account=randomUUID(),person=randomUUID(),member=randomUUID(),specialty=randomUUID();
  const region='T'+randomUUID().slice(0,8),province='T'+randomUUID().slice(0,8),commune='T'+randomUUID().slice(0,8);
  await client.query('INSERT INTO public.vitalia_regions(code,name) VALUES($1,$2)',[region,'Región sintética']);
  await client.query('INSERT INTO public.vitalia_provinces(code,region_code,name) VALUES($1,$2,$3)',[province,region,'Provincia sintética']);
  await client.query('INSERT INTO public.vitalia_communes(code,province_code,name) VALUES($1,$2,$3)',[commune,province,'Comuna sintética']);
  await client.query(`INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login','profesional')`,[account,account+'@example.invalid']);
  await client.query(`INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname) VALUES($1,$2,'Persona','Sintética')`,[person,account]);
  await client.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1)',[person]);
  const clinicInsert='INSERT INTO public.vitalia_clinics(id,name) VALUES($1,$2)';
  await client.query(clinicInsert,[clinic,'Clínica ficticia A']);await client.query(clinicInsert,[otherClinic,'Clínica ficticia B']);
  const branchInsert=`INSERT INTO public.vitalia_branches(id,clinic_id,commune_code,name,street,address_number)
   VALUES($1,$2,$3,$4,'Calle ficticia','S/N')`;
  await client.query(branchInsert,[branch,clinic,commune,'Sucursal ficticia A']);
  await client.query(branchInsert,[otherBranch,otherClinic,commune,'Sucursal ficticia B']);
  const location=await client.query('SELECT floor,unit,contact_phone FROM public.vitalia_branches WHERE id=$1',[branch]);
  assert(location.rows[0].floor===null&&location.rows[0].unit===null&&location.rows[0].contact_phone===null);
  const membership=`INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id) VALUES($1,$2,$3) RETURNING active,clinical_role`;
  const m=await client.query(membership,[member,clinic,person]);assert(m.rows[0].active===false&&m.rows[0].clinical_role==='profesional');
  const link='INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)';
  await client.query(link,[clinic,branch,member]);checks++;
  await rejected(link,[clinic,otherBranch,member],'23503');
  await rejected(link,[otherClinic,otherBranch,member],'23503');
  await rejected('UPDATE public.vitalia_branch_memberships SET clinic_id=$1 WHERE branch_id=$2 AND membership_id=$3',[otherClinic,branch,member],'23503');
  await rejected(link,[clinic,branch,randomUUID()],'23503');
  await rejected(link,[clinic,branch,member],'23505');
  await rejected(membership,[randomUUID(),clinic,person],'23505');
  await rejected(membership,[randomUUID(),randomUUID(),person],'23503');
  await rejected(membership,[randomUUID(),clinic,randomUUID()],'23503');
  await rejected('UPDATE public.vitalia_clinic_memberships SET clinical_role=$1 WHERE id=$2',['administrador',member],'23514');
  await rejected('UPDATE public.vitalia_clinic_memberships SET updated_at=created_at-INTERVAL \'1 day\' WHERE id=$1',[member],'23514');
  await rejected('UPDATE public.vitalia_clinic_memberships SET clinic_id=$1 WHERE id=$2',[otherClinic,member],'23503');
  await rejected('UPDATE public.vitalia_branches SET clinic_id=$1 WHERE id=$2',[otherClinic,branch],'23503');
  await rejected(clinicInsert,[randomUUID(),'  '],'23514');
  await rejected(branchInsert,[randomUUID(),clinic,'missing-'+commune,'Sucursal inválida'],'23503');
  await rejected('UPDATE public.vitalia_branches SET floor=$1 WHERE id=$2',[' ',branch],'23514');
  await rejected('UPDATE public.vitalia_branches SET address_number=$1 WHERE id=$2',['',branch],'23514');
  const specialtyInsert='INSERT INTO public.vitalia_specialties(id,name) VALUES($1,$2)';
  await client.query(specialtyInsert,[specialty,'Especialidad sintética '+specialty]);
  await rejected(specialtyInsert,[randomUUID(),('Especialidad sintética '+specialty).toUpperCase()],'23505');
  const specialtyLink='INSERT INTO public.vitalia_professional_specialties(professional_person_id,specialty_id) VALUES($1,$2)';
  await client.query(specialtyLink,[person,specialty]);checks++;
  await rejected(specialtyLink,[person,specialty],'23505');
  await rejected(specialtyLink,[person,randomUUID()],'23503');
  await rejected(specialtyLink,[randomUUID(),specialty],'23503');
  await rejected('DELETE FROM public.vitalia_clinics WHERE id=$1',[clinic],'23503');
  await rejected('DELETE FROM public.vitalia_clinic_memberships WHERE id=$1',[member],'23503');
  await rejected('DELETE FROM public.vitalia_branches WHERE id=$1',[branch],'23503');
  const role=await client.query(`SELECT a.role_code,p.verification_status FROM public.vitalia_accounts a
   JOIN public.vitalia_people x ON x.account_id=a.id JOIN public.vitalia_professional_profiles p ON p.person_id=x.id WHERE a.id=$1`,[account]);
  assert(role.rows[0].role_code==='profesional'&&role.rows[0].verification_status==='pending');
  return checks;
 }finally{if(started)await client.query('ROLLBACK');}
}
