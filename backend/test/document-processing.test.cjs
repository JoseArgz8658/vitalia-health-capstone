const {queueDocumentProcessing,claimDocumentProcessing,completeDocumentProcessing,failDocumentProcessing,findPatientProcessingStatus}=require('../dist/processing/repository');
const {processingResultSchema}=require('../dist/processing/result');
const {randomUUID}=require('node:crypto');
const account={id:randomUUID(),email:'test@example.invalid',role:'paciente',createdAt:new Date()};
const id=randomUUID(),doc=randomUUID();
const sample={status:'requires_review',source:'pdf',method:'direct',reading:{status:'text_ready',text:'Texto ficticio',pageCount:1,incidents:[]},ocr:null,inputText:'Texto ficticio',ai:{status:'requires_review',raw:'{"examen":"Ficticio","fecha":null,"resultados":[]}',extraction:{examen:'Ficticio',fecha:null,resultados:[]},incidents:[],approved:false,model:'qwen3:4b-instruct',promptVersion:3,elapsedMs:1},approved:false};
const database=rows=>({query:jest.fn(async()=>({rows}))});
test('cola limita a documento guardado de paciente autenticado y parametriza',async()=>{
 const db=database([{id}]);expect(await queueDocumentProcessing(db,account,doc)).toBe(id);
 const [sql,params]=db.query.mock.calls[0];
 expect(params.slice(1)).toEqual([doc,account.id,'qwen3:4b-instruct']);
 expect(sql).toContain("d.status='stored'");expect(sql).toContain('d.patient_id=$3');expect(sql).toContain('ON CONFLICT(document_id) DO NOTHING');
 expect(sql).not.toContain(account.id);
});
test('sin autorización de rol, identificador o modelo no consulta DB',async()=>{
 const db=database([]);
 await expect(queueDocumentProcessing(db,{...account,role:'administrador'},doc)).rejects.toThrow('paciente');
 await expect(queueDocumentProcessing(db,account,"' OR 1=1 --")).rejects.toThrow();
 await expect(queueDocumentProcessing(db,account,doc,'modelo-cloud')).rejects.toThrow();
 expect(db.query).not.toHaveBeenCalled();
});
test('documento ajeno o duplicado no revela detalles',async()=>{
 expect(await queueDocumentProcessing(database([]),account,doc)).toBeNull();
});
test('reclamo atómico requiere queued y devuelve null si ya reclamado',async()=>{
 const db=database([]);expect(await claimDocumentProcessing(db,id)).toBeNull();
 expect(db.query.mock.calls[0][0]).toContain("p.status='queued'");
 expect(db.query.mock.calls[0][1]).toEqual([id]);
});
test('finalización conserva JSON exacto, metadata modelo y estado protegido',async()=>{
 const db=database([{id}]);expect(await completeDocumentProcessing(db,id,sample)).toBe(true);
 const [sql,args]=db.query.mock.calls[0];
 expect(JSON.parse(args[2])).toEqual(sample);expect(args.slice(3)).toEqual(['application/pdf','qwen3:4b-instruct',3]);
 expect(sql).toContain("p.status='processing'");expect(sql).toContain('p.model=$5');
});
test('finalización obsoleta devuelve false, sin forzar sobrescritura',async()=>{
 expect(await completeDocumentProcessing(database([]),id,sample)).toBe(false);
});
test('resultado aprobado, estructura extra o extracción ausente no se persiste',async()=>{
 const db=database([]);
 for(const input of [{...sample,approved:true},{...sample,unexpected:1},{...sample,ai:null},{...sample,inputText:'otro texto'}]){
  await expect(completeDocumentProcessing(db,id,input)).rejects.toThrow();
 }
 expect(db.query).not.toHaveBeenCalled();
});
test('fecha inválida e incidencias permanecen sin corrección',async()=>{
 const value=structuredClone(sample);value.ai.extraction.fecha='31-11-2026';
 value.ai.incidents=[{code:'invalid_date',path:'fecha',message:'Fecha inválida'}];
 const db=database([{id}]);await completeDocumentProcessing(db,id,value);
 expect(JSON.parse(db.query.mock.calls[0][1][2]).ai.extraction.fecha).toBe('31-11-2026');
});
test('OCR y su confianza se conservan; imagen no admite lectura directa',()=>{
 const value={...sample,source:'png',method:'ocr',reading:null,ocr:{status:'requires_review',source:'png',text:sample.inputText,pages:[{page:1,text:sample.inputText,confidence:40}],incidents:[{code:'low_confidence',message:'Revisar'}],approved:false}};
 expect(processingResultSchema.parse(value).ocr.pages[0].confidence).toBe(40);
 expect(processingResultSchema.safeParse({...value,method:'direct'}).success).toBe(false);
});
test('resultados de rechazo y fallo de servicio son aceptados sin aprobación',async()=>{
 const rejected={status:'rejected',source:'pdf',method:null,reading:{status:'rejected',text:null,pageCount:null,incidents:[{code:'password_required',message:'Protegido'}]},ocr:null,inputText:null,ai:null,approved:false};
 const db=database([{id}]);await completeDocumentProcessing(db,id,rejected);
 expect(db.query.mock.calls[0][1][1]).toBe('rejected');
 const failed={...sample,status:'service_error',ai:null,error:{code:'extraction_unavailable',message:'No disponible'}};
 await completeDocumentProcessing(db,id,failed);expect(db.query.mock.calls[1][1][1]).toBe('failed');
});
test('fallo de lectura de imagen puede conservar diagnóstico sin OCR completo',()=>{
 const value={status:'service_error',source:'png',method:'ocr',reading:null,ocr:null,inputText:null,ai:null,approved:false,error:{code:'reading_unavailable',message:'No disponible'}};
 expect(processingResultSchema.safeParse(value).success).toBe(true);
});
test('interrupción usa código controlado y no cambia resultados terminados',async()=>{
 const db=database([]);expect(await failDocumentProcessing(db,id,'processing_interrupted')).toBe(false);
 expect(db.query.mock.calls[0][0]).toContain("status='processing'");
 await expect(failDocumentProcessing(db,id,'mensaje arbitrario')).rejects.toThrow();
 expect(db.query).toHaveBeenCalledTimes(1);
});
test('consulta de paciente solo selecciona estado propio sin resultado sin revisar',async()=>{
 const db=database([]);expect(await findPatientProcessingStatus(db,account,doc)).toBeNull();
 const [sql,args]=db.query.mock.calls[0];expect(args).toEqual([doc,account.id]);
 expect(sql).toContain('d.patient_id=$2');expect(sql).not.toMatch(/SELECT[^]*result/i);
});
