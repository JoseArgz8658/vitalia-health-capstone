import {createHash} from 'node:crypto';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
export class CredentialVerificationError extends Error {constructor(public status:number,public code:string){super(code);}}
const text=(n:number,min=1)=>z.string().trim().min(min).max(n);
export const credentialRequestInput=z.object({requestId:z.uuid(),expectedRevision:z.number().int().min(0).max(2147483646),registrationReference:text(200),supportingReference:text(500,5)}).strict();
export const credentialDecisionInput=z.object({requestId:z.uuid(),expectedRevision:z.number().int().min(0).max(2147483646),decision:z.enum(['verified','rejected']),sourceReference:text(500,5),checkedAt:z.iso.datetime({offset:true}),reason:text(1000,5),confirmed:z.literal(true)}).strict();
type Tx=Parameters<Parameters<DocumentDatabase['transaction']>[0]>[0];
function fail(status:number,code:string):never{throw new CredentialVerificationError(status,code);}
function ids(...values:string[]){if(values.some(v=>!z.uuid().safeParse(v).success))fail(400,'INVALID_CREDENTIAL_VERIFICATION');}
function role(a:AccountSummary){if(!['administrador','profesional'].includes(a.role))fail(403,'FORBIDDEN');}
function parse<T>(schema:z.ZodType<T>,input:unknown):T{const p=schema.safeParse(input);return p.success?p.data:fail(400,'INVALID_CREDENTIAL_VERIFICATION');}
const digest=(v:unknown)=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
async function target(tx:Tx,a:AccountSummary,clinic:string,member:string){
 if(!(await tx.query('SELECT id FROM public.vitalia_clinics WHERE id=$1 AND active',[clinic])).rows.length)fail(409,'CLINIC_UNAVAILABLE');
 if(a.role!=='administrador'&&!(await tx.query("SELECT m.id FROM public.vitalia_clinic_memberships m JOIN public.vitalia_people p ON p.id=m.professional_person_id WHERE m.clinic_id=$1 AND p.account_id=$2 AND m.clinical_role='jefe_clinico' AND m.active",[clinic,a.id])).rows.length)fail(403,'FORBIDDEN');
 const m=(await tx.query('SELECT m.id,m.professional_person_id AS person_id,p.account_id,p.first_name,p.first_surname FROM public.vitalia_clinic_memberships m JOIN public.vitalia_people p ON p.id=m.professional_person_id WHERE m.clinic_id=$1 AND m.id=$2',[clinic,member])).rows[0];
 if(!m)fail(404,'MEMBERSHIP_NOT_FOUND');return m;
}
const profileColumns='verification_status AS status,registration_reference AS "registrationReference",verification_revision AS revision,verification_request_id AS "verificationRequestId",verification_decided_at AS "decidedAt"';
async function lock(tx:Tx,clinic:string,person?:string){await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-onboarding-'+clinic]);if(person)await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-credential-'+person]);}
export function createCredentialVerificationService(db:DocumentDatabase){
 async function transaction<T>(fn:(tx:Tx)=>Promise<T>){try{return await db.transaction(fn);}catch(e){if(e instanceof CredentialVerificationError)throw e;const code=(e as {code?:string})?.code;if(['42P01','42703','42501'].includes(code??''))fail(503,'CREDENTIAL_VERIFICATION_UNAVAILABLE');if(code==='23505')fail(409,'CREDENTIAL_VERIFICATION_CONFLICT');if(['23503','23514','22001','22007'].includes(code??''))fail(400,'INVALID_CREDENTIAL_VERIFICATION');throw e;}}
 return {
 async details(a:AccountSummary,clinic:string,member:string){role(a);ids(clinic,member);return transaction(async tx=>{
 const m=await target(tx,a,clinic,member);const p=(await tx.query(`SELECT ${profileColumns} FROM public.vitalia_professional_profiles WHERE person_id=$1`,[m.person_id])).rows[0];
 const requests=(await tx.query(`SELECT r.id,r.registration_reference AS "registrationReference",r.supporting_reference AS "supportingReference",r.state,r.created_at AS "createdAt",r.requested_by AS "requestedBy",applicant.email AS "requestedByEmail",v.decision,v.actor_id AS "decidedBy",reviewer.email AS "decidedByEmail",v.source_reference AS "sourceReference",v.checked_at AS "checkedAt",v.reason,v.created_at AS "decidedAt" FROM public.vitalia_credential_requests r LEFT JOIN public.vitalia_credential_audit v ON v.request_id=r.id JOIN public.vitalia_accounts applicant ON applicant.id=r.requested_by LEFT JOIN public.vitalia_accounts reviewer ON reviewer.id=v.actor_id WHERE r.clinic_id=$1 AND r.membership_id=$2 ORDER BY r.created_at DESC,r.id DESC LIMIT 20`,[clinic,member])).rows;
 return {profile:p,requests,professional:{firstName:m.first_name,firstSurname:m.first_surname},canDecide:a.role==='administrador'&&m.account_id!==a.id};
 });},
 async request(a:AccountSummary,clinic:string,member:string,input:unknown){role(a);ids(clinic,member);const v=parse(credentialRequestInput,input);return transaction(async tx=>{
 await lock(tx,clinic);const m=await target(tx,a,clinic,member);await lock(tx,clinic,m.person_id);
 const hash=digest({clinic,member,...v});
 const previous=(await tx.query('SELECT requested_by,request_hash FROM public.vitalia_credential_requests WHERE id=$1',[v.requestId])).rows[0];
 if(previous){if(previous.requested_by!==a.id||previous.request_hash!==hash)fail(409,'CREDENTIAL_VERIFICATION_CONFLICT');return {recorded:true,replayed:true};}
 const p=(await tx.query(`SELECT ${profileColumns} FROM public.vitalia_professional_profiles WHERE person_id=$1 FOR UPDATE`,[m.person_id])).rows[0];if(!p||p.revision!==v.expectedRevision)fail(409,'CREDENTIAL_VERIFICATION_CONFLICT');
 if(!(await tx.query("SELECT role_code FROM public.vitalia_account_roles WHERE account_id=$1 AND role_code='profesional' AND active",[m.account_id])).rows.length)fail(409,'PROFESSIONAL_UNAVAILABLE');
 await tx.query('INSERT INTO public.vitalia_credential_requests(id,clinic_id,membership_id,person_id,requested_by,registration_reference,supporting_reference,request_hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8)',[v.requestId,clinic,member,m.person_id,a.id,v.registrationReference,v.supportingReference,hash]);
 return {recorded:true,replayed:false};
 });},
 async decide(a:AccountSummary,clinic:string,member:string,request:string,input:unknown){role(a);if(a.role!=='administrador')fail(403,'FORBIDDEN');ids(clinic,member,request);const v=parse(credentialDecisionInput,input);if(new Date(v.checkedAt).getTime()>Date.now())fail(400,'INVALID_CREDENTIAL_VERIFICATION');return transaction(async tx=>{
 await lock(tx,clinic);const m=await target(tx,a,clinic,member);if(m.account_id===a.id)fail(403,'FORBIDDEN');await lock(tx,clinic,m.person_id);
 const r=(await tx.query('SELECT id,state,registration_reference FROM public.vitalia_credential_requests WHERE id=$1 AND clinic_id=$2 AND membership_id=$3 AND person_id=$4 FOR UPDATE',[request,clinic,member,m.person_id])).rows[0];if(!r)fail(404,'CREDENTIAL_REQUEST_NOT_FOUND');
 const hash=digest({clinic,member,request,...v});const previous=(await tx.query('SELECT actor_id,request_hash FROM public.vitalia_credential_audit WHERE id=$1',[v.requestId])).rows[0];
 if(previous){if(previous.actor_id!==a.id||previous.request_hash!==hash)fail(409,'CREDENTIAL_VERIFICATION_CONFLICT');return {decided:true,replayed:true};}
 if(r.state!=='pending')fail(409,'CREDENTIAL_VERIFICATION_CONFLICT');
 const p=(await tx.query(`SELECT ${profileColumns} FROM public.vitalia_professional_profiles WHERE person_id=$1 FOR UPDATE`,[m.person_id])).rows[0];if(!p||p.revision!==v.expectedRevision)fail(409,'CREDENTIAL_VERIFICATION_CONFLICT');
 const next={status:v.decision,registrationReference:v.decision==='verified'?r.registration_reference:p.registrationReference,revision:p.revision+1,verificationRequestId:request};
 await tx.query('INSERT INTO public.vitalia_credential_audit(id,request_id,person_id,actor_id,decision,source_reference,checked_at,reason,confirmed,request_hash,before_state,after_state) VALUES($1,$2,$3,$4,$5,$6,$7,$8,true,$9,$10::jsonb,$11::jsonb)',[v.requestId,request,m.person_id,a.id,v.decision,v.sourceReference,v.checkedAt,v.reason,hash,JSON.stringify(p),JSON.stringify(next)]);
 await tx.query('UPDATE public.vitalia_professional_profiles SET verification_status=$2,registration_reference=$3,verification_revision=verification_revision+1,verification_request_id=$4,verification_decided_by=$5,verification_decided_at=(SELECT created_at FROM public.vitalia_credential_audit WHERE id=$6),updated_at=GREATEST(clock_timestamp(),updated_at) WHERE person_id=$1',[m.person_id,next.status,next.registrationReference,request,a.id,v.requestId]);
 await tx.query('UPDATE public.vitalia_credential_requests SET state=$2 WHERE id=$1',[request,v.decision]);
 return {decided:true,replayed:false};
 });}
 };
}
export type CredentialVerificationServices=ReturnType<typeof createCredentialVerificationService>;
