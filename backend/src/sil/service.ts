import {randomUUID} from 'node:crypto';
import {type Pool} from 'pg';

export class SilConflictError extends Error {}
export class SilNotFoundError extends Error {}
export interface SilResultInput {
  analyte: string;
  numericValue: number;
  unit: string;
  referenceMin?: number | null;
  referenceMax?: number | null;
}
export function createSilService(db: Pool) {
  return {
    async createOrder(patientId: string, actorId: string) {
      const id = randomUUID();
      const result = await db.query<{id:string;status:string}>(
        `INSERT INTO public.vitalia_sil_orders(id,patient_id,created_by,exam_code)
         SELECT $1,a.id,$3,'hemograma' FROM public.vitalia_accounts a
         WHERE a.id=$2 AND a.role_code='paciente'
         RETURNING id,status`, [id,patientId,actorId]);
      if (!result.rows.length) throw new SilNotFoundError();
      return result.rows[0];
    },
    async registerSample(orderId: string, barcode: string) {
      const client = await db.connect();
      let failed = false;
      try {
        await client.query('BEGIN');
        const updated = await client.query(
          `UPDATE public.vitalia_sil_orders SET status='sampled'
           WHERE id=$1 AND status='registered' RETURNING id`,[orderId]);
        if (!updated.rows.length) throw new SilConflictError();
        const id = randomUUID();
        await client.query(
          `INSERT INTO public.vitalia_sil_samples(id,order_id,barcode)
           VALUES($1,$2,$3)`,[id,orderId,barcode]);
        await client.query('COMMIT');
        return {id,orderId,barcode};
      } catch (error) {
        try { await client.query('ROLLBACK'); } catch { failed=true; }
        if ((error as {code?:string}).code==='23505') throw new SilConflictError();
        throw error;
      } finally { client.release(failed); }
    },
    async recordResults(orderId: string, results: SilResultInput[]) {
      const client = await db.connect();
      let failed = false;
      try {
        await client.query('BEGIN');
        const updated = await client.query(
          `UPDATE public.vitalia_sil_orders SET status='results_recorded'
           WHERE id=$1 AND status='sampled' RETURNING id`,[orderId]);
        if (!updated.rows.length) throw new SilConflictError();
        for (const item of results) {
          await client.query(
            `INSERT INTO public.vitalia_sil_results
             (id,order_id,analyte,numeric_value,unit,reference_min,reference_max)
             VALUES($1,$2,$3,$4,$5,$6,$7)`,
            [randomUUID(),orderId,item.analyte,item.numericValue,item.unit,
              item.referenceMin??null,item.referenceMax??null]);
        }
        await client.query('COMMIT');
        return {orderId,status:'results_recorded',count:results.length,synthetic:true};
      } catch (error) {
        try { await client.query('ROLLBACK'); } catch { failed=true; }
        if ((error as {code?:string}).code==='23505') throw new SilConflictError();
        throw error;
      } finally { client.release(failed); }
    },
    async getOrder(orderId: string) {
      const order = await db.query(
        `SELECT id,patient_id AS "patientId",exam_code AS "examCode",
          status,synthetic,created_at AS "createdAt"
         FROM public.vitalia_sil_orders WHERE id=$1`,[orderId]);
      if (!order.rows.length) throw new SilNotFoundError();
      const sample = await db.query(
        `SELECT barcode,sample_type AS "sampleType",registered_at AS "registeredAt"
         FROM public.vitalia_sil_samples WHERE order_id=$1`,[orderId]);
      const results = await db.query(
        `SELECT analyte,numeric_value::float8 AS "numericValue",unit,
          reference_min::float8 AS "referenceMin",reference_max::float8 AS "referenceMax"
         FROM public.vitalia_sil_results WHERE order_id=$1 ORDER BY analyte`,[orderId]);
      return {order:order.rows[0],sample:sample.rows[0]??null,results:results.rows};
    },
  };
}
export type SilServices=ReturnType<typeof createSilService>;
