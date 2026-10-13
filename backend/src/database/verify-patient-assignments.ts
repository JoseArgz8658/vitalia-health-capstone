import {randomUUID} from 'node:crypto';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {createPrivilegedAccount} from '../accounts/privileged';
import {insertPatientAccount} from '../accounts/repository';
import {hashPassword} from '../auth/password';
import {createAssignmentService} from '../assignments/service';
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
  const service=createAssignmentService(db);
  const input={patientEmail:patient.email,professionalEmail:professional.email};
  const first=await service.assign(admin,input),duplicate=await service.assign(admin,input);
  if(!first.changed||duplicate.changed||first.assignment.id!==duplicate.assignment.id)throw new Error('Duplicado inválido.');
  const own=await service.listProfessional(professional);
  if(!own.some(row=>row.id===patient.id)||(await service.listProfessional(other)).some(row=>row.id===patient.id))throw new Error('Aislamiento inválido.');
  const removed=await service.deactivate(admin,first.assignment.id);
  if(!removed.changed||removed.assignment.active||(await service.listProfessional(professional)).some(row=>row.id===patient.id))throw new Error('Desactivación inválida.');
  if((await service.deactivate(admin,first.assignment.id)).changed)throw new Error('Desactivación repetida.');
  const restored=await service.assign(admin,input);
  if(!restored.changed||restored.assignment.id!==first.assignment.id)throw new Error('Reactivación inválida.');
  const audit=await client.query<{action:string;actor_id:string}>(`SELECT action,actor_id FROM public.vitalia_assignment_audit WHERE assignment_id=$1`,[first.assignment.id]);
  if(audit.rows.length!==3||audit.rows.filter(row=>row.action==='activate').length!==2||audit.rows.some(row=>row.actor_id!==admin.id))throw new Error('Auditoría inválida.');
  await client.query('ROLLBACK');started=false;
  console.info('Asignaciones, aislamiento y auditoría correctos. Datos sintéticos revertidos.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo verificar asignaciones. Revisa PostgreSQL y migración 007.');}
 finally{
  if(started&&client)try{await client.query('ROLLBACK');}catch{failed=true;}
  client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});
 }
}
void main();
