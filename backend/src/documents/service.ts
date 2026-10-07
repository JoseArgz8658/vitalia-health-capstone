import { type Pool } from 'pg';
import { z } from 'zod';
import { type AccountSummary } from '../accounts/repository';
import { reserveDocument, completeDocument, listPatientDocuments, findPatientDocument } from './repository';
import { DocumentInputError, identifyDocument, MAX_FILE_BYTES } from './file-validation';

type Queryable = Pick<Pool, 'query'>;
export interface DocumentDatabase extends Queryable {
  transaction<T>(work: (db: Queryable) => Promise<T>): Promise<T>;
}
export function documentDatabase(pool: Pool): DocumentDatabase {
  return {
    query: pool.query.bind(pool) as Pool['query'],
    async transaction<T>(work: (db: Queryable) => Promise<T>) {
      const client = await pool.connect();
      let failed = false;
      try {
        await client.query('BEGIN');
        const result = await work(client);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        try { await client.query('ROLLBACK'); } catch { failed = true; }
        throw error;
      } finally { client.release(failed); }
    },
  };
}
export interface DocumentStorage {
  put(key: string, body: Buffer, contentType: string): Promise<void>;
  read(key: string): Promise<Buffer>;
  remove(key: string): Promise<void>;
}
export class DocumentNotFoundError extends Error {}
export interface IncomingDocument {
  metadata: unknown; name: string; contentType: string; body: Buffer;
}
async function audit(db: Queryable, account: AccountSummary, action: string, id: string | null) {
  await db.query(`INSERT INTO public.vitalia_document_audit
    (account_id, document_id, action) VALUES ($1,$2,$3)`, [account.id, id, action]);
}
export function createDocumentService(db: DocumentDatabase, storage: DocumentStorage) {
  return {
    async upload(account: AccountSummary, file: IncomingDocument) {
      const contentType = identifyDocument(file.body, file.contentType, file.name);
      const meta = z.object({
        examName: z.string(), examType: z.string(), examDate: z.string(),
      }).strict().safeParse(file.metadata);
      if (!meta.success) throw new DocumentInputError('Metadatos inválidos.');
      let reserved: { id: string; storageKey: string };
      try {
        reserved = await reserveDocument(db, account, {
          ...meta.data, originalName: file.name, contentType, sizeBytes: file.body.length,
        });
      } catch (error) {
        if (error instanceof z.ZodError) throw new DocumentInputError('Metadatos inválidos.');
        throw error;
      }
      try {
        await storage.put(reserved.storageKey, file.body, contentType);
        await db.transaction(async tx => {
          if (!await completeDocument(tx, account, reserved.id)) throw new Error('Reserva no confirmada.');
          await audit(tx, account, 'upload', reserved.id);
        });
      } catch (error) {
        // La reserva no se muestra en historial. Intentar compensar ambos recursos.
        try {
          await db.query(`UPDATE public.vitalia_documents SET status = 'failed'
            WHERE id = $1 AND patient_id = $2 AND status = 'pending'`, [reserved.id, account.id]);
        } catch { console.error('No se pudo marcar la carga fallida; revisar reservas pendientes.'); }
        try { await storage.remove(reserved.storageKey); }
        catch { console.error('No se pudo limpiar el objeto de una carga fallida; revisar S3.'); }
        throw error;
      }
      const result = await findPatientDocument(db, account, reserved.id);
      if (!result) throw new Error('Documento confirmado no disponible.');
      return result;
    },
    async list(account: AccountSummary, limit = 20, offset = 0) {
      return db.transaction(async tx => {
        const items = await listPatientDocuments(tx, account, limit, offset);
        await audit(tx, account, 'list', null);
        return items;
      });
    },
    async download(account: AccountSummary, id: string) {
      const item = await findPatientDocument(db, account, id);
      if (!item) throw new DocumentNotFoundError();
      // La clave proviene de la base, con filtro de propiedad; nunca del cliente.
      const result = await db.query<{ storage_key: string }>(`SELECT storage_key
        FROM public.vitalia_documents WHERE id = $1 AND patient_id = $2 AND status = 'stored'`,
        [id, account.id]);
      if (!result.rows.length) throw new DocumentNotFoundError();
      const body = await storage.read(result.rows[0].storage_key);
      if (body.length !== item.sizeBytes || body.length > MAX_FILE_BYTES) {
        throw new Error('Contenido almacenado inconsistente.');
      }
      await audit(db, account, 'download', id);
      return { item, body };
    },
  };
}
export type DocumentServices = ReturnType<typeof createDocumentService>;
