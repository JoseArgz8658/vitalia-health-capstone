import {randomUUID} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {hashPassword} from '../auth/password';
import {insertPatientAccount} from '../accounts/repository';
import {reserveDocument,completeDocument} from '../documents/repository';
import {queueDocumentProcessing,claimDocumentProcessing,completeDocumentProcessing,findProcessingForWorker,findPatientProcessingStatus} from '../processing/repository';
import {type DocumentExtractionResult} from '../ai/document-extraction';
async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,started=false,failed=false;
 try{
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();
  await client.query('BEGIN');started=true;
  const hash=await hashPassword(randomUUID());
  const a=await insertPatientAccount(client,randomUUID()+'@example.invalid',hash);
  const b=await insertPatientAccount(client,randomUUID()+'@example.invalid',hash);
  const doc=await reserveDocument(client,a,{examName:'Prueba sintética de procesamiento',examType:'Laboratorio',examDate:'2026-01-01',originalName:'sintetico.pdf',contentType:'application/pdf',sizeBytes:100});
  if(await queueDocumentProcessing(client,a,doc.id))throw new Error('Documento pendiente aceptado.');
  // Solo metadatos ficticios dentro de la transacción; no afirma existencia de objeto S3.
  await completeDocument(client,a,doc.id);
  if(await queueDocumentProcessing(client,b,doc.id))throw new Error('Acceso ajeno.');
  const id=await queueDocumentProcessing(client,a,doc.id);if(!id)throw new Error('No se reservó procesamiento.');
  if(await queueDocumentProcessing(client,a,doc.id))throw new Error('Duplicado aceptado.');
  if(await findPatientProcessingStatus(client,b,doc.id))throw new Error('Estado visible a otro paciente.');
  if(!await claimDocumentProcessing(client,id)||await claimDocumentProcessing(client,id))throw new Error('Reclamo inválido.');
  const text='Examen ficticio';
  const result:DocumentExtractionResult={status:'requires_review',source:'pdf',method:'direct',reading:{status:'text_ready',text,pageCount:1,incidents:[]},ocr:null,inputText:text,
   ai:{status:'requires_review',raw:'{"examen":"Examen ficticio","fecha":null,"resultados":[]}',extraction:{examen:'Examen ficticio',fecha:null,resultados:[]},incidents:[{code:'not_extracted',path:'fecha',message:'Revisar fecha.'},{code:'no_results',path:'resultados',message:'Revisar original.'}],approved:false,model:'qwen3:4b-instruct',promptVersion:3,elapsedMs:1},approved:false};
  if(!await completeDocumentProcessing(client,id,result)||await completeDocumentProcessing(client,id,result))throw new Error('Finalización inválida.');
  const stored=await findProcessingForWorker(client,id);
  if(stored?.status!=='requires_review'||!isDeepStrictEqual(stored.result?.ai?.extraction,result.ai?.extraction)||stored.result?.ai?.raw!==result.ai?.raw||stored.result?.approved!==false)throw new Error('Persistencia inválida.');
  const status=await findPatientProcessingStatus(client,a,doc.id);
  if(status?.status!=='requires_review'||'result' in status)throw new Error('Consulta de estado inválida.');
  await client.query('ROLLBACK');started=false;
  const check=await client.query('SELECT id FROM public.vitalia_document_processing WHERE id=$1',[id]);
  if(check.rows.length)throw new Error('Reversión fallida.');
  console.info('Persistencia y aislamiento de procesamiento correctos. Datos sintéticos revertidos.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo verificar procesamiento. Revisa PostgreSQL y la migración 006; no se guardaron datos de prueba intencionalmente.');}
 finally{
  if(started&&client)await client.query('ROLLBACK').catch(()=>{failed=true;process.exitCode=1;});
  client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});
 }
}
void main();
