import {type Pool} from 'pg';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {queueDocumentProcessing,findPatientProcessingStatus,findProcessingForWorker} from './repository';
type Database=Pick<Pool,'query'>;
export function parseManualArguments(args:string[]){
 if((args.length!==2&&args.length!==3)||args[0]!=='--document'||(args.length===3&&args[2]!=='--apply'))throw new Error('Uso: --document UUID [--apply]');
 return {documentId:z.uuid().parse(args[1]),apply:args.length===3};
}
// Operador local con acceso a DB; no sustituye autenticación o permisos de un endpoint.
export async function inspectManualDocument(db:Database,documentId:string){
 z.uuid().parse(documentId);
 const result=await db.query<{id:string;patient_id:string;content_type:string;size_bytes:number;created_at:Date}>(`SELECT d.id,d.patient_id,d.content_type,d.size_bytes,a.created_at
 FROM public.vitalia_documents d JOIN public.vitalia_accounts a ON a.id=d.patient_id
 WHERE d.id=$1 AND d.status='stored' AND a.role_code='paciente'`,[documentId]);
 const row=result.rows[0];if(!row)return null;
 const account:AccountSummary={id:row.patient_id,email:'',role:'paciente',createdAt:row.created_at};
 const existing=await findPatientProcessingStatus(db,account,documentId);
 const job=existing?await findProcessingForWorker(db,existing.id):null;
 return {documentId,contentType:row.content_type,sizeBytes:row.size_bytes,existing,account,model:job?.model??'qwen3:4b-instruct',promptVersion:job?.prompt_version??3};
}
export async function reserveManualProcessing(db:Database,inspection:NonNullable<Awaited<ReturnType<typeof inspectManualDocument>>>){
 const id=await queueDocumentProcessing(db,inspection.account,inspection.documentId);
 if(id)return id;
 const existing=await findPatientProcessingStatus(db,inspection.account,inspection.documentId);
 return existing?.status==='queued'?existing.id:null;
}
