import {type Pool} from 'pg';
import {z} from 'zod';
import {type DocumentExtractionResult,createDocumentExtraction} from '../ai/document-extraction';
import {type DocumentStorage} from '../documents/service';
import {identifyDocument,MAX_FILE_BYTES} from '../documents/file-validation';
import {claimDocumentProcessing,completeDocumentProcessing,failDocumentProcessing} from './repository';
type Database=Pick<Pool,'query'>;
export type ProcessingOutcome =
 | {outcome:'not_claimed';processingId:string}
 | {outcome:'requires_review'|'rejected'|'failed';processingId:string;approved:false}
 | {outcome:'processing_error';processingId:string;failureRecorded:boolean};
export function createProcessingWorker(db:Database,storage:Pick<DocumentStorage,'read'>,options:{
 process?:(data:Uint8Array,source:DocumentExtractionResult['source'],model:string)=>Promise<DocumentExtractionResult>;
}={}){
 const process=options.process??((data,source,model)=>createDocumentExtraction({model})(data,source));
 return async function processOne(id:string):Promise<ProcessingOutcome>{
  z.uuid().parse(id);
  const job=await claimDocumentProcessing(db,id);
  if(!job)return {outcome:'not_claimed',processingId:id};
  try{
   if(job.prompt_version!==3)throw new Error('Versión de prompt no compatible.');
   const document=await db.query<{storage_key:string;original_name:string;content_type:string;size_bytes:number;patient_id:string}>(`SELECT storage_key,original_name,content_type,size_bytes,patient_id
    FROM public.vitalia_documents WHERE id=$1 AND status='stored'`,[job.document_id]);
   const row=document.rows[0];if(!row||row.content_type!==job.content_type)throw new Error('Documento no disponible.');
   // Evitar usar una clave ajena aunque los metadatos estén inconsistentes.
   const expectedKey=`patients/${row.patient_id}/documents/${job.document_id}`;
   if(row.storage_key!==expectedKey||row.size_bytes<1||row.size_bytes>MAX_FILE_BYTES)throw new Error('Metadatos inconsistentes.');
   const body=await storage.read(row.storage_key);
   if(body.length!==row.size_bytes||body.length>MAX_FILE_BYTES)throw new Error('Contenido inconsistente.');
   const mime=identifyDocument(body,row.content_type,row.original_name);
   const source=({'application/pdf':'pdf','image/png':'png','image/jpeg':'jpeg'} as const)[mime as 'application/pdf'|'image/png'|'image/jpeg'];
   const result=await process(body,source,job.model);
   if(!await completeDocumentProcessing(db,id,result))throw new Error('No se pudo guardar resultado.');
   return {outcome:result.status==='service_error'?'failed':result.status,processingId:id,approved:false};
  }catch{
   let failureRecorded=false;
   try{failureRecorded=await failDocumentProcessing(db,id,'processing_failed');}catch{/* El comando informará que el estado no se pudo confirmar. */}
   return {outcome:'processing_error',processingId:id,failureRecorded};
  }
 };
}
