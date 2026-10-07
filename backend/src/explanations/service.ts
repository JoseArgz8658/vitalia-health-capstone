import {randomUUID} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {z} from 'zod';
import {type Pool} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {extractionSchema,type Extraction} from '../ai/contract';
import {renderExplanation,type Explanation} from './catalog';
import {type ExplanationGenerator} from './local-generator';
export class ExplanationForbiddenError extends Error {}
export class ExplanationNotFoundError extends Error {}
export class ExplanationPendingReviewError extends Error {}
export class ExplanationBusyError extends Error {}
export class ExplanationInputError extends Error {}
export class ExplanationUnavailableError extends Error {}
type DB=Pick<Pool,'query'>;
interface ApprovedReview{id:string;reviewed_extraction:Extraction}
interface Stored{id:string;review_id:string;status:'generating'|'ready'|'failed';result:Explanation|null;review_snapshot:Extraction;finished_at:Date|null;model:string;prompt_version:number;catalog_version:number}
function identity(account:AccountSummary,documentId:string){
 if(account.role!=='paciente')throw new ExplanationForbiddenError();
 if(!z.uuid().safeParse(documentId).success)throw new ExplanationNotFoundError();
}
async function owned(tx:DB,account:AccountSummary,documentId:string){
 const doc=await tx.query(`SELECT id FROM public.vitalia_documents WHERE id=$1 AND patient_id=$2 AND status='stored' FOR SHARE`,[documentId,account.id]);
 if(doc.rows.length!==1)throw new ExplanationNotFoundError();
 const found=await tx.query<ApprovedReview>(`SELECT id,reviewed_extraction FROM public.vitalia_professional_reviews
  WHERE document_id=$1 AND patient_id=$2 AND approved=true`,[documentId,account.id]);
 const row=found.rows[0];return row?{id:row.id,reviewed_extraction:extractionSchema.parse(row.reviewed_extraction)}:null;
}
async function audit(tx:DB,account:AccountSummary,doc:string,review:string|null,action:string){
 await tx.query(`INSERT INTO public.vitalia_explanation_audit (id,patient_id,document_id,review_id,action) VALUES ($1,$2,$3,$4,$5)`,[randomUUID(),account.id,doc,review,action]);
}
async function find(tx:DB,account:AccountSummary,documentId:string,reviewId:string){
 const result=await tx.query<Stored>(`SELECT id,review_id,status,result,review_snapshot,finished_at,model,prompt_version,catalog_version
  FROM public.vitalia_exam_explanations WHERE review_id=$1 AND document_id=$2 AND patient_id=$3`,[reviewId,documentId,account.id]);
 return result.rows[0]??null;
}
function publicState(row:Stored|null,review:ApprovedReview|null){
 let explanation:Explanation|null=null;
 if(row?.status==='ready'){
  if(!isDeepStrictEqual(row.review_snapshot,review?.reviewed_extraction)||row.catalog_version!==1||!row.result)throw new ExplanationUnavailableError();
  const checked=renderExplanation(row.review_snapshot,{items:row.result.items.map(item=>({index:item.index,concept:item.concept}))});
  if(!isDeepStrictEqual(checked,row.result))throw new ExplanationUnavailableError();explanation=checked;
 }
 return {status:review?row?.status??'not_requested':'not_available',reviewId:review?.id??null,
  explanation,approved:false,generatedAt:row?.status==='ready'?row.finished_at:null};
}
export function createExplanationService(db:DocumentDatabase,generate:ExplanationGenerator){
 let busy=false;
 return {
  async get(account:AccountSummary,documentId:string){
   identity(account,documentId);return db.transaction(async tx=>{
    const review=await owned(tx,account,documentId);
    const row=review?await find(tx,account,documentId,review.id):null;
    const state=publicState(row,review);await audit(tx,account,documentId,review?.id??null,'view');return state;
   });
  },
  async request(account:AccountSummary,documentId:string){
   identity(account,documentId);
   const preview=await db.transaction(async tx=>{
    const review=await owned(tx,account,documentId);if(!review)throw new ExplanationPendingReviewError();
    const row=await find(tx,account,documentId,review.id);return {review,row};
   });
   if(preview.row?.status==='ready')return publicState(preview.row,preview.review);
   if(busy)throw new ExplanationBusyError();
   if(preview.review.reviewed_extraction.resultados.length<1||preview.review.reviewed_extraction.resultados.length>20||
    Buffer.byteLength(JSON.stringify(preview.review.reviewed_extraction.resultados.map((row,index)=>({index,name:row.nombre}))))>12000)throw new ExplanationInputError();
   busy=true;const attempt=randomUUID();let reserved:Stored|null=null;
   try{
    const claim=await db.transaction(async tx=>{
     const review=await owned(tx,account,documentId);
     if(!review||review.id!==preview.review.id)throw new ExplanationPendingReviewError();
     const result=await tx.query<Stored>(`INSERT INTO public.vitalia_exam_explanations
      (id,review_id,document_id,patient_id,review_snapshot,status,attempt_id)
      VALUES ($1,$2,$3,$4,$5::jsonb,'generating',$6)
      ON CONFLICT (review_id) DO UPDATE SET status='generating',attempt_id=EXCLUDED.attempt_id,
       started_at=CURRENT_TIMESTAMP,finished_at=NULL,result=NULL,model=NULL,prompt_version=NULL,catalog_version=NULL,elapsed_ms=NULL
      WHERE vitalia_exam_explanations.document_id=EXCLUDED.document_id AND vitalia_exam_explanations.patient_id=EXCLUDED.patient_id
       AND ((vitalia_exam_explanations.status='failed' AND vitalia_exam_explanations.finished_at<CURRENT_TIMESTAMP-INTERVAL '30 seconds')
        OR (vitalia_exam_explanations.status='generating' AND vitalia_exam_explanations.started_at<CURRENT_TIMESTAMP-INTERVAL '3 minutes'))
      RETURNING id,review_id,status,result,review_snapshot,finished_at,model,prompt_version,catalog_version`,
      [randomUUID(),review.id,documentId,account.id,JSON.stringify(review.reviewed_extraction),attempt]);
     const row=result.rows[0]??null;
     if(row)await audit(tx,account,documentId,review.id,'request');
     return {row,review};
    });
    reserved=claim.row;
    if(!reserved)return db.transaction(async tx=>{
     const review=await owned(tx,account,documentId);if(!review)throw new ExplanationPendingReviewError();
     return publicState(await find(tx,account,documentId,review.id),review);
    });
    const generated=await generate(claim.review.reviewed_extraction);
    // No se publica texto libre del modelo ni datos numéricos escritos por él.
    const checked=renderExplanation(claim.review.reviewed_extraction,{items:generated.explanation.items.map(item=>({index:item.index,concept:item.concept}))});
    if(!isDeepStrictEqual(checked,generated.explanation)||generated.promptVersion!==1||generated.catalogVersion!==1)throw new ExplanationUnavailableError();
    return await db.transaction(async tx=>{
     const review=await owned(tx,account,documentId);if(!review||review.id!==claim.review.id)throw new ExplanationNotFoundError();
     const updated=await tx.query(`UPDATE public.vitalia_exam_explanations SET status='ready',result=$1::jsonb,
      model=$2,prompt_version=$3,catalog_version=$4,elapsed_ms=$5,finished_at=CURRENT_TIMESTAMP
      WHERE id=$6 AND attempt_id=$7 AND patient_id=$8 AND status='generating' RETURNING id`,
      [JSON.stringify(checked),generated.model,generated.promptVersion,generated.catalogVersion,generated.elapsedMs,reserved!.id,attempt,account.id]);
     if(updated.rows.length!==1)throw new ExplanationBusyError();
     await audit(tx,account,documentId,review.id,'ready');return publicState(await find(tx,account,documentId,review.id),review);
    });
   }catch(error){
    if(reserved)await db.transaction(async tx=>{
     const failed=await tx.query(`UPDATE public.vitalia_exam_explanations SET status='failed',result=NULL,finished_at=CURRENT_TIMESTAMP
      WHERE id=$1 AND attempt_id=$2 AND patient_id=$3 AND status='generating' RETURNING id`,[reserved!.id,attempt,account.id]);
     if(failed.rows.length)await audit(tx,account,documentId,preview.review.id,'failed');
    });
    if(error instanceof ExplanationNotFoundError||error instanceof ExplanationPendingReviewError||error instanceof ExplanationBusyError)throw error;
    throw new ExplanationUnavailableError();
   }finally{busy=false;}
  },
 };
}
export type ExplanationServices=ReturnType<typeof createExplanationService>;
