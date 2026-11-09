import {createSilService} from './sil/service';
import {createSilMainService} from './sil/main-service';
import {createCareHistoryService} from './care/history';
import {createCareInboxService} from './care/inbox';
import {createCareUploadService} from './care/upload';
import {createCareCatalogService} from './care/catalog';
import {createCredentialVerificationService} from './professional-credentials/service';
import {createTeamService} from './team/service';
import {createOnboardingService} from './onboarding/service';
import {createInstitutionService} from './institutions/service';
import {createProfileService} from './profiles/service';
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
       AND to_regclass('public.vitalia_exam_assistant_audit') IS NOT NULL
       AND to_regclass('public.vitalia_care_contacts') IS NOT NULL
       AND to_regclass('public.vitalia_care_access_audit') IS NOT NULL
       AND to_regclass('public.vitalia_approved_review_refs') IS NOT NULL
       AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='025_preliminary_assistant') AS ready`,
    );
    if (schema.rows[0]?.ready !== true) throw new Error('Faltan migraciones de acceso.');
    if (process.env.VITALIA_SIL_MAIN_MODE==='YES') {
      const mainSchema=await database.query<{ready:boolean}>(
        `SELECT to_regclass('public.vitalia_sil_main_laboratories') IS NOT NULL
           AND to_regclass('public.vitalia_sil_main_staff') IS NOT NULL
           AND to_regclass('public.vitalia_sil_main_patients') IS NOT NULL
           AND to_regclass('public.vitalia_sil_main_orders') IS NOT NULL
           AND to_regclass('public.vitalia_sil_main_reports') IS NOT NULL
           AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations
             WHERE version='038_sil_main_postanalytical')
           AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations
             WHERE version='039_sil_main_operator_review') AS ready`);
      if(mainSchema.rows[0]?.ready!==true) {
        throw new Error('SIL principal solicitado sin esquema 039: activación bloqueada.');
      }
    }
    const storageConfig = readStorageConfig(process.env);
    storage = createStorageClient(storageConfig);
    await checkPrivateBucket(storage, storageConfig);
    const careUpload = createCareUploadService(documentDatabase(database));
    const documents = createDocumentService(documentDatabase(database), s3DocumentStorage(storage, storageConfig), careUpload);
    const authenticate = await createCredentialAuthenticator(database);
    const register = createPatientRegistrar(database);
    server = createApp({
      authenticate,
      issue: (id,mode) => issueSession(database, id,mode),
      find: token => findSessionAccount(database, token),
      revoke: token => revokeSession(database, token),
    }, register, documents, createProcessingService(database), createAssignmentService(documentDatabase(database)), createProfessionalService(documentDatabase(database), s3DocumentStorage(storage, storageConfig)), createReviewService(documentDatabase(database)), createExplanationService(documentDatabase(database), createExplanationGenerator()), createExamAssistantService(documentDatabase(database), createExamAssistant()), createProfileService(documentDatabase(database)), createInstitutionService(documentDatabase(database)), createOnboardingService(documentDatabase(database)), createTeamService(documentDatabase(database)), createCredentialVerificationService(documentDatabase(database)), createCareCatalogService(database), careUpload, createCareInboxService(documentDatabase(database), s3DocumentStorage(storage, storageConfig)), createCareHistoryService(documentDatabase(database)), createSilService(database), createSilMainService(database)).listen(config.PORT, config.HOST);
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
