import {fork} from 'node:child_process';
import {join} from 'node:path';
import {imageDimensions,OCR_LIMITS,type OcrResult} from './contract';
export async function readOcr(input:Uint8Array,source:OcrResult['source']):Promise<OcrResult>{
 const reject=(code:string,message:string):OcrResult=>({status:'rejected',source,text:null,pages:[],incidents:[{code,message}],approved:false});
 if(!['png','jpeg','pdf'].includes(source))throw new Error('Formato OCR no admitido.');
 if(!(input instanceof Uint8Array)||!input.length||input.byteLength>OCR_LIMITS.bytes)return reject('invalid_size','Documento vacío o mayor de 10 MiB.');
 const b=Buffer.from(input);
 if(source==='pdf'){
  if(b.subarray(0,5).toString('ascii')!=='%PDF-')return reject('invalid_signature','Firma PDF incorrecta.');
 }else{
  const isPng=b.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
  const isJpeg=b[0]===255&&b[1]===216;
  if((source==='png'&&!isPng)||(source==='jpeg'&&!isJpeg))return reject('invalid_signature','Firma de imagen incorrecta.');
  const dims=imageDimensions(input);
  if(!dims||dims.width<1||dims.height<1||dims.width*dims.height>OCR_LIMITS.pixels)return reject('image_limit','Imagen inválida o mayor de cuatro millones de píxeles.');
 }
 return new Promise(resolve=>{
  const child=fork(join(__dirname,'reader-process.js'),[],{serialization:'advanced',stdio:['ignore','ignore','ignore','ipc'],execArgv:['--max-old-space-size=256']});
  let settled=false,result:OcrResult|null=null;
  const finish=(value:OcrResult)=>{if(settled)return;settled=true;clearTimeout(timer);resolve(value);};
  const timer=setTimeout(()=>{child.kill();finish(reject('ocr_timeout','OCR excedió 60 segundos.'));},OCR_LIMITS.timeoutMs);
  child.once('message',(message:OcrResult)=>{result=message;});
  child.once('error',()=>{child.kill();finish(reject('ocr_error','No se pudo iniciar el OCR.'));});
  child.once('close',(code,signal)=>finish(code===0&&!signal&&result?result:reject('ocr_error','El proceso OCR terminó de forma anormal.')));
  child.send({data:new Uint8Array(input),source},error=>{if(error){child.kill();finish(reject('ocr_error','No se pudo enviar el documento al OCR.'));}});
 });
}
