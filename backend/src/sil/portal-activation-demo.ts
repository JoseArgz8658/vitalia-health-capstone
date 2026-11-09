import {createHash,randomBytes,randomUUID,timingSafeEqual} from 'node:crypto';
import {type Pool,type PoolClient} from 'pg';
import {hashPassword} from '../auth/password';

export class PortalDemoConflict extends Error {}
export class PortalDemoNotFound extends Error {}
export class PortalDemoInvalidCode extends Error {}

const mailbox=new Map<string,{code:string;createdAt:number;expiresAt:number}>();
const tokenPattern=/^[A-Za-z0-9_-]{12}$/;
function storeDemoMail(email:string,code:string) {
  const now=Date.now();
  for(const [key,item] of mailbox){
    if(item.expiresAt<=now)mailbox.delete(key);
  }
  // Buzón efímero y acotado, incluso durante pruebas de carga.
  if(mailbox.size>=200&&!mailbox.has(email)){
    const oldest=mailbox.keys().next().value;
    if(oldest!==undefined)mailbox.delete(oldest);
  }
  mailbox.set(email,{code,createdAt:now,expiresAt:now+20*60*1000});
}

const demoEmailPattern=/^[a-z0-9.!#$%&'*+\/?^_`{|}~-]+@example\.invalid$/;
const sha=(value:string)=>createHash('sha256').update(value,'utf8').digest('hex');
const secureMatch=(a:string,b:string)=>{
  if(!tokenPattern.test(a)||!/^[a-f0-9]{64}$/.test(b))return false;
  return timingSafeEqual(Buffer.from(sha(a),'hex'),Buffer.from(b,'hex'));
};
const newCode=()=>randomBytes(9).toString('base64url');
const genericCodeFailure='La invitación no está disponible o los códigos no coinciden.';
function safeEmail(email:string){
  const clean=email.toLowerCase().trim();
  if(clean.length>254||!demoEmailPattern.test(clean))throw new PortalDemoConflict();
  return clean;
}
async function audit(client:PoolClient,patientId:string,actorId:string|null,
  action:string,details:Record<string,unknown>={}) {
  await client.query(
    `INSERT INTO public.vitalia_sil_portal_audit_demo
      (id,patient_id,actor_id,action,details)
      VALUES($1,$2,$3,$4,$5::jsonb)`,
    [randomUUID(),patientId,actorId,action,JSON.stringify(details)]);
}
function safeCodeError(){return new PortalDemoInvalidCode(genericCodeFailure);}
type NewProfile={
  email:string;givenNames:string;familyNames:string;birthDate:string;
  sexForReference:'female'|'male'|'not_specified';contactPhoneDemo?:string;
};

export function createSilPortalActivationDemo(db:Pool) {
  return {
    /** Alta del paciente sintético: crea un registro SIN contraseña conocida.
     *  El paciente sólo obtiene credenciales cuando valida ambos canales. */
    async provision(input:NewProfile,actorId:string){
      const email=safeEmail(input.email);
      const randomCredential=await hashPassword(randomBytes(32).toString('hex'));
      const id=randomUUID();
      const syntheticIdentifier='DEMO-'+randomBytes(6).toString('hex').toUpperCase();
      const client=await db.connect();
      let invalid=false;
      try{
        await client.query('BEGIN');
        await client.query(
          `INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code)
           VALUES($1,$2,$3,'paciente')`,
          [id,email,randomCredential]);
        // El rol paciente queda INACTIVO hasta completar la activación.
        // Ningún secreto de inicio de sesión es entregado al operador.
        await client.query(
          `UPDATE public.vitalia_account_roles
           SET active=false WHERE account_id=$1 AND role_code='paciente'`,[id]);
        await client.query(
          `INSERT INTO public.vitalia_sil_patient_profiles_demo(
            patient_id,synthetic_identifier,given_names,family_names,birth_date,
            sex_for_reference,contact_phone_demo)
           VALUES($1,$2,$3,$4,$5,$6,$7)`,
          [id,syntheticIdentifier,input.givenNames.trim(),input.familyNames.trim(),
           input.birthDate,input.sexForReference,input.contactPhoneDemo?.trim()||null]);
        await client.query(
          `INSERT INTO public.vitalia_sil_portal_access_demo(patient_id,status)
           VALUES($1,'pending')`,[id]);
        await audit(client,id,actorId,'patient_provisioned',{mode:'operator_demo'});
        await client.query('COMMIT');
        return {patient:{id,email,syntheticIdentifier,
          givenNames:input.givenNames.trim(),familyNames:input.familyNames.trim(),
          birthDate:input.birthDate},portalStatus:'pending'};
      }catch(error){
        try{await client.query('ROLLBACK');}catch{invalid=true;}
        if((error as {code?:string}).code==='23505')throw new PortalDemoConflict();
        throw error;
      }finally{client.release(invalid);}
    },
    async status(patientId:string,actorId:string){
      const client=await db.connect();
      try{
        const found=await client.query(
          `SELECT a.id,a.email,
            p.given_names AS "givenNames",p.family_names AS "familyNames",
            p.synthetic_identifier AS "syntheticIdentifier",
            p.birth_date::text AS "birthDate",
            access.status AS "portalStatus",
            access.contact_confirmed_at AS "contactConfirmedAt",
            access.identity_checked_at AS "identityCheckedAt",
            access.activated_at AS "activatedAt",
            i.created_at AS "invitedAt",i.expires_at AS "expiresAt",
            i.consumed_at AS "consumedAt",
            COALESCE(i.attempts,0) AS attempts
           FROM public.vitalia_accounts a
           JOIN public.vitalia_sil_patient_profiles_demo p ON p.patient_id=a.id
           LEFT JOIN public.vitalia_sil_portal_access_demo access ON access.patient_id=a.id
           LEFT JOIN LATERAL (
              SELECT created_at,expires_at,consumed_at,attempts
              FROM public.vitalia_sil_portal_invitations_demo
              WHERE patient_id=a.id ORDER BY created_at DESC,id DESC LIMIT 1
           ) i ON TRUE
           WHERE a.id=$1 AND a.role_code='paciente' AND
             a.email LIKE '%@example.invalid'`,[patientId]);
        if(found.rows.length!==1)throw new PortalDemoNotFound();
        await audit(client,patientId,actorId,'portal_access_read');
        return {patient:found.rows[0],canInvite:found.rows[0].portalStatus==='pending'||
          found.rows[0].portalStatus==='invited'};
      }finally{client.release();}
    },
    async invite(patientId:string,actorId:string,
      assertions:{contactConfirmed:true;identityChecked:true}){
      if(!assertions.contactConfirmed||!assertions.identityChecked)
        throw new PortalDemoConflict();
      const emailCode=newCode();
      const handoffCode=newCode();
      const id=randomUUID();
      const client=await db.connect();
      let invalid=false;
      let email='';
      try{
        await client.query('BEGIN');
        const result=await client.query<{
          email:string;status:string;givenNames:string;familyNames:string;
          syntheticIdentifier:string;birthDate:string;
        }>(
          `SELECT a.email,access.status,
             p.given_names AS "givenNames",p.family_names AS "familyNames",
             p.synthetic_identifier AS "syntheticIdentifier",
             p.birth_date::text AS "birthDate"
           FROM public.vitalia_sil_portal_access_demo access
           JOIN public.vitalia_accounts a ON a.id=access.patient_id
           JOIN public.vitalia_sil_patient_profiles_demo p ON p.patient_id=a.id
           WHERE access.patient_id=$1 AND a.role_code='paciente'
             AND a.email LIKE '%@example.invalid'
           FOR UPDATE OF access`,[patientId]);
        if(result.rows.length!==1)throw new PortalDemoNotFound();
        const patient=result.rows[0];
        email=patient.email;
        if(!['pending','invited'].includes(patient.status))
          throw new PortalDemoConflict();
        const recent=await client.query<{total:number}>(
          `SELECT COUNT(*)::int AS total
           FROM public.vitalia_sil_portal_invitations_demo
           WHERE patient_id=$1 AND created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'`,
          [patientId]);
        if(recent.rows[0].total>=3)throw new PortalDemoConflict();
        await client.query(
          `UPDATE public.vitalia_sil_portal_invitations_demo SET revoked_at=CURRENT_TIMESTAMP
           WHERE patient_id=$1 AND consumed_at IS NULL AND revoked_at IS NULL`,[patientId]);
        await client.query(
          `INSERT INTO public.vitalia_sil_portal_invitations_demo
           (id,patient_id,email_token_hash,handoff_token_hash,issued_by,expires_at)
           VALUES($1,$2,$3,$4,$5,CURRENT_TIMESTAMP + INTERVAL '20 minutes')`,
          [id,patientId,sha(emailCode),sha(handoffCode),actorId]);
        await client.query(
          `UPDATE public.vitalia_sil_portal_access_demo
            SET status='invited',contact_confirmed_at=CURRENT_TIMESTAMP,
              contact_confirmed_by=$2,identity_checked_at=CURRENT_TIMESTAMP,
              identity_checked_by=$2,updated_at=CURRENT_TIMESTAMP
            WHERE patient_id=$1`,[patientId,actorId]);
        await audit(client,patientId,actorId,'invitation_sent_demo',
          {delivery:'simulated_outbox',identityMethod:'operator_in_person_declaration'});
        await client.query('COMMIT');
        // El código del correo nunca se devuelve al operador.
        // Buzón simulado, sólo activo en el servicio DEMO aislado.
        storeDemoMail(email,emailCode);
        return {
          invitation:{id,patientId,status:'invited',expiresInMinutes:20,
            delivery:'simulated_outbox',contactEmail:email},
          handoffCode,
          recipient:{email,syntheticIdentifier:patient.syntheticIdentifier,
            givenNames:patient.givenNames,familyNames:patient.familyNames,
            birthDate:patient.birthDate},
        };
      }catch(error){
        try{await client.query('ROLLBACK');}catch{invalid=true;}
        throw error;
      }finally{client.release(invalid);}
    },
    /** Buzón local simulado: no implementa correo SMTP. No montar en producción. */
    demoMailbox(email:string){
      const address=safeEmail(email);
      const item=mailbox.get(address);
      if(!item||Date.now()>item.expiresAt)return {message:'No hay invitaciones vigentes.'};
      return {
        message:'Mensaje ficticio disponible. Nunca contiene informes ni datos clínicos.',
        subject:'Vitalia Health · Activa tu acceso privado (DEMO)',
        guidance:'Este mensaje sirve únicamente para activar el acceso. '
          +'Verifica que el correo de la invitación sea tuyo, introduce el '
          +'código y la clave recibida en persona, corrobora tus datos y '
          +'crea tu propia contraseña al ingresar. No compartas códigos. '
          +'Si no solicitaste este acceso, comunícate con el laboratorio.',
        emailCode:item.code,expiresAt:new Date(item.expiresAt).toISOString(),
      };
    },
    async activate(input:{
      email:string;emailCode:string;handoffCode:string;password:string;
      confirmedDetails:true;
    }){
      const email=safeEmail(input.email);
      if(!input.confirmedDetails)throw safeCodeError();
      const client=await db.connect();
      let invalid=false;
      try{
        await client.query('BEGIN');
        const result=await client.query<{
          patientId:string;status:string;invitationId:string|null;emailTokenHash:string|null;
          handoffTokenHash:string|null;attempts:number|null;expiresAt:Date|null
        }>(
          `SELECT a.id AS "patientId",access.status,
            i.id AS "invitationId",i.email_token_hash AS "emailTokenHash",
            i.handoff_token_hash AS "handoffTokenHash",
            i.attempts,i.expires_at AS "expiresAt"
           FROM public.vitalia_accounts a
           JOIN public.vitalia_sil_portal_access_demo access ON access.patient_id=a.id
           LEFT JOIN LATERAL (
             SELECT id,email_token_hash,handoff_token_hash,attempts,expires_at
             FROM public.vitalia_sil_portal_invitations_demo
             WHERE patient_id=a.id AND consumed_at IS NULL AND revoked_at IS NULL
             ORDER BY created_at DESC,id DESC LIMIT 1
           ) i ON TRUE
           WHERE a.email=$1 AND a.role_code='paciente'
           FOR UPDATE OF access`,[email]);
        const row=result.rows[0];
        if(!row||row.status!=='invited'||!row.invitationId||
           !row.emailTokenHash||!row.handoffTokenHash||
           !row.expiresAt||row.attempts===null||
           new Date(row.expiresAt).getTime()<=Date.now()||row.attempts>=5)
          throw safeCodeError();
        if(!secureMatch(input.emailCode,row.emailTokenHash) ||
           !secureMatch(input.handoffCode,row.handoffTokenHash)){
          const attempts=row.attempts+1;
          await client.query(
            `UPDATE public.vitalia_sil_portal_invitations_demo
             SET attempts=$2,revoked_at=CASE WHEN $2>=5 THEN CURRENT_TIMESTAMP ELSE NULL END
             WHERE id=$1`,[row.invitationId,attempts]);
          await audit(client,row.patientId,null,'invitation_failed',{attempts});
          await client.query('COMMIT');
          throw safeCodeError();
        }
        const hash=await hashPassword(input.password);
        await client.query(
          'UPDATE public.vitalia_accounts SET password_hash=$2 WHERE id=$1',
          [row.patientId,hash]);
        await client.query(
          `UPDATE public.vitalia_sil_portal_invitations_demo
           SET consumed_at=CURRENT_TIMESTAMP WHERE id=$1`,
          [row.invitationId]);
        await client.query(
          `UPDATE public.vitalia_sil_portal_access_demo
           SET status='active',activated_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP
           WHERE patient_id=$1`,[row.patientId]);
        await client.query(
          `UPDATE public.vitalia_account_roles
           SET active=true WHERE account_id=$1 AND role_code='paciente'`,
          [row.patientId]);
        await client.query(
          'DELETE FROM public.vitalia_sessions WHERE account_id=$1',[row.patientId]);
        await audit(client,row.patientId,row.patientId,'portal_activated',{method:'two_channel'});
        await client.query('COMMIT');
        mailbox.delete(email);
        return {activated:true,loginRequired:true};
      }catch(error){
        // Intentos fallidos ya comprometidos no deben revertirse.
        try{await client.query('ROLLBACK');}catch{invalid=true;}
        throw error;
      }finally{client.release(invalid);}
    },
  };
}
export type SilPortalActivationDemo=ReturnType<typeof createSilPortalActivationDemo>;
