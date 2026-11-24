import {createHash} from 'node:crypto';
import {readdir,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {PoolClient} from 'pg';
import {createApp} from '../app';
import {createCredentialAuthenticator} from '../auth/credentials';
import {createPatientRegistrar} from '../auth/registration';
import {hashPassword} from '../auth/password';
import {findSessionAccount,issueSession,revokeSession} from '../auth/sessions';
import {createSilMainService} from '../sil/main-service';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {silMainRehearsedPlan} from './sil-migration-policy';

import {seedUsability} from './seed-sil-demo';

const database='vitalia_usability';
const digest=(input:string|Buffer)=>createHash('sha256').update(input).digest('hex');
const admin='082d7672-6c6d-4db2-8b33-cd62b9c861f0';

async function bootstrap(tx:PoolClient){
  const tables=await tx.query(`SELECT tablename FROM pg_tables WHERE schemaname='public'`);
  if(tables.rows.length)throw new Error('Showcase exige una base vacía o inicializada por el generador.');
  const directory=resolve(__dirname,'../../database/migrations');
  const files=(await readdir(directory)).filter(file=>/^\d{3}_[a-z_]+\.sql$/.test(file)).sort();
  const plan=[...files.filter(file=>/^0(?:0[1-9]|1[01])_/.test(file)),
    ...silMainRehearsedPlan(files),...files.filter(file=>/^0(?:3[89]|4[0-6])_/.test(file))];
  if(plan.length!==41)throw new Error('El conjunto de migraciones showcase cambió.');
  await tx.query(`CREATE TABLE public.vitalia_schema_migrations (
    version text PRIMARY KEY,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())`);
  for(const file of plan){
    const sql=await readFile(resolve(directory,file),'utf8');
    await tx.query(sql);
    await tx.query('INSERT INTO public.vitalia_schema_migrations(version,checksum) VALUES ($1,$2)',
      [file.slice(0,-4),digest(sql.replace(/\r\n/g,'\n'))]);
  }
}

async function seed(tx:PoolClient){
  const [administrator,operator,patient]=await Promise.all(['ADMIN','OPERATOR','PATIENT'].map(role=>{
    const password=process.env['SHOWCASE_'+role+'_PASSWORD'];
    if(!password||password.length<24)throw new Error('Faltan credenciales locales del entorno de pruebas.');
    return hashPassword(password);
  }));
  await tx.query('INSERT INTO vitalia_accounts(id,email,role_code,password_hash) VALUES ($1,$2,$3,$4)',
    [admin,'admin@showcase.example.invalid','administrador',administrator]);
  await seedUsability(tx,admin,{operator,patient});
}

async function main(){
  const config=readDatabaseConfig(process.env);
  if(process.env.VITALIA_SHOWCASE!=='YES'||config.database!==database||config.user!==database||
    process.env.VITALIA_SIL_MAIN_MODE!=='YES')throw new Error('Conexión showcase requerida.');
  const pool=createDatabasePool(config);
  try{
    const tx=await pool.connect();
    try{
      await tx.query('BEGIN');
      const identity=await tx.query('SELECT current_database() AS database, current_user AS actor');
      if(identity.rows[0].database!==database||identity.rows[0].actor!==database)
        throw new Error('La conexión PostgreSQL no corresponde al showcase.');
      await tx.query("SELECT pg_advisory_xact_lock(hashtext('vitalia-showcase-init'))");
      const marker=await tx.query("SELECT to_regclass('public.vitalia_showcase_initialized') IS NOT NULL AS ready");
      if(!marker.rows[0].ready){
        await bootstrap(tx);
        await seed(tx);
        await tx.query('CREATE TABLE public.vitalia_showcase_initialized (created_at timestamptz DEFAULT now())');
        await tx.query('INSERT INTO public.vitalia_showcase_initialized DEFAULT VALUES');
      }
      await tx.query('COMMIT');
    } catch(error){
      await tx.query('ROLLBACK');
      throw error;
    } finally {
      tx.release();
    }
    if(process.argv[2]==='--seed-only'){
      await pool.end();
      return;
    }
    const authenticate=await createCredentialAuthenticator(pool,{guardPatientSession:true});
    createApp({
      authenticate,
      issue:(account,mode,hash)=>issueSession(pool,account,mode,hash),
      find:token=>findSessionAccount(pool,token),
      revoke:token=>revokeSession(pool,token),
    },createPatientRegistrar(pool,{demoOnly:true}),undefined,undefined,undefined,undefined,undefined,undefined,undefined,
    undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,
    undefined,undefined,createSilMainService(pool)).listen(Number(process.env.PORT??3000),
      process.env.VITALIA_RUNTIME==='container'?'0.0.0.0':'127.0.0.1');
  } catch(error){
    await pool.end();
    throw error;
  }
}

void main().catch(error=>{
  console.error('Showcase:',error instanceof Error ? error.message : 'error de inicialización');
  process.exitCode=1;
});
