import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {applyAdditionalMigration} from './additional-migration';

async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  const sql=await readFile(resolve(__dirname,'../../database/migrations/022_care_inbox.sql'),'utf8');
  const config=readDatabaseConfig(process.env);
  if(config.database!=='vitalia_dev')throw new Error('Base inesperada.');
  pool=createDatabasePool(config);client=await pool.connect();
  const result=await applyAdditionalMigration(client,'022_care_inbox',sql,'021_care_upload');
  console.info(result==='applied'?'Migración de bandeja por examen aplicada.':'La migración de bandeja por examen ya estaba aplicada.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo aplicar la migración 022. Revisa permisos, migración 021 e integridad del esquema.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
