import {readPdfText,type PdfReadResult} from '../pdf/reader';
import {readOcr} from '../ocr/reader';
import {type OcrResult} from '../ocr/contract';
import {createLocalExtractor,type LocalExtractionResult} from './local-extractor';
export type DocumentExtractionResult = {
 status:'requires_review'|'rejected'|'service_error';
 source:'pdf'|'png'|'jpeg'; method:'direct'|'ocr'|null;
 reading:PdfReadResult|null; ocr:OcrResult|null;
 inputText:string|null; ai:LocalExtractionResult|null; approved:false;
 error?:{code:'reading_unavailable'|'extraction_unavailable';message:string};
};
export function createDocumentExtraction(options:{
 model?:string; read?:typeof readPdfText; ocr?:typeof readOcr;
 extract?:(text:string)=>Promise<LocalExtractionResult>;
}={}){
 const read=options.read??readPdfText;
 const ocr=options.ocr??readOcr;
 const extract=options.extract??createLocalExtractor({model:options.model});
 return async function processDocument(data:Uint8Array,source:DocumentExtractionResult['source']):Promise<DocumentExtractionResult>{
  if(!['pdf','png','jpeg'].includes(source))throw new Error('Formato de documento no admitido.');
  const result:DocumentExtractionResult={status:'rejected',source,method:null,reading:null,ocr:null,inputText:null,ai:null,approved:false};
  try{
   if(source==='pdf'){
    result.reading=await read(data);
    if(result.reading.status==='rejected')return result;
    if(result.reading.status==='text_ready'){
     result.method='direct';result.inputText=result.reading.text;
    }
   }
   if(source!=='pdf'||result.reading?.status==='needs_ocr'){
    result.method='ocr';result.ocr=await ocr(data,source);
    if(result.ocr.status==='rejected')return result;
    result.inputText=result.ocr.text;
   }
  }catch{
   return {...result,status:'service_error',error:{code:'reading_unavailable',message:'No se pudo completar la lectura del documento.'}};
  }
  // Revalidar el límite común: nunca truncar ni enviar un texto vacío al modelo.
  if(!result.inputText?.trim()||Buffer.byteLength(result.inputText,'utf8')>12000)return result;
  try{
   result.ai=await extract(result.inputText);
   result.status=result.ai.status;
   return result;
  }catch{
   return {...result,status:'service_error',error:{code:'extraction_unavailable',message:'No se pudo completar la extracción con Ollama local.'}};
  }
 };
}
