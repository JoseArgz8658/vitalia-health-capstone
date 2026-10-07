import {type Pool} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {DocumentNotFoundError} from '../documents/service';
import {queueDocumentProcessing,findPatientProcessingStatus} from './repository';

export function createProcessingService(db:Pick<Pool,'query'>){
 async function owned(account:AccountSummary,id:string){
  const result=await db.query(`SELECT id FROM public.vitalia_documents
   WHERE id=$1 AND patient_id=$2 AND status='stored'`,[id,account.id]);
  if(!result.rows.length)throw new DocumentNotFoundError();
 }
 async function state(account:AccountSummary,id:string){
  const job=await findPatientProcessingStatus(db,account,id);
  const reviewed=job?.status==='requires_review'?await db.query<{created_at:Date}>(
   'SELECT created_at FROM public.vitalia_professional_reviews WHERE processing_id=$1 AND document_id=$2 AND patient_id=$3',
   [job.id,id,account.id]):null;
  const review=reviewed?.rows[0];
  // Solo estado y tiempos: no exponer extracción, texto, modelo o claves S3.
  return {status:job?.status??'not_requested',approved:false,reviewStatus:review?'approved':'not_reviewed',reviewedAt:review?.created_at??null,
   createdAt:job?.created_at??null,startedAt:job?.started_at??null,finishedAt:job?.finished_at??null};
 }
 return {
  async get(account:AccountSummary,id:string){await owned(account,id);return state(account,id);},
  async request(account:AccountSummary,id:string){
   await owned(account,id);
   const created=await queueDocumentProcessing(db,account,id);
   return {created:created!==null,processing:await state(account,id)};
  },
 };
}
export type ProcessingServices=ReturnType<typeof createProcessingService>;
