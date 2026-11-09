import {readFile,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {silMainRehearsedPlan} from './sil-migration-policy';

const old012='012_preliminary_assistant';
const newer012='012_profiles_locations';
const foundation='038_sil_main_postanalytical';
const finalName='039_sil_main_operator_review';
const sha=(sql:string)=>createHash('sha256')
  .update(sql.replace(/\r\n/g,'\n')).digest('hex');

async function main(){
  const args=process.argv.slice(2);
  const rehearse=args.length===1&&args[0]==='--rehearse';
  const apply=args.length===1&&args[0]==='--apply';
  const status=args.length===1&&args[0]==='--status';
  if(!apply&&!status&&!rehearse){
    console.error('Uso: node dist/database/migrate-main-sil.js --status|--apply|--rehearse');
    process.exitCode=1;return;
  }
  const config=readDatabaseConfig(process.env);
  const expectedDatabase=rehearse?'vitalia_restored':'vitalia';
  if(config.database!==expectedDatabase ||
    process.env.VITALIA_SIL_DEMO==='YES' ||
    process.env.VITALIA_SIL_PORTAL_MIGRATION_DEMO==='YES'){
    console.error('BLOQUEADO: la base no corresponde al modo de migración solicitado.');
    process.exitCode=1;return;
  }
  if(rehearse &&
    (process.env.VITALIA_ISOLATED_REHEARSAL!=='YES' ||
     process.env.PGHOST!=='127.0.0.1' || config.user!=='vitalia_restore')){
    console.error('BLOQUEADO: el ensayo requiere una copia temporal y conexión loopback explícita.');
    process.exitCode=1;return;
  }
  if(apply &&
    (process.env.VITALIA_MAIN_SIL_APPLY!=='CONFIRMED_AFTER_ISOLATED_TEST' ||
     !/^[a-fA-F0-9]{64}$/.test(process.env.VITALIA_MAIN_BACKUP_SHA256??''))){
    console.error('BLOQUEADO: se exige respaldo verificable y aprobación de migración.');
    process.exitCode=1;return;
  }
  const directory=resolve(__dirname,'../../database/migrations');
  const files=(await readdir(directory)).filter(file=>/^\d{3}_[a-z_]+\.sql$/.test(file));
  const plan=[...silMainRehearsedPlan(files),foundation+'.sql',finalName+'.sql'];
  if(!plan.every(file=>files.includes(file)))throw new Error('Faltan migraciones del SIL principal.');
  const allFiles=[
    ...files.filter(file=>/^0(?:0[1-9]|1[01])_/.test(file)),
    ...plan,
  ];
  const code=new Map<string,string>();
  for(const file of allFiles) {
    const version=file.slice(0,-4);
    code.set(version,await readFile(resolve(directory,file),'utf8'));
  }

  const pool=createDatabasePool(config);
  const client=await pool.connect();
  let broken=false;
  try{
    await client.query(status?'BEGIN READ ONLY':'BEGIN');
    await client.query(
      'SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-health-migrations']);
    const db=await client.query<{database:string;isolated:boolean}>(
      `SELECT current_database() AS database,
        current_user='vitalia_restore' AND inet_server_addr()='127.0.0.1'::inet AS isolated`);
    if(db.rows[0]?.database!==expectedDatabase || (rehearse && db.rows[0].isolated!==true)){
      throw new Error('La conexión no corresponde a la base solicitada.');
    }
    const history=await client.query<{version:string;checksum:string}>(
      'SELECT version,checksum FROM public.vitalia_schema_migrations ORDER BY version');
    const ledger=new Map(history.rows.map(row=>[row.version,row.checksum]));
    for(const [version,sql] of code){
      if(Number(version.slice(0,3))<=11 && ledger.get(version)!==sha(sql)){
        throw new Error('Checksum histórico no coincide: '+version);
      }
    }
    if(!ledger.has(old012)|| !/^[a-f0-9]{64}$/.test(ledger.get(old012)??'')){
      throw new Error('Historial 012 original no coincide.');
    }
    if([...ledger.keys()].some(v=>/^03[3-7]_/.test(v))){
      throw new Error('Migraciones DEMO 033-037 detectadas: operación bloqueada.');
    }
    const legacySchema=await client.query<{ok:boolean}>(
      `SELECT EXISTS(SELECT 1 FROM information_schema.columns
        WHERE table_schema='public'
        AND table_name='vitalia_exam_assistant_threads'
        AND column_name='processing_id' AND data_type='uuid')
        AND EXISTS(SELECT 1 FROM information_schema.columns
        WHERE table_schema='public'
        AND table_name='vitalia_exam_assistant_threads'
        AND column_name='review_id' AND is_nullable='YES') AS ok`);
    if(legacySchema.rows[0]?.ok!==true)
      throw new Error('Esquema legado de asistente 012 incompatible.');

    if(status){
      console.info('BASE: vitalia. Sólo lectura.');
      console.info('Historial original 012: verificado.');
      console.info('Migraciones registradas: '+history.rows.length);
      console.info('Plan permitido: 012_profiles_locations, 013–032, 038–039.');
      console.info('Excluidas: 033–037 DEMO.');
      console.info('No se escribió ninguna tabla.');
      await client.query('COMMIT');
      return;
    }

    const already=ledger.has(finalName);
    if(already){
      for(const version of plan.map(name=>name.slice(0,-4))){
        if(ledger.get(version)!==sha(code.get(version)!)){
          throw new Error('Migración aplicada con huella inesperada: '+version);
        }
      }
      console.info('SIL principal ya registrado. Sin cambios.');
      await client.query('COMMIT');
      return;
    }
    if(history.rows.length!==12 ||
      [...plan].some(file=>ledger.has(file.slice(0,-4))) ||
      [...ledger.keys()].some(v=>/^01[3-9]_|^02[0-9]_|^03[0-2]_/.test(v))){
      throw new Error('Historial parcial o inesperado. No se puede aplicar automáticamente.');
    }

    // Capturar en tablas TEMPORALES las filas históricas (no se imprimen).
    // Un UPDATE/DELETE inadvertido provoca ROLLBACK de toda la migración.
    await client.query(`CREATE TEMP TABLE _sil_original_rows
      (relation text NOT NULL,snapshot jsonb NOT NULL) ON COMMIT DROP`);
    const relations=await client.query<{tablename:string}>(
      `SELECT tablename FROM pg_tables
       WHERE schemaname='public' AND left(tablename,8)='vitalia_'
         AND tablename NOT IN('vitalia_schema_migrations','vitalia_sessions')
       ORDER BY tablename`);
    for(const row of relations.rows) {
      const name=row.tablename;
      if(!/^vitalia_[a-z_]+$/.test(name))throw new Error('Nombre de tabla inválido.');
      await client.query(
        `INSERT INTO _sil_original_rows
         SELECT $1,to_jsonb(t) FROM public."${name}" t`,[name]);
    }
    await client.query(`INSERT INTO _sil_original_rows
      VALUES('vitalia_roles','{"code":"operador_laboratorio"}'::jsonb),
            ('vitalia_roles','{"code":"validador_laboratorio"}'::jsonb)`);
    await client.query(`CREATE TEMP TABLE _sil_original_sessions ON COMMIT DROP AS
      SELECT to_jsonb(s)||jsonb_build_object('active_role',a.role_code) AS snapshot
      FROM public.vitalia_sessions s
      JOIN public.vitalia_accounts a ON a.id=s.account_id`);

    await client.query("SET LOCAL lock_timeout = '5s'");
    // Cada una se ejecuta dentro de la MISMA transacción PostgreSQL;
    // no permitir estados parcialmente actualizados en Vitalia principal.
    for(const file of plan){
      const version=file.slice(0,-4);
      const sql=code.get(version)!;
      await client.query(sql);
      await client.query(
        'INSERT INTO public.vitalia_schema_migrations(version,checksum) VALUES($1,$2)',
        [version,sha(sql)]);
      console.info('Migración ejecutada en transacción: '+version);
    }
    await client.query('SET CONSTRAINTS ALL IMMEDIATE');
    for(const row of relations.rows){
      const name=row.tablename;
      const data=await client.query<{changed:boolean}>(
        `WITH before_rows AS (
           SELECT snapshot FROM _sil_original_rows WHERE relation=$1
         ),after_rows AS(
           SELECT CASE WHEN $1='vitalia_documents'
              AND to_jsonb(t)->'care_flow'='false'::jsonb
             THEN to_jsonb(t)-'care_flow' ELSE to_jsonb(t) END AS snapshot
           FROM public."${name}" t
         )
         SELECT EXISTS(
           (TABLE before_rows EXCEPT ALL TABLE after_rows)
           UNION ALL
           (TABLE after_rows EXCEPT ALL TABLE before_rows)
         ) AS changed`,[name]);
      if(data.rows[0]?.changed!==false){
        throw new Error('Datos históricos alterados en: '+name);
      }
    }
    const sessions=await client.query<{changed:boolean}>(
      `SELECT EXISTS(
        (SELECT snapshot FROM _sil_original_sessions
         EXCEPT ALL SELECT to_jsonb(s) FROM public.vitalia_sessions s)
        UNION ALL
        (SELECT to_jsonb(s) FROM public.vitalia_sessions s
         EXCEPT ALL SELECT snapshot FROM _sil_original_sessions)
       ) AS changed`);
    if(sessions.rows[0]?.changed!==false)
      throw new Error('Sesiones originales alteradas.');
    const verified=await client.query<{ok:boolean}>(
      `SELECT
        (SELECT count(*)=35 FROM public.vitalia_schema_migrations)
        AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations
          WHERE version='012_preliminary_assistant')
        AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations
          WHERE version='012_profiles_locations')
        AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations
          WHERE version=$1)
        AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version=$2)
        AND NOT EXISTS (
          (SELECT id,role_code FROM public.vitalia_accounts
           EXCEPT ALL SELECT account_id,role_code FROM public.vitalia_account_roles)
          UNION ALL
          (SELECT account_id,role_code FROM public.vitalia_account_roles
           EXCEPT ALL SELECT id,role_code FROM public.vitalia_accounts)
        )
        AND to_regclass('public.vitalia_sil_main_reports') IS NOT NULL
        AS ok`,[foundation,finalName]);
    if(verified.rows[0]?.ok!==true)throw new Error('Estado final inválido.');
    await client.query('COMMIT');
    console.info(rehearse
      ?'SIL PRINCIPAL 012–032 + 038–039 ENSAYADO EN COPIA AISLADA. Migraciones en copia: 35.'
      :'SIL principal migrado 012–032 + 038–039; DEMO 033–037 omitida.');
    console.info('Historial, cuentas y sesiones originales preservados.');
  }catch(error){
    try{await client.query('ROLLBACK');}catch{broken=true;}
    process.exitCode=1;
    console.error('MIGRACIÓN NO COMPLETADA: transacción revertida o abortada.');
    console.error(error instanceof Error?error.message:'Error inesperado.');
  }finally{
    client.release(broken);
    await pool.end();
  }
}
void main().catch(()=>{
  process.exitCode=1;
  console.error('No se pudo planificar el SIL principal.');
});
