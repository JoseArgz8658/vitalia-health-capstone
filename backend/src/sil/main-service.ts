import {randomUUID,createHash} from 'node:crypto';
import {type Pool,type PoolClient} from 'pg';
import {identifyDocument} from '../documents/file-validation';
import {createSilPatientReportOverview} from './patient-report-overview';
import {createSilPatientEducation} from './patient-education';

export class SilMainAccessDenied extends Error {}
export class SilMainNotFound extends Error {}
export class SilMainConflict extends Error {}

type Queryable=Pick<Pool,'query'>;

export function createSilMainService(db:Pool) {
  // Reutilizar la lógica educativa validada, pero con consultas SQL propias
  // del SIL principal. No se lee ninguna tabla *_demo.
  const mainOverview=createSilPatientReportOverview(db,undefined,'main');
  const mainEducation=createSilPatientEducation(db,undefined,mainOverview,'main');
  async function audit(tx:Pick<PoolClient,'query'>,labId:string,actorId:string,
    action:'laboratory_created'|'staff_granted'|'patient_identity_linked'|
      'order_created'|'report_attached'|'report_published'|'report_downloaded',
    orderId:string|null=null,details:Record<string,unknown>={}) {
    await tx.query(
      `INSERT INTO public.vitalia_sil_main_audit
       (id,lab_id,order_id,actor_id,action,details)
       VALUES($1,$2,$3,$4,$5,$6::jsonb)`,
      [randomUUID(),labId,orderId,actorId,action,JSON.stringify(details)]);
  }
  async function operator(labId:string,accountId:string,query:Queryable=db){
    const check=await query.query(
      `SELECT 1 FROM public.vitalia_sil_main_staff s
       JOIN public.vitalia_sil_main_laboratories l ON l.id=s.lab_id AND l.active
       JOIN public.vitalia_account_roles r
         ON r.account_id=s.account_id
         AND r.role_code='operador_laboratorio' AND r.active
       WHERE s.lab_id=$1 AND s.account_id=$2
         AND s.kind='operator' AND s.active`,[labId,accountId]);
    if(!check.rows.length)throw new SilMainAccessDenied();
  }
  async function validator(labId:string,accountId:string,query:Queryable=db){
    const check=await query.query(
      `SELECT 1 FROM public.vitalia_sil_main_staff s
       JOIN public.vitalia_sil_main_laboratories l ON l.id=s.lab_id AND l.active
       JOIN public.vitalia_account_roles r
         ON r.account_id=s.account_id AND r.role_code='profesional' AND r.active
       JOIN public.vitalia_people p ON p.account_id=s.account_id
       JOIN public.vitalia_professional_profiles pr
         ON pr.person_id=p.id AND pr.verification_status='verified'
         AND pr.registration_reference IS NOT NULL
       WHERE s.lab_id=$1 AND s.account_id=$2
         AND s.kind='validator' AND s.active`,[labId,accountId]);
    if(!check.rows.length)throw new SilMainAccessDenied();
  }
  async function transaction<T>(operation:(tx:PoolClient)=>Promise<T>):Promise<T>{
    const tx=await db.connect();
    let failed=false;
    try{
      await tx.query('BEGIN');
      const value=await operation(tx);
      await tx.query('COMMIT');
      return value;
    }catch(error){
      try{await tx.query('ROLLBACK');}catch{failed=true;}
      throw error;
    }finally{tx.release(failed);}
  }

  return {
    getPatientReportOverview:mainOverview,
    askPatientReport:mainEducation.ask,
    async laboratoriesFor(accountId:string,role:string){
      const res=role==='administrador'
        ?await db.query(
          `SELECT id,display_name AS "displayName",active
           FROM public.vitalia_sil_main_laboratories ORDER BY display_name`)
        :await db.query(
          `SELECT l.id,l.display_name AS "displayName",l.active,s.kind
           FROM public.vitalia_sil_main_laboratories l
           JOIN public.vitalia_sil_main_staff s ON s.lab_id=l.id
           WHERE s.account_id=$1 AND s.active AND l.active
           ORDER BY l.display_name`,[accountId]);
      return {laboratories:res.rows};
    },

    async createLaboratory(name:string,adminId:string){
      return transaction(async tx=>{
        const id=randomUUID();
        const row=await tx.query(
          `INSERT INTO public.vitalia_sil_main_laboratories
           (id,display_name,created_by) VALUES($1,$2,$3)
           RETURNING id,display_name AS "displayName"`,[id,name,adminId]);
        await audit(tx,id,adminId,'laboratory_created');
        return {laboratory:row.rows[0]};
      });
    },

    async grantStaff(labId:string,accountId:string,kind:'operator'|'validator',adminId:string){
      return transaction(async tx=>{
        const lab=await tx.query(
          'SELECT 1 FROM public.vitalia_sil_main_laboratories WHERE id=$1 AND active FOR UPDATE',
          [labId]);
        if(!lab.rows.length)throw new SilMainNotFound();
        // Un profesional validador debe estar acreditado por el sistema original.
        const role=kind==='operator'?'operador_laboratorio':'profesional';
        const check=kind==='operator'
          ?await tx.query(
            `SELECT 1 FROM public.vitalia_account_roles
             WHERE account_id=$1 AND role_code=$2 AND active`,[accountId,role])
          :await tx.query(
            `SELECT 1 FROM public.vitalia_account_roles r
             JOIN public.vitalia_people p ON p.account_id=r.account_id
             JOIN public.vitalia_professional_profiles pr ON pr.person_id=p.id
             WHERE r.account_id=$1 AND r.role_code=$2 AND r.active
               AND pr.verification_status='verified'
               AND pr.registration_reference IS NOT NULL`,[accountId,role]);
        if(!check.rows.length)throw new SilMainAccessDenied();
        const created=await tx.query(
          `INSERT INTO public.vitalia_sil_main_staff
           (lab_id,account_id,kind,granted_by) VALUES($1,$2,$3,$4)
           ON CONFLICT(lab_id,account_id) DO NOTHING RETURNING lab_id`,
          [labId,accountId,kind,adminId]);
        if(!created.rows.length)throw new SilMainConflict();
        await audit(tx,labId,adminId,'staff_granted',null,{kind});
        return {membership:{labId,accountId,kind,active:true}};
      });
    },

    async associatePatient(labId:string,patientId:string,operatorId:string,
      evidenceReference:string) {
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        const account=await tx.query(
          `SELECT 1 FROM public.vitalia_account_roles
           WHERE account_id=$1 AND role_code='paciente' AND active`,[patientId]);
        if(!account.rows.length)throw new SilMainNotFound();
        const enrolled=await tx.query(
          `INSERT INTO public.vitalia_sil_main_patients
           (lab_id,patient_id,verified_by,identity_evidence_reference)
           VALUES($1,$2,$3,$4)
           ON CONFLICT(lab_id,patient_id) DO NOTHING RETURNING patient_id`,
          [labId,patientId,operatorId,evidenceReference]);
        if(!enrolled.rows.length)throw new SilMainConflict();
        await audit(tx,labId,operatorId,'patient_identity_linked');
        return {patientId,labId,linked:true};
      });
    },

    async createOrder(labId:string,patientId:string,examCodes:string[],operatorId:string){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        const patient=await tx.query(
          `SELECT 1 FROM public.vitalia_sil_main_patients
           WHERE lab_id=$1 AND patient_id=$2 AND active`,[labId,patientId]);
        if(!patient.rows.length)throw new SilMainNotFound();
        const codes=await tx.query(
          `SELECT code FROM public.vitalia_sil_exam_catalog
           WHERE active AND code=ANY($1::text[])`,[examCodes]);
        if(codes.rows.length!==examCodes.length || new Set(examCodes).size!==examCodes.length)
          throw new SilMainConflict();
        const id=randomUUID();
        const inserted=await tx.query(
          `INSERT INTO public.vitalia_sil_main_orders
           (id,lab_id,patient_id,created_by) VALUES($1,$2,$3,$4)
           RETURNING id,order_number AS "orderNumber",status`,
          [id,labId,patientId,operatorId]);
        for(const code of examCodes){
          await tx.query(
            `INSERT INTO public.vitalia_sil_main_order_exams(order_id,exam_code)
             VALUES($1,$2)`,[id,code]);
        }
        await audit(tx,labId,operatorId,'order_created',id,{exams:examCodes.length});
        return {order:{...inserted.rows[0],labId,patientId,examCodes}};
      });
    },

    async listOrders(labId:string,accountId:string,role:string,
      limit:number,offset:number){
      if(role==='profesional')await validator(labId,accountId);
      else if(role!=='administrador')await operator(labId,accountId);
      const results=await db.query(
        `SELECT o.id,o.order_number AS "orderNumber",o.status,
           o.patient_id AS "patientId",o.created_at AS "createdAt",
           ARRAY(SELECT e.exam_code FROM public.vitalia_sil_main_order_exams e
             WHERE e.order_id=o.id ORDER BY e.exam_code) AS "examCodes"
         FROM public.vitalia_sil_main_orders o
         JOIN public.vitalia_sil_main_laboratories l ON l.id=o.lab_id AND l.active
         WHERE o.lab_id=$1 ORDER BY o.created_at DESC,o.id LIMIT $2 OFFSET $3`,
        [labId,limit,offset]);
      return {orders:results.rows};
    },

    async attachReport(labId:string,orderId:string,operatorId:string,
      input:{fileName:string;authorizedProfessionalName:string;
        authorizationReference:string;externallyAuthorizedAt:string;
        patientMatchConfirmed:true},bytes:Buffer){
      identifyDocument(bytes,'application/pdf',input.fileName);
      if(bytes.length<8 || bytes.length>2*1024*1024 || !input.patientMatchConfirmed)
        throw new SilMainConflict();
      const date=new Date(input.externallyAuthorizedAt);
      if(!Number.isFinite(date.getTime()) || date.getTime()>Date.now())
        throw new SilMainConflict();
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        const row=await tx.query<{
          patientId:string;status:string;displayName:string
        }>(
          `SELECT o.patient_id AS "patientId",o.status,
              l.display_name AS "displayName"
           FROM public.vitalia_sil_main_orders o
           JOIN public.vitalia_sil_main_laboratories l ON l.id=o.lab_id
           WHERE o.id=$1 AND o.lab_id=$2 FOR UPDATE OF o`,
          [orderId,labId]);
        if(!row.rows.length)throw new SilMainNotFound();
        if(row.rows[0].status!=='registered')throw new SilMainConflict();
        const id=randomUUID();
        await tx.query(
          `INSERT INTO public.vitalia_sil_main_reports
           (id,order_id,lab_id,patient_id,file_name,pdf_data,pdf_sha256,
            issuing_laboratory,external_authorization_ref,authorized_professional_name,
            externally_authorized_at,patient_match_confirmed,attached_by)
           VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,true,$12)`,
          [id,orderId,labId,row.rows[0].patientId,input.fileName,
           bytes,createHash('sha256').update(bytes).digest('hex'),
           row.rows[0].displayName,input.authorizationReference,
           input.authorizedProfessionalName,date,operatorId]);
        await tx.query(
          `UPDATE public.vitalia_sil_main_orders
           SET status='report_attached' WHERE id=$1 AND lab_id=$2`,
          [orderId,labId]);
        await audit(tx,labId,operatorId,'report_attached',orderId,{reportId:id});
        return {report:{id,orderId,status:'report_attached'}};
      });
    },

    async publishReport(labId:string,orderId:string,validatorId:string){
      return transaction(async tx=>{
        await validator(labId,validatorId,tx);
        const report=await tx.query<{id:string}>(
          `UPDATE public.vitalia_sil_main_reports r
           SET published_at=CURRENT_TIMESTAMP,published_by=$3
           FROM public.vitalia_sil_main_orders o
           WHERE r.order_id=o.id AND r.order_id=$1 AND r.lab_id=$2
             AND o.lab_id=$2 AND o.status='report_attached'
             AND r.published_at IS NULL AND r.patient_match_confirmed
             AND r.attached_by<>$3
           RETURNING r.id`,[orderId,labId,validatorId]);
        if(!report.rows.length)throw new SilMainConflict();
        await tx.query(
          `UPDATE public.vitalia_sil_main_orders
           SET status='report_published'
           WHERE id=$1 AND lab_id=$2 AND status='report_attached'`,
          [orderId,labId]);
        await audit(tx,labId,validatorId,'report_published',orderId,
          {reportId:report.rows[0].id});
        return {publication:{orderId,reportId:report.rows[0].id,
          status:'report_published'}};
      });
    },

    async patientProfile(patientId:string){
      const profile=await db.query(
        `SELECT a.email,p.first_name AS "givenNames",
           p.first_surname AS "familyNames",
           p.birth_date::text AS "birthDate",p.phone,
           p.id IS NOT NULL AS "hasProfile"
         FROM public.vitalia_accounts a
         LEFT JOIN public.vitalia_people p ON p.account_id=a.id
         LEFT JOIN public.vitalia_patient_profiles pr ON pr.person_id=p.id
         WHERE a.id=$1 AND a.role_code='paciente'`,[patientId]);
      if(!profile.rows.length)throw new SilMainNotFound();
      return {profile:profile.rows[0]};
    },

    async patientReports(patientId:string){
      const found=await db.query(
        `SELECT r.id,r.file_name AS "fileName",
           r.issuing_laboratory AS "issuingLaboratory",
           r.externally_authorized_at AS "externallyAuthorizedAt",
           r.published_at AS "publishedAt",
           'VH-' || lpad(o.order_number::text,6,'0') AS "orderNumber",
           ARRAY(SELECT c.name FROM public.vitalia_sil_main_order_exams e
             JOIN public.vitalia_sil_exam_catalog c ON c.code=e.exam_code
             WHERE e.order_id=o.id ORDER BY c.name) AS "examNames",
           r.pdf_sha256 AS sha256
         FROM public.vitalia_sil_main_reports r
         JOIN public.vitalia_sil_main_orders o
           ON o.id=r.order_id AND o.lab_id=r.lab_id AND o.patient_id=r.patient_id
         JOIN public.vitalia_sil_main_patients p
           ON p.lab_id=r.lab_id AND p.patient_id=r.patient_id AND p.active
         JOIN public.vitalia_sil_main_laboratories l ON l.id=r.lab_id AND l.active
         WHERE r.patient_id=$1 AND r.published_at IS NOT NULL
           AND o.status='report_published'
         ORDER BY r.published_at DESC,r.id LIMIT 50`,[patientId]);
      return {reports:found.rows};
    },

    async downloadPatientReport(patientId:string,reportId:string){
      const file=await db.query<{
        id:string;labId:string;orderId:string;fileName:string;bytes:Buffer;sha256:string
      }>(
        `SELECT r.id,r.lab_id AS "labId",r.order_id AS "orderId",
             r.file_name AS "fileName",r.pdf_data AS bytes,r.pdf_sha256 AS sha256
         FROM public.vitalia_sil_main_reports r
         JOIN public.vitalia_sil_main_orders o
           ON o.id=r.order_id AND o.lab_id=r.lab_id AND o.patient_id=r.patient_id
         JOIN public.vitalia_sil_main_patients p
           ON p.lab_id=r.lab_id AND p.patient_id=r.patient_id AND p.active
         JOIN public.vitalia_sil_main_laboratories l ON l.id=r.lab_id AND l.active
         WHERE r.id=$1 AND r.patient_id=$2 AND r.published_at IS NOT NULL
           AND o.status='report_published'`,[reportId,patientId]);
      if(!file.rows.length)throw new SilMainNotFound();
      const item=file.rows[0];
      if(item.bytes.length>2*1024*1024 ||
         createHash('sha256').update(item.bytes).digest('hex')!==item.sha256)
        throw new SilMainConflict();
      await audit(db,item.labId,patientId,'report_downloaded',item.orderId,
        {reportId:item.id});
      return {fileName:item.fileName,bytes:item.bytes};
    },
  };
}

export type SilMainServices=ReturnType<typeof createSilMainService>;
