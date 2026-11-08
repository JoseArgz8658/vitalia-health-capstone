import {SIL_ANALYZER_ID} from './analyzer';
import {randomUUID} from 'node:crypto';
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
    action:'order_created'|'sample_received'|'results_simulated'|'results_manual',
    details:Record<string,string|number>) {
    await client.query(
      `INSERT INTO public.vitalia_sil_audit
       (id,order_id,actor_id,action,details) VALUES($1,$2,$3,$4,$5::jsonb)`,
      [randomUUID(),orderId,actorId,action,JSON.stringify(details)]);
  }
  return {
    async catalog() {
      const [exams,analytes] = await Promise.all([
        db.query<{code:string;name:string;sampleType:string}>(
          `SELECT code,name,sample_type AS "sampleType"
           FROM public.vitalia_sil_exam_catalog
           WHERE active ORDER BY name`),
        db.query<{examCode:string;analyte:string;unit:string}>(
          `SELECT a.exam_code AS "examCode",a.analyte,a.unit
           FROM public.vitalia_sil_exam_analytes a
           JOIN public.vitalia_sil_exam_catalog c ON c.code=a.exam_code
           WHERE c.active ORDER BY a.exam_code,a.analyte`),
      ]);
      return {exams:exams.rows.map(exam=>({
        ...exam,analytes:analytes.rows.filter(item=>item.examCode===exam.code)
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
        pendingReview:number;patients:number;
      }>(
        `SELECT
           COUNT(*)::int AS total,
           COUNT(*) FILTER (WHERE status='registered')::int AS "pendingSample",
           COUNT(*) FILTER (WHERE status='sampled')::int AS "pendingResults",
           COUNT(*) FILTER (WHERE status='results_recorded')::int AS "pendingReview",
           COUNT(DISTINCT patient_id)::int AS patients
         FROM public.vitalia_sil_orders`);
      return {summary:result.rows[0]};
    },
    async listOrders(limit=20,offset=0,status?:'registered'|'sampled'|'results_recorded',
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
        const updated = await client.query(
          `UPDATE public.vitalia_sil_orders SET status='results_recorded'
           WHERE id=$1 AND status='sampled' RETURNING id`,[orderId]);
        if (!updated.rows.length) throw new SilConflictError();
        const codes=await client.query<{exam_code:string}>(
          'SELECT exam_code FROM public.vitalia_sil_order_exams WHERE order_id=$1',[orderId]);
        const allowed=new Set(codes.rows.map(item=>item.exam_code));
        if(results.some(item=>!allowed.has(item.examCode??'hemograma')))
          throw new SilConflictError();
        for (const item of results) {
          await client.query(
            `INSERT INTO public.vitalia_sil_results
             (id,order_id,exam_code,analyte,numeric_value,unit,reference_min,reference_max,entry_method)
             VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
            [randomUUID(),orderId,item.examCode??'hemograma',item.analyte,
              item.numericValue,item.unit,item.referenceMin??null,item.referenceMax??null,source]);
        }
        await appendAudit(client,orderId,actorId,
          source==='manual'?'results_manual':'results_simulated',{count:results.length});
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
      const [exams,sample,results] = await Promise.all([
        db.query(
          `SELECT c.code,c.name,c.sample_type AS "sampleType"
           FROM public.vitalia_sil_order_exams e
           JOIN public.vitalia_sil_exam_catalog c ON c.code=e.exam_code
           WHERE e.order_id=$1 ORDER BY c.name`,[orderId]),
        db.query(
          `SELECT barcode,sample_type AS "sampleType",registered_at AS "registeredAt"
           FROM public.vitalia_sil_samples WHERE order_id=$1`,[orderId]),
        db.query(
          `SELECT exam_code AS "examCode",analyte,
            numeric_value::float8 AS "numericValue",unit,
            reference_min::float8 AS "referenceMin",reference_max::float8 AS "referenceMax"
           FROM public.vitalia_sil_results WHERE order_id=$1
           ORDER BY exam_code,analyte`,[orderId]),
      ]);
      return {order:order.rows[0],exams:exams.rows,
        sample:sample.rows[0]??null,results:results.rows};
    },
  };
}
export type SilServices=ReturnType<typeof createSilService>;
