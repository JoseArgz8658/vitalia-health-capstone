import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
import {type DocumentDatabase} from '../documents/service';
import {type AccountSummary} from '../accounts/repository';
import {createInstitutionService} from '../institutions/service';
export async function verifyInstitutions(client:Pick<PoolClient,'query'>):Promise<number>{
 let started=false,checks=0;const check=(v:boolean)=>{if(!v)throw new Error('Verificación institucional incorrecta.');checks++;};
 try{
  await client.query('BEGIN');started=true;
  if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['014_institution_audit'])).rows.length)throw new Error('Falta migración 014.');
  const actor=randomUUID(),cid=randomUUID(),cid2=randomUUID(),bid=randomUUID();
  await client.query(`INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login','administrador')`,[actor,actor+'@example.invalid']);
  const commune=(await client.query('SELECT code FROM public.vitalia_communes ORDER BY code LIMIT 1')).rows[0]?.code;
  if(!commune)throw new Error('Falta catálogo territorial.');
  const db={query:client.query.bind(client),transaction:async(work:(db:Pick<PoolClient,'query'>)=>Promise<unknown>)=>{
   await client.query('SAVEPOINT institution_work');try{const r=await work(client);await client.query('RELEASE SAVEPOINT institution_work');return r;}catch(e){await client.query('ROLLBACK TO SAVEPOINT institution_work');await client.query('RELEASE SAVEPOINT institution_work');throw e;}
  }} as DocumentDatabase;
  const service=createInstitutionService(db),a={id:actor,role:'administrador'} as AccountSummary;
  const input={requestId:cid,name:'Clínica sintética '+cid,contactPhone:null};
  const c=await service.create(a,input);check(c.created&&c.item.id===cid);
  check(!(await service.create(a,input)).created);
  let conflict=false;try{await service.create(a,{...input,name:'Distinta'});}catch(e){conflict=(e as {status:number}).status===409;}check(conflict);
  await service.create(a,{...input,requestId:cid2,name:'Otra clínica sintética '+cid2});
  const branch={requestId:bid,name:'Sucursal sintética',communeCode:commune,street:'Calle ficticia',addressNumber:'S/N',floor:null,unit:null,contactPhone:null};
  check((await service.createBranch(a,cid,branch)).created);check(!(await service.createBranch(a,cid,branch)).created);
  let wrong=false;try{await service.createBranch(a,cid2,branch);}catch(e){wrong=(e as {status:number}).status===409;}check(wrong);
  let missing=false;try{await service.createBranch(a,cid,{...branch,requestId:randomUUID(),communeCode:'99999'});}catch(e){missing=(e as {status:number}).status===400;}check(missing);
  const rows=await service.branches(a,cid);check(rows.length===1&&rows[0].clinicId===cid);
  check((await service.branches(a,cid2)).length===0);
  const audit=await client.query('SELECT actor_id,action FROM public.vitalia_institution_audit WHERE clinic_id IN($1,$2)',[cid,cid2]);
  check(audit.rows.length===3&&audit.rows.every(x=>x.actor_id===actor));
  check(audit.rows.filter(x=>x.action==='branch_created').length===1);
  for(const role of ['paciente','profesional']){let denied=false;try{await service.list({...a,role} as AccountSummary);}catch(e){denied=(e as {status:number}).status===403;}check(denied);}
  await client.query('UPDATE public.vitalia_clinics SET active=false WHERE id=$1',[cid]);
  let inactive=false;try{await service.createBranch(a,cid,{...branch,requestId:randomUUID()});}catch(e){inactive=(e as {status:number}).status===409;}check(inactive);
  return checks;
 }finally{if(started)await client.query('ROLLBACK');}
}
