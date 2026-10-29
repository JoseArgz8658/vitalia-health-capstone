const {reportSections,extractReportBlocks}=require('../dist/ai/report-blocks');
const {REPORT_FIELDS}=require('../dist/ai/report-fields');
const {createLocalExtractor}=require('../dist/ai/local-extractor');
const metadata={examen:'Panel ficticio',fecha:null,informe:Object.fromEntries(REPORT_FIELDS.map(key=>[key,null]))};
const row=nombre=>({nombre,valor:'1',unidad:'U/L',rango_referencia:null,estado_documento:null});
const text='Datos generales\n1. HEMOGRAMA COMPLETO\nFila Alfa\n2. QUIMICA CLINICA\nFila Beta\n3. PERFIL HEPATICO\nFila Gamma';
test('cortes en encabezados preservan exactamente texto y orden; tabla sin encabezados permanece completa',()=>{
 expect(reportSections(text).join('')).toBe(text);
 expect(reportSections(text)).toHaveLength(4);
 const table='Nombre\nAlfa\n1\nU/L\nReferencia\nBeta\n2\nU/L';expect(reportSections(table)).toEqual([table]);
});
test('datos generales y filas se ensamblan sin perder estado ni alterar orden',async()=>{
 const seen=[];
 const result=JSON.parse(await extractReportBlocks(text,async(schema,input)=>{
  seen.push(input);
  if(schema.required.includes('informe'))return JSON.stringify(metadata);
  const nombre=input.includes('Fila Alfa')?'Alfa':input.includes('Fila Beta')?'Beta':input.includes('Fila Gamma')?'Gamma':null;
  return JSON.stringify({resultados:nombre?[row(nombre)]:[]});
 }));
 expect(seen[0]).toBe(text);expect(seen.slice(1).join('')).toBe(text);
 expect(result.resultados.map(x=>x.nombre)).toEqual(['Alfa','Beta','Gamma']);expect(result.informe).toEqual(metadata.informe);
});
test('bloque inválido o transporte fallido impide devolver informe parcial',async()=>{
 for(const fail of [()=>JSON.stringify({resultados:[{nombre:'incompleto'}]}),()=>{throw new Error('fallo');}]){
  let calls=0;
  await expect(extractReportBlocks(text,async()=>{calls++;if(calls===1)return JSON.stringify(metadata);if(calls===2)return JSON.stringify({resultados:[row('Alfa')]});return fail();})).rejects.toThrow();
  expect(calls).toBe(3);
 }
});

test('solicitud bloqueada se cancela a los tres minutos y no inicia otra',async()=>{
 jest.useFakeTimers();
 const warn=jest.spyOn(console,'warn').mockImplementation(()=>{});
 try{
  const fetchImpl=jest.fn((_url,options)=>
   new Promise((_,reject)=>{
    options.signal.addEventListener(
     'abort',
     ()=>reject(new Error('cancelado')),
     {once:true}
    );
   })
  );

  const pending=createLocalExtractor({promptVersion:4,fetchImpl})('Texto ficticio');
  const rejected=expect(pending).rejects.toMatchObject({reason:'timeout'});

  await jest.advanceTimersByTimeAsync(180000);
  await rejected;
  expect(fetchImpl).toHaveBeenCalledTimes(1);
 }finally{
  jest.useRealTimers();
  warn.mockRestore();
 }
});

test('las solicitudes comparten seis minutos sin ampliar el presupuesto',async()=>{
 jest.useFakeTimers();const warn=jest.spyOn(console,'warn').mockImplementation(()=>{});
 try{
  let calls=0;
  const fetchImpl=jest.fn(async(_url,options)=>{
   const call=++calls;
   await new Promise((resolve,reject)=>{
    const timer=setTimeout(resolve,100000);
    options.signal.addEventListener('abort',()=>{clearTimeout(timer);reject(new Error('cancelado'));},{once:true});
   });
   return new Response(JSON.stringify({done:true,message:{content:JSON.stringify(call===1?metadata:{resultados:[]})}}));
  });
  const pending=createLocalExtractor({promptVersion:4,fetchImpl})(text);const rejected=expect(pending).rejects.toMatchObject({reason:'timeout'});
  await jest.advanceTimersByTimeAsync(360000);await rejected;expect(calls).toBe(4);
 }finally{jest.useRealTimers();warn.mockRestore();}
});
