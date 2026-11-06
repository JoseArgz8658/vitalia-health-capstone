import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {applyAdditionalMigration} from './additional-migration';

async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  const sql=await readFile(resolve(__dirname,'../../database/migrations/012_profiles_locations.sql'),'utf8');
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();
  const result=await applyAdditionalMigration(client,'012_profiles_locations',sql,'011_exam_assistant');
  console.info(result==='applied'?'Migración de perfiles y ubicación aplicada.':'La migración de perfiles y ubicación ya estaba aplicada.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo aplicar la migración 012. Revisa permisos, migración 011 e integridad del esquema.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
