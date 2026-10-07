import { randomUUID } from 'node:crypto';
import { type Pool } from 'pg';
import { z } from 'zod';
import { type AccountSummary } from '../accounts/repository';

type Database = Pick<Pool, 'query'>;
const metadata = z.object({
  examName: z.string().trim().min(1).max(100),
  examType: z.enum(['Laboratorio', 'Imagenología']),
  examDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
    const date = new Date(value + 'T00:00:00Z');
    return !Number.isNaN(date.getTime()) &&
      date.toISOString().slice(0, 10) === value &&
      value >= '1900-01-01' && value <= new Date().toISOString().slice(0, 10);
  }),
  originalName: z.string().min(1).max(255).refine(value => !/[\x00-\x1f\/\\]/.test(value)),
  contentType: z.enum(['application/pdf', 'image/jpeg', 'image/png']),
  sizeBytes: z.number().int().min(1).max(10 * 1024 * 1024),
}).strict();

function patient(account: AccountSummary): void {
  if (account.role !== 'paciente' || !z.uuid().safeParse(account.id).success) {
    throw new Error('Acceso de paciente requerido.');
  }
}
export interface DocumentSummary {
  id: string; examName: string; examType: string; examDate: string;
  originalName: string; contentType: string; sizeBytes: number; createdAt: Date;
}
interface DocumentRow {
  id: string; exam_name: string; exam_type: string; exam_date: string;
  original_name: string; content_type: string; size_bytes: number; created_at: Date;
}
const columns = `id, exam_name, exam_type, exam_date::text, original_name,
  content_type, size_bytes, created_at`;
function summary(row: DocumentRow): DocumentSummary {
  return { id: row.id, examName: row.exam_name, examType: row.exam_type,
    examDate: row.exam_date, originalName: row.original_name,
    contentType: row.content_type, sizeBytes: row.size_bytes, createdAt: row.created_at };
}

// Solo para el servicio interno de carga: recibe identidad comprobada, nunca req.body.
export async function reserveDocument(db: Database, account: AccountSummary, input: unknown) {
  patient(account);
  const data = metadata.parse(input);
  const id = randomUUID();
  const storageKey = `patients/${account.id}/documents/${id}`;
  await db.query(`INSERT INTO public.vitalia_documents
    (id, patient_id, exam_name, exam_type, exam_date, original_name, content_type, size_bytes, storage_key)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [id, account.id, data.examName, data.examType, data.examDate,
      data.originalName, data.contentType, data.sizeBytes, storageKey]);
  return { id, storageKey };
}
// El futuro servicio verificará el objeto en S3 antes de confirmar stored.
export async function completeDocument(db: Database, account: AccountSummary, id: string) {
  patient(account);
  const validId = z.uuid().parse(id);
  const result = await db.query(`UPDATE public.vitalia_documents SET status = 'stored'
    WHERE id = $1 AND patient_id = $2 AND status = 'pending' RETURNING id`, [validId, account.id]);
  return result.rows.length === 1;
}
export async function listPatientDocuments(db: Database, account: AccountSummary,
  limit = 20, offset = 0): Promise<DocumentSummary[]> {
  patient(account);
  z.number().int().min(1).max(100).parse(limit);
  z.number().int().min(0).max(10000).parse(offset);
  const result = await db.query<DocumentRow>(`SELECT ${columns} FROM public.vitalia_documents
    WHERE patient_id = $1 AND status = 'stored'
    ORDER BY exam_date DESC, created_at DESC, id DESC LIMIT $2 OFFSET $3`,
    [account.id, limit, offset]);
  return result.rows.map(summary);
}
export async function findPatientDocument(db: Database, account: AccountSummary,
  id: string): Promise<DocumentSummary | null> {
  patient(account);
  const validId = z.uuid().parse(id);
  const result = await db.query<DocumentRow>(`SELECT ${columns} FROM public.vitalia_documents
    WHERE id = $1 AND patient_id = $2 AND status = 'stored'`, [validId, account.id]);
  return result.rows.length ? summary(result.rows[0]) : null;
}
