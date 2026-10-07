import {z} from 'zod';
import {extractionSchema} from '../ai/contract';
const text=z.string().refine(v=>Buffer.byteLength(v,'utf8')<=12000);
const incident=z.object({code:z.string().min(1).max(100),path:z.string().max(200).optional(),page:z.number().int().min(1).max(10).optional(),message:z.string().max(1000)}).strict();
const incidents=z.array(incident).max(1000);
const reading=z.object({status:z.enum(['text_ready','needs_ocr','rejected']),text:text.nullable(),pageCount:z.number().int().min(1).max(10000).nullable(),incidents}).strict();
const ocr=z.object({status:z.enum(['requires_review','rejected']),source:z.enum(['pdf','png','jpeg']),text:text.nullable(),pages:z.array(z.object({page:z.number().int().min(1).max(3),text,confidence:z.number().finite().min(0).max(100)}).strict()).max(3),incidents,approved:z.literal(false)}).strict();
const ai=z.object({status:z.enum(['requires_review','rejected']),raw:z.string().max(131072),extraction:extractionSchema.nullable(),incidents,approved:z.literal(false),model:z.string().min(1).max(100),promptVersion:z.literal(3),elapsedMs:z.number().int().min(0)}).strict();
export const processingResultSchema=z.object({
 status:z.enum(['requires_review','rejected','service_error']),source:z.enum(['pdf','png','jpeg']),method:z.enum(['direct','ocr']).nullable(),
 reading:reading.nullable(),ocr:ocr.nullable(),inputText:text.nullable(),ai:ai.nullable(),approved:z.literal(false),
 error:z.object({code:z.enum(['reading_unavailable','extraction_unavailable']),message:z.string().max(1000)}).strict().optional(),
}).strict().superRefine((v,ctx)=>{
 if(v.status==='requires_review'&&(!v.ai||v.ai.status!=='requires_review'||!v.ai.extraction||!v.inputText?.trim()))ctx.addIssue({code:'custom',message:'Extracción pendiente de revisión incompleta.'});
 if(v.ai&&v.method==='ocr'&&(v.ocr?.status!=='requires_review'||v.inputText!==v.ocr.text))ctx.addIssue({code:'custom',message:'Texto OCR inconsistente.'});
 if(v.ai&&v.ai.status!==v.status)ctx.addIssue({code:'custom',message:'Estado IA incompatible.'});
 if(v.source!=='pdf'&&(v.reading!==null||v.method!=='ocr'))ctx.addIssue({code:'custom',message:'Lectura incompatible con imagen.'});
 if(v.method==='direct'&&(v.source!=='pdf'||v.reading?.status!=='text_ready'||v.ocr!==null||v.inputText!==v.reading.text))ctx.addIssue({code:'custom',message:'Texto directo inconsistente.'});
 if(v.method==='ocr'&&v.error?.code!=='reading_unavailable'&&(!v.ocr||v.ocr.source!==v.source))ctx.addIssue({code:'custom',message:'OCR inconsistente.'});
 if(v.ai?.status==='rejected'&&v.ai.extraction!==null)ctx.addIssue({code:'custom',message:'Extracción rechazada no debe exponer datos aceptados.'});
 if(v.ai&&(v.ai.status==='requires_review')&&(v.ai.extraction===null))ctx.addIssue({code:'custom',message:'Extracción ausente.'});
 if(v.status==='service_error'&&!v.error)ctx.addIssue({code:'custom',message:'Falta incidencia de servicio.'});
});
export type StoredProcessingResult=z.infer<typeof processingResultSchema>;
