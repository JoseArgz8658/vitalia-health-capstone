const {readPdfText,PDF_LIMITS}=require('../dist/pdf/reader');
const fixtures=require('./pdf-fixtures.json');
const data=name=>Buffer.from(fixtures[name],'base64');
test('PDF con texto conserva números, nombres y contenido',async()=>{
 const result=await readPdfText(data('texto'));
 expect(result.status).toBe('text_ready');expect(result.pageCount).toBe(1);
 expect(result.text).toContain('14,2 g/dL');expect(result.text).toContain('245.000');
 expect(result.text).toContain('Indicador Alfa');expect(result.incidents).toEqual([]);
});
test('imagen sin texto requiere OCR y no entrega extracción parcial',async()=>{
 const result=await readPdfText(data('imagen'));
 expect(result.status).toBe('needs_ocr');expect(result.text).toBeNull();
 expect(result.incidents[0]).toMatchObject({code:'page_without_text',page:1});
});
test('PDF mixto señala página sin texto y no entrega solo parte del documento',async()=>{
 const result=await readPdfText(data('mixto'));
 expect(result.status).toBe('needs_ocr');expect(result.text).toBeNull();
 expect(result.incidents[0].page).toBe(2);
});
test('PDF protegido se rechaza explícitamente',async()=>{
 expect((await readPdfText(data('protegido'))).incidents[0].code).toBe('password_required');
});
test('tamaño, firma y PDF dañado son rechazados',async()=>{
 expect((await readPdfText(Buffer.alloc(0))).incidents[0].code).toBe('invalid_size');
 expect((await readPdfText(Buffer.alloc(PDF_LIMITS.bytes+1))).incidents[0].code).toBe('invalid_size');
 expect((await readPdfText(Buffer.from('texto'))).incidents[0].code).toBe('invalid_signature');
 expect((await readPdfText(Buffer.from('%PDF-1.7\narchivo roto'))).status).toBe('rejected');
});
test('más de diez páginas se rechazan antes de extraer',async()=>{
 const result=await readPdfText(data('muchas_paginas'));
 expect(result.pageCount).toBe(11);expect(result.text).toBeNull();expect(result.incidents[0].code).toBe('page_limit');
});

test('cierre anormal del lector se devuelve como incidencia sin cerrar el padre',async()=>{
 const {EventEmitter}=require('node:events');
 const childProcess=require('node:child_process');
 const child=new EventEmitter();
 child.kill=jest.fn();
 child.send=jest.fn(()=>queueMicrotask(()=>child.emit('close',3221225477,null)));
 const spy=jest.spyOn(childProcess,'fork').mockReturnValue(child);
 try{
  const result=await readPdfText(data('texto'));
  expect(result.status).toBe('rejected');
  expect(result.incidents[0].code).toBe('reader_error');
 }finally{spy.mockRestore();}
});
test('lector bloqueado se termina al exceder el límite de tiempo',async()=>{
 const {EventEmitter}=require('node:events');
 const childProcess=require('node:child_process');
 const child=new EventEmitter();
 child.kill=jest.fn();child.send=jest.fn();
 const spy=jest.spyOn(childProcess,'fork').mockReturnValue(child);
 jest.useFakeTimers();
 try{
  const pending=readPdfText(data('texto'));
  jest.advanceTimersByTime(PDF_LIMITS.timeoutMs);
  const result=await pending;
  expect(child.kill).toHaveBeenCalled();
  expect(result.incidents[0].code).toBe('read_timeout');
 }finally{jest.useRealTimers();spy.mockRestore();}
});
