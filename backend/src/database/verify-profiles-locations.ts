import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {verifyProfilesLocations} from './profiles-locations-verification';

async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();
  const checks=await verifyProfilesLocations(client);
  console.info(`Perfiles y ubicación: ${checks} comprobaciones correctas. Datos sintéticos revertidos.`);
 }catch{failed=true;process.exitCode=1;console.error('No se pudo verificar perfiles y ubicación. Revisa PostgreSQL, permisos y migración 012.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
