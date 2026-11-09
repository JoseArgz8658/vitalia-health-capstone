import {randomUUID,createHash,randomBytes} from 'node:crypto';
import {hashPassword} from '../auth/password';
import {type Pool,type PoolClient} from 'pg';
import {createSilPatientRecoveryDemo} from './patient-recovery-demo';
import {readPdfText} from '../pdf/reader';
import {suggestMainResults} from './main-results-preview';
import {suggestMedicalRequestFields} from './medical-request-intake';
import {identifyDocument} from '../documents/file-validation';
import {createSilPatientReportOverview} from './patient-report-overview';
import {createSilPatientEducation} from './patient-education';

export class SilMainAccessDenied extends Error {}
export class SilMainNotFound extends Error {}
export class SilMainConflict extends Error {}

type MedicalRequestInput={
  fileName:string;prescriberName:string;documentReference:string;
  requestDate:string;patientIdentityConfirmed:true;humanReviewConfirmed:true;
};

function checkMedicalRequest(input:MedicalRequestInput,bytes:Buffer){
  identifyDocument(bytes,'application/pdf',input.fileName);
  const date=new Date(input.requestDate+'T00:00:00Z');
  if(bytes.length<8||bytes.length>2*1024*1024||
     !input.patientIdentityConfirmed||!input.humanReviewConfirmed||
     !Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==input.requestDate||
     date.getTime()>Date.now())throw new SilMainConflict();
}

type Queryable=Pick<Pool,'query'>;

export function createSilMainService(db:Pool) {
  // Reutilizar la lógica educativa validada, pero con consultas SQL propias
  // del SIL principal. No se lee ninguna tabla *_demo.
  const mainOverview=createSilPatientReportOverview(db,undefined,'main');
  const mainEducation=createSilPatientEducation(db,undefined,mainOverview,'main');
  async function audit(tx:Pick<PoolClient,'query'>,labId:string,actorId:string,
    action:'laboratory_created'|'operator_invited'|'operator_activated'|
      'staff_granted'|'operator_review_permission_changed'|'patient_identity_linked'|
      'order_created'|'medical_request_received'|'medical_request_downloaded'|
      'report_attached'|'report_review_accessed'|'report_published'|'report_downloaded'|
      'sample_received'|'results_recorded'|'results_approved'|'results_returned'|
      'patient_invited'|'patient_activated',
    orderId:string|null=null,details:Record<string,unknown>={}) {
    await tx.query(
      `INSERT INTO public.vitalia_sil_main_audit
       (id,lab_id,order_id,actor_id,action,details)
       VALUES($1,$2,$3,$4,$5,$6::jsonb)`,
      [randomUUID(),labId,orderId,actorId,action,JSON.stringify(details)]);
  }
  async function operator(labId:string,accountId:string,query:Queryable=db,
    requireReview=false){
    const check=await query.query(
      `SELECT 1 FROM public.vitalia_sil_main_staff s
       JOIN public.vitalia_sil_main_laboratories l ON l.id=s.lab_id AND l.active
       JOIN public.vitalia_account_roles r
         ON r.account_id=s.account_id
         AND r.role_code='operador_laboratorio' AND r.active
       WHERE s.lab_id=$1 AND s.account_id=$2
         AND s.kind='operator' AND s.active
         AND (NOT $3::boolean OR s.can_review_reports)
       FOR SHARE OF s,l,r`,[labId,accountId,requireReview]);
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

  let readingPdf=false;

  async function insertOrder(tx:PoolClient,labId:string,patientId:string,examCodes:string[],operatorId:string){
    const patient=await tx.query(
      `SELECT 1 FROM public.vitalia_sil_main_patients
       WHERE lab_id=$1 AND patient_id=$2 AND active FOR SHARE`,[labId,patientId]);
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
    return {order:{...inserted.rows[0],id,labId,patientId,examCodes}};
  }

  async function insertMedicalRequest(tx:PoolClient,labId:string,orderId:string,patientId:string,
    operatorId:string,input:MedicalRequestInput,bytes:Buffer){
    const id=randomUUID();
    const saved=await tx.query(
      `INSERT INTO public.vitalia_sil_main_medical_requests(
        id,order_id,lab_id,patient_id,document_reference,
        prescriber_name,request_date,file_name,pdf_data,pdf_sha256,
        patient_identity_confirmed,human_review_confirmed,received_by
      ) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,true,true,$11)
      ON CONFLICT DO NOTHING RETURNING id`,
      [id,orderId,labId,patientId,input.documentReference,input.prescriberName,
        input.requestDate,input.fileName,bytes,createHash('sha256').update(bytes).digest('hex'),operatorId]);
    if(!saved.rows.length)throw new SilMainConflict();
    await audit(tx,labId,operatorId,'medical_request_received',orderId,{requestId:id});
    return {request:{id,orderId,status:'received'}};
  }

  async function clinicalOrder(tx:PoolClient,labId:string,orderId:string){
    const order=await tx.query<{status:string}>(
      'SELECT status FROM public.vitalia_sil_main_orders WHERE id=$1 AND lab_id=$2 FOR UPDATE',
      [orderId,labId]);
    if(!order.rows.length)throw new SilMainNotFound();
    return order.rows[0].status;
  }
  async function containersFor(tx:PoolClient,orderId:string){
    return (await tx.query<{code:string;label:string;barcode:string|null}>(
      `SELECT DISTINCT c.code,c.label,s.barcode
       FROM public.vitalia_sil_main_order_exams e
       JOIN public.vitalia_sil_exam_containers m ON m.exam_code=e.exam_code
       JOIN public.vitalia_sil_containers c ON c.code=m.container_code
       LEFT JOIN public.vitalia_sil_main_samples s
         ON s.order_id=e.order_id AND s.container_code=c.code
       WHERE e.order_id=$1 ORDER BY c.code`,[orderId])).rows;
  }
  async function analytesFor(tx:PoolClient,orderId:string){
    return (await tx.query<{examCode:string;analyte:string;unit:string}>(
      `SELECT e.exam_code AS "examCode",a.analyte,a.unit
       FROM public.vitalia_sil_main_order_exams e
       JOIN public.vitalia_sil_exam_analytes a ON a.exam_code=e.exam_code
       WHERE e.order_id=$1 ORDER BY e.exam_code,a.analyte`,[orderId])).rows;
  }

  return {
    patientRecovery:createSilPatientRecoveryDemo(db,'main'),
    getPatientReportOverview:mainOverview,
    askPatientReport:mainEducation.ask,
    async laboratoriesFor(accountId:string,role:string){
      const res=role==='administrador'
        ?await db.query(
          `SELECT id,display_name AS "displayName",active
           FROM public.vitalia_sil_main_laboratories ORDER BY display_name`)
        :await db.query(
          `SELECT l.id,l.display_name AS "displayName",l.active,s.can_review_reports AS "canReviewReports"
           FROM public.vitalia_sil_main_laboratories l
           JOIN public.vitalia_sil_main_staff s ON s.lab_id=l.id
           WHERE s.account_id=$1 AND s.kind='operator' AND s.active AND l.active
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

    async inviteOperator(labId:string,email:string,adminId:string){
      const code=randomBytes(32).toString('base64url');
      const digest=createHash('sha256').update(code).digest('hex');
      const normalized=email.trim().toLowerCase();
      return transaction(async tx=>{
        const lab=await tx.query(
          'SELECT 1 FROM public.vitalia_sil_main_laboratories WHERE id=$1 AND active FOR UPDATE',
          [labId]);
        if(!lab.rows.length)throw new SilMainNotFound();
        const existing=await tx.query(
          'SELECT 1 FROM public.vitalia_accounts WHERE email=$1',[normalized]);
        if(existing.rows.length)throw new SilMainConflict();
        const recent=await tx.query<{total:number}>(
          `SELECT count(*)::int AS total
           FROM public.vitalia_sil_main_operator_invites
           WHERE lab_id=$1 AND email=$2
             AND created_at>CURRENT_TIMESTAMP-INTERVAL '1 hour'`,
          [labId,normalized]);
        if((recent.rows[0]?.total??0)>=3)throw new SilMainConflict();
        await tx.query(
          `UPDATE public.vitalia_sil_main_operator_invites
           SET revoked_at=CURRENT_TIMESTAMP
           WHERE lab_id=$1 AND email=$2
             AND consumed_at IS NULL AND revoked_at IS NULL`,
          [labId,normalized]);
        const id=randomUUID();
        const expiresAt=new Date(Date.now()+24*60*60*1000);
        await tx.query(
          `INSERT INTO public.vitalia_sil_main_operator_invites
           (id,lab_id,email,token_hash,issued_by,expires_at)
           VALUES($1,$2,$3,$4,$5,$6)`,
          [id,labId,normalized,digest,adminId,expiresAt]);
        await audit(tx,labId,adminId,'operator_invited',null,{inviteId:id});
        // Se entrega una única vez, por canal verificado externo.
        return {invitation:{labId,email:normalized,code,expiresAt}};
      });
    },

    async activateOperator(email:string,code:string,password:string){
      // Calcular scrypt fuera de la transacción para reducir el bloqueo.
      const credential=await hashPassword(password);
      const normalized=email.trim().toLowerCase();
      const digest=createHash('sha256').update(code).digest('hex');
      return transaction(async tx=>{
        const result=await tx.query<{id:string;labId:string}>(
          `SELECT id,lab_id AS "labId"
           FROM public.vitalia_sil_main_operator_invites
           WHERE email=$1 AND token_hash=$2 AND consumed_at IS NULL
             AND revoked_at IS NULL AND expires_at>CURRENT_TIMESTAMP
           FOR UPDATE`,[normalized,digest]);
        if(!result.rows.length)throw new SilMainAccessDenied();
        const invite=result.rows[0];
        const exists=await tx.query(
          'SELECT 1 FROM public.vitalia_accounts WHERE email=$1 FOR UPDATE',[normalized]);
        if(exists.rows.length)throw new SilMainConflict();
        const accountId=randomUUID();
        await tx.query(
          `INSERT INTO public.vitalia_accounts
           (id,email,password_hash,role_code)
           VALUES($1,$2,$3,'operador_laboratorio')`,
          [accountId,normalized,credential]);
        await tx.query(
          `INSERT INTO public.vitalia_sil_main_staff
           (lab_id,account_id,kind,granted_by)
           SELECT $1,$2,'operator',issued_by
           FROM public.vitalia_sil_main_operator_invites WHERE id=$3`,
          [invite.labId,accountId,invite.id]);
        await tx.query(
          `UPDATE public.vitalia_sil_main_operator_invites
           SET consumed_at=CURRENT_TIMESTAMP WHERE id=$1`,[invite.id]);
        await audit(tx,invite.labId,accountId,'operator_activated',
          null,{inviteId:invite.id});
        return {status:'activated'};
      });
    },

    async grantStaff(labId:string,accountId:string,adminId:string){
      return transaction(async tx=>{
        const lab=await tx.query(
          'SELECT 1 FROM public.vitalia_sil_main_laboratories WHERE id=$1 AND active FOR UPDATE',
          [labId]);
        if(!lab.rows.length)throw new SilMainNotFound();
        const check=await tx.query(
          `SELECT 1 FROM public.vitalia_account_roles
           WHERE account_id=$1 AND role_code='operador_laboratorio' AND active`,
          [accountId]);
        if(!check.rows.length)throw new SilMainAccessDenied();
        const created=await tx.query(
          `INSERT INTO public.vitalia_sil_main_staff
           (lab_id,account_id,kind,granted_by) VALUES($1,$2,'operator',$3)
           ON CONFLICT(lab_id,account_id) DO NOTHING RETURNING lab_id`,
          [labId,accountId,adminId]);
        if(!created.rows.length)throw new SilMainConflict();
        await audit(tx,labId,adminId,'staff_granted',null,{accountId,kind:'operator'});
        return {membership:{labId,accountId,kind:'operator',active:true,canReviewReports:false}};
      });
    },

    async setReviewPermission(labId:string,accountId:string,adminId:string,enabled:boolean){
      return transaction(async tx=>{
        const lab=await tx.query(
          'SELECT 1 FROM public.vitalia_sil_main_laboratories WHERE id=$1 AND active FOR UPDATE',
          [labId]);
        if(!lab.rows.length)throw new SilMainNotFound();
        await operator(labId,accountId,tx);
        const changed=await tx.query(
          `UPDATE public.vitalia_sil_main_staff SET can_review_reports=$3
           WHERE lab_id=$1 AND account_id=$2 AND can_review_reports<>$3
           RETURNING account_id`,[labId,accountId,enabled]);
        if(changed.rows.length){
          await audit(tx,labId,adminId,'operator_review_permission_changed',null,
            {accountId,enabled});
        }
        return {membership:{labId,accountId,canReviewReports:enabled}};
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
        return insertOrder(tx,labId,patientId,examCodes,operatorId);
      });
    },

    async listPatients(labId:string,operatorId:string,
      {limit,offset,search}:{limit:number;offset:number;search:string}){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        const result=await tx.query(
          `SELECT a.id,a.email,p.first_name AS "givenNames",p.first_surname AS "familyNames"
           FROM public.vitalia_sil_main_patients lp
           JOIN public.vitalia_accounts a ON a.id=lp.patient_id
           JOIN public.vitalia_account_roles r
             ON r.account_id=a.id AND r.role_code='paciente' AND r.active
           LEFT JOIN public.vitalia_people p ON p.account_id=a.id
           WHERE lp.lab_id=$1 AND lp.active
             AND strpos(lower(concat_ws(' ',a.email,p.first_name,p.first_surname)),lower($2))>0
           ORDER BY a.email,a.id LIMIT $3 OFFSET $4`,
          [labId,search,limit+1,offset]);
        return {patients:result.rows.slice(0,limit),hasMore:result.rows.length>limit};
      });
    },

    async listOrders(labId:string,accountId:string,role:string,
      limit:number,offset:number){
      if(role!=='administrador')await operator(labId,accountId);
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

    async clinicalDetails(labId:string,orderId:string,operatorId:string){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        const status=await clinicalOrder(tx,labId,orderId);
        const containers=await containersFor(tx,orderId);
        const analytes=await analytesFor(tx,orderId);
        const result=await tx.query(
          'SELECT status,values_json AS values FROM public.vitalia_sil_main_result_sets WHERE order_id=$1',
          [orderId]);
        const request=await tx.query<{present:boolean}>(
          `SELECT EXISTS(SELECT 1 FROM public.vitalia_sil_main_medical_requests
             WHERE lab_id=$1 AND order_id=$2) AS present`,[labId,orderId]);
        return {status,containers,analytes,results:result.rows[0]??null,
          hasMedicalRequest:request.rows[0].present};
      });
    },

    async recentOrderActivity(labId:string,orderId:string,operatorId:string){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        const order=await tx.query(
          'SELECT 1 FROM public.vitalia_sil_main_orders WHERE id=$1 AND lab_id=$2',
          [orderId,labId]);
        if(!order.rows.length)throw new SilMainNotFound();
        const limit=30;
        const events=await tx.query<{action:string;createdAt:Date;staffEmail:string|null}>(
          `SELECT a.action,a.created_at AS "createdAt",
             CASE WHEN a.action<>'report_downloaded' THEN actor.email END AS "staffEmail"
           FROM public.vitalia_sil_main_audit a
           JOIN public.vitalia_accounts actor ON actor.id=a.actor_id
           WHERE a.lab_id=$1 AND a.order_id=$2
           ORDER BY a.created_at DESC,a.id LIMIT $3`,[labId,orderId,limit+1]);
        return {events:events.rows.slice(0,limit),hasOlder:events.rows.length>limit};
      });
    },

    async receiveSample(labId:string,orderId:string,operatorId:string,code:string){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        if(await clinicalOrder(tx,labId,orderId)!=='registered')throw new SilMainConflict();
        const container=(await containersFor(tx,orderId)).find(item=>item.code===code);
        if(!container||container.barcode)throw new SilMainConflict();
        const barcode='LAB-'+randomUUID().toUpperCase();
        await tx.query(
          `INSERT INTO public.vitalia_sil_main_samples
           (order_id,lab_id,container_code,barcode,received_by) VALUES($1,$2,$3,$4,$5)`,
          [orderId,labId,code,barcode,operatorId]);
        await audit(tx,labId,operatorId,'sample_received',orderId,{containerCode:code});
        return {barcode};
      });
    },

    async previewAnalytes(labId:string,orderId:string,operatorId:string,bytes:Buffer){
      const {status,containers,analytes,results}=await this.clinicalDetails(labId,orderId,operatorId);
      const barcodes=containers.flatMap(row=>row.barcode?[row.barcode]:[]);
      if(status!=='registered'||!analytes.length||!barcodes.length||barcodes.length!==containers.length||
        (results&&results.status!=='returned'))throw new SilMainConflict();
      if(bytes.length<8||bytes.length>2*1024*1024)throw new SilMainConflict();
      identifyDocument(bytes,'application/pdf','resultados.pdf');
      if(readingPdf)throw new SilMainConflict();
      readingPdf=true;
      try {
        const reading=await readPdfText(bytes);
        if(reading.status!=='text_ready'||!reading.text){
          return {state:reading.status==='needs_ocr'?'needs_ocr':'unreadable',items:[]};
        }
        return suggestMainResults(reading.text,barcodes,analytes);
      } finally {
        readingPdf=false;
      }
    },

    async recordAnalytes(labId:string,orderId:string,operatorId:string,
      values:{examCode:string;analyte:string;numericValue:number}[]){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        if(await clinicalOrder(tx,labId,orderId)!=='registered')throw new SilMainConflict();
        const containers=await containersFor(tx,orderId);
        if(!containers.length||containers.some(item=>!item.barcode))throw new SilMainConflict();
        const expected=await analytesFor(tx,orderId);
        const provided=new Map(values.map(row=>[row.examCode+'|'+row.analyte,row.numericValue]));
        if(!expected.length||provided.size!==values.length||expected.length!==values.length||
          expected.some(row=>!provided.has(row.examCode+'|'+row.analyte)))throw new SilMainConflict();
        const previous=await tx.query<{status:string;values:unknown}>(
          'SELECT status,values_json AS values FROM public.vitalia_sil_main_result_sets WHERE order_id=$1',[orderId]);
        if(previous.rows.length&&previous.rows[0].status!=='returned')throw new SilMainConflict();
        const payload=expected.map(row=>({...row,numericValue:provided.get(row.examCode+'|'+row.analyte)}));
        await tx.query(
          `INSERT INTO public.vitalia_sil_main_result_sets(order_id,lab_id,status,values_json)
           VALUES($1,$2,'pending',$3::jsonb) ON CONFLICT(order_id) DO UPDATE
           SET status='pending',values_json=EXCLUDED.values_json`,[orderId,labId,JSON.stringify(payload)]);
        await audit(tx,labId,operatorId,'results_recorded',orderId,{
          count:payload.length,...(previous.rows.length?{previous:previous.rows[0].values}:{}),
        });
        return {status:'pending'};
      });
    },

    async reviewAnalytes(labId:string,orderId:string,operatorId:string,
      decision:'approved'|'returned',reason?:string){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx,true);
        if(await clinicalOrder(tx,labId,orderId)!=='registered')throw new SilMainConflict();
        const result=await tx.query(
          `UPDATE public.vitalia_sil_main_result_sets SET status=$2
           WHERE order_id=$1 AND status='pending' RETURNING order_id`,[orderId,decision]);
        if(!result.rows.length)throw new SilMainConflict();
        await audit(tx,labId,operatorId,decision==='approved'?'results_approved':'results_returned',
          orderId,reason?{reason}:{});
        return {status:decision};
      });
    },

    async invitePatient(labId:string,operatorId:string,email:string,identityReference:string){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',
          ['sil-patient-invite:'+labId+':'+email]);
        const account=await tx.query('SELECT 1 FROM public.vitalia_accounts WHERE email=$1',[email]);
        if(account.rows.length)throw new SilMainConflict();
        await tx.query(
          `UPDATE public.vitalia_sil_main_patient_invites SET expires_at=CURRENT_TIMESTAMP
           WHERE lab_id=$1 AND email=$2 AND used_at IS NULL AND expires_at>CURRENT_TIMESTAMP`,
          [labId,email]);
        const code=randomBytes(32).toString('base64url');
        const id=randomUUID();
        const invite=await tx.query<{expiresAt:Date}>(
          `INSERT INTO public.vitalia_sil_main_patient_invites
           (id,lab_id,issued_by,email,token_hash,identity_reference,expires_at)
           VALUES($1,$2,$3,$4,$5,$6,CURRENT_TIMESTAMP+INTERVAL '24 hours')
           RETURNING expires_at AS "expiresAt"`,
          [id,labId,operatorId,email,createHash('sha256').update(code).digest('hex'),identityReference]);
        await audit(tx,labId,operatorId,'patient_invited',null,{inviteId:id});
        return {email,code,expiresAt:invite.rows[0].expiresAt};
      });
    },

    async activatePatient(email:string,code:string,password:string){
      return transaction(async tx=>{
        const data=await tx.query<{id:string;labId:string;issuedBy:string;reference:string}>(
          `SELECT id,lab_id AS "labId",issued_by AS "issuedBy",identity_reference AS reference
           FROM public.vitalia_sil_main_patient_invites
           WHERE email=$1 AND token_hash=$2 AND used_at IS NULL
           AND expires_at>CURRENT_TIMESTAMP FOR UPDATE`,
          [email,createHash('sha256').update(code).digest('hex')]);
        const invite=data.rows[0];
        if(!invite)throw new SilMainAccessDenied();
        await operator(invite.labId,invite.issuedBy,tx);
        const id=randomUUID();
        const created=await tx.query(
          `INSERT INTO public.vitalia_accounts(id,email,role_code,password_hash)
           VALUES($1,$2,'paciente',$3) ON CONFLICT(email) DO NOTHING RETURNING id`,
          [id,email,await hashPassword(password)]);
        if(!created.rows.length)throw new SilMainAccessDenied();
        await tx.query(
          `INSERT INTO public.vitalia_sil_main_patients
           (lab_id,patient_id,verified_by,identity_evidence_reference) VALUES($1,$2,$3,$4)`,
          [invite.labId,id,invite.issuedBy,invite.reference]);
        await tx.query('UPDATE public.vitalia_sil_main_patient_invites SET used_at=CURRENT_TIMESTAMP WHERE id=$1',[invite.id]);
        await audit(tx,invite.labId,id,'patient_activated',null,{inviteId:invite.id});
        return {activated:true};
      });
    },

    async previewMedicalRequest(labId:string,operatorId:string,fileName:string,bytes:Buffer){
      await operator(labId,operatorId);
      identifyDocument(bytes,'application/pdf',fileName);
      if(bytes.length<8||bytes.length>2*1024*1024)throw new SilMainConflict();
      if(readingPdf)throw new SilMainConflict();
      readingPdf=true;
      try {
        const reading=await readPdfText(bytes);
        const catalog=await db.query<{code:string;name:string}>(
          'SELECT code,name FROM public.vitalia_sil_exam_catalog WHERE active ORDER BY name');
        return {
          state:reading.status,
          ...suggestMedicalRequestFields(reading.text??'',catalog.rows),
        };
      } finally {
        readingPdf=false;
      }
    },

    async createOrderFromMedicalRequest(labId:string,patientId:string,examCodes:string[],
      operatorId:string,input:MedicalRequestInput,bytes:Buffer){
      checkMedicalRequest(input,bytes);
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        const {order}=await insertOrder(tx,labId,patientId,examCodes,operatorId);
        const {request}=await insertMedicalRequest(tx,labId,order.id,patientId,operatorId,input,bytes);
        return {order,request};
      });
    },

    async attachMedicalRequest(labId:string,orderId:string,operatorId:string,
      input:MedicalRequestInput,bytes:Buffer){
      checkMedicalRequest(input,bytes);
      return transaction(async tx=>{
        await operator(labId,operatorId,tx);
        const order=await tx.query<{patientId:string;status:string}>(
          `SELECT patient_id AS "patientId",status
           FROM public.vitalia_sil_main_orders
           WHERE id=$1 AND lab_id=$2 FOR UPDATE`,[orderId,labId]);
        if(!order.rows.length)throw new SilMainNotFound();
        if(order.rows[0].status!=='registered')throw new SilMainConflict();
        return insertMedicalRequest(tx,labId,orderId,order.rows[0].patientId,operatorId,input,bytes);
      });
    },

    async downloadMedicalRequest(labId:string,orderId:string,actorId:string){
      return transaction(async tx=>{
        await operator(labId,actorId,tx);
        const file=await tx.query<{
          id:string;fileName:string;bytes:Buffer;sha256:string
        }>(
          `SELECT id,file_name AS "fileName",pdf_data AS bytes,pdf_sha256 AS sha256
           FROM public.vitalia_sil_main_medical_requests
           WHERE lab_id=$1 AND order_id=$2`,[labId,orderId]);
        if(!file.rows.length)throw new SilMainNotFound();
        const item=file.rows[0];
        if(item.bytes.length>2*1024*1024 ||
          createHash('sha256').update(item.bytes).digest('hex')!==item.sha256)
          throw new SilMainConflict();
        await audit(tx,labId,actorId,'medical_request_downloaded',orderId,{requestId:item.id});
        return {fileName:item.fileName,bytes:item.bytes};
      });
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
        const internal=await tx.query<{blocked:boolean}>(
          `SELECT (EXISTS(SELECT 1 FROM public.vitalia_sil_main_samples WHERE order_id=$1)
              OR EXISTS(SELECT 1 FROM public.vitalia_sil_main_result_sets WHERE order_id=$1))
            AND NOT EXISTS(SELECT 1 FROM public.vitalia_sil_main_result_sets
              WHERE order_id=$1 AND status='approved') AS blocked`,[orderId]);
        if(internal.rows[0].blocked)throw new SilMainConflict();
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

    async reportForReview(labId:string,orderId:string,operatorId:string){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx,true);
        const rows=await tx.query<{
          id:string;fileName:string;data:Buffer;sha256:string
        }>(
          `SELECT r.id,r.file_name AS "fileName",r.pdf_data AS data,
                  r.pdf_sha256 AS sha256
           FROM public.vitalia_sil_main_reports r
           JOIN public.vitalia_sil_main_orders o
             ON o.id=r.order_id AND o.lab_id=r.lab_id
           WHERE r.order_id=$1 AND r.lab_id=$2
             AND o.status='report_attached' AND r.published_at IS NULL
           FOR SHARE OF r`,
          [orderId,labId]);
        if(!rows.rows.length)throw new SilMainNotFound();
        const item=rows.rows[0];
        if(item.data.length>2*1024*1024 ||
           createHash('sha256').update(item.data).digest('hex')!==item.sha256)
          throw new SilMainConflict();
        await audit(tx,labId,operatorId,'report_review_accessed',
          orderId,{reportId:item.id});
        return {fileName:item.fileName,bytes:item.data};
      });
    },

    async publishReport(labId:string,orderId:string,operatorId:string){
      return transaction(async tx=>{
        await operator(labId,operatorId,tx,true);
        const report=await tx.query<{id:string}>(
          `UPDATE public.vitalia_sil_main_reports r
           SET published_at=CURRENT_TIMESTAMP,published_by=$3
           FROM public.vitalia_sil_main_orders o
           WHERE r.order_id=o.id AND r.order_id=$1 AND r.lab_id=$2
             AND o.lab_id=$2 AND o.status='report_attached'
             AND r.published_at IS NULL AND r.patient_match_confirmed
             AND EXISTS (
               SELECT 1 FROM public.vitalia_sil_main_audit a
               WHERE a.lab_id=$2 AND a.order_id=$1 AND a.actor_id=$3
                 AND a.action='report_review_accessed'
                 AND a.details->>'reportId'=r.id::text
             )
           RETURNING r.id`,[orderId,labId,operatorId]);
        if(!report.rows.length)throw new SilMainConflict();
        await tx.query(
          `UPDATE public.vitalia_sil_main_orders
           SET status='report_published'
           WHERE id=$1 AND lab_id=$2 AND status='report_attached'`,
          [orderId,labId]);
        await audit(tx,labId,operatorId,'report_published',orderId,
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
