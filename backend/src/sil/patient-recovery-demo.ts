import {createHash,randomBytes,randomUUID,timingSafeEqual} from 'node:crypto';
import {type Pool,type PoolClient} from 'pg';
import {hashPassword,verifyPassword} from '../auth/password';

export class SilRecoveryRejected extends Error {}
export class SilRecoveryBusy extends Error {}

const digest=(value:string)=>createHash('sha256').update(value,'utf8').digest('hex');
const sameDigest=(left:string,right:string)=>
  timingSafeEqual(Buffer.from(left,'hex'),Buffer.from(right,'hex'));

export function createSilPatientRecoveryDemo(db:Pick<Pool,'connect'>){
  let busy=false;
  async function transact<T>(work:(client:PoolClient)=>Promise<T>):Promise<T>{
    if(busy)throw new SilRecoveryBusy();
    busy=true;
    let client:PoolClient|undefined;
    let discard=false;
    try{
      client=await db.connect();
      await client.query('BEGIN');
      const result=await work(client);
      await client.query('COMMIT');
      return result;
    }catch(error){
      if(client)try{await client.query('ROLLBACK');}catch{discard=true;}
      throw error;
    }finally{
      client?.release(discard);
      busy=false;
    }
  }

  async function lockPatient(client:PoolClient,email:string){
    const {rows}=await client.query<{id:string;password_hash:string}>(
      `SELECT a.id,a.password_hash
       FROM public.vitalia_accounts a
       JOIN public.vitalia_account_roles role ON role.account_id=a.id
       LEFT JOIN public.vitalia_sil_portal_access_demo portal ON portal.patient_id=a.id
       WHERE a.email=$1 AND a.email LIKE '%@example.invalid'
         AND a.role_code='paciente' AND role.role_code='paciente' AND role.active
         AND (portal.status IS NULL OR portal.status='active')
       FOR UPDATE OF a`,[email]);
    return rows[0];
  }

  async function audit(client:PoolClient,patientId:string,action:string){
    await client.query(
      `INSERT INTO public.vitalia_sil_patient_security_audit_demo (id,patient_id,action)
       VALUES ($1,$2,$3)`,[randomUUID(),patientId,action]);
  }

  return {
    async generate(account:{id:string;email:string},currentPassword:string){
      return transact(async client=>{
        const patient=await lockPatient(client,account.email);
        if(!patient||patient.id!==account.id||
          !await verifyPassword(currentPassword,patient.password_hash))throw new SilRecoveryRejected();
        const key=randomBytes(32).toString('base64url');
        const issued=await client.query<{expires_at:Date}>(
          `INSERT INTO public.vitalia_sil_patient_recovery_demo
           (patient_id,key_hash,credential_digest,expires_at)
           VALUES ($1,$2,$3,statement_timestamp()+INTERVAL '90 days')
           ON CONFLICT(patient_id) DO UPDATE SET
             key_hash=EXCLUDED.key_hash,credential_digest=EXCLUDED.credential_digest,
             expires_at=EXCLUDED.expires_at
           RETURNING expires_at`,[patient.id,digest(key),digest(patient.password_hash)]);
        await audit(client,patient.id,'recovery_key_generated');
        return {recoveryKey:key,expiresAt:issued.rows[0].expires_at};
      });
    },
    async recover(email:string,recoveryKey:string,password:string){
      return transact(async client=>{
        const patient=await lockPatient(client,email);
        // Consultar siempre la misma ruta de código y devolver el mismo error.
        const {rows}=await client.query<{key_hash:string;credential_digest:string}>(
          `SELECT key_hash,credential_digest FROM public.vitalia_sil_patient_recovery_demo
           WHERE patient_id=$1 AND expires_at>statement_timestamp()`,[patient?.id??null]);
        const current=rows[0];
        const keyMatches=sameDigest(digest(recoveryKey),current?.key_hash??'0'.repeat(64));
        if(!patient||!current||!keyMatches||
          !sameDigest(digest(patient.password_hash),current.credential_digest))throw new SilRecoveryRejected();
        const hash=await hashPassword(password);
        await client.query(
          'UPDATE public.vitalia_accounts SET password_hash=$2 WHERE id=$1',[patient.id,hash]);
        await client.query(
          'DELETE FROM public.vitalia_sil_patient_recovery_demo WHERE patient_id=$1',[patient.id]);
        await client.query(
          'DELETE FROM public.vitalia_sessions WHERE account_id=$1 AND active_role=\'paciente\'',[patient.id]);
        await audit(client,patient.id,'password_recovered');
      });
    },
  };
}
export type SilPatientRecoveryDemo=ReturnType<typeof createSilPatientRecoveryDemo>;
