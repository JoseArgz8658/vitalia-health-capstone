import {createExamAssistantService} from './exam-assistant/service';
import {createExamAssistant} from './exam-assistant/local-model';
import {createExplanationService} from './explanations/service';
import {createExplanationGenerator} from './explanations/local-generator';
import {createReviewService} from './reviews/service';
import {createProfessionalService} from './professional/service';
import {createAssignmentService} from './assignments/service';
import {createProcessingService} from './processing/service';
import { type S3Client } from '@aws-sdk/client-s3';
import { readStorageConfig } from './storage/config';
import { createStorageClient, checkPrivateBucket } from './storage/s3';
import { createDocumentService, documentDatabase } from './documents/service';
import { s3DocumentStorage } from './documents/storage-adapter';
import { type Server } from 'node:http';
import { type Pool } from 'pg';
import { createApp } from './app';
import { readConfig } from './config';
import { readDatabaseConfig } from './database/config';
import { createDatabasePool } from './database/pool';
import { checkDatabaseAvailability } from './database/availability';
import { createCredentialAuthenticator } from './auth/credentials';
import { issueSession, findSessionAccount, revokeSession } from './auth/sessions';
import { createPatientRegistrar } from './auth/registration';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let storage: S3Client | undefined;
  let server: Server | undefined;
  let closing: Promise<void> | undefined;
  function shutdown(code = 0): Promise<void> {
    process.exitCode = Math.max(Number(process.exitCode ?? 0), code);
    if (!closing) closing = (async () => {
      if (server?.listening) {
        const current = server;
        await new Promise<void>(resolve => {
          const timer = setTimeout(() => current.closeAllConnections(), 10000);
          timer.unref();
          current.close(() => { clearTimeout(timer); resolve(); });
        });
      }
      storage?.destroy();
      if (pool) {
        try { await pool.end(); }
        catch { console.error('No se pudo cerrar PostgreSQL.'); process.exitCode = 1; }
      }
    })();
    return closing;
  }
  try {
    const config = readConfig(process.env);
    const database = createDatabasePool(readDatabaseConfig(process.env));
    pool = database;
    await checkDatabaseAvailability(database);
    const schema = await database.query<{ ready: boolean }>(
      `SELECT to_regclass('public.vitalia_accounts') IS NOT NULL
       AND to_regclass('public.vitalia_sessions') IS NOT NULL
       AND to_regclass('public.vitalia_documents') IS NOT NULL
       AND to_regclass('public.vitalia_document_audit') IS NOT NULL
       AND to_regclass('public.vitalia_document_processing') IS NOT NULL
       AND to_regclass('public.vitalia_patient_assignments') IS NOT NULL
       AND to_regclass('public.vitalia_assignment_audit') IS NOT NULL
       AND to_regclass('public.vitalia_professional_access_audit') IS NOT NULL
       AND to_regclass('public.vitalia_professional_reviews') IS NOT NULL
       AND to_regclass('public.vitalia_exam_explanations') IS NOT NULL
       AND to_regclass('public.vitalia_explanation_audit') IS NOT NULL
       AND to_regclass('public.vitalia_exam_assistant_threads') IS NOT NULL
       AND to_regclass('public.vitalia_exam_assistant_turns') IS NOT NULL
       AND to_regclass('public.vitalia_exam_assistant_audit') IS NOT NULL AS ready`,
    );
    if (schema.rows[0]?.ready !== true) throw new Error('Faltan migraciones de acceso.');
    const storageConfig = readStorageConfig(process.env);
    storage = createStorageClient(storageConfig);
    await checkPrivateBucket(storage, storageConfig);
    const documents = createDocumentService(documentDatabase(database), s3DocumentStorage(storage, storageConfig));
    const authenticate = await createCredentialAuthenticator(database);
    const register = createPatientRegistrar(database);
    server = createApp({
      authenticate,
      issue: id => issueSession(database, id),
      find: token => findSessionAccount(database, token),
      revoke: token => revokeSession(database, token),
    }, register, documents, createProcessingService(database), createAssignmentService(documentDatabase(database)), createProfessionalService(documentDatabase(database), s3DocumentStorage(storage, storageConfig)), createReviewService(documentDatabase(database)), createExplanationService(documentDatabase(database), createExplanationGenerator()), createExamAssistantService(documentDatabase(database), createExamAssistant())).listen(config.PORT, config.HOST);
    server.on('listening', () => console.info('Vitalia API iniciada en el entorno local.'));
    server.on('error', () => {
      console.error('No se pudo iniciar el servidor. Revisa el puerto y la dirección configurados.');
      void shutdown(1);
    });
    process.on('SIGINT', () => { void shutdown(); });
    process.on('SIGTERM', () => { void shutdown(); });
  } catch {
    console.error('No se pudo iniciar Vitalia API. Revisa configuración, PostgreSQL, S3 y las migraciones de acceso y documentos.');
    await shutdown(1);
  }
}
void main();
