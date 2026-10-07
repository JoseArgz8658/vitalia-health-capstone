import {randomUUID} from 'node:crypto';
import {type Pool} from 'pg';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {processingResultSchema,type StoredProcessingResult} from './result';
type Database=Pick<Pool,'query'>;
export type ProcessingStatus='queued'|'processing'|'requires_review'|'rejected'|'failed';
const identifier=z.uuid();
const modelSchema=z.string().min(1).max(100).regex(/^[a-zA-Z0-9_.:-]+$/).refine(v=>!v.toLowerCase().includes('cloud'));
function patient(account:AccountSummary){if(account.role!=='paciente')throw new Error('Identidad de paciente requerida.');identifier.parse(account.id);}
// Identidad ya autenticada. Nunca aceptar account desde un cuerpo HTTP.
export async function queueDocumentProcessing(db:Database,account:AccountSummary,documentId:string,model='qwen3:4b-instruct'){
 patient(account);identifier.parse(documentId);modelSchema.parse(model);
 const id=randomUUID();
 const result=await db.query<{id:string}>(`INSERT INTO public.vitalia_document_processing(id,document_id,model,prompt_version)
 SELECT $1,d.id,$4,3 FROM public.vitalia_documents d
 WHERE d.id=$2 AND d.patient_id=$3 AND d.status='stored'
 ON CONFLICT(document_id) DO NOTHING RETURNING id`,[id,documentId,account.id,model]);
 return result.rows[0]?.id??null;
}
// Uso interno del futuro procesador; no es una ruta pública ni concede permisos clínicos.
export async function claimDocumentProcessing(db:Database,id:string){
 identifier.parse(id);
 const result=await db.query<{id:string;document_id:string;model:string;prompt_version:number;content_type:string}>(`UPDATE public.vitalia_document_processing p
 SET status='processing',started_at=CURRENT_TIMESTAMP FROM public.vitalia_documents d
 WHERE p.id=$1 AND p.status='queued' AND d.id=p.document_id AND d.status='stored'
 RETURNING p.id,p.document_id,p.model,p.prompt_version,d.content_type`,[id]);
 return result.rows[0]??null;
}
export async function completeDocumentProcessing(db:Database,id:string,input:unknown):Promise<boolean>{
 identifier.parse(id);const value=processingResultSchema.parse(input);
 const json=JSON.stringify(value);if(Buffer.byteLength(json,'utf8')>1024*1024)throw new Error('Resultado demasiado grande.');
 const status=value.status==='service_error'?'failed':value.status;
 const mime={pdf:'application/pdf',png:'image/png',jpeg:'image/jpeg'}[value.source];
 const result=await db.query(`UPDATE public.vitalia_document_processing p SET status=$2,result=$3::jsonb,finished_at=CURRENT_TIMESTAMP
 FROM public.vitalia_documents d WHERE p.id=$1 AND p.status='processing' AND d.id=p.document_id AND d.content_type=$4
 AND ($5::text IS NULL OR (p.model=$5 AND p.prompt_version=$6)) RETURNING p.id`,
 [id,status,json,mime,value.ai?.model??null,value.ai?.promptVersion??null]);
 return result.rows.length===1;
}
export async function failDocumentProcessing(db:Database,id:string,code:'processing_interrupted'|'processing_failed'):Promise<boolean>{
 identifier.parse(id);z.enum(['processing_interrupted','processing_failed']).parse(code);
 const result=await db.query(`UPDATE public.vitalia_document_processing SET status='failed',failure_code=$2,finished_at=CURRENT_TIMESTAMP
 WHERE id=$1 AND status='processing' RETURNING id`,[id,code]);return result.rows.length===1;
}
// Estado visible al paciente, sin texto ni resultados aún no revisados.
export async function findPatientProcessingStatus(db:Database,account:AccountSummary,documentId:string){
 patient(account);identifier.parse(documentId);
 const result=await db.query<{id:string;status:ProcessingStatus;created_at:Date;started_at:Date|null;finished_at:Date|null}>(`SELECT p.id,p.status,p.created_at,p.started_at,p.finished_at
 FROM public.vitalia_document_processing p JOIN public.vitalia_documents d ON d.id=p.document_id
 WHERE d.id=$1 AND d.patient_id=$2 AND d.status='stored'`,[documentId,account.id]);
 return result.rows[0]??null;
}
// Lectura técnica interna. No usar como consulta de pacientes o profesionales.
export async function findProcessingForWorker(db:Database,id:string){
 identifier.parse(id);
 const result=await db.query<{id:string;document_id:string;status:ProcessingStatus;model:string;prompt_version:number;result:StoredProcessingResult|null;failure_code:string|null}>(
 `SELECT id,document_id,status,model,prompt_version,result,failure_code FROM public.vitalia_document_processing WHERE id=$1`,[id]);
 return result.rows[0]??null;
}
