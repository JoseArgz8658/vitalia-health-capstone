import {type Pool} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';

async function main(){
 let pool:Pool|undefined;
 try{
  const config=readDatabaseConfig(process.env);
  if(config.database!=='vitalia_dev')throw new Error('Base inesperada.');
  pool=createDatabasePool(config);
  const result=await pool.query<{ready:boolean}>(`SELECT
   EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='025_preliminary_assistant')
   AND EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='vitalia_exam_assistant_threads' AND column_name='processing_id' AND data_type='uuid')
   AND EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='vitalia_exam_assistant_threads' AND column_name='review_id' AND is_nullable='YES')
   AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.vitalia_exam_assistant_threads'::regclass AND conname='vitalia_assistant_one_source' AND contype='c' AND convalidated)
   AND EXISTS(SELECT 1 FROM pg_index WHERE indexrelid=to_regclass('public.vitalia_assistant_processing_unique') AND indisunique AND indisvalid)
   AND to_regclass('public.vitalia_current_approved_reviews') IS NOT NULL
   AND has_column_privilege('vitalia_app','public.vitalia_exam_assistant_threads','processing_id','INSERT')
   AND has_table_privilege('vitalia_app','public.vitalia_current_approved_reviews','SELECT') AS ready`);
  if(result.rows[0]?.ready!==true)throw new Error('Compatibilidad incompleta.');
  console.info('Compatibilidad del asistente preliminar: esquema 025 y permisos correctos. Verificación de solo lectura.');
 }catch{process.exitCode=1;console.error('No se pudo verificar el asistente preliminar. Revisa la migración 025 y los permisos de vitalia_app.');}
 finally{if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
