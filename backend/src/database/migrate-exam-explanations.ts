import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {applyAdditionalMigration} from './additional-migration';
async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  const sql=await readFile(resolve(__dirname,'../../database/migrations/010_exam_explanations.sql'),'utf8');
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();
  const result=await applyAdditionalMigration(client,'010_exam_explanations',sql,'009_professional_reviews');
  console.info(result==='applied'?'Migración de explicaciones de exámenes aplicada.':'La migración de explicaciones de exámenes ya estaba aplicada.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo aplicar la migración de explicaciones de exámenes. Revisa PostgreSQL y la migración previa 009.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
