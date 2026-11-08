import {SIL_ANALYZER_ID} from './analyzer';
import {randomUUID,createHash} from 'node:crypto';
import {identifyDocument} from '../documents/file-validation';
import {type Pool,type PoolClient} from 'pg';

export class SilConflictError extends Error {}
export class SilNotFoundError extends Error {}
export interface SilResultInput {
  analyte: string;
  numericValue: number;
  unit: string;
  examCode?: string;
  referenceMin?: number | null;
  referenceMax?: number | null;
}

export interface SilManualInput {
  examCode:string;
  analyte:string;
  numericValue:number;
}
export function createSilService(db: Pool) {
  async function appendAudit(client:PoolClient,orderId:string,actorId:string,
    action:'order_created'|'sample_received'|'results_simulated'|'results_manual'|
      'results_corrected'|'review_approved'|'review_rejected'|
      'external_report_attached'|'external_report_published'|'external_report_downloaded',
    details:Record<string,unknown>) {
    await client.query(
      `INSERT INTO public.vitalia_sil_audit
       (id,order_id,actor_id,action,details) VALUES($1,$2,$3,$4,$5::jsonb)`,
      [randomUUID(),orderId,actorId,action,JSON.stringify(details)]);
  }
  return {
    async catalog() {
      const [exams,analytes,containers] = await Promise.all([
        db.query<{code:string;name:string;sampleType:string}>(
          `SELECT code,name,sample_type AS "sampleType"
           FROM public.vitalia_sil_exam_catalog
           WHERE active ORDER BY name`),
        db.query<{examCode:string;analyte:string;unit:string}>(
          `SELECT a.exam_code AS "examCode",a.analyte,a.unit
           FROM public.vitalia_sil_exam_analytes a
           JOIN public.vitalia_sil_exam_catalog c ON c.code=a.exam_code
           WHERE c.active ORDER BY a.exam_code,a.analyte`),
        db.query<{examCode:string;containerCode:string;containerLabel:string}>(
          `SELECT m.exam_code AS "examCode",c.code AS "containerCode",
                  c.label AS "containerLabel"
           FROM public.vitalia_sil_exam_containers m
           JOIN public.vitalia_sil_containers c ON c.code=m.container_code`),
      ]);
      return {exams:exams.rows.map(exam=>({
        ...exam,
        ...(containers.rows.find(item=>item.examCode===exam.code)??{}),
        analytes:analytes.rows.filter(item=>item.examCode===exam.code)
          .map(({analyte,unit})=>({analyte,unit})),
      }))};
    },
    async createOrder(patientId: string, actorId: string, examCodes: string[] = ['hemograma']) {
      const client = await db.connect();
      let failed = false;
      try {
        await client.query('BEGIN');
        const enabled=await client.query<{code:string}>(
          `SELECT code FROM public.vitalia_sil_exam_catalog
           WHERE active AND code=ANY($1::text[])`,[examCodes]);
        if(enabled.rows.length!==examCodes.length ||
           new Set(examCodes).size!==examCodes.length) throw new SilNotFoundError();
        const id = randomUUID();
        const result = await client.query<{id:string;status:string;orderNumber:string}>(
          `INSERT INTO public.vitalia_sil_orders(id,patient_id,created_by,exam_code)
           SELECT $1,a.id,$3,$4 FROM public.vitalia_accounts a
           WHERE a.id=$2 AND a.role_code='paciente'
           RETURNING id,status,'VH-' || lpad(order_number::text,6,'0') AS "orderNumber"`,
          [id,patientId,actorId,examCodes[0]]);
        if (!result.rows.length) throw new SilNotFoundError();
        for(const code of examCodes) {
          await client.query(
            `INSERT INTO public.vitalia_sil_order_exams(order_id,exam_code) VALUES($1,$2)`,
            [id,code]);
        }
        await appendAudit(client,id,actorId,'order_created',{exams:examCodes.length});
        await client.query('COMMIT');
        return {...result.rows[0],examCodes};
      } catch(error) {
        try { await client.query('ROLLBACK'); } catch {failed=true;}
        throw error;
      } finally {client.release(failed);}
    },
    async findPatientByEmail(email: string) {
      const result=await db.query<{id:string;email:string}>(
        `SELECT id,email FROM public.vitalia_accounts
         WHERE email=$1 AND role_code='paciente'`,[email]);
      if(!result.rows.length) throw new SilNotFoundError();
      return result.rows[0];
    },
    async summary() {
      const result=await db.query<{
        total:number;pendingSample:number;pendingResults:number;
        pendingReview:number;returned:number;approved:number;attached:number;published:number;patients:number;
      }>(
        `SELECT
           COUNT(*)::int AS total,
           COUNT(*) FILTER (WHERE status='registered')::int AS "pendingSample",
           COUNT(*) FILTER (WHERE status='sampled')::int AS "pendingResults",
           COUNT(*) FILTER (WHERE status='results_recorded')::int AS "pendingReview",
           COUNT(*) FILTER (WHERE status='review_rejected')::int AS returned,
           COUNT(*) FILTER (WHERE status='review_approved')::int AS approved,
           COUNT(*) FILTER (WHERE status='report_attached')::int AS attached,
           COUNT(*) FILTER (WHERE status='report_published')::int AS published,
           COUNT(DISTINCT patient_id)::int AS patients
         FROM public.vitalia_sil_orders`);
      return {summary:result.rows[0]};
    },
    async listOrders(limit=20,offset=0,
      status?:'registered'|'sampled'|'results_recorded'|'review_rejected'|'review_approved'|
        'report_attached'|'report_published',
      search='') {
      const clauses:string[]=[];
      const params:Array<string|number>=[];
      if(status) {
        params.push(status);
        clauses.push(`o.status=$${params.length}`);
      }
      if(search) {
        params.push('%'+search.toLowerCase()+'%');
        const p='$'+params.length;
        // Buscar el correo, identificador legible o UUID completo.
        clauses.push(`(a.email ILIKE ${p} OR
          ('VH-' || lpad(o.order_number::text,6,'0')) ILIKE ${p} OR
          o.id::text ILIKE ${p})`);
      }
      const where=clauses.length?'WHERE '+clauses.join(' AND '):'';
      const count=await db.query<{total:number}>(
        `SELECT COUNT(*)::int AS total FROM public.vitalia_sil_orders o
         JOIN public.vitalia_accounts a ON a.id=o.patient_id ${where}`,params);
      const pageArgs=[...params,limit,offset];
      const limitIndex=pageArgs.length-1;
      const offsetIndex=pageArgs.length;
      const result=await db.query(
        `SELECT o.id,'VH-' || lpad(o.order_number::text,6,'0') AS "orderNumber",
           o.patient_id AS "patientId",a.email AS "patientEmail",
           o.status,o.created_at AS "createdAt",
           COALESCE(array_agg(DISTINCT e.exam_code) FILTER (WHERE e.exam_code IS NOT NULL),
             ARRAY[]::text[]) AS "examCodes",
           (SELECT COUNT(*)::int FROM public.vitalia_sil_results r
             WHERE r.order_id=o.id) AS "resultCount"
         FROM public.vitalia_sil_orders o
         JOIN public.vitalia_accounts a ON a.id=o.patient_id
         LEFT JOIN public.vitalia_sil_order_exams e ON e.order_id=o.id
         ${where}
         GROUP BY o.id,a.email
         ORDER BY o.order_number DESC LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
        pageArgs);
      return {orders:result.rows,limit,offset,total:count.rows[0].total};
    },
    async registerSample(orderId:string,barcode:string,containerCode:string,
      actorId:string,receiptNote?:string) {
      const client=await db.connect();
      let failed=false;
      try {
        await client.query('BEGIN');
        const order=await client.query<{status:string}>(
          `SELECT status FROM public.vitalia_sil_orders WHERE id=$1 FOR UPDATE`,[orderId]);
        if(!order.rows.length) throw new SilNotFoundError();
        if(order.rows[0].status!=='registered') throw new SilConflictError();
        const required=await client.query<{containerCode:string}>(
          `SELECT DISTINCT m.container_code AS "containerCode"
           FROM public.vitalia_sil_order_exams e
           JOIN public.vitalia_sil_exam_containers m ON m.exam_code=e.exam_code
           WHERE e.order_id=$1`,[orderId]);
        if(!required.rows.some(row=>row.containerCode===containerCode))
          throw new SilConflictError();
        const id=randomUUID();
        const inserted=await client.query<{registeredAt:Date}>(
          `INSERT INTO public.vitalia_sil_samples
           (id,order_id,barcode,container_code,received_by,receipt_note)
           VALUES($1,$2,$3,$4,$5,$6) RETURNING registered_at AS "registeredAt"`,
          [id,orderId,barcode,containerCode,actorId,receiptNote??null]);
        const outstanding=await client.query<{pending:number}>(
          `SELECT COUNT(*)::int AS pending
           FROM (
             SELECT DISTINCT m.container_code
             FROM public.vitalia_sil_order_exams e
             JOIN public.vitalia_sil_exam_containers m ON m.exam_code=e.exam_code
             WHERE e.order_id=$1
           ) required
           WHERE NOT EXISTS (
             SELECT 1 FROM public.vitalia_sil_samples s
             WHERE s.order_id=$1 AND s.container_code=required.container_code
           )`,[orderId]);
        const status=outstanding.rows[0].pending===0?'sampled':'registered';
        if(status==='sampled'){
          await client.query(
            `UPDATE public.vitalia_sil_orders SET status='sampled'
             WHERE id=$1 AND status='registered'`,[orderId]);
        }
        await appendAudit(client,orderId,actorId,'sample_received',
          {container:containerCode,remaining:outstanding.rows[0].pending});
        await client.query('COMMIT');
        return {id,orderId,barcode,containerCode,status,
          registeredAt:inserted.rows[0].registeredAt};
      }catch(error){
        try{await client.query('ROLLBACK');}catch{failed=true;}
        if((error as {code?:string}).code==='23505') throw new SilConflictError();
        throw error;
      }finally{client.release(failed);}
    },
    async recordResults(orderId:string,results:SilResultInput[],
      actorId:string,source:'manual'|'simulated'='simulated') {
      const client = await db.connect();
      let failed = false;
      try {
        await client.query('BEGIN');
        const order=await client.query<{status:string}>(
          `SELECT status FROM public.vitalia_sil_orders WHERE id=$1 FOR UPDATE`,[orderId]);
        if(!order.rows.length) throw new SilNotFoundError();
        const wasReturned=order.rows[0].status==='review_rejected';
        if(order.rows[0].status!=='sampled' && !(wasReturned && source==='manual'))
          throw new SilConflictError();
        const codes=await client.query<{exam_code:string}>(
          'SELECT exam_code FROM public.vitalia_sil_order_exams WHERE order_id=$1',[orderId]);
        const allowed=new Set(codes.rows.map(item=>item.exam_code));
        if(results.some(item=>!allowed.has(item.examCode??'hemograma')))
          throw new SilConflictError();
        let previousResults:unknown[]=[];
        if(wasReturned) {
          const previous=await client.query(
            `SELECT exam_code AS "examCode",analyte,
               numeric_value::float8 AS "numericValue",unit
             FROM public.vitalia_sil_results
             WHERE order_id=$1 ORDER BY exam_code,analyte`,[orderId]);
          previousResults=previous.rows;
          await client.query(
            `DELETE FROM public.vitalia_sil_results WHERE order_id=$1`,[orderId]);
        }
        for (const item of results) {
          await client.query(
            `INSERT INTO public.vitalia_sil_results
             (id,order_id,exam_code,analyte,numeric_value,unit,reference_min,reference_max,entry_method)
             VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
            [randomUUID(),orderId,item.examCode??'hemograma',item.analyte,
              item.numericValue,item.unit,item.referenceMin??null,item.referenceMax??null,source]);
        }
        await client.query(
          `UPDATE public.vitalia_sil_orders SET status='results_recorded'
           WHERE id=$1`,[orderId]);
        await appendAudit(client,orderId,actorId,
          wasReturned?'results_corrected':
          source==='manual'?'results_manual':'results_simulated',
          wasReturned?{count:results.length,previousResults}:{count:results.length});
        await client.query('COMMIT');
        return {orderId,status:'results_recorded',count:results.length,synthetic:true};
      } catch (error) {
        try { await client.query('ROLLBACK'); } catch {failed=true;}
        if ((error as {code?:string}).code==='23505') throw new SilConflictError();
        throw error;
      } finally {client.release(failed);}
    },
    async recordManualResults(orderId:string,values:SilManualInput[],actorId:string) {
      const expected=await db.query<{
        examCode:string;analyte:string;unit:string;
        referenceMin:number|null;referenceMax:number|null;
      }>(
        `SELECT e.exam_code AS "examCode",a.analyte,a.unit,
           a.reference_min::float8 AS "referenceMin",
           a.reference_max::float8 AS "referenceMax"
         FROM public.vitalia_sil_order_exams e
         JOIN public.vitalia_sil_exam_analytes a ON a.exam_code=e.exam_code
         WHERE e.order_id=$1 ORDER BY e.exam_code,a.analyte`,[orderId]);
      if(!expected.rows.length || values.length!==expected.rows.length)
        throw new SilConflictError();
      const provided=new Map<string,number>();
      for(const value of values){
        const key=value.examCode+'\u0000'+value.analyte;
        if(provided.has(key))throw new SilConflictError();
        provided.set(key,value.numericValue);
      }
      const records:SilResultInput[]=[];
      for(const item of expected.rows){
        const key=item.examCode+'\u0000'+item.analyte;
        const value=provided.get(key);
        if(value===undefined)throw new SilConflictError();
        records.push({...item,numericValue:value});
      }
      return this.recordResults(orderId,records,actorId,'manual');
    },
    async simulateAnalyzer(orderId: string,actorId:string) {
      // Solo plantillas sintéticas del catálogo. No conecta con equipos médicos.
      const data=await db.query<{
        examCode:string;analyte:string;unit:string;numericValue:number;
        referenceMin:number|null;referenceMax:number|null;
      }>(
        `SELECT e.exam_code AS "examCode",a.analyte,a.unit,
           a.demo_value::float8 AS "numericValue",
           a.reference_min::float8 AS "referenceMin",
           a.reference_max::float8 AS "referenceMax"
         FROM public.vitalia_sil_order_exams e
         JOIN public.vitalia_sil_exam_analytes a ON a.exam_code=e.exam_code
         WHERE e.order_id=$1 ORDER BY e.exam_code,a.analyte`,[orderId]);
      if (!data.rows.length) throw new SilConflictError();
      const recorded=await this.recordResults(orderId,data.rows,actorId,'simulated');
      const requested=new Set(data.rows.map(item=>item.examCode));
      const analyzerId=requested.size===1&&requested.has('hemograma')
        ? SIL_ANALYZER_ID : 'simulador-paneles-v1';
      return {...recorded,analyzerId,simulated:true,
        notice:'SIMULACIÓN: resultados de prueba, sin validez clínica.'};
    },
    async reviewOrder(orderId:string,actorId:string,
      decision:'approve'|'return',note:string) {
      if(decision==='return' && note.trim().length<10)
        throw new SilConflictError();
      const client=await db.connect();
      let failed=false;
      try{
        await client.query('BEGIN');
        const current=await client.query<{status:string}>(
          `SELECT status FROM public.vitalia_sil_orders WHERE id=$1 FOR UPDATE`,[orderId]);
        if(!current.rows.length)throw new SilNotFoundError();
        if(current.rows[0].status!=='results_recorded')
          throw new SilConflictError();
        const checks=await client.query<{expected:number;actual:number;matched:number}>(
          `SELECT
            (SELECT COUNT(*)::int FROM public.vitalia_sil_order_exams e
              JOIN public.vitalia_sil_exam_analytes a ON a.exam_code=e.exam_code
              WHERE e.order_id=$1) AS expected,
            (SELECT COUNT(*)::int FROM public.vitalia_sil_results r
              WHERE r.order_id=$1) AS actual,
            (SELECT COUNT(*)::int FROM public.vitalia_sil_results r
              JOIN public.vitalia_sil_exam_analytes a
              ON a.exam_code=r.exam_code AND a.analyte=r.analyte
              WHERE r.order_id=$1) AS matched`,[orderId]);
        const check=checks.rows[0];
        if(!check || check.expected===0 || check.expected!==check.actual ||
          check.expected!==check.matched) throw new SilConflictError();
        const status=decision==='approve'?'review_approved':'review_rejected';
        await client.query(
          `UPDATE public.vitalia_sil_orders SET status=$2 WHERE id=$1`,
          [orderId,status]);
        await appendAudit(client,orderId,actorId,status,
          {decision,note:note.trim(),resultCount:check.actual});
        await client.query('COMMIT');
        return {orderId,status,decision};
      }catch(error){
        try{await client.query('ROLLBACK');}catch{failed=true;}
        throw error;
      }finally{client.release(failed);}
    },
    async attachExternalReport(orderId:string,actorId:string,input:{
      fileName:string;issuingLaboratory:string;authorizationReference:string;
      externallyAuthorizedAt:string;patientMatchConfirmed:true;
    },bytes:Buffer) {
      if(!input.patientMatchConfirmed || bytes.length<8 || bytes.length>2*1024*1024)
        throw new SilConflictError();
      identifyDocument(bytes,'application/pdf',input.fileName);
      const date=new Date(input.externallyAuthorizedAt);
      if(!Number.isFinite(date.getTime()) || date.getTime()>Date.now())
        throw new SilConflictError();
      const client=await db.connect();
      let failed=false;
      try{
        await client.query('BEGIN');
        const order=await client.query<{status:string;patientId:string;synthetic:boolean}>(
          `SELECT status,patient_id AS "patientId",synthetic
             FROM public.vitalia_sil_orders WHERE id=$1 FOR UPDATE`,[orderId]);
        if(!order.rows.length)throw new SilNotFoundError();
        if(order.rows[0].status!=='registered' || !order.rows[0].synthetic)
          throw new SilConflictError();
        const id=randomUUID();
        const checksum=createHash('sha256').update(bytes).digest('hex');
        await client.query(
          `INSERT INTO public.vitalia_sil_external_reports(
            id,order_id,patient_id,file_name,pdf_data,pdf_sha256,
            issuing_laboratory,external_authorization_ref,
            externally_authorized_at,patient_match_confirmed,received_by)
           VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,true,$10)`,
          [id,orderId,order.rows[0].patientId,input.fileName,bytes,checksum,
            input.issuingLaboratory,input.authorizationReference,date,actorId]);
        await client.query(
          `UPDATE public.vitalia_sil_orders SET status='report_attached' WHERE id=$1`,
          [orderId]);
        await appendAudit(client,orderId,actorId,'external_report_attached',{
          reportId:id,fileSha256:checksum,issuer:input.issuingLaboratory,
          authorizationReference:input.authorizationReference,
          patientMatchConfirmed:true
        });
        await client.query('COMMIT');
        return {id,orderId,status:'report_attached',fileName:input.fileName,
          sha256:checksum};
      }catch(error){
        try{await client.query('ROLLBACK');}catch{failed=true;}
        if((error as {code?:string}).code==='23505')throw new SilConflictError();
        throw error;
      }finally{client.release(failed);}
    },
    async publishExternalReport(orderId:string,actorId:string) {
      const client=await db.connect();
      let failed=false;
      try{
        await client.query('BEGIN');
        const order=await client.query<{status:string}>(
          `SELECT status FROM public.vitalia_sil_orders WHERE id=$1 FOR UPDATE`,[orderId]);
        if(!order.rows.length)throw new SilNotFoundError();
        if(order.rows[0].status!=='report_attached')throw new SilConflictError();
        const report=await client.query<{id:string}>(
          `UPDATE public.vitalia_sil_external_reports
             SET published_at=CURRENT_TIMESTAMP,published_by=$2
             WHERE order_id=$1 AND published_at IS NULL AND patient_match_confirmed
             RETURNING id`,[orderId,actorId]);
        if(!report.rows.length)throw new SilConflictError();
        await client.query(
          `UPDATE public.vitalia_sil_orders SET status='report_published' WHERE id=$1`,
          [orderId]);
        await appendAudit(client,orderId,actorId,'external_report_published',
          {reportId:report.rows[0].id});
        await client.query('COMMIT');
        return {orderId,reportId:report.rows[0].id,status:'report_published'};
      }catch(error){
        try{await client.query('ROLLBACK');}catch{failed=true;}
        throw error;
      }finally{client.release(failed);}
    },
    async listPatientReports(patientId:string) {
      const result=await db.query(
        `SELECT r.id,r.file_name AS "fileName",
           r.issuing_laboratory AS "issuingLaboratory",
           r.externally_authorized_at AS "externallyAuthorizedAt",
           r.published_at AS "publishedAt",
           'VH-' || lpad(o.order_number::text,6,'0') AS "orderNumber",
           r.pdf_sha256 AS sha256
         FROM public.vitalia_sil_external_reports r
         JOIN public.vitalia_sil_orders o ON o.id=r.order_id
         WHERE r.patient_id=$1 AND r.published_at IS NOT NULL
           AND o.status='report_published'
         ORDER BY r.published_at DESC LIMIT 50`,[patientId]);
      return {reports:result.rows};
    },
    async downloadPatientReport(patientId:string,reportId:string) {
      const result=await db.query<{
        id:string;orderId:string;fileName:string;data:Buffer;sha256:string
      }>(
        `SELECT r.id,r.order_id AS "orderId",r.file_name AS "fileName",
                r.pdf_data AS data,r.pdf_sha256 AS sha256
           FROM public.vitalia_sil_external_reports r
           JOIN public.vitalia_sil_orders o ON o.id=r.order_id
           WHERE r.id=$1 AND r.patient_id=$2 AND r.published_at IS NOT NULL
           AND o.status='report_published'`,[reportId,patientId]);
      if(!result.rows.length)throw new SilNotFoundError();
      const item=result.rows[0];
      if(item.data.length>2*1024*1024 ||
        createHash('sha256').update(item.data).digest('hex')!==item.sha256)
        throw new SilConflictError();
      await db.query(
        `INSERT INTO public.vitalia_sil_audit(id,order_id,actor_id,action,details)
         VALUES($1,$2,$3,'external_report_downloaded',$4::jsonb)`,
        [randomUUID(),item.orderId,patientId,JSON.stringify({reportId:item.id})]);
      return {fileName:item.fileName,bytes:item.data};
    },
    async getOrder(orderId: string) {
      const order = await db.query(
        `SELECT o.id,'VH-' || lpad(o.order_number::text,6,'0') AS "orderNumber",
          o.patient_id AS "patientId",a.email AS "patientEmail",
          o.exam_code AS "examCode",
          o.status,o.synthetic,o.created_at AS "createdAt"
         FROM public.vitalia_sil_orders o
         JOIN public.vitalia_accounts a ON a.id=o.patient_id
         WHERE o.id=$1`,[orderId]);
      if (!order.rows.length) throw new SilNotFoundError();
      const [exams,samples,required,results,audit,report] = await Promise.all([
        db.query(
          `SELECT c.code,c.name,c.sample_type AS "sampleType"
           FROM public.vitalia_sil_order_exams e
           JOIN public.vitalia_sil_exam_catalog c ON c.code=e.exam_code
           WHERE e.order_id=$1 ORDER BY c.name`,[orderId]),
        db.query(
          `SELECT s.barcode,s.container_code AS "containerCode",
            COALESCE(c.label,'Recepción anterior sin tipo de tubo') AS "containerLabel",
            s.sample_type AS "sampleType",s.receipt_note AS "receiptNote",
            s.registered_at AS "registeredAt",a.email AS "receivedBy"
           FROM public.vitalia_sil_samples s
           LEFT JOIN public.vitalia_sil_containers c ON c.code=s.container_code
           LEFT JOIN public.vitalia_accounts a ON a.id=s.received_by
           WHERE s.order_id=$1 ORDER BY s.registered_at,s.id`,[orderId]),
        db.query(
          `SELECT DISTINCT c.code,c.label
           FROM public.vitalia_sil_order_exams e
           JOIN public.vitalia_sil_exam_containers m ON m.exam_code=e.exam_code
           JOIN public.vitalia_sil_containers c ON c.code=m.container_code
           WHERE e.order_id=$1 ORDER BY c.code`,[orderId]),
        db.query(
          `SELECT exam_code AS "examCode",analyte,
            numeric_value::float8 AS "numericValue",unit,
            reference_min::float8 AS "referenceMin",reference_max::float8 AS "referenceMax",
            entry_method AS "entryMethod"
           FROM public.vitalia_sil_results WHERE order_id=$1
           ORDER BY exam_code,analyte`,[orderId]),
        db.query(
          `SELECT e.action,e.details,e.created_at AS "createdAt",
                  a.email AS "actorEmail"
           FROM public.vitalia_sil_audit e
           JOIN public.vitalia_accounts a ON a.id=e.actor_id
           WHERE e.order_id=$1 ORDER BY e.created_at,e.id`,[orderId]),
        db.query(
          `SELECT id,file_name AS "fileName",
            issuing_laboratory AS "issuingLaboratory",
            external_authorization_ref AS "authorizationReference",
            externally_authorized_at AS "externallyAuthorizedAt",
            received_at AS "receivedAt",published_at AS "publishedAt",
            pdf_sha256 AS sha256
           FROM public.vitalia_sil_external_reports WHERE order_id=$1`,[orderId]),
      ]);
      return {order:order.rows[0],exams:exams.rows,
        sample:samples.rows[0]??null,samples:samples.rows,
        requiredContainers:required.rows,results:results.rows,audit:audit.rows,
        externalReport:report.rows[0]??null,
        latestReview:audit.rows.filter(item=>
          item.action==='review_approved'||item.action==='review_rejected').at(-1)??null};
    },
  };
}
export type SilServices=ReturnType<typeof createSilService>;
