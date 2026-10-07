import {ollamaUrl} from '../runtime/local-services';
import {type PoolClient} from 'pg';
import {acquireProcessorLock,releaseProcessorLock} from '../processing/queue';
import {type Pool} from 'pg';
import {type S3Client} from '@aws-sdk/client-s3';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {readStorageConfig} from '../storage/config';
import {createStorageClient,checkPrivateBucket} from '../storage/s3';
import {s3DocumentStorage} from '../documents/storage-adapter';
import {createProcessingWorker} from '../processing/worker';
import {parseManualArguments,inspectManualDocument,reserveManualProcessing} from '../processing/manual';
async function main(){
 let pool:Pool|undefined,storage:S3Client|undefined,client:PoolClient|undefined,locked=false;
 try{
  const args=parseManualArguments(process.argv.slice(2));
  pool=createDatabasePool(readDatabaseConfig(process.env));
  const inspection=await inspectManualDocument(pool,args.documentId);
  if(!inspection)throw new Error('Documento guardado no encontrado.');
  console.info(JSON.stringify({documentId:inspection.documentId,contentType:inspection.contentType,sizeBytes:inspection.sizeBytes,processingStatus:inspection.existing?.status??'sin_trabajo'},null,2));
  if(!args.apply){console.info('Solo consulta. No se modificó PostgreSQL ni S3 ni se llamó a la IA.');return;}
  client=await pool.connect();locked=await acquireProcessorLock(client);if(!locked)throw new Error('Procesador automático activo.');
  if(inspection.existing&&inspection.existing.status!=='queued')throw new Error('El trabajo ya está reclamado o terminado; no se repetirá.');
  const config=readStorageConfig(process.env);storage=createStorageClient(config);await checkPrivateBucket(storage,config);
  // Comprobar disponibilidad local antes de reservar un trabajo nuevo.
  const model=inspection.model;
  if(inspection.promptVersion!==3)throw new Error('Versión de prompt no compatible.');
  const response=await fetch(ollamaUrl('tags'),{redirect:'error',signal:AbortSignal.timeout(5000)});
  if(!response.ok)throw new Error('Ollama no disponible.');
  const list=await response.json() as {models?:{name?:string}[]};
  if(!list.models?.some(item=>item.name===model))throw new Error('Modelo local no disponible.');
  const id=await reserveManualProcessing(pool,inspection);if(!id)throw new Error('No se pudo reservar el trabajo.');
  const result=await createProcessingWorker(pool,s3DocumentStorage(storage,config))(id);
  console.info(JSON.stringify(result,null,2));
  if(result.outcome==='processing_error'||result.outcome==='failed'||result.outcome==='not_claimed')process.exitCode=1;
  console.info('El resultado no está aprobado. El documento S3 original se conserva.');
 }catch{process.exitCode=1;console.error('No se pudo completar el procesamiento manual. Revisa documento, estado, migración 006, PostgreSQL, S3 y Ollama local.');}
 finally{if(client&&locked)await releaseProcessorLock(client).catch(()=>undefined);client?.release(true);storage?.destroy();if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
