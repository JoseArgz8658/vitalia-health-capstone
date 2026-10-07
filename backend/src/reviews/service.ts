import {randomUUID} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {z} from 'zod';
import {type Pool} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {extractionSchema,isCalendarDate} from '../ai/contract';
import {processingResultSchema} from '../processing/result';

type Database=Pick<Pool,'query'>;
export class ReviewForbiddenError extends Error {}
export class ReviewNotFoundError extends Error {}
export class ReviewInputError extends Error {}
export class ReviewConflictError extends Error {}
const inputSchema=z.object({processingId:z.uuid(),extraction:extractionSchema,
 observations:z.string().trim().max(2000),confirmedOriginal:z.literal(true)}).strict();
interface ReviewRow {id:string;processing_id:string;reviewer_id:string;reviewer_email:string;original_extraction:unknown;reviewed_extraction:unknown;observations:string;created_at:Date}
function summary(row:ReviewRow){return {id:row.id,processingId:row.processing_id,reviewerId:row.reviewer_id,
 reviewerEmail:row.reviewer_email,extraction:extractionSchema.parse(row.reviewed_extraction),
 observations:row.observations,reviewedAt:row.created_at,approved:true};}
function identity(account:AccountSummary,patientId:string,documentId:string){
 if(account.role!=='profesional')throw new ReviewForbiddenError();
 if(!z.uuid().safeParse(patientId).success||!z.uuid().safeParse(documentId).success)throw new ReviewNotFoundError();
}
async function assigned(tx:Database,account:AccountSummary,patientId:string,documentId:string){
 const result=await tx.query<{id:string}>(`SELECT x.id FROM public.vitalia_patient_assignments x
 JOIN public.vitalia_accounts p ON p.id=x.patient_id AND p.role_code='paciente'
 JOIN public.vitalia_accounts r ON r.id=x.professional_id AND r.role_code='profesional'
 JOIN public.vitalia_documents d ON d.patient_id=x.patient_id AND d.id=$3 AND d.status='stored'
 WHERE x.professional_id=$1 AND x.patient_id=$2 AND x.active=true FOR SHARE OF x,p,r,d`,[account.id,patientId,documentId]);
 if(result.rows.length!==1)throw new ReviewNotFoundError();return result.rows[0].id;
}
async function findReview(tx:Database,documentId:string){
 const result=await tx.query<ReviewRow>(`SELECT v.id,v.processing_id,v.reviewer_id,a.email AS reviewer_email,
 v.original_extraction,v.reviewed_extraction,v.observations,v.created_at
 FROM public.vitalia_professional_reviews v JOIN public.vitalia_accounts a ON a.id=v.reviewer_id
 WHERE v.document_id=$1`,[documentId]);
 return result.rows[0]??null;
}
export function createReviewService(db:DocumentDatabase){
 return {
  async getPatient(account:AccountSummary,documentId:string){
   if(account.role!=='paciente')throw new ReviewForbiddenError();
   if(!z.uuid().safeParse(documentId).success)throw new ReviewNotFoundError();
   return db.transaction(async tx=>{
    const owned=await tx.query<{id:string}>(`SELECT id FROM public.vitalia_documents
     WHERE id=$1 AND patient_id=$2 AND status='stored' FOR SHARE`,[documentId,account.id]);
    if(owned.rows.length!==1)throw new ReviewNotFoundError();
    const found=await tx.query<ReviewRow>(`SELECT v.id,v.processing_id,v.reviewed_extraction,v.observations,v.created_at
     FROM public.vitalia_professional_reviews v
     WHERE v.document_id=$1 AND v.patient_id=$2 AND v.approved=true`,[documentId,account.id]);
    const row=found.rows[0];
    return {review:row?{extraction:extractionSchema.parse(row.reviewed_extraction),
     observations:row.observations,reviewedAt:row.created_at,approved:true}:null};
   });
  },
  async get(account:AccountSummary,patientId:string,documentId:string){
   identity(account,patientId,documentId);
   return db.transaction(async tx=>{
    const assignmentId=await assigned(tx,account,patientId,documentId);
    const found=await tx.query<{id:string;status:string;result:unknown}>(`SELECT id,status,result FROM public.vitalia_document_processing WHERE document_id=$1`,[documentId]);
    const job=found.rows[0];const value=job?.status==='requires_review'?processingResultSchema.parse(job.result):null;
    const review=await findReview(tx,documentId);
    await tx.query(`INSERT INTO public.vitalia_professional_access_audit
     (id,professional_id,patient_id,assignment_id,action,document_id,processing_id) VALUES ($1,$2,$3,$4,'view_extraction',$5,$6)`,
     [randomUUID(),account.id,patientId,assignmentId,documentId,job?.id??null]);
    return {processingId:job?.id??null,originalExtraction:value?.ai?.extraction??null,
     canReview:!!value?.ai?.extraction&&!review,review:review?summary(review):null};
   });
  },
  async approve(account:AccountSummary,patientId:string,documentId:string,input:unknown){
   identity(account,patientId,documentId);const parsed=inputSchema.safeParse(input);
   if(!parsed.success)throw new ReviewInputError();
   const reviewed=parsed.data.extraction;
   if(!reviewed.resultados.length||(reviewed.fecha!==null&&!isCalendarDate(reviewed.fecha))||Buffer.byteLength(JSON.stringify(parsed.data),'utf8')>24*1024)throw new ReviewInputError();
   return db.transaction(async tx=>{
    const assignmentId=await assigned(tx,account,patientId,documentId);
    const found=await tx.query<{id:string;status:string;result:unknown}>(`SELECT id,status,result FROM public.vitalia_document_processing WHERE document_id=$1 FOR UPDATE`,[documentId]);
    const job=found.rows[0];if(!job||job.id!==parsed.data.processingId||job.status!=='requires_review')throw new ReviewConflictError();
    if(await findReview(tx,documentId))throw new ReviewConflictError();
    const value=processingResultSchema.parse(job.result);const original=value.ai?.extraction;
    if(!original)throw new ReviewConflictError();
    const missing=reviewed.examen===null||reviewed.fecha===null||reviewed.resultados.some(row=>Object.values(row).some(field=>field===null));
    if((missing||!isDeepStrictEqual(original,reviewed))&&!parsed.data.observations)throw new ReviewInputError();
    await tx.query(`INSERT INTO public.vitalia_professional_reviews
     (id,processing_id,document_id,patient_id,assignment_id,reviewer_id,original_extraction,reviewed_extraction,observations,confirmed_original)
     VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,$9,true)`,
     [randomUUID(),job.id,documentId,patientId,assignmentId,account.id,JSON.stringify(original),JSON.stringify(reviewed),parsed.data.observations]);
    const saved=await findReview(tx,documentId);if(!saved)throw new Error('Revisión no guardada.');
    return summary(saved);
   });
  },
 };
}
export type ReviewServices=ReturnType<typeof createReviewService>;
