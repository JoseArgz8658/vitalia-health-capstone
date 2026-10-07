import { fork } from 'node:child_process';
import { join } from 'node:path';
export type PdfReadResult = {
  status: 'text_ready' | 'needs_ocr' | 'rejected';
  text: string | null;
  pageCount: number | null;
  incidents: { code: string; page?: number; message: string }[];
};
export const PDF_LIMITS = { bytes: 10 * 1024 * 1024, pages: 10, textBytes: 12000, timeoutMs: 15000 } as const;
export async function readPdfText(input: Uint8Array): Promise<PdfReadResult> {
  const reject = (code: string, message: string): PdfReadResult => ({status:'rejected',text:null,pageCount:null,incidents:[{code,message}]});
  if (!(input instanceof Uint8Array) || input.byteLength === 0 || input.byteLength > PDF_LIMITS.bytes) return reject('invalid_size','PDF vacío o mayor de 10 MiB.');
  if (Buffer.from(input.subarray(0,5)).toString('ascii') !== '%PDF-') return reject('invalid_signature','El contenido no comienza con la firma PDF.');
  return new Promise(resolve => {
    // Proceso separado: un fallo nativo del parser no comparte memoria con el padre.
    const child = fork(join(__dirname,'reader-worker.js'), [], {
      serialization: 'advanced', stdio: ['ignore','ignore','ignore','ipc'],
      execArgv: ['--max-old-space-size=128'],
    });
    let settled=false;
    let result:PdfReadResult|null=null;
    const finish=(value:PdfReadResult)=>{
      if(settled)return;
      settled=true;clearTimeout(timer);resolve(value);
    };
    const timer=setTimeout(()=>{
      child.kill();
      finish(reject('read_timeout','La lectura excedió 15 segundos.'));
    },PDF_LIMITS.timeoutMs);
    child.once('message',(message:PdfReadResult)=>{result=message;});
    child.once('error',()=>{
      child.kill();
      finish(reject('reader_error','No se pudo iniciar o comunicar con el lector PDF.'));
    });
    // Esperar el cierre limpio; una respuesta previa no oculta un cierre anormal.
    child.once('close',(code,signal)=>{
      finish(code===0 && !signal && result ? result : reject('reader_error','El proceso lector terminó de forma anormal.'));
    });
    child.send({data:new Uint8Array(input)},error=>{
      if(error){child.kill();finish(reject('reader_error','No se pudo enviar el PDF al lector.'));}
    });
  });
}
