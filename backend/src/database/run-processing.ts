import {setTimeout as pause} from 'node:timers/promises';
import {type Pool,type PoolClient} from 'pg';
import {type S3Client} from '@aws-sdk/client-s3';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {readStorageConfig} from '../storage/config';
import {createStorageClient,checkPrivateBucket} from '../storage/s3';
import {s3DocumentStorage} from '../documents/storage-adapter';
import {createProcessingWorker} from '../processing/worker';
import {UnconfirmedProcessingError,acquireProcessorLock,releaseProcessorLock,recoverInterruptedProcessing,createQueueProcessor} from '../processing/queue';
import {ollamaUrl} from '../runtime/local-services';
async function availableModels(){
 const response=await fetch(ollamaUrl('tags'),{redirect:'error',signal:AbortSignal.timeout(5000)});
 if(!response.ok)throw new Error('IA local no disponible.');
 const value=await response.json() as {models?:{name?:unknown}[]};
 return Array.isArray(value.models)?value.models.flatMap(item=>typeof item.name==='string'&&/^[a-zA-Z0-9_.:-]{1,100}$/.test(item.name)&&!item.name.toLowerCase().includes('cloud')?[item.name]:[]):[];
}
async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,storage:S3Client|undefined,locked=false,failed=false;
 const stop=new AbortController();const onStop=()=>stop.abort();process.on('SIGINT',onStop);process.on('SIGTERM',onStop);
 try{
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();
  locked=await acquireProcessorLock(client);if(!locked)throw new Error('Ya hay un procesador activo.');
  const config=readStorageConfig(process.env);storage=createStorageClient(config);await checkPrivateBucket(storage,config);
  const interrupted=await recoverInterruptedProcessing(client);
  console.info(`Procesador automático iniciado. Trabajos interrumpidos señalados: ${interrupted}.`);
  const tick=createQueueProcessor(client,createProcessingWorker(client,s3DocumentStorage(storage,config)),availableModels);
  let warned=false;
  while(!stop.signal.aborted){
   try{
    const result=await tick();
    if(result.state==='model_unavailable'){if(!warned)console.info('Esperando un modelo local instalado; los trabajos permanecen pendientes.');warned=true;}
    else{warned=false;if(result.state==='processed')console.info(JSON.stringify(result.result));}
   }catch(error){
    if(error instanceof UnconfirmedProcessingError)throw error;
    // Comprobar conexión: una sesión perdida ya no garantiza el bloqueo exclusivo.
    try{await client.query('SELECT 1');}catch{throw new Error('Conexión del procesador perdida.');}
    if(!warned)console.error('Procesamiento temporalmente no disponible. Revisa Ollama y servicios locales.');warned=true;
   }
   if(!stop.signal.aborted)await pause(2000,undefined,{signal:stop.signal}).catch(()=>undefined);
  }
  console.info('Procesador detenido; el trabajo activo terminó antes del cierre.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo mantener el procesador. Revisa PostgreSQL, migraciones, S3 y que no haya otro procesador activo.');}
 finally{
  process.off('SIGINT',onStop);process.off('SIGTERM',onStop);
  if(client&&locked)try{await releaseProcessorLock(client);}catch{failed=true;}
  client?.release(failed);storage?.destroy();if(pool)await pool.end().catch(()=>{process.exitCode=1;});
 }
}
void main();
