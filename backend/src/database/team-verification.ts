import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
import {type DocumentDatabase} from '../documents/service';
import {type AccountSummary} from '../accounts/repository';
import {createTeamService} from '../team/service';
export async function verifyTeam(client:Pick<PoolClient,'query'>):Promise<number>{
 let checks=0,begun=false;
 const check=(ok:boolean)=>{if(!ok)throw new Error('Comprobación del equipo incorrecta.');checks++;};
 const denied=async(fn:()=>Promise<unknown>,status:number)=>{let ok=false;try{await fn();}catch(e){ok=(e as {status:number}).status===status;}check(ok);};
 try{
  await client.query('BEGIN');begun=true;
  if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['016_membership_management'])).rows.length)throw new Error('Falta migración 016.');
  const db={query:client.query.bind(client),transaction:async(fn:(tx:Pick<PoolClient,'query'>)=>Promise<unknown>)=>{await client.query('SAVEPOINT team_check');try{const r=await fn(client);await client.query('RELEASE SAVEPOINT team_check');return r;}catch(e){await client.query('ROLLBACK TO SAVEPOINT team_check');await client.query('RELEASE SAVEPOINT team_check');throw e;}}} as DocumentDatabase;
  const s=createTeamService(db),clinic=randomUUID(),other=randomUUID();
  for(const id of [clinic,other])await client.query('INSERT INTO public.vitalia_clinics(id,name) VALUES($1,$2)',[id,'Clínica sintética '+id]);
  async function person(role:string){const id=randomUUID(),pid=randomUUID();await client.query("INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login',$3)",[id,id+'@example.invalid',role]);if(role==='profesional'){await client.query("INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname) VALUES($1,$2,'Persona','Sintética')",[pid,id]);await client.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1)',[pid]);}return {account:{id,role} as AccountSummary,pid};}
  const ca=await person('profesional'),cb=await person('profesional'),member=await person('profesional'),admin=await person('administrador'),patient=await person('paciente');
  const chiefA=randomUUID(),chiefB=randomUUID(),ma=randomUUID(),mb=randomUUID();
  for(const [id,cid,pid,role] of [[chiefA,clinic,ca.pid,'jefe_clinico'],[chiefB,other,cb.pid,'jefe_clinico'],[ma,clinic,member.pid,'profesional'],[mb,other,member.pid,'profesional']])await client.query('INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id,clinical_role,active) VALUES($1,$2,$3,$4,true)',[id,cid,pid,role]);
  const commune=(await client.query('SELECT code FROM public.vitalia_communes ORDER BY code LIMIT 1')).rows[0]?.code;if(!commune)throw new Error('Falta catálogo territorial.');
  const ba=randomUUID(),bb=randomUUID(),s1=randomUUID(),s2=randomUUID();
  for(const [id,cid]of [[ba,clinic],[bb,other]])await client.query("INSERT INTO public.vitalia_branches(id,clinic_id,commune_code,name,street,address_number) VALUES($1,$2,$3,'Sucursal ficticia','Calle ficticia','S/N')",[id,cid,commune]);
  for(const id of [s1,s2])await client.query('INSERT INTO public.vitalia_specialties(id,name) VALUES($1,$2)',[id,'Especialidad sintética '+id]);
  await client.query('INSERT INTO public.vitalia_professional_specialties(professional_person_id,specialty_id) VALUES($1,$2)',[member.pid,s1]);
  for(const [cid,mid,bid,sid]of [[clinic,ma,ba,s1],[other,mb,bb,s2]]){await client.query('INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)',[cid,bid,mid]);await client.query('INSERT INTO public.vitalia_membership_specialties(clinic_id,membership_id,specialty_id) VALUES($1,$2,$3)',[cid,mid,sid]);}
  const first=await s.list(ca.account,clinic);check(first.members.length===2&&first.members.every(m=>m.clinicId===clinic));check(first.members.find(m=>m.id===ma)?.specialties[0].id===s1);
  check((await s.list(admin.account,other)).members.length===2);
  await denied(()=>s.list(ca.account,other),403);await denied(()=>s.list(member.account,clinic),403);await denied(()=>s.list(patient.account,clinic),403);
  const change={requestId:randomUUID(),expectedRevision:0,active:false,branchIds:[] as string[],specialtyIds:[s2],reason:'Suspensión sintética para prueba'};
  await denied(()=>s.update(admin.account,clinic,ma,change),403);await denied(()=>s.update(member.account,clinic,ma,change),403);
  await denied(()=>s.update(ca.account,clinic,chiefA,change),403);await denied(()=>s.update(ca.account,clinic,mb,change),404);
  await denied(()=>s.update(ca.account,clinic,ma,{...change,clinicalRole:'jefe_clinico'}),400);
  await denied(()=>s.update(ca.account,clinic,ma,{...change,branchIds:[bb]}),400);
  check((await s.update(ca.account,clinic,ma,change)).updated);
  const updated=(await s.list(ca.account,clinic)).members.find(m=>m.id===ma);check(updated?.active===false&&updated.revision===1&&updated.branches.length===0&&updated.specialties[0].id===s2);
  const untouched=(await s.list(cb.account,other)).members.find(m=>m.id===mb);check(untouched?.active===true&&untouched.revision===0&&untouched.branches[0].id===bb&&untouched.specialties[0].id===s2);
  check((await client.query('SELECT specialty_id FROM public.vitalia_professional_specialties WHERE professional_person_id=$1',[member.pid])).rows[0].specialty_id===s1);
  check((await s.update(ca.account,clinic,ma,change)).replayed);
  check((await s.history(ca.account,clinic,ma)).length===1);
  await denied(()=>s.update(ca.account,clinic,ma,{...change,reason:'Motivo alterado'}),409);
  await denied(()=>s.update(ca.account,clinic,ma,{...change,requestId:randomUUID()}),409);
  await denied(()=>s.update(cb.account,other,mb,{...change,expectedRevision:0}),409);
  const history=await s.history(ca.account,clinic,ma);check(history[0].actorId===ca.account.id&&history[0].beforeState.active===true&&history[0].afterState.active===false&&history[0].reason===change.reason);
  await denied(()=>s.history(ca.account,other,mb),403);await denied(()=>s.history(member.account,clinic,ma),403);
  await denied(()=>s.update(ca.account,clinic,ma,{...change,requestId:randomUUID(),expectedRevision:1}),400);
  check((await s.update(ca.account,clinic,ma,{...change,requestId:randomUUID(),expectedRevision:1,active:true,branchIds:[ba],reason:'Reactivación sintética autorizada'})).updated);
  check((await s.list(ca.account,clinic)).members.find(m=>m.id===ma)?.revision===2);
  check((await s.history(admin.account,clinic,ma)).length===2);
  const account=(await client.query('SELECT role_code,password_hash FROM public.vitalia_accounts WHERE id=$1',[member.account.id])).rows[0];check(account.role_code==='profesional'&&account.password_hash==='synthetic-no-login');
  await client.query('UPDATE public.vitalia_branches SET active=false WHERE id=$1',[ba]);
  await client.query('UPDATE public.vitalia_specialties SET active=false WHERE id=ANY($1::uuid[])',[[s1,s2]]);
  await denied(()=>s.update(ca.account,clinic,ma,{...change,requestId:randomUUID(),expectedRevision:2,branchIds:[ba],specialtyIds:[s1]}),400);
  check((await s.update(ca.account,clinic,ma,{...change,requestId:randomUUID(),expectedRevision:2,branchIds:[ba],specialtyIds:[s2]})).updated);
  const retained=(await s.list(ca.account,clinic)).members.find(m=>m.id===ma);check(retained?.revision===3&&retained.branches[0].active===false&&retained.specialties[0].active===false);
  await client.query('UPDATE public.vitalia_clinic_memberships SET active=false,updated_at=CURRENT_TIMESTAMP WHERE id=$1',[chiefA]);
  await denied(()=>s.update(ca.account,clinic,ma,{...change,requestId:randomUUID(),expectedRevision:2}),403);await denied(()=>s.history(ca.account,clinic,ma),403);
  await client.query('UPDATE public.vitalia_clinics SET active=false WHERE id=$1',[other]);await denied(()=>s.list(cb.account,other),409);
  let immutable=false;try{await db.transaction(async tx=>{await tx.query('UPDATE public.vitalia_membership_audit SET reason=$1 WHERE id=$2',['Cambio rechazado',change.requestId]);});}catch{immutable=true;}check(immutable);
  let noDelete=false;try{await db.transaction(async tx=>{await tx.query('DELETE FROM public.vitalia_membership_audit WHERE id=$1',[change.requestId]);});}catch{noDelete=true;}check(noDelete);
  return checks;
 }finally{if(begun)await client.query('ROLLBACK');}
}
