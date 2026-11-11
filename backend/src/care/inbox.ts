import {randomUUID} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {extractionSchema,type Extraction} from '../ai/contract';
import {processingResultSchema} from '../processing/result';
import {reviewedExtractionValid} from '../reviews/validation';
import {type Pool} from 'pg';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase,type DocumentStorage} from '../documents/service';
import {identifyDocument,MAX_FILE_BYTES} from '../documents/file-validation';
type DB=Pick<Pool,'query'>;
export class CareInboxError extends Error {
 constructor(public readonly status:number,public readonly code:string){super(code);}
}
const joins=`FROM public.vitalia_exam_care c
 JOIN public.vitalia_documents d ON d.id=c.document_id AND d.patient_id=c.patient_id AND d.status='stored' AND d.care_flow
 JOIN public.vitalia_clinic_memberships m ON m.id=c.responsible_membership_id AND m.clinic_id=c.clinic_id AND m.active
 JOIN public.vitalia_people p ON p.id=m.professional_person_id
 JOIN public.vitalia_account_roles g ON g.account_id=p.account_id AND g.role_code='profesional' AND g.active
 JOIN public.vitalia_professional_profiles f ON f.person_id=p.id AND f.verification_status='verified'
 JOIN public.vitalia_credential_audit a ON a.request_id=f.verification_request_id AND a.person_id=p.id AND a.decision='verified'
 JOIN public.vitalia_clinics cl ON cl.id=c.clinic_id AND cl.active
 JOIN public.vitalia_branches b ON b.id=c.branch_id AND b.clinic_id=c.clinic_id AND b.active
 JOIN public.vitalia_branch_memberships bm ON bm.membership_id=m.id AND bm.branch_id=b.id AND bm.clinic_id=cl.id
 JOIN public.vitalia_specialties s ON s.id=c.specialty_id AND s.active
 JOIN public.vitalia_membership_specialties ms ON ms.membership_id=m.id AND ms.specialty_id=s.id AND ms.clinic_id=cl.id
 JOIN public.vitalia_people patient ON patient.account_id=c.patient_id
 JOIN public.vitalia_care_contacts contact ON contact.document_id=d.id AND contact.patient_id=c.patient_id`;
const scope=`p.account_id=$1 AND c.status IN ('requested','active','completed')
 AND f.registration_reference=a.after_state->>'registrationReference'
 AND f.verification_revision::text=a.after_state->>'revision'
 AND f.verification_decided_by=a.actor_id AND f.verification_decided_at=a.created_at`;
const columns=`c.id,c.status,c.revision,c.document_id,c.patient_id,c.clinic_id,c.responsible_membership_id,c.specialty_id,c.branch_id,
 cl.name AS clinic_name,b.name AS branch_name,s.name AS specialty_name,
 concat_ws(' ',patient.first_name,patient.additional_names,patient.first_surname,patient.second_surname) AS patient_name,
 d.exam_name,d.exam_type,d.exam_date::text,d.original_name,d.content_type,d.size_bytes,d.storage_key`;
interface Row {
 id:string;status:string;revision:number;document_id:string;patient_id:string;clinic_id:string;responsible_membership_id:string;specialty_id:string;branch_id:string;
 clinic_name:string;branch_name:string;specialty_name:string;patient_name:string;
 exam_name:string;exam_type:string;exam_date:string;original_name:string;content_type:string;size_bytes:number;storage_key:string;
 referral_reason:string|null;referred_by:string|null;phone:string;email:string;street:string;address_number:string;residence_commune:string;consultation_commune:string;confirmed_at:Date;
}
function professional(a:AccountSummary){if(a.role!=='profesional')throw new CareInboxError(403,'FORBIDDEN');}
function summary(r:Row){return {id:r.id,status:r.status,revision:r.revision,clinicName:r.clinic_name,branchName:r.branch_name,
 specialtyName:r.specialty_name,patientName:r.patient_name,document:{id:r.document_id,examName:r.exam_name,examType:r.exam_type,
 examDate:r.exam_date,originalName:r.original_name,contentType:r.content_type,sizeBytes:r.size_bytes}};}
function translate(e:unknown):never{
 if(e instanceof CareInboxError)throw e;
 const code=(e as {code?:string})?.code;
 if(['42P01','42703','42501'].includes(code??''))throw new CareInboxError(503,'CARE_INBOX_UNAVAILABLE');
 if(code==='P0001')throw new CareInboxError(404,'CARE_NOT_FOUND');
 if(['40001','40P01'].includes(code??''))throw new CareInboxError(409,'CARE_CHANGED');
 throw e;
}
async function load(tx:DB,a:AccountSummary,id:string,update=false){
 const result=await tx.query<Row>(`SELECT ${columns},contact.phone,contact.email,contact.street,contact.address_number,
 residence.name AS residence_commune,zone.name AS consultation_commune,contact.created_at AS confirmed_at,ref.reason AS referral_reason,
 concat_ws(' ',previous_person.first_name,previous_person.first_surname) AS referred_by
 ${joins}
 LEFT JOIN public.vitalia_exam_referrals ref ON ref.target_care_id=c.id
 LEFT JOIN public.vitalia_people previous_person ON previous_person.account_id=ref.actor_id JOIN public.vitalia_communes residence ON residence.code=contact.residence_commune_code
 JOIN public.vitalia_communes zone ON zone.code=contact.consultation_commune_code
 WHERE ${scope} AND c.id=$2 ${update?'FOR UPDATE OF c':'FOR SHARE OF c'} FOR SHARE OF d`,[a.id,id]);
 const row=result.rows[0];if(!row)throw new CareInboxError(404,'CARE_NOT_FOUND');
 // Mantener elegibilidad y relaciones bloqueadas mientras se expone contenido o se inicia la atención.
 await tx.query('SELECT public.vitalia_lock_care_selection($1,$2,$3)',[row.responsible_membership_id,row.specialty_id,row.branch_id]);
 return row;
}
async function audit(tx:DB,a:AccountSummary,action:'list'|'view'|'download'|'view_review'|'referral_options',id:string|null){
 await tx.query('INSERT INTO public.vitalia_care_access_audit(care_id,actor_id,action) VALUES($1,$2,$3)',[id,a.id,action]);
}
interface CareReview {id:string;processing_id:string;reviewer_id:string;reviewer_email:string;reviewed_extraction:Extraction;observations:string;created_at:Date}
async function savedReview(tx:DB,id:string){
 return (await tx.query<CareReview>(`SELECT r.id,r.processing_id,r.reviewer_id,a.email AS reviewer_email,
  r.reviewed_extraction,r.observations,r.created_at FROM public.vitalia_care_reviews r
  JOIN public.vitalia_accounts a ON a.id=r.reviewer_id WHERE r.care_id=$1`,[id])).rows[0]??null;
}
function reviewSummary(r:CareReview){return {id:r.id,processingId:r.processing_id,reviewerId:r.reviewer_id,
 reviewerEmail:r.reviewer_email,extraction:extractionSchema.parse(r.reviewed_extraction),observations:r.observations,reviewedAt:r.created_at,approved:true};}
const careReviewInput=z.object({processingId:z.uuid(),extraction:extractionSchema,observations:z.string().trim().max(2000),
 confirmedOriginal:z.literal(true),expectedRevision:z.number().int().min(0).max(2147483646)}).strict();
const referralInput=z.object({requestId:z.uuid(),expectedRevision:z.number().int().min(0).max(2147483646),
 membershipId:z.uuid(),branchId:z.uuid(),specialtyId:z.uuid(),reason:z.string().trim().min(5).max(500),confirmed:z.literal(true)}).strict();
async function receipt(tx:DB,a:AccountSummary,id:string,v:z.infer<typeof referralInput>){
 const r=(await tx.query<{actor_id:string;source_care_id:string;reason:string;revision:number;responsible_membership_id:string;branch_id:string;specialty_id:string}>(
  `SELECT r.actor_id,r.source_care_id,r.reason,s.revision,t.responsible_membership_id,t.branch_id,t.specialty_id
  FROM public.vitalia_exam_referrals r JOIN public.vitalia_exam_care s ON s.id=r.source_care_id
  JOIN public.vitalia_exam_care t ON t.id=r.target_care_id WHERE r.id=$1`,[v.requestId])).rows[0];
 if(!r)return null;
 if(r.actor_id!==a.id)throw new CareInboxError(404,'CARE_NOT_FOUND');
 if(r.source_care_id!==id||r.reason!==v.reason||r.revision!==v.expectedRevision+1||
  r.responsible_membership_id!==v.membershipId||r.branch_id!==v.branchId||r.specialty_id!==v.specialtyId)throw new CareInboxError(409,'CARE_CHANGED');
 return {referred:true,targetCareId:v.requestId,replayed:true};
}
export function createCareInboxService(db:DocumentDatabase,storage:Pick<DocumentStorage,'read'>){return {
 async list(a:AccountSummary,input:unknown){professional(a);
  const schema=z.object({offset:z.string().regex(/^(0|[1-9]\d*)$/).transform(Number).pipe(z.number().int().max(100000)).optional().default(0)}).strict();
  const parsed=schema.safeParse(input);if(!parsed.success)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  try{return await db.transaction(async tx=>{
   const rows=(await tx.query<Row>(`SELECT ${columns} ${joins} WHERE ${scope}
    ORDER BY c.created_at DESC,c.id DESC LIMIT 21 OFFSET $2`,[a.id,parsed.data.offset])).rows;
   await audit(tx,a,'list',null);
   return {items:rows.slice(0,20).map(summary),nextOffset:rows.length>20?parsed.data.offset+20:null};
  });}catch(e){translate(e);}
 },
 async details(a:AccountSummary,id:string){professional(a);if(!z.uuid().safeParse(id).success)throw new CareInboxError(404,'CARE_NOT_FOUND');
  try{return await db.transaction(async tx=>{
   const r=await load(tx,a,id);await audit(tx,a,'view',id);
   return {care:summary(r),referral:r.referral_reason?{reason:r.referral_reason,referredBy:r.referred_by}:null,contact:{phone:r.phone,email:r.email,street:r.street,addressNumber:r.address_number,
    residenceCommune:r.residence_commune,consultationCommune:r.consultation_commune,confirmedAt:r.confirmed_at}};
  });}catch(e){translate(e);}
 },
 async begin(a:AccountSummary,id:string,input:unknown){professional(a);if(!z.uuid().safeParse(id).success)throw new CareInboxError(404,'CARE_NOT_FOUND');
  const parsed=z.object({expectedRevision:z.number().int().min(0).max(2147483646)}).strict().safeParse(input);
  if(!parsed.success)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  try{return await db.transaction(async tx=>{
   const r=await load(tx,a,id,true),expected=parsed.data.expectedRevision;
   if(r.status==='active'&&r.revision===expected+1)return {started:true,replayed:true};
   if(r.status!=='requested'||r.revision!==expected)throw new CareInboxError(409,'CARE_CHANGED');
   await tx.query(`UPDATE public.vitalia_exam_care SET status='active',updated_by=$2,revision=revision+1 WHERE id=$1`,[id,a.id]);
   return {started:true,replayed:false};
  });}catch(e){translate(e);}
 },
 async referralOptions(a:AccountSummary,id:string,input:unknown){professional(a);
  if(!z.uuid().safeParse(id).success)throw new CareInboxError(404,'CARE_NOT_FOUND');
  const parsed=z.object({offset:z.string().regex(/^(0|[1-9]\d*)$/).transform(Number).pipe(z.number().int().max(100000)).optional().default(0)}).strict().safeParse(input);
  if(!parsed.success)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  try{return await db.transaction(async tx=>{
   const source=await load(tx,a,id);if(!['requested','active'].includes(source.status))throw new CareInboxError(409,'CARE_CHANGED');
   const rows=(await tx.query(`SELECT m.id AS "membershipId",b.id AS "branchId",b.name AS "branchName",b.street,
    b.address_number AS "addressNumber",co.name AS "communeName",s.id AS "specialtyId",s.name AS "specialtyName",
    concat_ws(' ',p.first_name,p.additional_names,p.first_surname,p.second_surname) AS "professionalName"
    FROM public.vitalia_clinic_memberships m JOIN public.vitalia_people p ON p.id=m.professional_person_id
    JOIN public.vitalia_professional_profiles f ON f.person_id=p.id AND f.verification_status='verified'
    JOIN public.vitalia_account_roles g ON g.account_id=p.account_id AND g.role_code='profesional' AND g.active
    JOIN public.vitalia_credential_audit v ON v.request_id=f.verification_request_id AND v.person_id=p.id AND v.decision='verified'
    JOIN public.vitalia_branch_memberships bm ON bm.membership_id=m.id AND bm.clinic_id=m.clinic_id
    JOIN public.vitalia_branches b ON b.id=bm.branch_id AND b.clinic_id=m.clinic_id AND b.active
    JOIN public.vitalia_communes co ON co.code=b.commune_code
    JOIN public.vitalia_membership_specialties ms ON ms.membership_id=m.id AND ms.clinic_id=m.clinic_id
    JOIN public.vitalia_specialties s ON s.id=ms.specialty_id AND s.active
    WHERE m.clinic_id=$1 AND m.id<>$2 AND m.active
     AND f.registration_reference=v.after_state->>'registrationReference'
     AND f.verification_revision::text=v.after_state->>'revision'
     AND f.verification_decided_by=v.actor_id AND f.verification_decided_at=v.created_at
    ORDER BY b.name,b.id,s.name,s.id,p.first_surname,p.first_name,m.id LIMIT 31 OFFSET $3`,
   [source.clinic_id,source.responsible_membership_id,parsed.data.offset])).rows;
   await audit(tx,a,'referral_options',id);
   return {expectedRevision:source.revision,clinicName:source.clinic_name,items:rows.slice(0,30),nextOffset:rows.length>30?parsed.data.offset+30:null};
  });}catch(e){translate(e);}
 },
 async refer(a:AccountSummary,id:string,input:unknown){professional(a);
  if(!z.uuid().safeParse(id).success)throw new CareInboxError(404,'CARE_NOT_FOUND');
  const parsed=referralInput.safeParse(input);if(!parsed.success)throw new CareInboxError(400,'INVALID_CARE_REFERRAL');const v=parsed.data;
  try{return await db.transaction(async tx=>{
   await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-care-referral-'+id]);
   const previous=await receipt(tx,a,id,v);if(previous)return previous;
   const source=await load(tx,a,id,true);
   if(!['requested','active'].includes(source.status)||source.revision!==v.expectedRevision||
    v.membershipId===source.responsible_membership_id||await savedReview(tx,id))throw new CareInboxError(409,'CARE_CHANGED');
   const target=await tx.query(`SELECT m.id FROM public.vitalia_clinic_memberships m
    JOIN public.vitalia_branch_memberships bm ON bm.membership_id=m.id AND bm.clinic_id=m.clinic_id
    JOIN public.vitalia_branches b ON b.id=bm.branch_id AND b.clinic_id=m.clinic_id AND b.active
    JOIN public.vitalia_membership_specialties ms ON ms.membership_id=m.id AND ms.clinic_id=m.clinic_id
    JOIN public.vitalia_specialties s ON s.id=ms.specialty_id AND s.active
    WHERE m.id=$1 AND m.clinic_id=$2 AND b.id=$3 AND s.id=$4 AND m.active`,
    [v.membershipId,source.clinic_id,v.branchId,v.specialtyId]);
   if(target.rows.length!==1)throw new CareInboxError(409,'CARE_CHANGED');
   try{await tx.query('SELECT public.vitalia_lock_care_selection($1,$2,$3)',[v.membershipId,v.specialtyId,v.branchId]);}
   catch(e){if((e as {code?:string})?.code==='P0001')throw new CareInboxError(409,'CARE_CHANGED');throw e;}
   await tx.query("UPDATE public.vitalia_exam_care SET status='referred',updated_by=$2,revision=revision+1 WHERE id=$1",[id,a.id]);
   await tx.query(`INSERT INTO public.vitalia_exam_care(id,document_id,patient_id,clinic_id,branch_id,responsible_membership_id,
    specialty_id,kind,previous_care_id,requested_by,updated_by) VALUES($1,$2,$3,$4,$5,$6,$7,'referral',$8,$9,$9)`,
    [v.requestId,source.document_id,source.patient_id,source.clinic_id,v.branchId,v.membershipId,v.specialtyId,id,a.id]);
   await tx.query(`INSERT INTO public.vitalia_exam_referrals(id,clinic_id,document_id,patient_id,source_care_id,target_care_id,actor_id,reason)
    VALUES($1,$2,$3,$4,$5,$1,$6,$7)`,[v.requestId,source.clinic_id,source.document_id,source.patient_id,id,a.id,v.reason]);
   return {referred:true,targetCareId:v.requestId,replayed:false};
  });}catch(e){
   if(['23505','23503'].includes((e as {code?:string})?.code??''))throw new CareInboxError(409,'CARE_CHANGED');translate(e);
  }
 },
 async review(a:AccountSummary,id:string){professional(a);if(!z.uuid().safeParse(id).success)throw new CareInboxError(404,'CARE_NOT_FOUND');
  try{return await db.transaction(async tx=>{
   const r=await load(tx,a,id),review=await savedReview(tx,id);
   const job=(await tx.query<{id:string;status:string;result:unknown}>(
    'SELECT id,status,result FROM public.vitalia_document_processing WHERE document_id=$1',[r.document_id])).rows[0];
   const value=job?.result==null?null:processingResultSchema.parse(job.result),original=value?.ai?.extraction??null;
   await audit(tx,a,'view_review',id);
   return {processingId:job?.id??null,processingStatus:job?.status??'not_requested',expectedRevision:r.revision,
    originalExtraction:original,sourceText:value?.inputText??null,
    canReview:r.status==='active'&&job?.status==='requires_review'&&original!==null&&!review,
    review:review?reviewSummary(review):null};
  });}catch(e){translate(e);}
 },
 async approve(a:AccountSummary,id:string,input:unknown){professional(a);if(!z.uuid().safeParse(id).success)throw new CareInboxError(404,'CARE_NOT_FOUND');
  const parsed=careReviewInput.safeParse(input);
  if(!parsed.success||Buffer.byteLength(JSON.stringify(parsed.data),'utf8')>24*1024)throw new CareInboxError(400,'INVALID_CARE_REVIEW');
  const v=parsed.data;
  try{return await db.transaction(async tx=>{
   const r=await load(tx,a,id,true),existing=await savedReview(tx,id);
   if(existing){
    if(r.status==='completed'&&r.revision===v.expectedRevision+1&&existing.processing_id===v.processingId&&
      existing.reviewer_id===a.id&&existing.observations===v.observations&&isDeepStrictEqual(existing.reviewed_extraction,v.extraction))return reviewSummary(existing);
    throw new CareInboxError(409,'CARE_CHANGED');
   }
   if(r.status!=='active'||r.revision!==v.expectedRevision)throw new CareInboxError(409,'CARE_CHANGED');
   await tx.query('SELECT public.vitalia_lock_review_processing($1,$2)',[v.processingId,r.document_id]);
   const job=(await tx.query<{id:string;status:string;result:unknown}>(
    'SELECT id,status,result FROM public.vitalia_document_processing WHERE document_id=$1',[r.document_id])).rows[0];
   if(!job||job.id!==v.processingId||job.status!=='requires_review')throw new CareInboxError(409,'CARE_CHANGED');
   const original=processingResultSchema.parse(job.result).ai?.extraction;
   if(!original)throw new CareInboxError(409,'CARE_CHANGED');
   if(!reviewedExtractionValid(v.extraction,original,v.observations))throw new CareInboxError(400,'INVALID_CARE_REVIEW');
   await tx.query(`INSERT INTO public.vitalia_care_reviews(id,care_id,document_id,patient_id,processing_id,reviewer_membership_id,
    reviewer_id,original_extraction,reviewed_extraction,observations,confirmed_original)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9::jsonb,$10,true)`,
    [randomUUID(),id,r.document_id,r.patient_id,job.id,r.responsible_membership_id,a.id,JSON.stringify(original),JSON.stringify(v.extraction),v.observations]);
   await tx.query("UPDATE public.vitalia_exam_care SET status='completed',updated_by=$2,revision=revision+1 WHERE id=$1",[id,a.id]);
   const saved=await savedReview(tx,id);if(!saved)throw new Error('Revisión no disponible.');return reviewSummary(saved);
  });}catch(e){translate(e);}
 },
 async download(a:AccountSummary,id:string){professional(a);if(!z.uuid().safeParse(id).success)throw new CareInboxError(404,'CARE_NOT_FOUND');
  try{
   const before=await db.transaction(tx=>load(tx,a,id));
   if(before.storage_key!==`patients/${before.patient_id}/documents/${before.document_id}`||before.size_bytes<1||before.size_bytes>MAX_FILE_BYTES)throw new Error('Objeto inconsistente.');
   const body=await storage.read(before.storage_key);
   if(body.length!==before.size_bytes)throw new Error('Objeto incompleto.');
   identifyDocument(body,before.content_type,before.original_name);
   return await db.transaction(async tx=>{
    const after=await load(tx,a,id);
    if(['document_id','storage_key','size_bytes','content_type','original_name'].some(k=>after[k as keyof Row]!==before[k as keyof Row]))throw new CareInboxError(409,'CARE_CHANGED');
    await audit(tx,a,'download',id);return {item:summary(after).document,body};
   });
  }catch(e){translate(e);}
 }
};}
export type CareInboxServices=ReturnType<typeof createCareInboxService>;
