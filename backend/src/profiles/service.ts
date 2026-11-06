import {randomUUID} from 'node:crypto';
import {type Pool} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {profileInput} from './validation';
import {createTerritoryService} from './territories';
import {createMeasurementService} from './measurements';
import {ProfileError} from './errors';
export {ProfileError} from './errors';

type Queryable=Pick<Pool,'query'>;
interface Person{id:string;first_name:string;additional_names:string|null;first_surname:string;second_surname:string|null;birth_date:string|null;phone:string|null;preferred_commune_code:string|null;revision:string}
interface Identifier{id:string;normalized_value:string;verification_status:string}
function allowed(account:AccountSummary){if(!['paciente','profesional'].includes(account.role))throw new ProfileError(403,'FORBIDDEN');}
async function read(tx:Queryable,account:AccountSummary){
 const person=(await tx.query<Person>(`SELECT id,first_name,additional_names,first_surname,second_surname,
 birth_date::text,phone,preferred_commune_code,updated_at::text AS revision FROM public.vitalia_people WHERE account_id=$1`,[account.id])).rows[0];
 if(!person)return {profile:null};
 const rut=(await tx.query<Identifier>(`SELECT id,normalized_value,verification_status FROM public.vitalia_person_identifiers
 WHERE person_id=$1 AND country_code='CL' AND identifier_type='RUT'`,[person.id])).rows[0];
 return {profile:{firstName:person.first_name,additionalNames:person.additional_names,firstSurname:person.first_surname,
 secondSurname:person.second_surname,birthDate:person.birth_date,phone:person.phone,preferredCommuneCode:person.preferred_commune_code,
 revision:person.revision,rut:rut?.normalized_value??null,rutVerified:rut?.verification_status==='verified',
 complete:account.role==='paciente'?person.birth_date!==null:true}};
}
function translate(error:unknown):never{
 if(error instanceof ProfileError)throw error;
 const code=(error as {code?:string})?.code;
 if(code==='23505')throw new ProfileError(409,'PROFILE_CONFLICT');
 if(code==='23503'||code==='23514')throw new ProfileError(400,'INVALID_PROFILE');
 if(code==='42501'||code==='42P01')throw new ProfileError(503,'PROFILE_UNAVAILABLE');
 throw error;
}
export function createProfileService(db:DocumentDatabase){return {
 ...createMeasurementService(db),
 territories:createTerritoryService(db),
 async get(account:AccountSummary){allowed(account);try{return await db.transaction(tx=>read(tx,account));}catch(e){translate(e);}},
 async save(account:AccountSummary,input:unknown){
  allowed(account);const parsed=profileInput.safeParse(input);if(!parsed.success)throw new ProfileError(400,'INVALID_PROFILE');
  const value=parsed.data;
  try{return await db.transaction(async tx=>{
   // Serializa cambios de la misma cuenta, incluida la creación inicial de persona.
   await tx.query('SELECT pg_advisory_xact_lock(hashtext($1),hashtext($2))',['vitalia-profile',account.id]);
   const owner=await tx.query('SELECT id FROM public.vitalia_accounts WHERE id=$1',[account.id]);
   if(owner.rows.length!==1)throw new ProfileError(401,'UNAUTHORIZED');
   const current=(await tx.query<{id:string;revision:string}>('SELECT id,updated_at::text AS revision FROM public.vitalia_people WHERE account_id=$1',[account.id])).rows[0];
   if((current?.revision??null)!==value.revision)throw new ProfileError(409,'PROFILE_CONFLICT');
   const id=current?.id??randomUUID();
   const existing=current?(await tx.query<Identifier>(`SELECT id,normalized_value,verification_status FROM public.vitalia_person_identifiers
    WHERE person_id=$1 AND country_code='CL' AND identifier_type='RUT' FOR UPDATE`,[id])).rows[0]:undefined;
   if(existing&&((existing.verification_status==='verified'&&existing.normalized_value!==value.rut)||value.rut===null))throw new ProfileError(409,'PROFILE_CONFLICT');
   if(current)await tx.query(`UPDATE public.vitalia_people SET first_name=$2,additional_names=$3,first_surname=$4,
    second_surname=$5,birth_date=$6,phone=$7,preferred_commune_code=$8,updated_at=clock_timestamp() WHERE id=$1`,
    [id,value.firstName,value.additionalNames,value.firstSurname,value.secondSurname,value.birthDate,value.phone,value.preferredCommuneCode]);
   else await tx.query(`INSERT INTO public.vitalia_people(id,account_id,first_name,additional_names,first_surname,second_surname,birth_date,phone,preferred_commune_code)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[id,account.id,value.firstName,value.additionalNames,value.firstSurname,value.secondSurname,value.birthDate,value.phone,value.preferredCommuneCode]);
   if(value.rut&&!existing)await tx.query(`INSERT INTO public.vitalia_person_identifiers(id,person_id,country_code,identifier_type,normalized_value)
    VALUES($1,$2,'CL','RUT',$3)`,[randomUUID(),id,value.rut]);
   else if(value.rut&&existing&&value.rut!==existing.normalized_value)await tx.query(`UPDATE public.vitalia_person_identifiers SET normalized_value=$2
    WHERE id=$1 AND verification_status='not_verified'`,[existing.id,value.rut]);
   if(account.role==='paciente')await tx.query('INSERT INTO public.vitalia_patient_profiles(person_id) VALUES($1) ON CONFLICT DO NOTHING',[id]);
   else await tx.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1) ON CONFLICT DO NOTHING',[id]);
   return read(tx,account);
  });}catch(e){translate(e);}
 }
};}
export type ProfileServices=ReturnType<typeof createProfileService>;
