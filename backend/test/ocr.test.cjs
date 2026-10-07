const {readOcr}=require('../dist/ocr/reader');
const {imageDimensions,summarizeOcr,OCR_LIMITS}=require('../dist/ocr/contract');
const fixtures=require('./ocr-fixtures.json');
const pdfs=require('./pdf-fixtures.json');
jest.setTimeout(30000);
test.each(['png','jpeg','pdf'])('OCR real de %s conserva cifras sintéticas y requiere revisión',async source=>{
 const result=await readOcr(Buffer.from(fixtures[source],'base64'),source);
 expect(result.status).toBe('requires_review');expect(result.approved).toBe(false);
 expect(result.text).toContain('14,2');expect(result.text).toContain('245.000');
 expect(result.text).toContain('01-10-2026');expect(result.pages).toHaveLength(1);
 // No afirmar fidelidad de unidades: µ puede reconocerse como u incluso con confianza alta.
});
test('imagen en blanco no produce texto listo',async()=>{
 const result=await readOcr(Buffer.from(fixtures.blank,'base64'),'png');
 expect(result.status).toBe('rejected');expect(result.text).toBeNull();
 expect(result.incidents.some(i=>i.code==='no_text')).toBe(true);
});
test('PDF protegido y más de tres páginas quedan rechazados',async()=>{
 expect((await readOcr(Buffer.from(pdfs.protegido,'base64'),'pdf')).incidents[0].code).toBe('password_required');
 expect((await readOcr(Buffer.from(pdfs.muchas_paginas,'base64'),'pdf')).incidents[0].code).toBe('page_limit');
});
test('tamaño, firma y resolución se validan antes del OCR',async()=>{
 expect((await readOcr(Buffer.alloc(0),'png')).incidents[0].code).toBe('invalid_size');
 expect((await readOcr(Buffer.alloc(OCR_LIMITS.bytes+1),'pdf')).incidents[0].code).toBe('invalid_size');
 expect((await readOcr(Buffer.from('x'),'jpeg')).incidents[0].code).toBe('invalid_signature');
 const image=Buffer.from(fixtures.png,'base64');image.writeUInt32BE(100000,16);
 expect((await readOcr(image,'png')).incidents[0].code).toBe('image_limit');
 expect(imageDimensions(Buffer.from(fixtures.jpeg,'base64'))).toEqual({width:1800,height:700});
});
test('texto de baja confianza queda señalado y no se corrige',()=>{
 const result=summarizeOcr('png',[{page:1,text:'245.000 /uL',confidence:40}]);
 expect(result.text).toBe('245.000 /uL');expect(result.approved).toBe(false);
 expect(result.incidents[0].code).toBe('low_confidence');
});
test('página sin texto impide entregar documento parcial; límite no trunca',()=>{
 const result=summarizeOcr('pdf',[{page:1,text:'texto',confidence:90},{page:2,text:'',confidence:0}]);
 expect(result.status).toBe('rejected');expect(result.text).toBeNull();
 expect(summarizeOcr('png',[{page:1,text:'á'.repeat(6001),confidence:90}]).incidents[0].code).toBe('text_limit');
});
test('cierre anormal se devuelve como incidencia y tiempo excedido termina proceso',async()=>{
 const {EventEmitter}=require('node:events'),cp=require('node:child_process');
 const child=new EventEmitter();child.kill=jest.fn();
 child.send=jest.fn(()=>queueMicrotask(()=>child.emit('close',3221225477,null)));
 const spy=jest.spyOn(cp,'fork').mockReturnValue(child);
 try{expect((await readOcr(Buffer.from(fixtures.png,'base64'),'png')).incidents[0].code).toBe('ocr_error');}
 finally{spy.mockRestore();}
 const hung=new EventEmitter();hung.kill=jest.fn();hung.send=jest.fn();
 const spy2=jest.spyOn(cp,'fork').mockReturnValue(hung);jest.useFakeTimers();
 try{
  const pending=readOcr(Buffer.from(fixtures.png,'base64'),'png');jest.advanceTimersByTime(OCR_LIMITS.timeoutMs);
  expect((await pending).incidents[0].code).toBe('ocr_timeout');expect(hung.kill).toHaveBeenCalled();
 }finally{spy2.mockRestore();jest.useRealTimers();}
});
