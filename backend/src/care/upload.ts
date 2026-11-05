import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import {type Pool} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
type DB=Pick<Pool,'query'>;
export class CareUploadError extends Error {
 constructor(public readonly status:number,public readonly code:string){super(code);}
}
export const careUploadInput=z.object({
 clinicId:z.uuid(),branchId:z.uuid(),membershipId:z.uuid(),specialtyId:z.uuid(),
 residenceCommuneCode:z.string().regex(/^\d{5}$/),consultationCommuneCode:z.string().regex(/^\d{5}$/),
 street:z.string().trim().min(1).max(200),addressNumber:z.string().trim().min(1).max(40),
 phone:z.string().trim().regex(/^\+?[0-9]{8,15}$/),confirmed:z.literal(true),
 saveProfile:z.boolean(),profileRevision:z.string().min(1).max(100),
}).strict();
export type CareUploadInput=z.infer<typeof careUploadInput>;
function patient(a:AccountSummary){if(a.role!=='paciente')throw new CareUploadError(403,'FORBIDDEN');}
function translate(e:unknown):never{
 if(e instanceof CareUploadError)throw e;
 const code=(e as {code?:string})?.code;
 if(['42P01','42703','42501'].includes(code??''))throw new CareUploadError(503,'CARE_UPLOAD_UNAVAILABLE');
 if(['P0001','23503','23505','23514','40001','40P01'].includes(code??''))throw new CareUploadError(409,'CARE_SELECTION_CHANGED');
 throw e;
}
async function context(tx:DB,a:AccountSummary,lock=false){
 const row=(await tx.query<{id:string;phone:string|null;street:string|null;addressNumber:string|null;residenceCommuneCode:string|null;preferredCommuneCode:string|null;revision:string;email:string}>(`
 SELECT p.id,p.phone,p.street,p.address_number AS "addressNumber",p.residence_commune_code AS "residenceCommuneCode",
  p.preferred_commune_code AS "preferredCommuneCode",p.updated_at::text AS revision,a.email
 FROM public.vitalia_people p JOIN public.vitalia_accounts a ON a.id=p.account_id
 WHERE p.account_id=$1 ${lock?'FOR UPDATE OF p FOR SHARE OF a':''}`,[a.id])).rows[0];
 if(!row)throw new CareUploadError(409,'CARE_PROFILE_REQUIRED');
 return row;
}
async function selection(tx:DB,v:CareUploadInput,lock:boolean){
 if(lock)await tx.query('SELECT public.vitalia_lock_care_selection($1,$2,$3)',[v.membershipId,v.specialtyId,v.branchId]);
 const found=await tx.query<{id:string}>(`SELECT m.id FROM public.vitalia_clinic_memberships m
 JOIN public.vitalia_people p ON p.id=m.professional_person_id
 JOIN public.vitalia_professional_profiles f ON f.person_id=p.id
 JOIN public.vitalia_account_roles g ON g.account_id=p.account_id AND g.role_code='profesional' AND g.active
 JOIN public.vitalia_clinics c ON c.id=m.clinic_id AND c.active
 JOIN public.vitalia_branch_memberships bm ON bm.membership_id=m.id AND bm.clinic_id=c.id
 JOIN public.vitalia_branches b ON b.id=bm.branch_id AND b.clinic_id=c.id AND b.active
 JOIN public.vitalia_membership_specialties ms ON ms.membership_id=m.id AND ms.clinic_id=c.id
 JOIN public.vitalia_specialties s ON s.id=ms.specialty_id AND s.active
 WHERE m.id=$1 AND c.id=$2 AND b.id=$3 AND s.id=$4 AND b.commune_code=$5 AND m.active
 `,
 [v.membershipId,v.clinicId,v.branchId,v.specialtyId,v.consultationCommuneCode]);
 if(found.rows.length!==1)throw new CareUploadError(409,'CARE_SELECTION_CHANGED');
 await tx.query('SELECT public.vitalia_assert_care_selection($1,$2,$3)',[v.membershipId,v.specialtyId,v.branchId]);
 const commune=await tx.query('SELECT code FROM public.vitalia_communes WHERE code=$1',[v.residenceCommuneCode]);
 if(!commune.rows.length)throw new CareUploadError(400,'INVALID_CARE_CONTACT');
}
export function createCareUploadService(db:DocumentDatabase){return {
 parse(input:unknown):CareUploadInput{
  let value:unknown=input;
  if(typeof input==='string'){try{value=JSON.parse(input);}catch{throw new CareUploadError(400,'INVALID_CARE_CONTACT');}}
  const parsed=careUploadInput.safeParse(value);
  if(!parsed.success)throw new CareUploadError(400,'INVALID_CARE_CONTACT');return parsed.data;
 },
 async context(a:AccountSummary){patient(a);try{return await db.transaction(async tx=>{const {id,...value}=await context(tx,a);return value;});}catch(e){translate(e);}},
 async preflight(a:AccountSummary,v:CareUploadInput){patient(a);try{await db.transaction(async tx=>{
  const p=await context(tx,a);if(v.saveProfile&&p.revision!==v.profileRevision)throw new CareUploadError(409,'CARE_PROFILE_CHANGED');
  await selection(tx,v,false);
 });}catch(e){translate(e);}},
 async attach(tx:DB,a:AccountSummary,documentId:string,v:CareUploadInput){patient(a);try{
  // Sigue el bloqueo del perfil usado en la edición existente. Nunca sostiene locks durante S3.
  await tx.query('SELECT pg_advisory_xact_lock(hashtext($1),hashtext($2))',['vitalia-profile',a.id]);
  const p=await context(tx,a,true);
  if(v.saveProfile&&p.revision!==v.profileRevision)throw new CareUploadError(409,'CARE_PROFILE_CHANGED');
  await selection(tx,v,true);
  if(v.saveProfile)await tx.query(`UPDATE public.vitalia_people SET phone=$2,street=$3,address_number=$4,
   residence_commune_code=$5,updated_at=GREATEST(clock_timestamp(),updated_at+interval '1 microsecond') WHERE id=$1`,
   [p.id,v.phone,v.street,v.addressNumber,v.residenceCommuneCode]);
  await tx.query('UPDATE public.vitalia_documents SET care_flow=true WHERE id=$1 AND patient_id=$2',[documentId,a.id]);
  const careId=randomUUID();
  await tx.query(`INSERT INTO public.vitalia_exam_care(id,document_id,patient_id,clinic_id,branch_id,responsible_membership_id,specialty_id,kind,requested_by,updated_by)
   VALUES($1,$2,$3,$4,$5,$6,$7,'initial',$3,$3)`,[careId,documentId,a.id,v.clinicId,v.branchId,v.membershipId,v.specialtyId]);
  await tx.query(`INSERT INTO public.vitalia_care_contacts(care_id,document_id,patient_id,residence_commune_code,consultation_commune_code,street,address_number,phone,email,confirmed)
   VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,true)`,[careId,documentId,a.id,v.residenceCommuneCode,v.consultationCommuneCode,v.street,v.addressNumber,v.phone,p.email]);
 }catch(e){translate(e);}}
};}
export type CareUploadServices=ReturnType<typeof createCareUploadService>;
