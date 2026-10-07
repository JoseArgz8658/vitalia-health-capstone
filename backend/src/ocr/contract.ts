export type OcrPage = { page: number; text: string; confidence: number };
export type OcrResult = {
 status: 'requires_review' | 'rejected'; source: 'png' | 'jpeg' | 'pdf';
 text: string | null; pages: OcrPage[];
 incidents: { code: string; page?: number; message: string }[]; approved: false;
};
export const OCR_LIMITS = {bytes:10*1024*1024,pages:3,pixels:4_000_000,textBytes:12000,timeoutMs:60000} as const;
export function imageDimensions(data:Uint8Array):{width:number;height:number}|null{
 const b=Buffer.from(data);
 if(b.length>=24&&b.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))return {width:b.readUInt32BE(16),height:b.readUInt32BE(20)};
 if(b.length<4||b[0]!==255||b[1]!==216)return null;
 let i=2;
 while(i+4<=b.length){
  if(b[i++]!==255)return null;
  while(b[i]===255)i++;
  const marker=b[i++];
  if(marker===217||marker===218)return null;
  if(marker===1||(marker>=208&&marker<=215))continue;
  if(i+2>b.length)return null;
  const size=b.readUInt16BE(i);
  if(size<2||i+size>b.length)return null;
  if([192,193,194,195,197,198,199,201,202,203,205,206,207].includes(marker)){
   if(size<8)return null;
   return {height:b.readUInt16BE(i+3),width:b.readUInt16BE(i+5)};
  }
  i+=size;
 }
 return null;
}
export function summarizeOcr(source:OcrResult['source'],pages:OcrPage[]):OcrResult{
 const incidents:OcrResult['incidents']=[];
 for(const page of pages){
  if(!/[\p{L}\p{N}]/u.test(page.text))incidents.push({code:'no_text',page:page.page,message:'No se reconoció texto aprovechable.'});
  if(!Number.isFinite(page.confidence)||page.confidence<70)incidents.push({code:'low_confidence',page:page.page,message:'Confianza OCR baja; comprobar cada dato contra el original.'});
 }
 const text=pages.map(p=>p.text).join('\n\n');
 if(Buffer.byteLength(text,'utf8')>OCR_LIMITS.textBytes)return {status:'rejected',source,text:null,pages:[],approved:false,incidents:[{code:'text_limit',message:'Texto mayor de 12000 bytes; no se entrega truncado.'}]};
 const rejected=!pages.length||incidents.some(i=>i.code==='no_text');
 return {status:rejected?'rejected':'requires_review',source,text:rejected?null:text,pages,incidents,approved:false};
}
