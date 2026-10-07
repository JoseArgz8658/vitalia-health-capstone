const {createDocumentExtraction}=require('../dist/ai/document-extraction');
const pdfs=require('./pdf-fixtures.json'),images=require('./ocr-fixtures.json');
const reading={status:'text_ready',text:'Texto directo',pageCount:1,incidents:[]};
const ocrResult={status:'requires_review',source:'pdf',text:'Texto OCR /uL',pages:[{page:1,text:'Texto OCR /uL',confidence:50}],incidents:[{code:'low_confidence',page:1,message:'Revisar'}],approved:false};
const ai={status:'requires_review',raw:'{}',extraction:null,incidents:[],approved:false,model:'simulado',promptVersion:3,elapsedMs:1};
test('PDF con texto usa lectura directa y no OCR',async()=>{
 const ocr=jest.fn(),extract=jest.fn(async()=>ai);
 const result=await createDocumentExtraction({read:async()=>reading,ocr,extract})(Buffer.from('x'),'pdf');
 expect(result.method).toBe('direct');expect(result.reading).toEqual(reading);expect(result.ai).toEqual(ai);
 expect(extract).toHaveBeenCalledWith('Texto directo');expect(ocr).not.toHaveBeenCalled();expect(result.approved).toBe(false);
});
test('PDF sin texto usa OCR completo y conserva resultado e incidencias',async()=>{
 const extract=jest.fn(async()=>ai),ocr=jest.fn(async()=>ocrResult);
 const result=await createDocumentExtraction({read:async()=>({...reading,status:'needs_ocr',text:null}),ocr,extract})(Buffer.from('x'),'pdf');
 expect(result.method).toBe('ocr');expect(result.ocr).toEqual(ocrResult);expect(extract).toHaveBeenCalledWith(ocrResult.text);
 expect(result.reading.status).toBe('needs_ocr');expect(result.inputText).toContain('/uL');
});
test.each(['png','jpeg'])('imagen %s no usa lector PDF',async source=>{
 const read=jest.fn(),extract=jest.fn(async()=>ai),ocr=jest.fn(async()=>({...ocrResult,source}));
 const result=await createDocumentExtraction({read,ocr,extract})(Buffer.from('x'),source);
 expect(read).not.toHaveBeenCalled();expect(result.method).toBe('ocr');expect(extract).toHaveBeenCalledWith(ocrResult.text);
});
test('PDF rechazado se detiene sin OCR ni IA',async()=>{
 const ocr=jest.fn(),extract=jest.fn();
 const result=await createDocumentExtraction({read:async()=>({...reading,status:'rejected',text:null}),ocr,extract})(Buffer.from('x'),'pdf');
 expect(result.status).toBe('rejected');expect(result.ai).toBeNull();expect(ocr).not.toHaveBeenCalled();expect(extract).not.toHaveBeenCalled();
});
test('OCR rechazado se conserva y no llega a IA',async()=>{
 const extract=jest.fn();
 const result=await createDocumentExtraction({ocr:async()=>({...ocrResult,status:'rejected',text:null}),extract})(Buffer.from('x'),'png');
 expect(result.status).toBe('rejected');expect(result.ocr.status).toBe('rejected');expect(extract).not.toHaveBeenCalled();
});
test.each(['','á'.repeat(6001)])('texto vacío o excedido se detiene',async text=>{
 const extract=jest.fn();
 const result=await createDocumentExtraction({read:async()=>({...reading,text}),extract})(Buffer.from('x'),'pdf');
 expect(result.status).toBe('rejected');expect(extract).not.toHaveBeenCalled();
});
test('servicio fallido conserva lectura y texto; respuesta rechazada conserva raw',async()=>{
 const result=await createDocumentExtraction({read:async()=>reading,extract:async()=>{throw Error('privado');}})(Buffer.from('x'),'pdf');
 expect(result.status).toBe('service_error');expect(result.inputText).toBe(reading.text);expect(JSON.stringify(result)).not.toContain('privado');
 const rejected=await createDocumentExtraction({read:async()=>reading,extract:async()=>({...ai,status:'rejected',raw:'{'})})(Buffer.from('x'),'pdf');
 expect(rejected.status).toBe('rejected');expect(rejected.ai.raw).toBe('{');
});
test('fallo inesperado del lector no llama a OCR ni IA',async()=>{
 const extract=jest.fn(),ocr=jest.fn();
 const result=await createDocumentExtraction({read:async()=>{throw Error('detalle');},ocr,extract})(Buffer.from('x'),'pdf');
 expect(result.error.code).toBe('reading_unavailable');expect(extract).not.toHaveBeenCalled();expect(ocr).not.toHaveBeenCalled();
});
test('PDF protegido real se detiene y texto real se transmite exactamente',async()=>{
 const extract=jest.fn(async()=>ai),ocr=jest.fn();const process=createDocumentExtraction({extract,ocr});
 expect((await process(Buffer.from(pdfs.protegido,'base64'),'pdf')).status).toBe('rejected');
 expect(extract).not.toHaveBeenCalled();expect(ocr).not.toHaveBeenCalled();
 const result=await process(Buffer.from(pdfs.texto,'base64'),'pdf');
 expect(extract).toHaveBeenCalledWith(result.reading.text);expect(result.method).toBe('direct');
});
test('PDF escaneado real llega a IA por OCR sin corregir unidades',async()=>{
 const extract=jest.fn(async()=>ai);
 const result=await createDocumentExtraction({extract})(Buffer.from(images.pdf,'base64'),'pdf');
 expect(result.reading.status).toBe('needs_ocr');expect(result.ocr.status).toBe('requires_review');
 expect(result.method).toBe('ocr');expect(extract).toHaveBeenCalledWith(result.ocr.text);
 expect(result.inputText).toContain('245.000');expect(result.approved).toBe(false);
},30000);
