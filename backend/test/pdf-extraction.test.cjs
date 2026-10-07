const {createPdfExtraction}=require('../dist/ai/pdf-extraction');
const {createLocalExtractor}=require('../dist/ai/local-extractor');
const fixtures=require('./pdf-fixtures.json');
const reading={status:'text_ready',text:'Texto ficticio completo',pageCount:1,incidents:[]};
const ai={status:'requires_review',raw:'{}',extraction:{examen:'Ficticio',fecha:null,resultados:[]},incidents:[],approved:false,model:'simulado',promptVersion:3,elapsedMs:1};
test('envía exactamente texto disponible y conserva lectura y salida IA',async()=>{
 const extract=jest.fn(async()=>ai);
 const result=await createPdfExtraction({read:async()=>reading,extract})(Buffer.from('x'));
 expect(extract).toHaveBeenCalledWith(reading.text);
 expect(result).toEqual({status:'requires_review',reading,ai,approved:false});
});
test.each(['needs_ocr','rejected'])('%s no invoca la IA',async status=>{
 const extract=jest.fn();
 const result=await createPdfExtraction({read:async()=>({...reading,status,text:null}),extract})(Buffer.from('x'));
 expect(result.status).toBe(status);expect(result.ai).toBeNull();expect(extract).not.toHaveBeenCalled();
});
test('estado text_ready sin texto se rechaza antes del modelo',async()=>{
 const extract=jest.fn();
 const result=await createPdfExtraction({read:async()=>({...reading,text:' '}),extract})(Buffer.from('x'));
 expect(result.status).toBe('rejected');expect(extract).not.toHaveBeenCalled();
});
test('JSON rechazado conserva respuesta y no se aprueba',async()=>{
 const result=await createPdfExtraction({read:async()=>reading,extract:async()=>({...ai,status:'rejected',raw:'{',extraction:null})})(Buffer.from('x'));
 expect(result.status).toBe('rejected');expect(result.ai.raw).toBe('{');expect(result.approved).toBe(false);
});
test('fallo del servicio conserva texto y no expone error interno',async()=>{
 const result=await createPdfExtraction({read:async()=>reading,extract:async()=>{throw Error('detalle privado');}})(Buffer.from('x'));
 expect(result.status).toBe('service_error');expect(result.reading).toEqual(reading);expect(result.ai).toBeNull();
 expect(JSON.stringify(result)).not.toContain('detalle privado');
});
test('integración con PDF real y transporte simulado conserva texto hasta Ollama',async()=>{
 let sent;
 const extract=createLocalExtractor({fetchImpl:async(url,init)=>{
  sent=JSON.parse(init.body).messages[1].content;
  return new Response(JSON.stringify({done:true,message:{content:JSON.stringify({examen:'Perfil ficticio de lectura',fecha:'01-10-2026',resultados:[]})}}));
 }});
 const result=await createPdfExtraction({extract})(Buffer.from(fixtures.texto,'base64'));
 expect(sent).toBe(`DOCUMENTO FICTICIO:\n${result.reading.text}`);
 expect(sent).toContain('245.000');expect(result.ai.incidents[0].code).toBe('no_results');
 expect(result.status).toBe('requires_review');expect(result.approved).toBe(false);
});
test('PDF imagen y protegido reales quedan detenidos antes de IA',async()=>{
 const extract=jest.fn();const processPdf=createPdfExtraction({extract});
 expect((await processPdf(Buffer.from(fixtures.imagen,'base64'))).status).toBe('needs_ocr');
 expect((await processPdf(Buffer.from(fixtures.protegido,'base64'))).status).toBe('rejected');
 expect(extract).not.toHaveBeenCalled();
});
