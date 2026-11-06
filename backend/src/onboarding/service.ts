import {createHash, randomBytes, randomUUID} from 'node:crypto';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {hashPassword,verifyPassword} from '../auth/password';
export class OnboardingError extends Error {constructor(public status:number,public code:string){super(code);}}
const text=(n:number)=>z.string().trim().min(1).max(n);
const uuid=z.uuid();
const ids=z.array(uuid).max(20).refine(a=>new Set(a).size===a.length);
const email=z.string().trim().toLowerCase().pipe(z.email().max(254));
export const authorizationInput=z.object({requestId:uuid,nomineeEmail:email,requesterName:text(150),requesterPosition:text(150),requesterContact:text(254),evidenceReference:text(500),requestedAt:z.iso.datetime({offset:true})}).strict();
export const invitationInput=z.object({requestId:uuid,email,authorizationId:uuid.nullable(),branchIds:ids,specialtyIds:ids}).strict();
export const activationInput=z.object({token:z.string().regex(/^[a-f0-9]{64}$/),firstName:text(100),firstSurname:text(100),password:z.string().refine(s=>Array.from(s).length>=12&&Buffer.byteLength(s,'utf8')<=1024),confirmation:z.string().max(1024)}).strict().refine(v=>v.password===v.confirmation);
const professionalPasswordFields={
 currentPassword:z.string().min(1).refine(s=>Buffer.byteLength(s,'utf8')<=1024),
 professionalPassword:z.string().refine(s=>Array.from(s).length>=12&&Buffer.byteLength(s,'utf8')<=1024).optional(),
 professionalConfirmation:z.string().max(1024).optional(),
};
export const professionalPasswordInput=z.object(professionalPasswordFields).strict();
type Tx=Parameters<Parameters<DocumentDatabase['transaction']>[0]>[0];
const authorizationCols='id,clinic_id AS "clinicId",nominee_email AS "nomineeEmail",requester_name AS "requesterName",requester_position AS "requesterPosition",requester_contact AS "requesterContact",evidence_reference AS "evidenceReference",requested_at AS "requestedAt",recorded_by AS "recordedBy",verified_by AS "verifiedBy",verified_at AS "verifiedAt",revoked_at AS "revokedAt"';
const inviteCols='id,email,clinical_role AS "clinicalRole",expires_at AS "expiresAt",revoked_at AS "revokedAt",activated_at AS "activatedAt"';
function fail(status:number,code:string):never{throw new OnboardingError(status,code);}
function admin(a:AccountSummary){if(a.role!=='administrador')fail(403,'FORBIDDEN');}
function checkId(id:string){if(!uuid.safeParse(id).success)fail(400,'INVALID_ONBOARDING');}
function parse<T>(schema:z.ZodType<T>,input:unknown):T{const p=schema.safeParse(input);return p.success?p.data:fail(400,'INVALID_ONBOARDING');}
function digest(token:string){return createHash('sha256').update(token).digest('hex');}
function translate(e:unknown):never{if(e instanceof OnboardingError)throw e;const c=(e as {code?:string})?.code;if(c==='23505')fail(409,'ONBOARDING_CONFLICT');if(['23503','23514','22001','22007'].includes(c??''))fail(400,'INVALID_ONBOARDING');if(['42501','42P01'].includes(c??''))fail(503,'ONBOARDING_UNAVAILABLE');throw e;}
async function lock(tx:Tx,clinic:string){await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-onboarding-'+clinic]);}
async function audit(tx:Tx,a:string,clinic:string,action:string,authorization:string|null=null,invitation:string|null=null){await tx.query('INSERT INTO public.vitalia_onboarding_audit(id,actor_id,clinic_id,authorization_id,invitation_id,action) VALUES($1,$2,$3,$4,$5,$6)',[randomUUID(),a,clinic,authorization,invitation,action]);}
async function clinicActive(tx:Tx,id:string){if(!(await tx.query('SELECT id FROM public.vitalia_clinics WHERE id=$1 AND active',[id])).rows.length)fail(409,'CLINIC_UNAVAILABLE');}
async function chief(tx:Pick<Tx,'query'>,a:AccountSummary,clinic:string){if(a.role!=='profesional')fail(403,'FORBIDDEN');if(!(await tx.query(`SELECT m.id FROM public.vitalia_clinic_memberships m JOIN public.vitalia_people p ON p.id=m.professional_person_id JOIN public.vitalia_clinics c ON c.id=m.clinic_id WHERE p.account_id=$1 AND m.clinic_id=$2 AND m.clinical_role='jefe_clinico' AND m.active AND c.active`,[a.id,clinic])).rows.length)fail(403,'FORBIDDEN');}
async function manage(tx:Pick<Tx,'query'>,a:AccountSummary,clinic:string){checkId(clinic);if(a.role!=='administrador')await chief(tx,a,clinic);}
async function validAuthorization(tx:Tx,clinic:string,id:string,nominee:string){const r=await tx.query('SELECT id FROM public.vitalia_institution_authorizations WHERE clinic_id=$1 AND id=$2 AND verified_at IS NOT NULL AND revoked_at IS NULL AND nominee_email=$3 FOR UPDATE',[clinic,id,nominee]);if(!r.rows.length)fail(409,'AUTHORIZATION_REQUIRED');}
async function noChief(tx:Tx,clinic:string){if((await tx.query("SELECT id FROM public.vitalia_clinic_memberships WHERE clinic_id=$1 AND clinical_role='jefe_clinico' AND active",[clinic])).rows.length)fail(409,'CHIEF_ALREADY_EXISTS');}
async function choices(tx:Tx,clinic:string,branches:string[],specialties:string[]){
 const b=await tx.query('SELECT id FROM public.vitalia_branches WHERE clinic_id=$1 AND id=ANY($2::uuid[]) AND active',[clinic,branches]);
 const s=await tx.query('SELECT id FROM public.vitalia_specialties WHERE id=ANY($1::uuid[]) AND active',[specialties]);
 if(b.rows.length!==branches.length||s.rows.length!==specialties.length)fail(400,'INVALID_ONBOARDING');
}
async function professionalCredential(tx:Tx,a:AccountSummary,v:z.infer<typeof professionalPasswordInput>,requireExisting=false){
 await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-password-'+a.id]);
 const account=(await tx.query('SELECT id,role_code,password_hash FROM public.vitalia_accounts WHERE id=$1',[a.id])).rows[0];
 const roles=(await tx.query('SELECT role_code,password_hash,active FROM public.vitalia_account_roles WHERE account_id=$1',[a.id])).rows;
 const current=roles.find(r=>r.role_code===a.role&&r.active);
 const currentHash=current?.password_hash??(account?.role_code===a.role?account.password_hash:null);
 if(!currentHash||!await verifyPassword(v.currentPassword,currentHash))fail(403,'CURRENT_PASSWORD_INVALID');
 const professional=roles.find(r=>r.role_code==='profesional');
 if(requireExisting&&!professional?.active)fail(403,'FORBIDDEN');
 if(professional&&!professional.active)fail(403,'FORBIDDEN');
 const alreadyConfigured=professional?.password_hash||account.role_code==='profesional';
 if(alreadyConfigured){
  if(a.role!=='profesional'||v.professionalPassword!==undefined||v.professionalConfirmation!==undefined)fail(409,'PROFESSIONAL_PASSWORD_EXISTS');
  return null;
 }
 if(!v.professionalPassword||v.professionalPassword!==v.professionalConfirmation)fail(400,'PROFESSIONAL_PASSWORD_REQUIRED');
 if(await verifyPassword(v.professionalPassword,account.password_hash))fail(400,'PASSWORD_REUSED');
 return hashPassword(v.professionalPassword);
}
export function createOnboardingService(db:DocumentDatabase){
 let activating=false;
 async function transaction<T>(fn:(tx:Tx)=>Promise<T>){try{return await db.transaction(fn);}catch(e){translate(e);}}
 return {
 async context(a:AccountSummary){if(!['administrador','profesional'].includes(a.role))fail(403,'FORBIDDEN');try{
 const clinics=a.role==='administrador'?await db.query('SELECT id,name FROM public.vitalia_clinics WHERE active ORDER BY name,id LIMIT 200'):await db.query(`SELECT DISTINCT c.id,c.name FROM public.vitalia_clinics c JOIN public.vitalia_clinic_memberships m ON m.clinic_id=c.id JOIN public.vitalia_people p ON p.id=m.professional_person_id WHERE p.account_id=$1 AND c.active AND m.active AND m.clinical_role='jefe_clinico' ORDER BY c.name,c.id LIMIT 200`,[a.id]);
 return {clinics:clinics.rows};}catch(e){translate(e);}},
 async details(a:AccountSummary,clinic:string){return transaction(async tx=>{await manage(tx,a,clinic);await clinicActive(tx,clinic);
 return {branches:(await tx.query('SELECT id,name FROM public.vitalia_branches WHERE clinic_id=$1 AND active ORDER BY name,id LIMIT 200',[clinic])).rows,specialties:(await tx.query('SELECT id,name FROM public.vitalia_specialties WHERE active ORDER BY name,id LIMIT 200')).rows,
 invitations:(await tx.query(`SELECT ${inviteCols} FROM public.vitalia_professional_invitations WHERE clinic_id=$1 ${a.role==='administrador'?'':"AND clinical_role='profesional'"} ORDER BY created_at DESC,id LIMIT 50`,[clinic])).rows,
 authorizations:a.role==='administrador'?(await tx.query(`SELECT ${authorizationCols} FROM public.vitalia_institution_authorizations WHERE clinic_id=$1 ORDER BY created_at DESC,id LIMIT 50`,[clinic])).rows:[]};});},
 async record(a:AccountSummary,clinic:string,input:unknown){admin(a);checkId(clinic);const v=parse(authorizationInput,input);if(new Date(v.requestedAt).getTime()>Date.now())fail(400,'INVALID_ONBOARDING');return transaction(async tx=>{
 await lock(tx,clinic);await clinicActive(tx,clinic);
 const r=await tx.query(`INSERT INTO public.vitalia_institution_authorizations(id,clinic_id,nominee_email,requester_name,requester_position,requester_contact,evidence_reference,requested_at,recorded_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING ${authorizationCols}`,[v.requestId,clinic,v.nomineeEmail,v.requesterName,v.requesterPosition,v.requesterContact,v.evidenceReference,v.requestedAt,a.id]);
 await audit(tx,a.id,clinic,'authorization_recorded',v.requestId);return r.rows[0];});},
 async verify(a:AccountSummary,clinic:string,id:string,input:unknown){admin(a);checkId(clinic);checkId(id);parse(z.object({confirmed:z.literal(true),...professionalPasswordFields}).strict(),input);return transaction(async tx=>{
 await lock(tx,clinic);await clinicActive(tx,clinic);const r=await tx.query(`UPDATE public.vitalia_institution_authorizations SET verified_by=$3,verified_at=CURRENT_TIMESTAMP WHERE clinic_id=$1 AND id=$2 AND verified_at IS NULL AND revoked_at IS NULL RETURNING ${authorizationCols}`,[clinic,id,a.id]);if(!r.rows.length)fail(409,'AUTHORIZATION_UNAVAILABLE');await audit(tx,a.id,clinic,'authorization_verified',id);return r.rows[0];});},
 async revokeAuthorization(a:AccountSummary,clinic:string,id:string){admin(a);checkId(clinic);checkId(id);return transaction(async tx=>{await lock(tx,clinic);const r=await tx.query('UPDATE public.vitalia_institution_authorizations SET revoked_at=CURRENT_TIMESTAMP WHERE clinic_id=$1 AND id=$2 AND revoked_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.vitalia_professional_invitations i WHERE i.authorization_id=$2 AND i.activated_at IS NOT NULL) RETURNING id',[clinic,id]);if(!r.rows.length)fail(409,'AUTHORIZATION_UNAVAILABLE');await audit(tx,a.id,clinic,'authorization_revoked',id);});},
 async addSpecialty(a:AccountSummary,clinic:string,input:unknown){admin(a);checkId(clinic);const v=parse(z.object({name:text(150)}).strict(),input);return transaction(async tx=>{await clinicActive(tx,clinic);const r=await tx.query('INSERT INTO public.vitalia_specialties(id,name) VALUES($1,$2) RETURNING id,name',[randomUUID(),v.name]);await audit(tx,a.id,clinic,'specialty_created');return r.rows[0];});},
 async invite(a:AccountSummary,clinic:string,input:unknown){checkId(clinic);const v=parse(invitationInput,input);return transaction(async tx=>{
 await lock(tx,clinic);await clinicActive(tx,clinic);let role:string;
 if(a.role==='administrador'){if(!v.authorizationId)fail(409,'AUTHORIZATION_REQUIRED');await validAuthorization(tx,clinic,v.authorizationId,v.email);await noChief(tx,clinic);role='jefe_clinico';}
 else {await chief(tx,a,clinic);if(v.authorizationId)fail(403,'FORBIDDEN');role='profesional';}
 await choices(tx,clinic,v.branchIds,v.specialtyIds);
 const existing=(await tx.query('SELECT id,role_code FROM public.vitalia_accounts WHERE email=$1',[v.email])).rows[0];
 if(existing?.role_code==='administrador')fail(409,'EXISTING_ACCOUNT');
 if(role==='jefe_clinico'&&(await tx.query("SELECT id FROM public.vitalia_professional_invitations WHERE clinic_id=$1 AND clinical_role='jefe_clinico' AND activated_at IS NULL AND revoked_at IS NULL AND expires_at>CURRENT_TIMESTAMP",[clinic])).rows.length)fail(409,'ONBOARDING_CONFLICT');
 const token=randomBytes(32).toString('hex');
 const r=await tx.query(`INSERT INTO public.vitalia_professional_invitations(id,clinic_id,authorization_id,email,clinical_role,invited_by,token_hash) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING ${inviteCols}`,[v.requestId,clinic,v.authorizationId,v.email,role,a.id,digest(token)]);
 for(const id of v.branchIds)await tx.query('INSERT INTO public.vitalia_invitation_branches(clinic_id,invitation_id,branch_id) VALUES($1,$2,$3)',[clinic,v.requestId,id]);
 for(const id of v.specialtyIds)await tx.query('INSERT INTO public.vitalia_invitation_specialties(invitation_id,specialty_id) VALUES($1,$2)',[v.requestId,id]);
 await audit(tx,a.id,clinic,'invitation_created',v.authorizationId,v.requestId);return {item:r.rows[0],token};});},
 async revoke(a:AccountSummary,clinic:string,id:string){checkId(clinic);checkId(id);return transaction(async tx=>{await lock(tx,clinic);await manage(tx,a,clinic);const r=await tx.query(`UPDATE public.vitalia_professional_invitations SET revoked_at=CURRENT_TIMESTAMP WHERE clinic_id=$1 AND id=$2 AND activated_at IS NULL AND revoked_at IS NULL ${a.role==='administrador'?'':"AND clinical_role='profesional'"} RETURNING id,authorization_id`,[clinic,id]);if(!r.rows.length)fail(409,'INVITATION_UNAVAILABLE');await audit(tx,a.id,clinic,'invitation_revoked',r.rows[0].authorization_id,id);});},
 async changeProfessionalPassword(a:AccountSummary,input:unknown){
 if(a.role!=='profesional')fail(403,'FORBIDDEN');
 const v=parse(professionalPasswordInput.extend({confirmed:z.literal(true)}),input);
 if(!v.professionalPassword||v.professionalPassword!==v.professionalConfirmation)fail(400,'PROFESSIONAL_PASSWORD_REQUIRED');
 const newPassword=v.professionalPassword;
 if(activating)fail(429,'ACTIVATION_BUSY');activating=true;
 try{return await transaction(async tx=>{
  await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-password-'+a.id]);
  const account=(await tx.query('SELECT id,role_code,password_hash FROM public.vitalia_accounts WHERE id=$1',[a.id])).rows[0];
  const roles=(await tx.query('SELECT role_code,password_hash,active FROM public.vitalia_account_roles WHERE account_id=$1',[a.id])).rows;
  const role=roles.find(r=>r.role_code==='profesional'&&r.active);
  const currentHash=role?.password_hash??(account?.role_code==='profesional'?account.password_hash:null);
  if(!role||!currentHash||!await verifyPassword(v.currentPassword,currentHash))fail(403,'CURRENT_PASSWORD_INVALID');
  if(await verifyPassword(newPassword,currentHash))fail(400,'PASSWORD_UNCHANGED');
  if(account.role_code!=='profesional'&&await verifyPassword(newPassword,account.password_hash))fail(400,'PASSWORD_REUSED');
  const passwordHash=await hashPassword(newPassword);
  await tx.query("UPDATE public.vitalia_account_roles SET password_hash=$2 WHERE account_id=$1 AND role_code='profesional' AND active",[a.id,passwordHash]);
  await tx.query("DELETE FROM public.vitalia_sessions WHERE account_id=$1 AND active_role='profesional'",[a.id]);
  return {changed:true};
 });}finally{activating=false;}
 },
 async configureProfessionalPassword(a:AccountSummary,input:unknown){
 if(a.role!=='paciente')fail(403,'FORBIDDEN');
 const v=parse(professionalPasswordInput,input);
 if(activating)fail(429,'ACTIVATION_BUSY');activating=true;
 try{return await transaction(async tx=>{
  const passwordHash=await professionalCredential(tx,a,v,true);
  await tx.query("UPDATE public.vitalia_account_roles SET password_hash=$2 WHERE account_id=$1 AND role_code='profesional' AND active AND password_hash IS NULL",[a.id,passwordHash]);
  await tx.query("DELETE FROM public.vitalia_sessions WHERE account_id=$1 AND active_role='profesional'",[a.id]);
  return {configured:true};
 });}finally{activating=false;}
 },
 async accept(a:AccountSummary,input:unknown){
 if(!['paciente','profesional'].includes(a.role))fail(403,'FORBIDDEN');
 const v=parse(z.object({token:z.string().regex(/^[a-f0-9]{64}$/),firstName:text(100),firstSurname:text(100),confirmed:z.literal(true),...professionalPasswordFields}).strict(),input);
 if(activating)fail(429,'ACTIVATION_BUSY');activating=true;
 try{return await transaction(async tx=>{
  const hash=digest(v.token);const found=(await tx.query('SELECT clinic_id FROM public.vitalia_professional_invitations WHERE token_hash=$1',[hash])).rows[0];if(!found)fail(400,'INVITATION_UNAVAILABLE');
  await lock(tx,found.clinic_id);
  const inv=(await tx.query('SELECT * FROM public.vitalia_professional_invitations WHERE token_hash=$1 AND activated_at IS NULL AND revoked_at IS NULL AND expires_at>CURRENT_TIMESTAMP FOR UPDATE',[hash])).rows[0];
  if(!inv)fail(400,'INVITATION_UNAVAILABLE');
  const account=(await tx.query('SELECT id,email,role_code FROM public.vitalia_accounts WHERE id=$1',[a.id])).rows[0];
  if(!account||account.email!==inv.email)fail(403,'INVITATION_ACCOUNT_MISMATCH');
  if(account.role_code==='administrador')fail(403,'FORBIDDEN');
  const professionalHash=await professionalCredential(tx,a,v);
  await clinicActive(tx,inv.clinic_id);
  if(inv.clinical_role==='jefe_clinico'){await validAuthorization(tx,inv.clinic_id,inv.authorization_id,inv.email);await noChief(tx,inv.clinic_id);}
  else await chief(tx,{id:inv.invited_by,role:'profesional'} as AccountSummary,inv.clinic_id);
  const branches=(await tx.query('SELECT branch_id FROM public.vitalia_invitation_branches WHERE invitation_id=$1',[inv.id])).rows.map(r=>r.branch_id);
  const specialties=(await tx.query('SELECT specialty_id FROM public.vitalia_invitation_specialties WHERE invitation_id=$1',[inv.id])).rows.map(r=>r.specialty_id);
  await choices(tx,inv.clinic_id,branches,specialties);
  let person=(await tx.query('SELECT id FROM public.vitalia_people WHERE account_id=$1',[a.id])).rows[0]?.id;
  if(!person){person=randomUUID();await tx.query('INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname) VALUES($1,$2,$3,$4)',[person,a.id,v.firstName,v.firstSurname]);}
  if((await tx.query('SELECT id FROM public.vitalia_clinic_memberships WHERE clinic_id=$1 AND professional_person_id=$2',[inv.clinic_id,person])).rows.length)fail(409,'ALREADY_MEMBER');
  await tx.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1) ON CONFLICT DO NOTHING',[person]);
  await tx.query("INSERT INTO public.vitalia_account_roles(account_id,role_code,grant_source,invitation_id) VALUES($1,'profesional','invitation_accepted',$2) ON CONFLICT(account_id,role_code) DO NOTHING",[a.id,inv.id]);
  if(professionalHash)await tx.query("UPDATE public.vitalia_account_roles SET password_hash=$2 WHERE account_id=$1 AND role_code='profesional' AND active AND password_hash IS NULL",[a.id,professionalHash]);
  // Un permiso global revocado no se reactiva por aceptar otra invitación.
  if(!(await tx.query("SELECT role_code FROM public.vitalia_account_roles WHERE account_id=$1 AND role_code='profesional' AND active",[a.id])).rows.length)fail(403,'FORBIDDEN');
  const membership=randomUUID();await tx.query('INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id,clinical_role,active) VALUES($1,$2,$3,$4,true)',[membership,inv.clinic_id,person,inv.clinical_role]);
  for(const id of branches)await tx.query('INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)',[inv.clinic_id,id,membership]);
  for(const id of specialties)await tx.query('INSERT INTO public.vitalia_membership_specialties(clinic_id,membership_id,specialty_id) VALUES($1,$2,$3)',[inv.clinic_id,membership,id]);
  await tx.query('UPDATE public.vitalia_professional_invitations SET activated_at=CURRENT_TIMESTAMP,activated_account_id=$2 WHERE id=$1',[inv.id,a.id]);
  await audit(tx,a.id,inv.clinic_id,'invitation_activated',inv.authorization_id,inv.id);
  return {accepted:true};
 });}finally{activating=false;}},
 async activate(input:unknown){const v=parse(activationInput,input);if(activating)fail(429,'ACTIVATION_BUSY');activating=true;try{
 // Rechazar tokens inválidos antes de calcular scrypt; revalidar bajo bloqueo tras el hash.
 const hash=digest(v.token);const pre=await db.query('SELECT id FROM public.vitalia_professional_invitations WHERE token_hash=$1 AND activated_at IS NULL AND revoked_at IS NULL AND expires_at>CURRENT_TIMESTAMP',[hash]);if(!pre.rows.length)fail(400,'INVITATION_UNAVAILABLE');
 const passwordHash=await hashPassword(v.password);
 return await transaction(async tx=>{
 const found=(await tx.query('SELECT clinic_id FROM public.vitalia_professional_invitations WHERE token_hash=$1',[hash])).rows[0];if(!found)fail(400,'INVITATION_UNAVAILABLE');await lock(tx,found.clinic_id);
 const inv=(await tx.query('SELECT * FROM public.vitalia_professional_invitations WHERE token_hash=$1 AND activated_at IS NULL AND revoked_at IS NULL AND expires_at>CURRENT_TIMESTAMP FOR UPDATE',[hash])).rows[0];if(!inv)fail(400,'INVITATION_UNAVAILABLE');
 await clinicActive(tx,inv.clinic_id);
 if(inv.clinical_role==='jefe_clinico'){await validAuthorization(tx,inv.clinic_id,inv.authorization_id,inv.email);await noChief(tx,inv.clinic_id);}
 else {await chief(tx,{id:inv.invited_by,role:'profesional'} as AccountSummary,inv.clinic_id);}
 const branches=(await tx.query('SELECT branch_id FROM public.vitalia_invitation_branches WHERE invitation_id=$1',[inv.id])).rows.map(r=>r.branch_id);
 const specialties=(await tx.query('SELECT specialty_id FROM public.vitalia_invitation_specialties WHERE invitation_id=$1',[inv.id])).rows.map(r=>r.specialty_id);
 await choices(tx,inv.clinic_id,branches,specialties);
 const account=randomUUID(),person=randomUUID(),membership=randomUUID();
 if((await tx.query('SELECT id FROM public.vitalia_accounts WHERE email=$1',[inv.email])).rows.length)fail(409,'EXISTING_ACCOUNT');
 await tx.query("INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,$3,'profesional')",[account,inv.email,passwordHash]);
 await tx.query('INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname) VALUES($1,$2,$3,$4)',[person,account,v.firstName,v.firstSurname]);
 await tx.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1)',[person]);
 await tx.query('INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id,clinical_role,active) VALUES($1,$2,$3,$4,true)',[membership,inv.clinic_id,person,inv.clinical_role]);
 for(const id of branches)await tx.query('INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)',[inv.clinic_id,id,membership]);
 for(const id of specialties){
  await tx.query('INSERT INTO public.vitalia_professional_specialties(professional_person_id,specialty_id) VALUES($1,$2)',[person,id]);
  await tx.query('INSERT INTO public.vitalia_membership_specialties(clinic_id,membership_id,specialty_id) VALUES($1,$2,$3)',[inv.clinic_id,membership,id]);
 }
 await tx.query('UPDATE public.vitalia_professional_invitations SET activated_at=CURRENT_TIMESTAMP,activated_account_id=$2 WHERE id=$1',[inv.id,account]);
 await audit(tx,account,inv.clinic_id,'invitation_activated',inv.authorization_id,inv.id);
 return {activated:true};});
 }catch(e){translate(e);}finally{activating=false;}}
 };
}
export type OnboardingServices=ReturnType<typeof createOnboardingService>;
