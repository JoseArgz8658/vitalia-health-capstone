const {randomUUID}=require('node:crypto');
const {createProcessingWorker}=require('../dist/processing/worker');
const {parseManualArguments,inspectManualDocument,reserveManualProcessing}=require('../dist/processing/manual');
const fixtures=require('./pdf-fixtures.json');
const id=randomUUID(),documentId=randomUUID(),patientId=randomUUID();
const body=Buffer.from(fixtures.texto,'base64');
const job={id,document_id:documentId,model:'qwen3:4b-instruct',prompt_version:3,content_type:'application/pdf'};
const row={storage_key:`patients/${patientId}/documents/${documentId}`,original_name:'ficticio.pdf',content_type:'application/pdf',size_bytes:body.length,patient_id:patientId};
const text='Texto ficticio';
const result={status:'requires_review',source:'pdf',method:'direct',reading:{status:'text_ready',text,pageCount:1,incidents:[]},ocr:null,inputText:text,ai:{status:'requires_review',raw:'{"examen":"Ficticio","fecha":null,"resultados":[]}',extraction:{examen:'Ficticio',fecha:null,resultados:[]},incidents:[],approved:false,model:job.model,promptVersion:3,elapsedMs:1},approved:false};
function dbMock({claim=true,document=row,complete=true,failure=true}={}){
 return {query:jest.fn(async(sql)=>{
  if(sql.includes("SET status='processing'"))return {rows:claim?[job]:[]};
  if(sql.includes('SELECT storage_key'))return {rows:document?[document]:[]};
  if(sql.includes('result=$3::jsonb'))return {rows:complete?[{id}]:[]};
  if(sql.includes('failure_code=$2'))return {rows:failure?[{id}]:[]};
  throw Error('Consulta inesperada');
 })};
}
test('trabajo ya reclamado no lee S3 ni invoca IA',async()=>{
 const storage={read:jest.fn()},process=jest.fn();
 expect((await createProcessingWorker(dbMock({claim:false}),storage,{process})(id)).outcome).toBe('not_claimed');
 expect(storage.read).not.toHaveBeenCalled();expect(process).not.toHaveBeenCalled();
});
test('descarga clave de DB, valida y guarda salida completa sin transacción larga',async()=>{
 const db=dbMock(),storage={read:jest.fn(async()=>body)},process=jest.fn(async()=>result);
 expect(await createProcessingWorker(db,storage,{process})(id)).toEqual({outcome:'requires_review',processingId:id,approved:false});
 expect(storage.read).toHaveBeenCalledWith(row.storage_key);expect(process).toHaveBeenCalledWith(body,'pdf',job.model);
 const saved=db.query.mock.calls.find(([sql])=>sql.includes('result=$3::jsonb'));
 expect(JSON.parse(saved[1][2])).toEqual(result);
 expect(db.query.mock.calls.some(([sql])=>sql==='BEGIN')).toBe(false);
});
test.each([null,{...row,storage_key:`patients/${randomUUID()}/documents/${documentId}`}])('documento ausente o clave ajena detiene descarga',async document=>{
 const storage={read:jest.fn()},process=jest.fn();
 const output=await createProcessingWorker(dbMock({document}),storage,{process})(id);
 expect(output).toMatchObject({outcome:'processing_error',failureRecorded:true});expect(storage.read).not.toHaveBeenCalled();expect(process).not.toHaveBeenCalled();
});
test('bytes inconsistentes no llegan al modelo y marcan fallo controlado',async()=>{
 const process=jest.fn();const db=dbMock();
 const output=await createProcessingWorker(db,{read:async()=>body.subarray(0,10)},{process})(id);
 expect(output.outcome).toBe('processing_error');expect(process).not.toHaveBeenCalled();
 expect(db.query.mock.calls.some(([sql,args])=>sql.includes('failure_code=$2')&&args[1]==='processing_failed')).toBe(true);
});
test('firma incompatible no llega al modelo aunque tamaño coincida',async()=>{
 const process=jest.fn();
 const output=await createProcessingWorker(dbMock(),{read:async()=>Buffer.alloc(body.length)},{process})(id);
 expect(output.outcome).toBe('processing_error');expect(process).not.toHaveBeenCalled();
});
test('fallo S3 no invoca procesamiento ni expone mensajes internos',async()=>{
 const process=jest.fn();
 const output=await createProcessingWorker(dbMock(),{read:async()=>{throw Error('secret');}},{process})(id);
 expect(output.failureRecorded).toBe(true);expect(process).not.toHaveBeenCalled();expect(JSON.stringify(output)).not.toContain('secret');
});
test('resultado de servicio fallido se guarda como failed, sin borrarlo',async()=>{
 const db=dbMock();const value={...result,status:'service_error',ai:null,error:{code:'extraction_unavailable',message:'No disponible'}};
 const output=await createProcessingWorker(db,{read:async()=>body},{process:async()=>value})(id);
 expect(output.outcome).toBe('failed');
 expect(db.query.mock.calls.find(([sql])=>sql.includes('result=$3::jsonb'))[1][1]).toBe('failed');
});
test('no guardar resultado informa fallo y no afirma cierre confirmado',async()=>{
 const output=await createProcessingWorker(dbMock({complete:false,failure:false}),{read:async()=>body},{process:async()=>result})(id);
 expect(output).toMatchObject({outcome:'processing_error',failureRecorded:false});
});
test('argumentos manuales requieren UUID y apply explícito',()=>{
 expect(parseManualArguments(['--document',documentId])).toEqual({documentId,apply:false});
 expect(parseManualArguments(['--document',documentId,'--apply']).apply).toBe(true);
 for(const args of [[],['--document','invalid'],['--document',documentId,'--force']])expect(()=>parseManualArguments(args)).toThrow();
});
test('consulta manual no escribe ni expone contraseñas, texto o clave S3',async()=>{
 const db={query:jest.fn(async(sql)=>({rows:sql.includes('SELECT d.id')?[{id:documentId,patient_id:patientId,content_type:row.content_type,size_bytes:body.length,created_at:new Date()}]:[]}))};
 const inspection=await inspectManualDocument(db,documentId);expect(inspection.existing).toBeNull();expect(inspection.model).toBe(job.model);
 expect(db.query.mock.calls.every(([sql])=>sql.startsWith('SELECT'))).toBe(true);
 expect(db.query.mock.calls.map(([sql])=>sql).join(' ')).not.toMatch(/password_hash|storage_key/);
});
test('reserva manual reutiliza solo un queued; nunca repite trabajo terminado',async()=>{
 const inspection={documentId,account:{id:patientId,role:'paciente'}};
 const db={query:jest.fn(async(sql)=>({rows:sql.startsWith('INSERT')?[]:[{id,status:'requires_review'}]}))};
 expect(await reserveManualProcessing(db,inspection)).toBeNull();
});
