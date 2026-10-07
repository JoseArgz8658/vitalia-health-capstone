import { type PoolClient } from 'pg';

type Client = Pick<PoolClient, 'query'>;
export interface RecoveryCandidate { id: string; patient_id: string; storage_key: string }
export interface RecoveryResult { candidates: number; cleaned: number; skipped: number; failed: number }
export async function previewRecovery(client: Client, onlyIds?: readonly string[]): Promise<RecoveryCandidate[]> {
  const result = await client.query<RecoveryCandidate>(`SELECT d.id, d.patient_id, d.storage_key
    FROM public.vitalia_documents d
    LEFT JOIN public.vitalia_document_cleanup c ON c.document_id = d.id
    WHERE d.status IN ('pending', 'failed')
      AND d.created_at < CURRENT_TIMESTAMP - INTERVAL '1 hour'
      AND c.document_id IS NULL
      AND ($1::uuid[] IS NULL OR d.id = ANY($1::uuid[]))
    ORDER BY d.created_at, d.id LIMIT 100`, [onlyIds ?? null]);
  return result.rows;
}
// Cliente dedicado: el bloqueo advisory pertenece a su conexión, no a un pool.
export async function applyRecovery(client: Client,
  remove: (key: string) => Promise<void>, onlyIds?: readonly string[]): Promise<RecoveryResult> {
  const lock = await client.query<{ locked: boolean }>(
    'SELECT pg_try_advisory_lock(hashtext($1)) AS locked', ['vitalia-document-recovery']);
  if (lock.rows[0]?.locked !== true) throw new Error('Hay otra recuperación en ejecución.');
  try {
    const candidates = await previewRecovery(client, onlyIds);
    const result: RecoveryResult = { candidates: candidates.length, cleaned: 0, skipped: 0, failed: 0 };
    for (const item of candidates) {
      if (item.storage_key !== `patients/${item.patient_id}/documents/${item.id}` ||
          !/^[a-f0-9-]{36}$/.test(item.id) || !/^[a-f0-9-]{36}$/.test(item.patient_id)) {
        result.failed++; continue;
      }
      // Revalida estado: una carga ya confirmada nunca se elimina.
      const claimed = await client.query<{ id: string }>(`UPDATE public.vitalia_documents d
        SET status = 'failed' WHERE id = $1 AND status IN ('pending', 'failed')
        AND created_at < CURRENT_TIMESTAMP - INTERVAL '1 hour'
        AND NOT EXISTS (SELECT 1 FROM public.vitalia_document_cleanup c WHERE c.document_id = d.id)
        RETURNING id`, [item.id]);
      if (claimed.rows.length !== 1) { result.skipped++; continue; }
      try {
        await remove(item.storage_key);
        await client.query(`INSERT INTO public.vitalia_document_cleanup(document_id)
          VALUES ($1) ON CONFLICT (document_id) DO NOTHING`, [item.id]);
        result.cleaned++;
      } catch {
        // No se registra como limpiado; podrá reintentarse.
        result.failed++;
      }
    }
    return result;
  } finally {
    await client.query('SELECT pg_advisory_unlock(hashtext($1))', ['vitalia-document-recovery']);
  }
}
