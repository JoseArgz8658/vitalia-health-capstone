import {createWorker} from 'tesseract.js';
import {PDFParse} from 'pdf-parse';
import {OCR_LIMITS,summarizeOcr,type OcrResult,type OcrPage} from './contract';
// El paquete de idioma se instala con npm ci; no se obtiene desde una URL.
const language: {langPath:string;gzip:boolean}=require('@tesseract.js-data/spa');
async function run(data:Uint8Array,source:OcrResult['source']):Promise<OcrResult>{
 const reject=(code:string,message:string):OcrResult=>({status:'rejected',source,text:null,pages:[],incidents:[{code,message}],approved:false});
 let parser:PDFParse|undefined;
 let worker:Awaited<ReturnType<typeof createWorker>>|undefined;
 try{
  let count=1;
  if(source==='pdf'){
   parser=new PDFParse({data:new Uint8Array(data),stopAtErrors:true,isEvalSupported:false});
   const info=await parser.getInfo({parsePageInfo:true});count=info.total;
   if(count<1||count>OCR_LIMITS.pages)return reject('page_limit','OCR admite entre una y tres páginas.');
   for(const page of info.pages){
    const scale=1600/page.width;
    if(!Number.isFinite(scale)||scale<=0||Math.ceil(page.width*scale)*Math.ceil(page.height*scale)>OCR_LIMITS.pixels)return reject('image_limit','Resolución de página excesiva o inválida.');
   }
  }
  worker=await createWorker('spa',1,{langPath:language.langPath,gzip:language.gzip,cacheMethod:'none',errorHandler:()=>undefined});
  const pages:OcrPage[]=[];
  for(let page=1;page<=count;page++){
   let image:Uint8Array=data;
   if(parser){
    const screenshot=await parser.getScreenshot({partial:[page],desiredWidth:1600,imageBuffer:true,imageDataUrl:false});
    const shot=screenshot.pages[0];
    if(!shot||shot.width*shot.height>OCR_LIMITS.pixels)return reject('image_limit','No se pudo renderizar la página dentro del límite.');
    image=shot.data;
   }
   const result=await worker.recognize(Buffer.from(image));
   pages.push({page,text:result.data.text.trim(),confidence:result.data.confidence});
   if(Buffer.byteLength(pages.map(p=>p.text).join('\n\n'),'utf8')>OCR_LIMITS.textBytes)return reject('text_limit','Texto mayor de 12000 bytes; no se entrega truncado.');
  }
  return summarizeOcr(source,pages);
 }catch(error){
  return reject(error instanceof Error&&error.name==='PasswordException'?'password_required':'ocr_error','No se pudo reconocer el documento; comprobar original y formato.');
 }finally{
  if(worker)await worker.terminate().catch(()=>undefined);
  if(parser)await parser.destroy().catch(()=>undefined);
 }
}
process.once('message',async(message:{data:Uint8Array;source:OcrResult['source']})=>{
 const result=await run(message.data,message.source);
 process.send?.(result,(error:Error|null)=>{if(process.connected)process.disconnect();if(error)process.exitCode=1;});
});
