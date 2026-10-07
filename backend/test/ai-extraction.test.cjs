const { reviewExtraction, isCalendarDate } = require('../dist/ai/contract');
const { createLocalExtractor } = require('../dist/ai/local-extractor');
const row={nombre:'Indicador ficticio',valor:'1.234,50',unidad:'U/L',rango_referencia:'1.000,00–2.000,00 U/L'};
const complete={examen:'Perfil ficticio',fecha:'01-10-2026',resultados:[row]};
const response=(value,extra={})=>new Response(JSON.stringify({done:true,message:{content:JSON.stringify(value)},...extra}));
test('datos completos conservados y siempre pendientes de revisión',()=>{
 const raw=JSON.stringify(complete), result=reviewExtraction(raw);
 expect(result).toMatchObject({raw,extraction:complete,incidents:[],status:'requires_review',approved:false});
});
test('fecha inválida conserva original y no oculta campo null',()=>{
 const result=reviewExtraction(JSON.stringify({...complete,fecha:'31-02-2026',resultados:[{...row,unidad:null}]}));
 expect(result.extraction.fecha).toBe('31-02-2026');
 expect(result.incidents.map(i=>[i.code,i.path])).toEqual([['invalid_date','fecha'],['not_extracted','resultados[0].unidad']]);
});
test('valor null conserva unidad y rango',()=>{
 const result=reviewExtraction(JSON.stringify({...complete,resultados:[{...row,valor:null}]}));
 expect(result.extraction.resultados[0]).toEqual({...row,valor:null});
 expect(result.incidents).toHaveLength(1);
});
test('JSON, claves extra y tipos incorrectos rechazados sin perder original',()=>{
 for(const raw of ['{',JSON.stringify({...complete,diagnostico:'x'}),JSON.stringify({...complete,resultados:[{...row,valor:123}]})]){
  expect(reviewExtraction(raw)).toMatchObject({status:'rejected',extraction:null,raw,approved:false});
 }
});
test('sin resultados y campos ausentes genera incidencias',()=>{
 expect(reviewExtraction(JSON.stringify({examen:null,fecha:null,resultados:[]})).incidents.map(i=>i.code)).toEqual(['not_extracted','not_extracted','no_results']);
});
test('calendario distingue años bisiestos',()=>{
 for(const v of ['31-11-2026','29-02-2027','29-02-1900','2026-10-01']) expect(isCalendarDate(v)).toBe(false);
 for(const v of ['29-02-2028','29-02-2000','01-10-2026']) expect(isCalendarDate(v)).toBe(true);
});
test('solicitud solo local, sin redirección y con prompt congelado',async()=>{
 const result=await createLocalExtractor({fetchImpl:async(url,init)=>{
  expect(url).toBe('http://127.0.0.1:11434/api/chat');expect(init.redirect).toBe('error');
  const body=JSON.parse(init.body);expect(body.model).toBe('qwen3:4b-instruct');expect(body.stream).toBe(false);
  expect(body.messages[0].content).toContain('INDEPENDIENTEMENTE');return response(complete);
 }})('Texto ficticio');
 expect(result).toMatchObject({extraction:complete,promptVersion:3,approved:false});
});
test('entrada inválida y modelo cloud fallan antes de red',async()=>{
 const fetchImpl=jest.fn(), extract=createLocalExtractor({fetchImpl});
 await expect(extract(' ')).rejects.toThrow('texto');await expect(extract('á'.repeat(6001))).rejects.toThrow('texto');
 expect(fetchImpl).not.toHaveBeenCalled();expect(()=>createLocalExtractor({model:'model-cloud'})).toThrow('local');
});
test('HTTP, transporte e incompleto producen error de servicio',async()=>{
 await expect(createLocalExtractor({fetchImpl:async()=>new Response('',{status:404})})('x')).rejects.toThrow('HTTP 404');
 await expect(createLocalExtractor({fetchImpl:async()=>{throw Error('privado');}})('x')).rejects.toThrow('No se pudo');
 await expect(createLocalExtractor({fetchImpl:async()=>response(complete,{done_reason:'length'})})('x')).rejects.toThrow('incompleta');
});
test('límite de respuesta y JSON del modelo inválido',async()=>{
 await expect(createLocalExtractor({fetchImpl:async()=>new Response('x'.repeat(131073))})('x')).rejects.toThrow('grande');
 const result=await createLocalExtractor({fetchImpl:async()=>new Response(JSON.stringify({done:true,message:{content:'{'}}))})('x');
 expect(result).toMatchObject({status:'rejected',raw:'{'});
});
