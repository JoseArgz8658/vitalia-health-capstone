import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {createCredentialVerificationService} from '../professional-credentials/service';
type Client=Pick<PoolClient,'query'>;
export async function verifyProfessionalCredentials(client:Client):Promise<number>{
 let started=false,checks=0;
 const check=(ok:boolean)=>{if(!ok)throw new Error('Comprobación de credenciales incorrecta.');checks++;};
 async function denied(fn:()=>Promise<unknown>,status:number){let actual=0;try{await fn();}catch(e){actual=(e as {status:number}).status;}check(actual===status);}
 async function deniedSQL(sql:string,args:unknown[],code:string){await client.query('SAVEPOINT invalid_credential_sql');let error:unknown;try{await client.query(sql,args);}catch(e){error=e;}await client.query('ROLLBACK TO SAVEPOINT invalid_credential_sql');await client.query('RELEASE SAVEPOINT invalid_credential_sql');check((error as {code?:string})?.code===code);}
 try{
 await client.query('BEGIN');started=true;
 if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['020_professional_credentials'])).rows.length)throw new Error('Falta migración 020.');
 const db={query:client.query.bind(client),transaction:async(fn:(tx:Client)=>Promise<unknown>)=>{await client.query('SAVEPOINT credential_work');try{const value=await fn(client);await client.query('RELEASE SAVEPOINT credential_work');return value;}catch(e){await client.query('ROLLBACK TO SAVEPOINT credential_work');await client.query('RELEASE SAVEPOINT credential_work');throw e;}}} as DocumentDatabase;
 const service=createCredentialVerificationService(db),clinic=randomUUID(),otherClinic=randomUUID();
 const admin={id:randomUUID(),role:'administrador'} as AccountSummary,chief={id:randomUUID(),role:'profesional'} as AccountSummary,professional={id:randomUUID(),role:'profesional'} as AccountSummary,patient={id:randomUUID(),role:'paciente'} as AccountSummary;
 for(const a of [admin,chief,professional,patient])await client.query("INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login',$3)",[a.id,a.id+'@example.invalid',a.role]);
 for(const id of [clinic,otherClinic])await client.query('INSERT INTO public.vitalia_clinics(id,name) VALUES($1,$2)',[id,'Clínica ficticia '+id]);
 const chiefPerson=randomUUID(),person=randomUUID(),chiefMember=randomUUID(),member=randomUUID(),outside=randomUUID();
 for(const [id,account]of [[chiefPerson,chief.id],[person,professional.id]]){await client.query("INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname) VALUES($1,$2,'Persona','Ficticia')",[id,account]);await client.query('INSERT INTO public.vitalia_professional_profiles(person_id) VALUES($1)',[id]);}
 for(const [id,cid,p,role]of [[chiefMember,clinic,chiefPerson,'jefe_clinico'],[member,clinic,person,'profesional'],[outside,otherClinic,person,'profesional']])await client.query('INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id,clinical_role,active) VALUES($1,$2,$3,$4,true)',[id,cid,p,role]);
 const initial=await service.details(chief,clinic,member);check(initial.profile.status==='pending');check(initial.requests.length===0);check(!initial.canDecide);check((await service.details(admin,clinic,member)).canDecide);
 await denied(()=>service.details(patient,clinic,member),403);
 await denied(()=>service.details(professional,clinic,member),403);
 await denied(()=>service.details(chief,otherClinic,outside),403);
 const request=randomUUID(),input={requestId:request,expectedRevision:0,registrationReference:'SYNTHETIC-ONLY',supportingReference:'Antecedentes exclusivamente sintéticos'};
 check((await service.request(chief,clinic,member,input)).recorded);
 check((await service.request(chief,clinic,member,input)).replayed);
 await denied(()=>service.request(chief,clinic,member,{...input,supportingReference:'Otro texto sintético'}),409);
 await denied(()=>service.request(admin,otherClinic,outside,{...input,requestId:randomUUID()}),409);
 check((await service.details(admin,otherClinic,outside)).requests.length===0);
 check((await service.details(admin,clinic,member)).profile.status==='pending');
 await client.query("UPDATE public.vitalia_professional_profiles SET verification_status='verified',registration_reference='NO-EVIDENCE' WHERE person_id=$1",[person]);
 await deniedSQL('SELECT public.vitalia_assert_care_professional($1)',[member],'P0001');
 await client.query("UPDATE public.vitalia_professional_profiles SET verification_status='pending',registration_reference=NULL WHERE person_id=$1",[person]);
 await deniedSQL('UPDATE public.vitalia_credential_requests SET state=$2 WHERE id=$1',[request,'verified'],'P0001');
 await deniedSQL('DELETE FROM public.vitalia_credential_requests WHERE id=$1',[request],'P0001');
 const decision={requestId:randomUUID(),expectedRevision:0,decision:'verified',sourceReference:'Fuente consultada exclusivamente sintética',checkedAt:new Date(Date.now()-60000).toISOString(),reason:'Comprobación exclusivamente sintética',confirmed:true};
 await denied(()=>service.decide(chief,clinic,member,request,decision),403);
 await denied(()=>service.decide(admin,clinic,member,request,{...decision,confirmed:false}),400);
 await denied(()=>service.decide(admin,clinic,member,request,{...decision,checkedAt:new Date(Date.now()+86400000).toISOString()}),400);
 await denied(()=>service.decide(admin,clinic,member,request,{...decision,expectedRevision:1}),409);
 await denied(()=>service.decide(admin,otherClinic,outside,request,decision),404);
 await denied(()=>service.decide({...admin,id:professional.id},clinic,member,request,decision),403);
 check((await service.decide(admin,clinic,member,request,decision)).decided);
 check((await service.decide(admin,clinic,member,request,decision)).replayed);
 const verified=(await service.details(chief,clinic,member)).profile;
 check(verified.status==='verified'&&verified.registrationReference==='SYNTHETIC-ONLY'&&verified.revision===1&&verified.verificationRequestId===request);
 check((await client.query('SELECT public.vitalia_assert_care_professional($1) AS actor',[member])).rows[0].actor===professional.id);
 check((await client.query('SELECT public.vitalia_assert_care_professional($1) AS actor',[outside])).rows[0].actor===professional.id);
 await client.query("UPDATE public.vitalia_professional_profiles SET registration_reference='TAMPERED' WHERE person_id=$1",[person]);
 await deniedSQL('SELECT public.vitalia_assert_care_professional($1)',[member],'P0001');
 await client.query("UPDATE public.vitalia_professional_profiles SET registration_reference='SYNTHETIC-ONLY',verification_revision=2 WHERE person_id=$1",[person]);
 await deniedSQL('SELECT public.vitalia_assert_care_professional($1)',[member],'P0001');
 await client.query('UPDATE public.vitalia_professional_profiles SET verification_revision=1 WHERE person_id=$1',[person]);
 await denied(()=>service.decide(admin,clinic,member,request,{...decision,requestId:randomUUID()}),409);
 await denied(()=>service.decide(admin,clinic,member,request,{...decision,reason:'Un fundamento distinto'}),409);
 await deniedSQL('UPDATE public.vitalia_credential_audit SET reason=$2 WHERE id=$1',[decision.requestId,'Cambio sintético'],'P0001');
 await deniedSQL('DELETE FROM public.vitalia_credential_audit WHERE id=$1',[decision.requestId],'P0001');
 await deniedSQL('UPDATE public.vitalia_credential_requests SET registration_reference=$2 WHERE id=$1',[request,'Otro'],'P0001');
 const rejectedRequest=randomUUID();await service.request(admin,otherClinic,outside,{...input,requestId:rejectedRequest,expectedRevision:1});
 check((await service.details(chief,clinic,member)).requests.length===1);
 await service.decide(admin,otherClinic,outside,rejectedRequest,{...decision,requestId:randomUUID(),expectedRevision:1,decision:'rejected',reason:'Antecedentes sintéticos no coinciden'});
 const rejected=(await service.details(admin,clinic,member)).profile;
 check(rejected.status==='rejected'&&rejected.revision===2);
 await deniedSQL('SELECT public.vitalia_assert_care_professional($1)',[member],'P0001');
 await deniedSQL('SELECT public.vitalia_assert_care_professional($1)',[outside],'P0001');
 check((await service.details(chief,clinic,member)).requests.length===1);
 check((await service.details(admin,otherClinic,outside)).requests.length===1);
 check((await client.query("SELECT role_code FROM public.vitalia_account_roles WHERE account_id=$1 AND role_code='profesional' AND active",[professional.id])).rows.length===1);
 check((await client.query('SELECT active,clinical_role FROM public.vitalia_clinic_memberships WHERE id=$1',[member])).rows[0].active===true);
 check((await client.query('SELECT id FROM public.vitalia_patient_assignments WHERE professional_id=$1',[professional.id])).rows.length===0);
 check((await client.query('SELECT id FROM public.vitalia_exam_care WHERE responsible_membership_id=$1',[member])).rows.length===0);
 // La jefatura puede registrar sus antecedentes, pero no aprobarlos.
 const own=randomUUID();check((await service.request(chief,clinic,chiefMember,{...input,requestId:own})).recorded);
 await denied(()=>service.decide(chief,clinic,chiefMember,own,decision),403);
 return checks;
 }finally{if(started)await client.query('ROLLBACK');}
}
