import {type PoolClient} from 'pg';
import {type ProcessingOutcome} from './worker';
type Database=Pick<PoolClient,'query'>;
export class UnconfirmedProcessingError extends Error {}
export const PROCESSOR_LOCK='vitalia-document-processor';
export async function acquireProcessorLock(db:Database){
 const result=await db.query<{locked:boolean}>('SELECT pg_try_advisory_lock(hashtext($1)) AS locked',[PROCESSOR_LOCK]);
 return result.rows[0]?.locked===true;
}
export async function releaseProcessorLock(db:Database){await db.query('SELECT pg_advisory_unlock(hashtext($1))',[PROCESSOR_LOCK]);}
// Solo ejecutar con el bloqueo exclusivo adquirido; los comandos manuales usan el mismo bloqueo.
export async function recoverInterruptedProcessing(db:Database){
 const result=await db.query(`UPDATE public.vitalia_document_processing SET status='failed',failure_code='processing_interrupted',finished_at=CURRENT_TIMESTAMP
 WHERE status='processing' RETURNING id`);return result.rows.length;
}
export function createQueueProcessor(db:Database,processOne:(id:string)=>Promise<ProcessingOutcome>,availableModels:()=>Promise<string[]>){
 return async()=>{
  const models=await availableModels();
  if(!models.length)return {state:'model_unavailable' as const};
  const pending=await db.query<{id:string}>(`SELECT p.id FROM public.vitalia_document_processing p
 JOIN public.vitalia_documents d ON d.id=p.document_id
 WHERE p.status='queued' AND p.prompt_version=3 AND p.model=ANY($1::text[]) AND d.status='stored'
 ORDER BY p.created_at,p.id LIMIT 1`,[models]);
  if(!pending.rows[0])return {state:'idle' as const};
  const result=await processOne(pending.rows[0].id);
  if(result.outcome==='processing_error'&&!result.failureRecorded)throw new UnconfirmedProcessingError('Estado de procesamiento no confirmado.');
  return {state:'processed' as const,result};
 };
}
