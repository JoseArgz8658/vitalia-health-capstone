import {createCredentialVerificationService} from '../professional-credentials/service';
import {type DocumentDatabase} from '../documents/service';
import {type AccountSummary} from '../accounts/repository';
import {randomUUID} from 'node:crypto';
import {type PoolClient} from 'pg';
type Client=Pick<PoolClient,'query'>;
// Datos ficticios bajo una transacción exclusiva; nunca modifica exámenes reales.
export async function verifyExamCare(client:Client):Promise<number>{
 let begun=false,checks=0;
 const check=(ok:boolean)=>{if(!ok)throw new Error('Comprobación de atención incorrecta.');checks++;};
 async function denied(sql:string,args:unknown[],code:string){
  await client.query('SAVEPOINT care_invalid');let error:unknown;
  try{await client.query(sql,args);}catch(e){error=e;}
  await client.query('ROLLBACK TO SAVEPOINT care_invalid');await client.query('RELEASE SAVEPOINT care_invalid');
  check((error as {code?:string})?.code===code);
 }
 try{
  await client.query('BEGIN');begun=true;
  if(!(await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['019_exam_care_reviews'])).rows.length)throw new Error('Falta migración 019.');
  const patient=randomUUID(),otherPatient=randomUUID(),admin=randomUUID();
  const clinic=randomUUID(),otherClinic=randomUUID(),branch=randomUUID(),otherBranch=randomUUID(),specialty=randomUUID(),unlinkedSpecialty=randomUUID();
  const professionals=Array.from({length:3},()=>({account:randomUUID(),person:randomUUID(),member:randomUUID()}));
  const region='T'+randomUUID().slice(0,8),province='T'+randomUUID().slice(0,8),commune='T'+randomUUID().slice(0,8);
  await client.query('INSERT INTO public.vitalia_regions(code,name) VALUES($1,$2)',[region,'Región ficticia']);
  await client.query('INSERT INTO public.vitalia_provinces(code,region_code,name) VALUES($1,$2,$3)',[province,region,'Provincia ficticia']);
  await client.query('INSERT INTO public.vitalia_communes(code,province_code,name) VALUES($1,$2,$3)',[commune,province,'Comuna ficticia']);
  for(const [id,role]of [[patient,'paciente'],[otherPatient,'paciente'],[admin,'administrador'],...professionals.map(p=>[p.account,'profesional'])])await client.query("INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,'synthetic-no-login',$3)",[id,id+'@example.invalid',role]);
  for(const id of [clinic,otherClinic])await client.query('INSERT INTO public.vitalia_clinics(id,name) VALUES($1,$2)',[id,'Clínica ficticia '+id]);
  for(const [id,cid]of [[branch,clinic],[otherBranch,otherClinic]])await client.query("INSERT INTO public.vitalia_branches(id,clinic_id,commune_code,name,street,address_number) VALUES($1,$2,$3,'Sede ficticia','Calle ficticia','S/N')",[id,cid,commune]);
  for(const id of [specialty,unlinkedSpecialty])await client.query('INSERT INTO public.vitalia_specialties(id,name) VALUES($1,$2)',[id,'Especialidad ficticia '+id]);
  for(const [index,p]of professionals.entries()){
   const cid=index===2?otherClinic:clinic,bid=index===2?otherBranch:branch;
   await client.query("INSERT INTO public.vitalia_people(id,account_id,first_name,first_surname) VALUES($1,$2,'Persona','Ficticia')",[p.person,p.account]);
   await client.query("INSERT INTO public.vitalia_professional_profiles(person_id,verification_status,registration_reference) VALUES($1,'verified','SYNTHETIC-NOT-A-REAL-REGISTRATION')",[p.person]);
   await client.query("INSERT INTO public.vitalia_clinic_memberships(id,clinic_id,professional_person_id,active) VALUES($1,$2,$3,true)",[p.member,cid,p.person]);
   await client.query('INSERT INTO public.vitalia_membership_specialties(clinic_id,membership_id,specialty_id) VALUES($1,$2,$3)',[cid,p.member,specialty]);
   await client.query('INSERT INTO public.vitalia_branch_memberships(clinic_id,branch_id,membership_id) VALUES($1,$2,$3)',[cid,bid,p.member]);
  }
  // 020 endurece elegibilidad: preparar procedencia sintética cuando esa migración exista.
  if((await client.query("SELECT to_regclass('public.vitalia_credential_requests') AS name")).rows[0]?.name){
   const db={query:client.query.bind(client),transaction:async(fn:(tx:Client)=>Promise<unknown>)=>fn(client)} as DocumentDatabase;
   const credentials=createCredentialVerificationService(db),actor={id:admin,role:'administrador'} as AccountSummary;
   for(const [index,p]of professionals.entries()){
    const cid=index===2?otherClinic:clinic,id=randomUUID();
    await credentials.request(actor,cid,p.member,{requestId:id,expectedRevision:0,registrationReference:'SYNTHETIC',supportingReference:'Evidencia exclusivamente sintética'});
    await credentials.decide(actor,cid,p.member,id,{requestId:randomUUID(),expectedRevision:0,decision:'verified',sourceReference:'Fuente exclusivamente sintética',checkedAt:new Date(Date.now()-10000).toISOString(),reason:'Comprobación sintética',confirmed:true});
   }
  }
  const first=professionals[0],second=professionals[1],outside=professionals[2];
  const document=randomUUID(),otherDocument=randomUUID(),processing=randomUUID(),otherProcessing=randomUUID();
  for(const id of [document,otherDocument])await client.query("INSERT INTO public.vitalia_documents(id,patient_id,exam_name,exam_type,exam_date,original_name,content_type,size_bytes,storage_key,status) VALUES($1,$2,'Examen ficticio','Laboratorio',CURRENT_DATE,'ficticio.pdf','application/pdf',20,$3,'stored')",[id,patient,'synthetic/'+id]);
  const extraction={examen:'Examen ficticio',fecha:null,resultados:[]};
  for(const [id,doc]of [[processing,document],[otherProcessing,otherDocument]])await client.query("INSERT INTO public.vitalia_document_processing(id,document_id,status,model,prompt_version,result,started_at,finished_at) VALUES($1,$2,'requires_review','synthetic',1,$3::jsonb,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",[id,doc,JSON.stringify({status:'requires_review',approved:false,ai:{extraction}})]);
  const insert="INSERT INTO public.vitalia_exam_care(id,document_id,patient_id,clinic_id,branch_id,responsible_membership_id,specialty_id,kind,previous_care_id,prior_review_id,requested_by,updated_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11)";
  const args=(id:string,member=first.member,cid=clinic,bid:string|null=branch,kind='initial',previous:string|null=null,review:string|null=null,actor=patient)=>[id,document,patient,cid,bid,member,specialty,kind,previous,review,actor];
  await denied(insert,args(randomUUID(),first.member,clinic,branch,'initial',null,null,admin),'P0001');
  const mismatch=args(randomUUID());mismatch[2]=otherPatient;await denied(insert,mismatch,'P0001');
  await denied(insert,args(randomUUID(),outside.member,clinic,branch),'P0001');
  await denied(insert,args(randomUUID(),first.member,clinic,otherBranch),'P0001');
  const missing=args(randomUUID());missing[6]=unlinkedSpecialty;await denied(insert,missing,'P0001');
  for(const [sql,values,restore,restored]of [
   ["UPDATE public.vitalia_professional_profiles SET verification_status='pending' WHERE person_id=$1",[first.person],"UPDATE public.vitalia_professional_profiles SET verification_status='verified' WHERE person_id=$1",[first.person]],
   ['UPDATE public.vitalia_professional_profiles SET registration_reference=NULL WHERE person_id=$1',[first.person],"UPDATE public.vitalia_professional_profiles SET registration_reference='SYNTHETIC' WHERE person_id=$1",[first.person]],
   ['UPDATE public.vitalia_clinic_memberships SET active=false WHERE id=$1',[first.member],'UPDATE public.vitalia_clinic_memberships SET active=true WHERE id=$1',[first.member]],
   ['UPDATE public.vitalia_clinics SET active=false WHERE id=$1',[clinic],'UPDATE public.vitalia_clinics SET active=true WHERE id=$1',[clinic]],
   ["UPDATE public.vitalia_account_roles SET active=false WHERE account_id=$1 AND role_code='profesional'",[first.account],"UPDATE public.vitalia_account_roles SET active=true WHERE account_id=$1 AND role_code='profesional'",[first.account]],
   ['UPDATE public.vitalia_specialties SET active=false WHERE id=$1',[specialty],'UPDATE public.vitalia_specialties SET active=true WHERE id=$1',[specialty]],
  ] as [string,unknown[],string,unknown[]][]){await client.query(sql,values);await denied(insert,args(randomUUID()),'P0001');await client.query(restore,restored);}
  const care=randomUUID();await client.query(insert,args(care));
  check((await client.query('SELECT status,revision FROM public.vitalia_exam_care WHERE id=$1',[care])).rows[0].status==='requested');
  check((await client.query('SELECT action FROM public.vitalia_care_audit WHERE care_id=$1',[care])).rows[0].action==='requested');
  await denied(insert,args(randomUUID()),'23505');
  await denied('UPDATE public.vitalia_exam_care SET responsible_membership_id=$2 WHERE id=$1',[care,second.member],'P0001');
  await denied('DELETE FROM public.vitalia_exam_care WHERE id=$1',[care],'P0001');
  const transition="UPDATE public.vitalia_exam_care SET status=$2,revision=revision+1,updated_by=$3 WHERE id=$1";
  await denied(transition,[care,'active',admin],'P0001');
  await denied("UPDATE public.vitalia_exam_care SET status='active',updated_by=$2 WHERE id=$1",[care,first.account],'P0001');
  await client.query(transition,[care,'active',first.account]);checks++;
  await denied(transition,[care,'completed',first.account],'P0001');
  const insertReview="INSERT INTO public.vitalia_care_reviews(id,care_id,document_id,patient_id,processing_id,reviewer_membership_id,reviewer_id,original_extraction,reviewed_extraction,observations,confirmed_original) VALUES($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$8::jsonb,'Observación ficticia',true)";
  const review=randomUUID(),reviewArgs=[review,care,document,patient,processing,first.member,first.account,JSON.stringify(extraction)];
  const wrongAuthor=[...reviewArgs];wrongAuthor[6]=second.account;await denied(insertReview,wrongAuthor,'P0001');
  const wrongOriginal=[...reviewArgs];wrongOriginal[7]='{}';await denied(insertReview,wrongOriginal,'P0001');
  const wrongProcessing=[...reviewArgs];wrongProcessing[4]=otherProcessing;await denied(insertReview,wrongProcessing,'P0001');
  await client.query(insertReview,reviewArgs);checks++;
  await denied(insertReview,[randomUUID(),...reviewArgs.slice(1)],'23505');
  await denied("UPDATE public.vitalia_care_reviews SET observations='Cambio' WHERE id=$1",[review],'P0001');
  await denied('DELETE FROM public.vitalia_care_reviews WHERE id=$1',[review],'P0001');
  await client.query(transition,[care,'completed',first.account]);checks++;
  await denied(transition,[care,'active',first.account],'P0001');
  const opinion=randomUUID();await client.query(insert,args(opinion,second.member,clinic,branch,'second_opinion',care,review));checks++;
  await denied(insert,args(randomUUID(),second.member,clinic,branch,'second_opinion',care,review),'23505');
  await client.query(transition,[opinion,'active',second.account]);
  const secondReview=randomUUID();await client.query(insertReview,[secondReview,opinion,document,patient,processing,second.member,second.account,JSON.stringify(extraction)]);
  check((await client.query('SELECT id FROM public.vitalia_care_reviews WHERE processing_id=$1',[processing])).rows.length===2);
  await client.query(transition,[opinion,'completed',second.account]);
  check((await client.query('SELECT prior_review_id FROM public.vitalia_exam_care WHERE id=$1',[opinion])).rows[0].prior_review_id===review);
  check((await client.query('SELECT reviewer_id FROM public.vitalia_care_reviews WHERE id=$1',[review])).rows[0].reviewer_id===first.account);
  await denied(insert,args(randomUUID(),first.member,clinic,branch,'second_opinion',opinion,review),'P0001');
  // Otra atención del documento de prueba permite comprobar derivación institucional.
  const source=randomUUID(),target=randomUUID();const src=args(source);src[1]=otherDocument;await client.query(insert,src);
  await client.query(transition,[source,'active',first.account]);await client.query(transition,[source,'referred',first.account]);
  await denied('SET CONSTRAINTS vitalia_care_referral_pair IMMEDIATE',[],'P0001');
  await denied(insert,args(randomUUID(),outside.member,otherClinic,otherBranch,'referral',source,null,first.account),'P0001');
  const dst=args(target,second.member,clinic,branch,'referral',source,null,first.account);dst[1]=otherDocument;await client.query(insert,dst);
  const referral=randomUUID(),referralSql="INSERT INTO public.vitalia_exam_referrals(id,clinic_id,document_id,patient_id,source_care_id,target_care_id,actor_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7,$8)";
  await denied(referralSql,[randomUUID(),otherClinic,otherDocument,patient,source,target,first.account,'Motivo ficticio'],'23503');
  await denied(referralSql,[randomUUID(),clinic,otherDocument,patient,source,target,admin,'Motivo ficticio'],'P0001');
  await client.query(referralSql,[referral,clinic,otherDocument,patient,source,target,first.account,'Motivo ficticio']);checks++;
  await denied('DELETE FROM public.vitalia_exam_referrals WHERE id=$1',[referral],'P0001');
  await denied("UPDATE public.vitalia_exam_referrals SET reason='Cambio' WHERE id=$1",[referral],'P0001');
  await client.query(transition,[target,'cancelled',patient]);checks++;
  const again=randomUUID();const reselection=args(again,first.member,clinic,branch,'reselection',target);reselection[1]=otherDocument;await client.query(insert,reselection);checks++;
  await denied('UPDATE public.vitalia_care_audit SET actor_id=$1 WHERE care_id=$2',[admin,care],'P0001');
  await denied('DELETE FROM public.vitalia_care_audit WHERE care_id=$1',[care],'P0001');
  check((await client.query("SELECT count(*)::int AS total FROM public.vitalia_care_audit WHERE action='review_approved' AND care_id=ANY($1::uuid[])",[[care,opinion]])).rows[0].total===2);
  check((await client.query('SELECT id FROM public.vitalia_patient_assignments WHERE patient_id=$1',[patient])).rows.length===0);
  check((await client.query('SELECT id FROM public.vitalia_professional_reviews WHERE patient_id=$1',[patient])).rows.length===0);
  check((await client.query("SELECT 1 FROM pg_trigger WHERE tgname='vitalia_reviews_immutable' AND tgenabled<>'D'")).rows.length===1);
  check((await client.query('DELETE FROM public.vitalia_membership_specialties WHERE membership_id=$1 AND specialty_id=$2',[first.member,specialty])).rowCount===1);
  await denied(transition,[again,'active',first.account],'P0001');
  check((await client.query('SELECT id FROM public.vitalia_care_reviews WHERE id=$1',[review])).rows.length===1);
  await client.query('SET CONSTRAINTS vitalia_care_referral_pair IMMEDIATE');checks++;
  return checks;
 }finally{if(begun)await client.query('ROLLBACK');}
}
