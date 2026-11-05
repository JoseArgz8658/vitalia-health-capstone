import {createHash} from 'node:crypto';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
export class TeamError extends Error {constructor(public status:number,public code:string){super(code);}}
const ids=z.array(z.uuid()).max(20).refine(a=>new Set(a).size===a.length);
export const membershipInput=z.object({requestId:z.uuid(),expectedRevision:z.number().int().min(0).max(2147483646),active:z.boolean(),branchIds:ids,specialtyIds:ids,reason:z.string().trim().min(5).max(500)}).strict();
type Tx=Parameters<Parameters<DocumentDatabase['transaction']>[0]>[0];
function fail(status:number,code:string):never {throw new TeamError(status,code);}
function identifier(id:string){if(!z.uuid().safeParse(id).success)fail(400,'INVALID_TEAM');}
function role(a:AccountSummary,write=false){if(write?a.role!=='profesional':!['profesional','administrador'].includes(a.role))fail(403,'FORBIDDEN');}
function page(limit:number,offset:number){if(!Number.isInteger(limit)||limit<1||limit>20||!Number.isInteger(offset)||offset<0||offset>10000)fail(400,'INVALID_TEAM');}
const sorted=(values:string[])=>[...values].sort();
async function authority(tx:Tx,a:AccountSummary,clinic:string,write=false){
 role(a,write);
 if(!(await tx.query('SELECT id FROM public.vitalia_clinics WHERE id=$1 AND active',[clinic])).rows.length)fail(409,'CLINIC_UNAVAILABLE');
 if(a.role==='administrador')return;
 if(!(await tx.query(`SELECT m.id FROM public.vitalia_clinic_memberships m JOIN public.vitalia_people p ON p.id=m.professional_person_id WHERE m.clinic_id=$1 AND p.account_id=$2 AND m.active AND m.clinical_role='jefe_clinico'`,[clinic,a.id])).rows.length)fail(403,'FORBIDDEN');
}
function translate(e:unknown):never {if(e instanceof TeamError)throw e;const c=(e as {code?:string})?.code;if(['42501','42P01','42703'].includes(c??''))fail(503,'TEAM_UNAVAILABLE');if(['23503','23514','22001'].includes(c??''))fail(400,'INVALID_TEAM');if(c==='23505')fail(409,'TEAM_CONFLICT');throw e;}
const memberSelect=`SELECT m.id,m.clinic_id AS "clinicId",m.clinical_role AS "clinicalRole",m.active,m.revision,
 p.first_name AS "firstName",p.first_surname AS "firstSurname",a.email,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'active',b.active) ORDER BY b.name,b.id) FROM public.vitalia_branch_memberships bm JOIN public.vitalia_branches b ON b.id=bm.branch_id AND b.clinic_id=bm.clinic_id WHERE bm.clinic_id=m.clinic_id AND bm.membership_id=m.id),'[]'::jsonb) AS branches,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active) ORDER BY s.name,s.id) FROM public.vitalia_membership_specialties ms JOIN public.vitalia_specialties s ON s.id=ms.specialty_id WHERE ms.clinic_id=m.clinic_id AND ms.membership_id=m.id),'[]'::jsonb) AS specialties
 FROM public.vitalia_clinic_memberships m JOIN public.vitalia_people p ON p.id=m.professional_person_id JOIN public.vitalia_accounts a ON a.id=p.account_id`;
export function createTeamService(db:DocumentDatabase){
 async function transaction<T>(fn:(tx:Tx)=>Promise<T>){try{return await db.transaction(fn);}catch(e){translate(e);}}
 return {
 async list(a:AccountSummary,clinic:string,limit=20,offset=0){role(a);identifier(clinic);page(limit,offset);return transaction(async tx=>{
 await authority(tx,a,clinic);
 return {members:(await tx.query(`${memberSelect} WHERE m.clinic_id=$1 ORDER BY p.first_name,p.first_surname,m.id LIMIT $2 OFFSET $3`,[clinic,limit,offset])).rows,
 branches:(await tx.query('SELECT id,name,active FROM public.vitalia_branches WHERE clinic_id=$1 AND active ORDER BY name,id LIMIT 200',[clinic])).rows,
 specialties:(await tx.query('SELECT id,name,active FROM public.vitalia_specialties WHERE active ORDER BY name,id LIMIT 200')).rows};
 });},
 async history(a:AccountSummary,clinic:string,membership:string,limit=20,offset=0){role(a);identifier(clinic);identifier(membership);page(limit,offset);return transaction(async tx=>{
 await authority(tx,a,clinic);
 if(!(await tx.query('SELECT id FROM public.vitalia_clinic_memberships WHERE clinic_id=$1 AND id=$2',[clinic,membership])).rows.length)fail(404,'MEMBERSHIP_NOT_FOUND');
 return (await tx.query(`SELECT h.id,h.actor_id AS "actorId",a.email AS "actorEmail",h.action,h.reason,h.before_state AS "beforeState",h.after_state AS "afterState",h.created_at AS "createdAt" FROM public.vitalia_membership_audit h JOIN public.vitalia_accounts a ON a.id=h.actor_id WHERE h.clinic_id=$1 AND h.membership_id=$2 ORDER BY h.created_at DESC,h.id LIMIT $3 OFFSET $4`,[clinic,membership,limit,offset])).rows;
 });},
 async update(a:AccountSummary,clinic:string,membership:string,input:unknown){role(a,true);identifier(clinic);identifier(membership);const parsed=membershipInput.safeParse(input);if(!parsed.success)fail(400,'INVALID_TEAM');
 const v=parsed.data;v.branchIds=sorted(v.branchIds);v.specialtyIds=sorted(v.specialtyIds);
 const requestHash=createHash('sha256').update(JSON.stringify({clinic,membership,expectedRevision:v.expectedRevision,active:v.active,branchIds:v.branchIds,specialtyIds:v.specialtyIds,reason:v.reason})).digest('hex');
 return transaction(async tx=>{
 // Compartido con emisión y activación: una suspensión no se intercala con esos cambios.
 await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-onboarding-'+clinic]);
 await authority(tx,a,clinic,true);
 const member=(await tx.query('SELECT m.id,m.active,m.revision,m.clinical_role,p.account_id FROM public.vitalia_clinic_memberships m JOIN public.vitalia_people p ON p.id=m.professional_person_id WHERE m.clinic_id=$1 AND m.id=$2 FOR UPDATE OF m',[clinic,membership])).rows[0];
 if(!member)fail(404,'MEMBERSHIP_NOT_FOUND');
 if(member.clinical_role!=='profesional'||member.account_id===a.id)fail(403,'FORBIDDEN');
 const previous=(await tx.query('SELECT actor_id,clinic_id,membership_id,request_hash FROM public.vitalia_membership_audit WHERE id=$1',[v.requestId])).rows[0];
 if(previous){if(previous.actor_id!==a.id||previous.clinic_id!==clinic||previous.membership_id!==membership||previous.request_hash!==requestHash)fail(409,'TEAM_CONFLICT');return {updated:true,replayed:true};}
 if(member.revision!==v.expectedRevision)fail(409,'TEAM_CONFLICT');
 const branches=(await tx.query('SELECT branch_id FROM public.vitalia_branch_memberships WHERE clinic_id=$1 AND membership_id=$2',[clinic,membership])).rows.map(r=>r.branch_id);
 const specialties=(await tx.query('SELECT specialty_id FROM public.vitalia_membership_specialties WHERE clinic_id=$1 AND membership_id=$2',[clinic,membership])).rows.map(r=>r.specialty_id);
 const before={active:member.active,revision:member.revision,branchIds:sorted(branches),specialtyIds:sorted(specialties)};
 if(member.active===v.active&&JSON.stringify(before.branchIds)===JSON.stringify(v.branchIds)&&JSON.stringify(before.specialtyIds)===JSON.stringify(v.specialtyIds))fail(400,'NO_MEMBERSHIP_CHANGE');
 const validB=await tx.query('SELECT id FROM public.vitalia_branches WHERE clinic_id=$1 AND id=ANY($2::uuid[]) AND (active OR id=ANY($3::uuid[]))',[clinic,v.branchIds,branches]);
 const validS=await tx.query('SELECT id FROM public.vitalia_specialties WHERE id=ANY($1::uuid[]) AND (active OR id=ANY($2::uuid[]))',[v.specialtyIds,specialties]);
 if(validB.rows.length!==v.branchIds.length||validS.rows.length!==v.specialtyIds.length)fail(400,'INVALID_TEAM');
 const changed=await tx.query('UPDATE public.vitalia_clinic_memberships SET active=$3,revision=revision+1,updated_at=GREATEST(clock_timestamp(),updated_at) WHERE clinic_id=$1 AND id=$2 AND revision=$4 RETURNING revision',[clinic,membership,v.active,v.expectedRevision]);
 if(!changed.rows.length)fail(409,'TEAM_CONFLICT');
 await tx.query('DELETE FROM public.vitalia_branch_memberships WHERE clinic_id=$1 AND membership_id=$2',[clinic,membership]);
 for(const id of v.branchIds)await tx.query('INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)',[clinic,id,membership]);
 await tx.query('DELETE FROM public.vitalia_membership_specialties WHERE clinic_id=$1 AND membership_id=$2',[clinic,membership]);
 for(const id of v.specialtyIds)await tx.query('INSERT INTO public.vitalia_membership_specialties(clinic_id,membership_id,specialty_id) VALUES($1,$2,$3)',[clinic,membership,id]);
 const after={active:v.active,revision:changed.rows[0].revision,branchIds:v.branchIds,specialtyIds:v.specialtyIds};
 await tx.query("INSERT INTO public.vitalia_membership_audit(id,clinic_id,membership_id,actor_id,action,reason,request_hash,before_state,after_state) VALUES($1,$2,$3,$4,'membership_updated',$5,$6,$7::jsonb,$8::jsonb)",[v.requestId,clinic,membership,a.id,v.reason,requestHash,JSON.stringify(before),JSON.stringify(after)]);
 return {updated:true,replayed:false};
 });}
 };
}
export type TeamServices=ReturnType<typeof createTeamService>;
