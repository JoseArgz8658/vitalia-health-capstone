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
    // En Vitalia principal el servicio migrate de Compose sirve SOLO
    // como verificador de esquema ya integrado (nunca modifica SQL).
    // La aplicación real debe instalarse mediante migrate-main-sil --apply,
    // después de restauración aislada y aprobación explícita.
    if(config.database==='vitalia'){
      pool=createDatabasePool(config);
      client=await pool.connect();
      await client.query('BEGIN READ ONLY');
      const ready=await client.query<{ok:boolean}>(
        `SELECT
          to_regclass('public.vitalia_account_roles') IS NOT NULL
          AND to_regclass('public.vitalia_sil_main_laboratories') IS NOT NULL
          AND to_regclass('public.vitalia_sil_main_reports') IS NOT NULL
          AND to_regclass('public.vitalia_sil_main_operator_invites') IS NOT NULL
          AND EXISTS (SELECT 1 FROM public.vitalia_schema_migrations
            WHERE version='012_preliminary_assistant')
          AND EXISTS (SELECT 1 FROM public.vitalia_schema_migrations
            WHERE version='012_profiles_locations')
          AND EXISTS (SELECT 1 FROM public.vitalia_schema_migrations
            WHERE version='032_sil_audit_download')
          AND EXISTS (SELECT 1 FROM public.vitalia_schema_migrations
            WHERE version='038_sil_main_postanalytical')
          AND EXISTS (SELECT 1 FROM public.vitalia_schema_migrations
            WHERE version='039_sil_main_operator_review')
          AND NOT EXISTS (SELECT 1 FROM public.vitalia_schema_migrations
            WHERE left(version,3) BETWEEN '033' AND '037') AS ok`);
      if(ready.rows[0]?.ok!==true){
        throw new Error('Base principal aún no integrada: no se aplicará ninguna migración automática.');
      }
      await client.query('COMMIT');
      console.info('Vitalia principal: esquema SIL 039 verificado en solo lectura.');
      return;
    }
    // La migración automática solo se conserva para vitalia_dev aislada.
    if(config.database!=='vitalia_dev') {
      throw new Error('Migrador no autorizado para esta base.');
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
