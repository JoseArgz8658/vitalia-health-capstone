import {readFile,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {applyAccountsMigration} from './accounts-migration';
import {applyAdditionalMigration} from './additional-migration';
async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  const directory=resolve(__dirname,'../../database/migrations');
  const files=(await readdir(directory)).filter(file=>/^\d{3}_[a-z_]+\.sql$/.test(file)).sort();
  if(files[0]!=='001_accounts.sql')throw new Error('Migraciones incompletas.');
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();let previous='';
  for(const file of files){
   const version=file.slice(0,-4),sql=await readFile(resolve(directory,file),'utf8');
   const result=previous?await applyAdditionalMigration(client,version,sql,previous):await applyAccountsMigration(client,sql);
   console.info(`${version}: ${result==='applied'?'aplicada':'ya aplicada'}.`);previous=version;
  }
 }catch{failed=true;process.exitCode=1;console.error('No se pudieron completar las migraciones. Revisa PostgreSQL y la integridad de los archivos SQL.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
