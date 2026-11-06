import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';

type Client=Pick<PoolClient,'query'>;
// Usa una conexión exclusiva: todos los datos sintéticos terminan en ROLLBACK.
export async function verifyProfilesLocations(client:Client):Promise<number>{
 let started=false,checks=0;
 async function rejected(sql:string,values:unknown[],code:string){
  await client.query('SAVEPOINT rejected_input');
  let error:unknown;
  try{await client.query(sql,values);}catch(value){error=value;}
  await client.query('ROLLBACK TO SAVEPOINT rejected_input');
  await client.query('RELEASE SAVEPOINT rejected_input');
  if(!error||typeof error!=='object'||!('code' in error)||error.code!==code)throw new Error('No se rechazó la entrada como se esperaba.');
  checks++;
 }
 try{
  await client.query('BEGIN');started=true;
  const version=await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['012_profiles_locations']);
  if(version.rows.length!==1)throw new Error('Falta migración 012.');
  const a=randomUUID(),b=randomUUID(),p=randomUUID(),other=randomUUID(),region='T'+randomUUID().slice(0,8),province='T'+randomUUID().slice(0,8),commune='T'+randomUUID().slice(0,8);
  await client.query(`INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES
   ($1,$2,'synthetic-no-login','paciente'),($3,$4,'synthetic-no-login','profesional')`,[a,a+'@example.invalid',b,b+'@example.invalid']);
  const empty=await client.query('SELECT id FROM public.vitalia_people WHERE account_id IN ($1,$2)',[a,b]);
  if(empty.rows.length)throw new Error('Perfil fabricado automáticamente.');checks++;
  await client.query('INSERT INTO public.vitalia_regions(code,name) VALUES($1,$2)',[region,'Región ficticia de comprobación']);
  await client.query('INSERT INTO public.vitalia_provinces(code,region_code,name) VALUES($1,$2,$3)',[province,region,'Provincia ficticia']);
  await client.query('INSERT INTO public.vitalia_communes(code,province_code,name) VALUES($1,$2,$3)',[commune,province,'Comuna ficticia']);
  const person=`INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname,birth_date,preferred_commune_code)
   VALUES($1,$2,$3,$4,$5::date,$6)`;
  await client.query(person,[p,a,'Persona','Sintética','2000-01-01',commune]);
  await client.query(person,[other,b,'Otra','Sintética',null,null]);
  const defaults=await client.query(`SELECT phone,additional_names,second_surname FROM public.vitalia_people WHERE id=$1`,[p]);
  if(defaults.rows[0].phone!==null||defaults.rows[0].additional_names!==null||defaults.rows[0].second_surname!==null)throw new Error('Datos opcionales inválidos.');checks++;
  await client.query('INSERT INTO public.vitalia_patient_profiles(person_id) VALUES($1)',[p]);
  await client.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1)',[p]);
  const professional=await client.query('SELECT verification_status FROM public.vitalia_professional_profiles WHERE person_id=$1',[p]);
  if(professional.rows[0].verification_status!=='pending')throw new Error('Verificación profesional automática.');checks++;
  const identifier=`INSERT INTO public.vitalia_person_identifiers(id,person_id,country_code,identifier_type,normalized_value)
   VALUES($1,$2,'CL','RUT',$3) RETURNING verification_status`;
  // Valor sintético deliberado: este bloque prueba unicidad, no valida el módulo 11.
  const identifierValue='SYNTHETIC-'+randomUUID();
  const id=await client.query(identifier,[randomUUID(),p,identifierValue]);
  if(id.rows[0].verification_status!=='not_verified')throw new Error('Identidad verificada automáticamente.');checks++;
  await rejected(identifier,[randomUUID(),other,identifierValue],'23505');
  await rejected(identifier,[randomUUID(),p,'SYNTHETIC-'+randomUUID()],'23505');
  await rejected(person,[randomUUID(),a,'Otro','Duplicado',null,null],'23505');
  await rejected(person,[randomUUID(),randomUUID(),'Sin','Cuenta',null,null],'23503');
  await rejected('UPDATE public.vitalia_people SET first_name=$1 WHERE id=$2',['   ',p],'23514');
  await rejected('UPDATE public.vitalia_people SET phone=$1 WHERE id=$2',['',p],'23514');
  await rejected("UPDATE public.vitalia_people SET birth_date=CURRENT_DATE+1 WHERE id=$1",[p],'23514');
  await rejected("UPDATE public.vitalia_people SET birth_date='infinity'::date WHERE id=$1",[p],'23514');
  await rejected('UPDATE public.vitalia_people SET preferred_commune_code=$1 WHERE id=$2',['missing-'+region,p],'23503');
  await rejected('UPDATE public.vitalia_provinces SET region_code=$1 WHERE code=$2',['missing-'+region,province],'23503');
  await rejected('UPDATE public.vitalia_communes SET province_code=$1 WHERE code=$2',['missing-'+province,commune],'23503');
  await rejected('DELETE FROM public.vitalia_people WHERE id=$1',[p],'23503');
  const measurement=`INSERT INTO public.vitalia_patient_measurements
   (id,patient_person_id,measured_at,weight_kg,height_cm,source,recorded_by)
   VALUES($1,$2,CURRENT_TIMESTAMP,$3,$4,$5,$6)`;
  await client.query(measurement,[randomUUID(),p,'70.5',null,'patient_reported',a]);
  await client.query(measurement,[randomUUID(),p,null,'170.2','patient_reported',a]);checks++;
  for(const [weight,height] of [[null,null],['0',null],['-1',null],['NaN',null],['Infinity',null],[null,'0'],[null,'-2'],[null,'NaN'],[null,'Infinity']]){
   await rejected(measurement,[randomUUID(),p,weight,height,'patient_reported',a],'23514');
  }
  await rejected(measurement,[randomUUID(),other,'70',null,'patient_reported',b],'23503');
  await rejected(measurement,[randomUUID(),p,'70',null,'unknown',a],'23514');
  await rejected(measurement,[randomUUID(),p,'70',null,'patient_reported',randomUUID()],'23503');
  await rejected(`UPDATE public.vitalia_patient_measurements SET measured_at=CURRENT_TIMESTAMP+INTERVAL '1 day' WHERE patient_person_id=$1`,[p],'23514');
  await rejected('UPDATE public.vitalia_person_identifiers SET verification_status=$1 WHERE person_id=$2',['automatic',p],'23514');
  await rejected('UPDATE public.vitalia_professional_profiles SET verification_status=$1 WHERE person_id=$2',['automatic',p],'23514');
  const role=await client.query('SELECT role_code FROM public.vitalia_accounts WHERE id=$1',[a]);
  if(role.rows[0].role_code!=='paciente')throw new Error('El perfil cambió permisos globales.');checks++;
  return checks;
 }finally{if(started)await client.query('ROLLBACK');}
}
