import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {applyAdditionalMigration} from './additional-migration';
async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  const sql=await readFile(resolve(__dirname,'../../database/migrations/011_exam_assistant.sql'),'utf8');
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();
  const result=await applyAdditionalMigration(client,'011_exam_assistant',sql,'010_exam_explanations');
  console.info(result==='applied'?'Migración de asistente por examen aplicada.':'La migración de asistente por examen ya estaba aplicada.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo aplicar la migración de asistente por examen. Revisa PostgreSQL y la migración previa 010.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
