import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {loadTerritorialCatalog} from './territorial-catalog';
async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,failed=false;
 try{
  // Carga administrativa deliberada para el entorno local validado del equipo.
  const config=readDatabaseConfig(process.env);
  if(config.database!=='vitalia_dev')throw new Error('Base inesperada.');
  const text=await readFile(resolve(__dirname,'../../database/catalogs/chile-cut-2018.json'),'utf8');
  if(createHash('sha256').update(text.replace(/\r\n/g,'\n')).digest('hex')!=='6abd3fc3c73cc687ad4e1d8b01b83981026716456c0f70bc02c690f61565ca03')throw new Error('Catálogo alterado.');
  pool=createDatabasePool(config);client=await pool.connect();
  const result=await loadTerritorialCatalog(client,JSON.parse(text));
  console.info(result==='loaded'?'Catálogo territorial cargado: 16 regiones, 56 provincias y 346 comunas.':'El catálogo territorial ya estaba cargado y coincide.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo cargar el catálogo. Revisa vitalia_dev, migración 012, permisos administrativos e integridad del archivo. No se sobrescriben datos territoriales distintos.');}
 finally{client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
