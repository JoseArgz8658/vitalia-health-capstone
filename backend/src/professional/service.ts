import {randomUUID} from 'node:crypto';
import {type Pool} from 'pg';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase,type DocumentStorage} from '../documents/service';
import {identifyDocument,MAX_FILE_BYTES} from '../documents/file-validation';
import {processingResultSchema} from '../processing/result';

type Database=Pick<Pool,'query'>;
export class ProfessionalForbiddenError extends Error {}
export class ProfessionalNotFoundError extends Error {}
export class ProfessionalInputError extends Error {}
interface DocumentRow {id:string;exam_name:string;exam_type:string;exam_date:string;original_name:string;content_type:string;size_bytes:number;created_at:Date;storage_key:string}
const columns='id,exam_name,exam_type,exam_date::text,original_name,content_type,size_bytes,created_at,storage_key';
function summary(row:DocumentRow){return {id:row.id,examName:row.exam_name,examType:row.exam_type,examDate:row.exam_date,
 originalName:row.original_name,contentType:row.content_type,sizeBytes:row.size_bytes,createdAt:row.created_at};}
function identity(account:AccountSummary,patientId:string,documentId?:string){
 if(account.role!=='profesional')throw new ProfessionalForbiddenError();
 if(!z.uuid().safeParse(patientId).success||(documentId!==undefined&&!z.uuid().safeParse(documentId).success))throw new ProfessionalNotFoundError();
}
async function assigned(tx:Database,account:AccountSummary,patientId:string){
 const result=await tx.query<{id:string}>(`SELECT x.id FROM public.vitalia_patient_assignments x
 JOIN public.vitalia_accounts p ON p.id=x.patient_id AND p.role_code='paciente'
 JOIN public.vitalia_accounts r ON r.id=x.professional_id AND r.role_code='profesional'
 WHERE x.professional_id=$1 AND x.patient_id=$2 AND x.active=true FOR SHARE OF x,p,r`,[account.id,patientId]);
 if(result.rows.length!==1)throw new ProfessionalNotFoundError();
 return result.rows[0].id;
}
async function document(tx:Database,patientId:string,id:string){
 const result=await tx.query<DocumentRow>(`SELECT ${columns} FROM public.vitalia_documents
 WHERE id=$1 AND patient_id=$2 AND status='stored'`,[id,patientId]);
 if(result.rows.length!==1)throw new ProfessionalNotFoundError();return result.rows[0];
}
async function audit(tx:Database,account:AccountSummary,patientId:string,assignmentId:string,
 action:'list'|'view_extraction'|'download',documentId:string|null=null,processingId:string|null=null){
 await tx.query(`INSERT INTO public.vitalia_professional_access_audit
 (id,professional_id,patient_id,assignment_id,action,document_id,processing_id) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
 [randomUUID(),account.id,patientId,assignmentId,action,documentId,processingId]);
}
export function createProfessionalService(db:DocumentDatabase,storage:Pick<DocumentStorage,'read'>){
 return {
  async list(account:AccountSummary,patientId:string,limit=20,offset=0){
   identity(account,patientId);
   if(!z.number().int().min(1).max(20).safeParse(limit).success||!z.number().int().min(0).max(10000).safeParse(offset).success)throw new ProfessionalInputError();
   return db.transaction(async tx=>{
    const assignmentId=await assigned(tx,account,patientId);
    const result=await tx.query<DocumentRow>(`SELECT ${columns} FROM public.vitalia_documents
     WHERE patient_id=$1 AND status='stored' ORDER BY exam_date DESC,created_at DESC,id DESC LIMIT $2 OFFSET $3`,[patientId,limit,offset]);
    await audit(tx,account,patientId,assignmentId,'list');return result.rows.map(summary);
   });
  },
  async extraction(account:AccountSummary,patientId:string,documentId:string){
   identity(account,patientId,documentId);
   return db.transaction(async tx=>{
    const assignmentId=await assigned(tx,account,patientId);const item=await document(tx,patientId,documentId);
    const found=await tx.query<{id:string;status:string;result:unknown;failure_code:string|null}>(`SELECT id,status,result,failure_code FROM public.vitalia_document_processing WHERE document_id=$1`,[documentId]);
    const job=found.rows[0];const value=job?.result==null?null:processingResultSchema.parse(job.result);
    const processing={status:job?.status??'not_requested',approved:false,
     method:value?.method??null,sourceText:value?.inputText??null,extraction:value?.ai?.extraction??null,
     incidents:{reading:[...(value?.reading?.incidents??[]),...(value?.error?[value.error]:[]),...(job?.failure_code?[{code:'processing_failed',message:'El procesamiento falló antes de guardar la extracción.'}]:[])],ocr:value?.ocr?.incidents??[],ai:value?.ai?.incidents??[]},
     model:value?.ai?.model??null,promptVersion:value?.ai?.promptVersion??null};
    await audit(tx,account,patientId,assignmentId,'view_extraction',documentId,job?.id??null);
    return {document:summary(item),processing};
   });
  },
  async download(account:AccountSummary,patientId:string,documentId:string){
   identity(account,patientId,documentId);
   const item=await db.transaction(async tx=>{await assigned(tx,account,patientId);return document(tx,patientId,documentId);});
   if(item.storage_key!==`patients/${patientId}/documents/${documentId}`||item.size_bytes<1||item.size_bytes>MAX_FILE_BYTES)throw new Error('Objeto inconsistente.');
   const body=await storage.read(item.storage_key);
   if(body.length!==item.size_bytes||body.length>MAX_FILE_BYTES)throw new Error('Tamaño inconsistente.');
   identifyDocument(body,item.content_type,item.original_name);
   // No mantener una transacción durante S3. Revalidar la asignación antes de entregar.
   return db.transaction(async tx=>{
    const assignmentId=await assigned(tx,account,patientId);const current=await document(tx,patientId,documentId);
    if(current.storage_key!==item.storage_key||current.size_bytes!==item.size_bytes||current.content_type!==item.content_type||current.original_name!==item.original_name)throw new Error('Documento cambió.');
    await audit(tx,account,patientId,assignmentId,'download',documentId);return {item:summary(current),body};
   });
  },
 };
}
export type ProfessionalServices=ReturnType<typeof createProfessionalService>;
