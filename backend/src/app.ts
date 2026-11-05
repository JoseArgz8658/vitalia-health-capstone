import {createCareHistoryRouter} from './care/history-router';
import {type CareHistoryServices} from './care/history';
import {createCareInboxRouter} from './care/inbox-router';
import {type CareInboxServices} from './care/inbox';
import {createCareUploadRouter} from './care/upload-router';
import {type CareUploadServices} from './care/upload';
import {createCareCatalogRouter} from './care/catalog-router';
import {type CareCatalogServices} from './care/catalog';
import {createCredentialVerificationRouter} from './professional-credentials/router';
import {type CredentialVerificationServices} from './professional-credentials/service';
import {createTeamRouter} from './team/router';
import {type TeamServices} from './team/service';
import {createOnboardingRouter} from './onboarding/router';
import {type OnboardingServices} from './onboarding/service';
import {createInstitutionRouter} from './institutions/router';
import {type InstitutionServices} from './institutions/service';
import {createProfileRouter} from './profiles/router';
import {type ProfileServices} from './profiles/service';
import {createExamAssistantRouter} from './exam-assistant/router';
import {type ExamAssistantServices} from './exam-assistant/service';
import {createExplanationRouter} from './explanations/router';
import {type ExplanationServices} from './explanations/service';
import {createPatientReviewRouter} from './reviews/patient-router';
import {createReviewRouter} from './reviews/router';
import {type ReviewServices} from './reviews/service';
import {createProfessionalRouter} from './professional/router';
import {type ProfessionalServices} from './professional/service';
import {createAssignmentRouter} from './assignments/router';
import {type AssignmentServices} from './assignments/service';
import {createProcessingRouter} from './processing/router';
import {type ProcessingServices} from './processing/service';
import { createDocumentRouter } from './documents/router';
import { type DocumentServices } from './documents/service';
import { localWebCors } from './http/local-web-cors';
import express, { type ErrorRequestHandler } from 'express';
import { createAuthRouter, type AuthServices } from './auth/router';
import { createRegistrationRouter } from './auth/registration-router';
import { type PatientRegistrar } from './auth/registration';

export function createApp(auth?: AuthServices, register?: PatientRegistrar, documents?: DocumentServices, processing?: ProcessingServices, assignments?: AssignmentServices, professional?: ProfessionalServices, reviews?: ReviewServices, explanations?: ExplanationServices, assistant?: ExamAssistantServices, profiles?: ProfileServices, institutions?: InstitutionServices, onboarding?: OnboardingServices, team?: TeamServices, credentialVerification?: CredentialVerificationServices, careCatalog?: CareCatalogServices, careUpload?: CareUploadServices, careInbox?: CareInboxServices, careHistory?: CareHistoryServices) {
  const app = express();
  app.disable('x-powered-by');
  app.use(localWebCors);
  app.use(express.json({ limit: '32kb' }));

  // Solo disponibilidad del proceso; no implica conexión a datos ni servicios.
  app.get('/api/health', (_req, res) => {
    res.status(200).json({ status: 'ok', service: 'vitalia-api' });
  });

  if (auth && careHistory) app.use('/api/documents', createCareHistoryRouter(auth, careHistory));
  if (auth && careInbox) app.use('/api/care-inbox', createCareInboxRouter(auth, careInbox));
  if (auth && careUpload) app.use('/api/care', createCareUploadRouter(auth, careUpload));
  if (auth && careCatalog) app.use('/api/care', createCareCatalogRouter(auth, careCatalog));
  if (auth && credentialVerification) app.use('/api/professional-credentials', createCredentialVerificationRouter(auth, credentialVerification));
  if (auth && team) app.use('/api/team', createTeamRouter(auth, team));
  if (auth && onboarding) app.use('/api/onboarding', createOnboardingRouter(auth, onboarding));
  if (auth && institutions) app.use('/api/institutions', createInstitutionRouter(auth, institutions));
  if (auth && profiles) app.use('/api/profile', createProfileRouter(auth, profiles));
  if (auth && assistant) app.use('/api/documents', createExamAssistantRouter(auth, assistant));

  if (auth && explanations) app.use('/api/documents', createExplanationRouter(auth, explanations));

  if (auth && reviews) app.use('/api/documents', createPatientReviewRouter(auth, reviews));

  if (auth && reviews) app.use('/api/professional', createReviewRouter(auth, reviews));

  if (auth && professional) app.use('/api/professional', createProfessionalRouter(auth, professional));

  if (auth && assignments) app.use('/api/assignments', createAssignmentRouter(auth, assignments));

  if (auth && processing) app.use('/api/documents', createProcessingRouter(auth, processing));

  if (auth && documents) app.use('/api/documents', createDocumentRouter(auth, documents));

  if (register) app.use('/api/auth', createRegistrationRouter(register));
  if (auth) app.use('/api/auth', createAuthRouter(auth));

  app.use((_req, res) => {
    res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Recurso no disponible.' } });
  });

  const handleError: ErrorRequestHandler = (error, _req, res, next) => {
    if (res.headersSent) { next(error); return; }
    const status = error?.type === 'entity.too.large' ? 413
      : error?.type === 'entity.parse.failed' ? 400 : 500;
    res.status(status).json({ error: {
      code: status === 413 ? 'PAYLOAD_TOO_LARGE' : status === 400 ? 'INVALID_JSON' : 'INTERNAL_ERROR',
      message: status === 413 ? 'Solicitud demasiado grande.'
        : status === 400 ? 'La solicitud contiene JSON inválido.' : 'No se pudo completar la solicitud.',
    } });
  };
  app.use(handleError);
  return app;
}
