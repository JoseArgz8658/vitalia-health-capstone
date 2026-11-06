import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {verifyTeam} from './team-verification';

async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  const config=readDatabaseConfig(process.env);
  if(config.database!=='vitalia_dev')throw new Error('Base inesperada.');
  pool=createDatabasePool(config);client=await pool.connect();
  const checks=await verifyTeam(client);
  console.info(`Gestión del equipo: ${checks} comprobaciones correctas. Datos sintéticos revertidos.`);
 }catch{failed=true;process.exitCode=1;console.error('No se pudo verificar gestión del equipo. Revisa PostgreSQL, permisos y migración 016.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
