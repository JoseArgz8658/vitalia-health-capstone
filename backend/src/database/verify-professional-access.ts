import {randomUUID} from 'node:crypto';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {createPrivilegedAccount} from '../accounts/privileged';
import {insertPatientAccount} from '../accounts/repository';
import {hashPassword} from '../auth/password';
import {createAssignmentService} from '../assignments/service';
import {reserveDocument,completeDocument} from '../documents/repository';
import {createProfessionalService,ProfessionalNotFoundError} from '../professional/service';
import {queueDocumentProcessing,claimDocumentProcessing,completeDocumentProcessing} from '../processing/repository';
async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,started=false,failed=false;
 try{
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();
  await client.query('BEGIN');started=true;
  const password=randomUUID();
  const create=(role:'administrador'|'profesional')=>createPrivilegedAccount(client!,{email:randomUUID()+'@example.invalid',role,password,confirmation:password});
  const admin=await create('administrador'),professional=await create('profesional'),other=await create('profesional');
  const patient=await insertPatientAccount(client,randomUUID()+'@example.invalid',await hashPassword(password));
  const db={query:client.query.bind(client) as Pool['query'],transaction:async<T>(work:(db:Pick<Pool,'query'>)=>Promise<T>)=>work(client!)};
  const assignments=createAssignmentService(db);
  const relation=await assignments.assign(admin,{patientEmail:patient.email,professionalEmail:professional.email});
  const body=Buffer.from('%PDF-1.4\nDocumento ficticio\n%%EOF');
  const doc=await reserveDocument(client,patient,{examName:'Prueba acceso profesional',examType:'Laboratorio',examDate:'2026-01-01',originalName:'ficticio.pdf',contentType:'application/pdf',sizeBytes:body.length});
  await completeDocument(client,patient,doc.id);
  const processingId=await queueDocumentProcessing(client,patient,doc.id);if(!processingId)throw new Error();
  await claimDocumentProcessing(client,processingId);
  const text='Examen ficticio';
  await completeDocumentProcessing(client,processingId,{status:'requires_review',source:'pdf',method:'direct',reading:{status:'text_ready',text,pageCount:1,incidents:[]},ocr:null,inputText:text,
   ai:{status:'requires_review',raw:'{"examen":"Examen ficticio","fecha":null,"resultados":[]}',extraction:{examen:'Examen ficticio',fecha:null,resultados:[]},incidents:[],approved:false,model:'qwen3:4b-instruct',promptVersion:3,elapsedMs:1},approved:false});
  // Almacenamiento sustituido con bytes ficticios: no escribe ni lee S3 real.
  const service=createProfessionalService(db,{read:async()=>body});
  if(!(await service.list(professional,patient.id)).some(item=>item.id===doc.id))throw new Error();
  const view=await service.extraction(professional,patient.id,doc.id);
  if(view.processing.extraction?.examen!=='Examen ficticio'||view.processing.approved!==false)throw new Error();
  if(!(await service.download(professional,patient.id,doc.id)).body.equals(body))throw new Error();
  async function denied(work:()=>Promise<unknown>){try{await work();}catch(error){if(error instanceof ProfessionalNotFoundError)return;throw error;}throw new Error('Acceso indebido.');}
  await denied(()=>service.list(other,patient.id));
  await assignments.deactivate(admin,relation.assignment.id);
  await denied(()=>service.extraction(professional,patient.id,doc.id));
  await denied(()=>service.download(professional,patient.id,doc.id));
  const audit=await client.query<{action:string;professional_id:string}>(`SELECT action,professional_id FROM public.vitalia_professional_access_audit WHERE patient_id=$1`,[patient.id]);
  if(audit.rows.length!==3||audit.rows.some(row=>row.professional_id!==professional.id)||new Set(audit.rows.map(row=>row.action)).size!==3)throw new Error('Auditoría inválida.');
  await client.query('ROLLBACK');started=false;
  console.info('Acceso profesional, aislamiento y auditoría correctos. Datos sintéticos revertidos; S3 sustituido.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo verificar acceso profesional. Revisa PostgreSQL y migración 008.');}
 finally{
  if(started&&client)try{await client.query('ROLLBACK');}catch{failed=true;}
  client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});
 }
}
void main();
