import { PDFParse } from 'pdf-parse';
import { PDF_LIMITS, type PdfReadResult } from './reader';
async function parse(data:Uint8Array):Promise<PdfReadResult>{
  // Uint8Array copiado evita transferir directamente el Buffer recibido.
  const parser=new PDFParse({data:new Uint8Array(data),stopAtErrors:true,isEvalSupported:false});
  let pageCount:number|null=null;
  try {
    const info=await parser.getInfo();pageCount=info.total;
    if(pageCount<1||pageCount>PDF_LIMITS.pages)return {status:'rejected',text:null,pageCount,incidents:[{code:'page_limit',message:'Se admiten entre 1 y 10 páginas.'}]};
    const pages:string[]=[];
    const incidents:PdfReadResult['incidents']=[];
    let bytes=0;
    for(let page=1;page<=pageCount;page++){
      const result=await parser.getText({partial:[page],pageJoiner:''});
      const text=result.pages.map(p=>p.text).join('\n').trim();
      if(!/[\p{L}\p{N}]/u.test(text))incidents.push({code:'page_without_text',page,message:'Página sin texto aprovechable; requiere OCR o comprobación.'});
      pages.push(text);bytes+=Buffer.byteLength(text,'utf8')+(page>1?2:0);
      if(bytes>PDF_LIMITS.textBytes)return {status:'rejected',text:null,pageCount,incidents:[{code:'text_limit',message:'El texto excede 12000 bytes; no se entrega truncado.'}]};
    }
    if(incidents.length)return {status:'needs_ocr',text:null,pageCount,incidents};
    return {status:'text_ready',text:pages.join('\n\n'),pageCount,incidents:[]};
  }catch(error){
    const protectedPdf=error instanceof Error&&error.name==='PasswordException';
    return {status:'rejected',text:null,pageCount,incidents:[{code:protectedPdf?'password_required':'invalid_pdf',message:protectedPdf?'PDF protegido; no se intenta desbloquear.':'PDF dañado o no legible.'}]};
  }finally{await parser.destroy().catch(()=>undefined);}
}
process.once('message',async(message:{data:Uint8Array})=>{
  const result=await parse(message.data).catch(()=>({
    status:'rejected',text:null,pageCount:null,
    incidents:[{code:'reader_error',message:'No se pudo iniciar el lector PDF.'}],
  }));
  if(process.send){
    process.send(result,(error:Error|null)=>{
      if(process.connected)process.disconnect();
      if(error)process.exitCode=1;
    });
  }
});
