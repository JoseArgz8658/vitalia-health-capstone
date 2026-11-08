'use strict';
const {createSilResultsFilePreview}=require('../dist/sil/results-file-preview');
const {SilConflictError}=require('../dist/sil/service');
const id='11111111-1111-4111-8111-111111111111';
const pdf=Buffer.from('%PDF-1.4\n%%EOF');
const source='Identificador de paciente: DEMO-0001\nGlucosa 91 mg/dL\nHbA1c 5.4 %\n';
const expected=[
  {examCode:'glicemia',analyte:'Glucosa',unit:'mg/dL'},
  {examCode:'hba1c',analyte:'HbA1c',unit:'%'},
];
function fakeDb(status='sampled',identifier='DEMO-0001'){
 return {query:jest.fn(async(sql,args)=>{
   expect(args).toEqual([id]);
   if(sql.includes('SELECT o.status'))return {rows:[{status,identifier}]};
   if(sql.includes('FROM public.vitalia_sil_order_exams'))return {rows:expected};
   throw Error('unexpected SQL');
 })};
}
function read(text=source,status='text_ready'){
 return jest.fn(async()=>({status,text,pageCount:1,incidents:[]}));
}
function extract(incidents=[],results=[
 {nombre:'Glucosa',valor:'91',unidad:'mg/dL',rango_referencia:null},
 {nombre:'HbA1c',valor:'5.4',unidad:'%',rango_referencia:null},
]) {
 return jest.fn(async()=>({
  status:'requires_review',extraction:{examen:'Perfil de prueba',fecha:null,resultados:results},
  incidents,approved:false,raw:'{}',model:'stub',promptVersion:3,elapsedMs:0,
 }));
}
test('extrae propuestas pero nunca escribe en PostgreSQL',async()=>{
 const db=fakeDb(),reader=read(),extractor=extract();
 const preview=await createSilResultsFilePreview(db,{read:reader,extract:extractor})(id,pdf);
 expect(preview.state).toBe('ready');
 expect(preview.confirmed).toBe(false);
 expect(preview.items.map(x=>x.suggestedValue)).toEqual([91,5.4]);
 expect(db.query).toHaveBeenCalledTimes(2);
 expect(db.query.mock.calls.some(([sql])=>/INSERT|UPDATE|DELETE/.test(sql))).toBe(false);
});
test('incongruencia de identidad impide usar IA y propone ingreso manual',async()=>{
 const extractor=extract();
 const preview=await createSilResultsFilePreview(fakeDb(),{
   read:read(source.replace('DEMO-0001','DEMO-0002')),extract:extractor,
 })(id,pdf);
 expect(preview.state).toBe('identity_mismatch');
 expect(preview.items.every(x=>x.suggestedValue===null)).toBe(true);
 expect(extractor).not.toHaveBeenCalled();
});
test('incidencia de IA deja solo el valor dudoso vacío para corrección humana',async()=>{
 const preview=await createSilResultsFilePreview(fakeDb(),{
  read:read(),extract:extract([{
    code:'not_in_source',path:'resultados[1].valor',
    message:'Valor no verificable',
  }]),
 })(id,pdf);
 expect(preview.state).toBe('needs_manual');
 expect(preview.items[0].suggestedValue).toBe(91);
 expect(preview.items[1].suggestedValue).toBeNull();
 expect(preview.items[1].warning).toMatch(/incidencia/);
});
test('rechaza propuesta cuando unidad no coincide o cifra es ambigua',async()=>{
 const preview=await createSilResultsFilePreview(fakeDb(),{
  read:read(),extract:extract([],[
   {nombre:'Glucosa',valor:'91',unidad:'mmol/L',rango_referencia:null},
   {nombre:'HbA1c',valor:'5,4.8',unidad:'%',rango_referencia:null},
  ]),
 })(id,pdf);
 expect(preview.items.every(x=>x.suggestedValue===null)).toBe(true);
});
test('sin Ollama no hay guardado automático y la captura manual sigue disponible',async()=>{
 const preview=await createSilResultsFilePreview(fakeDb(),{
  read:read(),extract:async()=>{throw Error('offline');},
 })(id,pdf);
 expect(preview.state).toBe('analysis_unavailable');
 expect(preview.generatedBy).toBe('none');
 expect(preview.items.every(x=>x.suggestedValue===null)).toBe(true);
});
test('orden sin recepción de muestra no admite carga IA',async()=>{
 const extractor=extract();
 await expect(createSilResultsFilePreview(fakeDb('registered'),{
  read:read(),extract:extractor,
 })(id,pdf)).rejects.toBeInstanceOf(SilConflictError);
 expect(extractor).not.toHaveBeenCalled();
});
test('PDF sin texto indica captura manual u OCR',async()=>{
 const extractor=extract();
 const preview=await createSilResultsFilePreview(fakeDb(),{
  read:read(null,'needs_ocr'),extract:extractor,
 })(id,pdf);
 expect(preview.state).toBe('needs_ocr');
 expect(extractor).not.toHaveBeenCalled();
});
