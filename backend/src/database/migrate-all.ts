import {readFile,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {applyAccountsMigration} from './accounts-migration';
import {applyAdditionalMigration} from './additional-migration';
import {silDemoMigrationPlan} from './sil-migration-policy';

/**
 * Migrador LEGADO de la base aislada vitalia_dev.
 * La base principal vitalia tiene una migración 012 histórica distinta y
 * NUNCA se debe recorrer automáticamente con el migrador de la DEMO.
 */
async function main() {
  let pool:Pool|undefined;
  let client:PoolClient|undefined;
  let failed=false;
  try {
    const config=readDatabaseConfig(process.env);
    // Fallar ANTES de abrir la conexión o ejecutar cualquier SQL.
    if(config.database!=='vitalia_dev') {
      throw new Error('Migrador bloqueado para Vitalia principal.');
    }
    const directory=resolve(__dirname,'../../database/migrations');
    const files=(await readdir(directory))
      .filter(file=>/^\d{3}_[a-z_]+\.sql$/.test(file));
    const selected=silDemoMigrationPlan(
      files,config.database,process.env.VITALIA_SIL_PORTAL_MIGRATION_DEMO==='YES');
    pool=createDatabasePool(config);
    client=await pool.connect();
    let previous='';
    for(const file of selected){
      const version=file.slice(0,-4);
      const sql=await readFile(resolve(directory,file),'utf8');
      const result=previous
        ?await applyAdditionalMigration(client,version,sql,previous)
        :await applyAccountsMigration(client,sql);
      console.info(`${version}: ${result==='applied'?'aplicada':'ya aplicada'}.`);
      previous=version;
    }
  }catch(error) {
    failed=true;
    process.exitCode=1;
    console.error('Migrador general bloqueado o fallido. '
      +'No usarlo con vitalia principal; consulta el PR de integración SIL.');
  }finally{
    client?.release(failed);
    if(pool)await pool.end().catch(()=>{process.exitCode=1;});
  }
}
void main();
