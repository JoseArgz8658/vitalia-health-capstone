import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {verifyAccountModes} from './account-modes-verification';

async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  const config=readDatabaseConfig(process.env);
  if(config.database!=='vitalia_dev')throw new Error('Base inesperada.');
  pool=createDatabasePool(config);client=await pool.connect();
  const checks=await verifyAccountModes(client);
  console.info(`Modos de cuenta: ${checks} comprobaciones correctas. Datos sintéticos revertidos.`);
 }catch{failed=true;process.exitCode=1;console.error('No se pudo verificar modos de cuenta. Revisa PostgreSQL, permisos y migración 017.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
