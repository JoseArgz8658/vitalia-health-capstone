import express,{Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {createLoginAttemptLimiter} from '../auth/login-limit';
import {createSilPatientRecoveryRouterDemo} from './patient-recovery-router-demo';
import {DocumentInputError} from '../documents/file-validation';
import {SilEducationNotFound,SilEducationBusy,SilEducationUnavailable}
  from './patient-education';
import {
  SilMainAccessDenied,SilMainNotFound,SilMainConflict,type SilMainServices
} from './main-service';

const uuid=z.uuid();
const examCode=z.string().regex(/^[a-z0-9_]{3,40}$/);
const pdfFileName=z.string().trim().min(5).max(120).regex(/[.]pdf$/i)
  .refine(value=>!/[\/\\\x00-\x1f]/.test(value));
const medicalRequest=z.object({
  fileName:pdfFileName,
  prescriberName:z.string().trim().min(3).max(150),
  // Compatibilidad con clientes anteriores. La referencia administrativa se
  // asigna siempre en el servidor al persistir el PDF, nunca desde este valor.
  documentReference:z.string().trim().min(6).max(150).optional(),
  requestDate:z.iso.date(),
  patientIdentityConfirmed:z.literal(true),
  humanReviewConfirmed:z.literal(true),
});
function medicalRequestHeaders(req:express.Request){
  try {
    return {
      fileName:decodeURIComponent(req.get('x-request-filename')??''),
      prescriberName:decodeURIComponent(req.get('x-request-prescriber')??''),
      documentReference:decodeURIComponent(req.get('x-request-reference')??''),
      requestDate:req.get('x-request-date'),
      patientIdentityConfirmed:req.get('x-request-identity-confirmed')==='true',
      humanReviewConfirmed:req.get('x-request-reviewed')==='true',
    };
  } catch {
    return undefined;
  }
}
const laboratoryId=uuid;
const labPath=async(req:express.Request,res:express.Response,next:express.NextFunction)=>{
  if(!laboratoryId.safeParse(req.params.labId).success){
    res.status(404).json({error:{code:'NOT_FOUND'}});return;
  }
  next();
};

/**
 * Rutas exclusivas de Vitalia PRINCIPAL. Nunca reutilizan un permiso
 * de DEMO ni obtienen un laboratorio de una variable de entorno.
 * Todos los recursos de operador se limitan por labId y pertenencia activa.
 */
export function createSilMainRouter(auth:Pick<AuthServices,'find'>,
  main:SilMainServices) {
  const router=Router();
  const allowOperatorActivation=createLoginAttemptLimiter();
  // Activación pública solo con invitación de 256 bits ya emitida por admin.
  // No requiere contraseña de otro usuario ni permite elegir un rol.
  router.post('/operators/activate',async(req,res)=>{
    res.set('Cache-Control','private, no-store');
    if(!allowOperatorActivation(req.ip??req.socket.remoteAddress??'local')){
      res.status(429).json({error:{code:'RATE_LIMITED'}});return;
    }
    const data=z.object({
      email:z.string().trim().toLowerCase().pipe(z.email().max(254)),
      code:z.string().regex(/^[A-Za-z0-9_-]{43}$/),
      password:z.string().refine(v=>[...v].length>=12
        && Buffer.byteLength(v,'utf8')<=1024),
    }).strict().safeParse(req.body);
    if(!data.success){
      res.status(400).json({error:{code:'INVALID_INVITATION'}});return;
    }
    res.status(201).json(await main.activateOperator(
      data.data.email,data.data.code,data.data.password));
  });
  const allowPatientActivation=createLoginAttemptLimiter();
  router.post('/patients/activate',async(req,res)=>{
    res.set('Cache-Control','no-store');
    if(!allowPatientActivation(req.ip??req.socket.remoteAddress??'local')){
      res.status(429).json({error:{code:'RATE_LIMITED'}});return;
    }
    const data=z.object({
      email:z.string().trim().toLowerCase().pipe(z.email().max(254)),
      code:z.string().regex(/^[A-Za-z0-9_-]{43}$/),
      password:z.string().refine(v=>[...v].length>=12&&Buffer.byteLength(v,'utf8')<=1024),
    }).strict().safeParse(req.body);
    if(!data.success){res.status(400).json({error:{code:'INVALID_INVITATION'}});return;}
    res.status(201).json(await main.activatePatient(data.data.email,data.data.code,data.data.password));
  });
  router.use('/patient/recovery',createSilPatientRecoveryRouterDemo(auth,main.patientRecovery,'main'));
  router.use(async(req,res,next)=>{
    res.set('Cache-Control','private, no-store');
    const tokenParts=req.get('Authorization')?.split(' ');
    const token=tokenParts?.length===2 &&
      tokenParts[0].toLowerCase()==='bearer' &&
      isSessionToken(tokenParts[1])?tokenParts[1]:null;
    const account=token?await auth.find(token):null;
    if(!account){
      res.status(401).json({error:{code:'UNAUTHORIZED'}});return;
    }
    res.locals.account=account;
    next();
  });
  const administrator=(req:express.Request,res:express.Response,next:express.NextFunction)=>{
    if(res.locals.account.role!=='administrador'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    next();
  };
  const patient=(req:express.Request,res:express.Response,next:express.NextFunction)=>{
    if(res.locals.account.role!=='paciente'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    next();
  };
  const staff=(req:express.Request,res:express.Response,next:express.NextFunction)=>{
    if(!['administrador','operador_laboratorio'].includes(
      res.locals.account.role)){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    next();
  };

  router.get('/labs',staff,async(_req,res)=>{
    const result=await main.laboratoriesFor(
      res.locals.account.id,res.locals.account.role);
    res.json(result);
  });

  router.post('/labs',administrator,async(req,res)=>{
    const data=z.object({displayName:z.string().trim().min(3).max(150)})
      .strict().safeParse(req.body);
    if(!data.success){
      res.status(400).json({error:{code:'INVALID_LABORATORY'}});return;
    }
    res.status(201).json(await main.createLaboratory(
      data.data.displayName,res.locals.account.id));
  });

  router.post('/labs/:labId/operator-invitations',administrator,labPath,
    async(req,res)=>{
      const data=z.object({
        email:z.string().trim().toLowerCase().pipe(z.email().max(254)),
      }).strict().safeParse(req.body);
      if(!data.success){
        res.status(400).json({error:{code:'INVALID_INVITATION'}});return;
      }
      res.status(201).json(await main.inviteOperator(
        req.params.labId as string,data.data.email,res.locals.account.id));
    });

  // La lista de operadores se limita al laboratorio seleccionado y al administrador.
  router.get('/labs/:labId/staff',administrator,labPath,async(req,res)=>{
    res.json(await main.listStaff(req.params.labId as string));
  });

  router.post('/labs/:labId/staff',administrator,labPath,async(req,res)=>{
    const data=z.object({
      accountId:uuid,
    }).strict().safeParse(req.body);
    if(!data.success){
      res.status(400).json({error:{code:'INVALID_STAFF'}});return;
    }
    res.status(201).json(await main.grantStaff(
      req.params.labId as string,data.data.accountId,
      res.locals.account.id));
  });

  router.post('/labs/:labId/staff/review-permission',administrator,labPath,async(req,res)=>{
    const data=z.object({accountId:uuid,enabled:z.boolean()}).strict().safeParse(req.body);
    if(!data.success){
      res.status(400).json({error:{code:'INVALID_STAFF'}});return;
    }
    res.json(await main.setReviewPermission(
      req.params.labId as string,data.data.accountId,res.locals.account.id,data.data.enabled));
  });

  router.get('/labs/:labId/patients',staff,labPath,async(req,res)=>{
    if(res.locals.account.role!=='operador_laboratorio'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const page=z.object({
      limit:z.coerce.number().int().min(1).max(50).default(20),
      offset:z.coerce.number().int().min(0).max(10000).default(0),
      search:z.string().trim().max(120).default(''),
    }).strict().safeParse(req.query);
    if(!page.success){res.status(400).json({error:{code:'INVALID_PAGE'}});return;}
    res.json(await main.listPatients(req.params.labId as string,res.locals.account.id,page.data));
  });

  router.post('/labs/:labId/patients',staff,labPath,async(req,res)=>{
    if(res.locals.account.role!=='operador_laboratorio'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const data=z.object({
      patientId:uuid,
      identityEvidenceReference:z.string().trim().min(6).max(150),
      identityVerified:z.literal(true),
    }).strict().safeParse(req.body);
    if(!data.success){
      res.status(400).json({error:{code:'INVALID_PATIENT_LINK'}});return;
    }
    res.status(201).json(await main.associatePatient(
      req.params.labId as string,data.data.patientId,
      res.locals.account.id,data.data.identityEvidenceReference));
  });

  router.get('/labs/:labId/orders',staff,labPath,async(req,res)=>{
    const data=z.object({
      limit:z.coerce.number().int().min(1).max(50).default(20),
      offset:z.coerce.number().int().min(0).max(10000).default(0),
      search:z.string().trim().min(1).max(254).optional(),
      status:z.enum(['registered','report_attached','report_published']).optional(),
      patientId:uuid.optional(),
    }).strict().safeParse(req.query);
    if(!data.success){res.status(400).json({error:{code:'INVALID_PAGE'}});return;}
    if(res.locals.account.role!=='operador_laboratorio'&&(data.data.search||data.data.patientId)){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const {limit,offset,...filters}=data.data;
    res.json(await main.listOrders(
      req.params.labId as string,res.locals.account.id,res.locals.account.role,
      limit,offset,filters));
  });

  const allowPatientInvite=createLoginAttemptLimiter();
  router.post('/labs/:labId/patient-invitations',staff,labPath,async(req,res)=>{
    if(res.locals.account.role!=='operador_laboratorio'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    if(!allowPatientInvite(res.locals.account.id)){
      res.status(429).json({error:{code:'RATE_LIMITED'}});return;
    }
    const data=z.object({
      email:z.string().trim().toLowerCase().pipe(z.email().max(254)),
      identityReference:z.string().trim().min(6).max(150),
      identityConfirmed:z.literal(true),
    }).strict().safeParse(req.body);
    if(!data.success){res.status(400).json({error:{code:'INVALID_INVITATION'}});return;}
    res.status(201).json(await main.invitePatient(req.params.labId as string,res.locals.account.id,
      data.data.email,data.data.identityReference));
  });

  // Derivaciones pendientes: sin cuenta ni orden hasta que un operador
  // verifique identidad y el paciente active su acceso al laboratorio.
  router.post('/labs/:labId/medical-requests/pending',staff,labPath,
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      let name:string,email:string;
      try{
        name=decodeURIComponent(req.get('x-request-filename')??'');
        email=decodeURIComponent(req.get('x-request-patient-email')??'').trim().toLowerCase();
      }catch{
        res.status(400).json({error:{code:'INVALID_PENDING_REQUEST'}});return;
      }
      const validName=pdfFileName.safeParse(name);
      const validEmail=z.union([z.literal(''),z.email().max(254)]).safeParse(email);
      if(!validName.success||!validEmail.success||!Buffer.isBuffer(req.body)){
        res.status(400).json({error:{code:'INVALID_PENDING_REQUEST'}});return;
      }
      res.status(201).json(await main.savePendingMedicalRequest(
        req.params.labId as string,res.locals.account.id,
        validName.data,req.body,email||null));
    });

  router.get('/labs/:labId/medical-requests/pending',staff,labPath,async(req,res)=>{
    if(res.locals.account.role!=='operador_laboratorio'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const page=z.object({
      limit:z.coerce.number().int().min(1).max(50).default(20),
      offset:z.coerce.number().int().min(0).max(10000).default(0),
    }).strict().safeParse(req.query);
    if(!page.success){res.status(400).json({error:{code:'INVALID_PAGE'}});return;}
    res.json(await main.listPendingMedicalRequests(req.params.labId as string,
      res.locals.account.id,page.data.limit,page.data.offset));
  });

  router.get('/labs/:labId/medical-requests/pending/:pendingId/file',
    staff,labPath,async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      if(!uuid.safeParse(req.params.pendingId).success){
        res.status(404).json({error:{code:'NOT_FOUND'}});return;
      }
      const file=await main.downloadPendingMedicalRequest(req.params.labId as string,
        req.params.pendingId as string,res.locals.account.id);
      res.set('Cache-Control','private, no-store');
      res.set('X-Content-Type-Options','nosniff');
      res.set('Content-Type','application/pdf');
      res.set('Content-Disposition',"attachment; filename*=UTF-8''"+
        encodeURIComponent(file.fileName));
      res.set('Content-Length',String(file.bytes.length));
      res.send(file.bytes);
    });

  router.post('/labs/:labId/medical-requests/pending/:pendingId/complete',
    staff,labPath,async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      if(!uuid.safeParse(req.params.pendingId).success){
        res.status(404).json({error:{code:'NOT_FOUND'}});return;
      }
      const parsed=medicalRequest.omit({fileName:true}).extend({
        patientId:uuid,
        patientEmail:z.email().max(254).transform(s=>s.trim().toLowerCase()),
        examCodes:z.array(examCode).min(1).max(6)
          .refine(items=>new Set(items).size===items.length),
      }).strict().safeParse(req.body);
      if(!parsed.success){
        res.status(400).json({error:{code:'INVALID_PENDING_COMPLETION'}});return;
      }
      const {patientId,patientEmail,examCodes,...request}=parsed.data;
      res.status(201).json(await main.completePendingMedicalRequest(
        req.params.labId as string,req.params.pendingId as string,
        res.locals.account.id,patientId,patientEmail,examCodes,request));
    });

  const clinicalPath='/labs/:labId/orders/:orderId/clinical';
  const clinicalOperator=(req:express.Request,res:express.Response,next:express.NextFunction)=>{
    if(res.locals.account.role!=='operador_laboratorio'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    if(!uuid.safeParse(req.params.orderId).success){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    next();
  };
  router.get(clinicalPath,staff,labPath,clinicalOperator,async(req,res)=>{
    res.json(await main.clinicalDetails(req.params.labId as string,req.params.orderId as string,res.locals.account.id));
  });
  router.get(clinicalPath+'/audit',staff,labPath,clinicalOperator,async(req,res)=>{
    res.json(await main.recentOrderActivity(req.params.labId as string,
      req.params.orderId as string,res.locals.account.id));
  });
  router.post(clinicalPath+'/samples',staff,labPath,clinicalOperator,async(req,res)=>{
    const data=z.object({containerCode:examCode}).strict().safeParse(req.body);
    if(!data.success){res.status(400).json({error:{code:'INVALID_SAMPLE'}});return;}
    res.status(201).json(await main.receiveSample(req.params.labId as string,
      req.params.orderId as string,res.locals.account.id,data.data.containerCode));
  });
  router.post(clinicalPath+'/results/preview',staff,labPath,clinicalOperator,
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
      if(!Buffer.isBuffer(req.body)){
        res.status(400).json({error:{code:'INVALID_RESULTS_PDF'}});return;
      }
      res.json(await main.previewAnalytes(req.params.labId as string,
        req.params.orderId as string,res.locals.account.id,req.body));
    });
  router.post(clinicalPath+'/results',staff,labPath,clinicalOperator,async(req,res)=>{
    const data=z.object({values:z.array(z.object({
      examCode,analyte:z.string().trim().min(1).max(100),numericValue:z.number().min(-1e9).max(1e9),
    }).strict()).min(1).max(100)}).strict().safeParse(req.body);
    if(!data.success){res.status(400).json({error:{code:'INVALID_RESULTS'}});return;}
    res.status(201).json(await main.recordAnalytes(req.params.labId as string,
      req.params.orderId as string,res.locals.account.id,data.data.values));
  });
  router.post(clinicalPath+'/review',staff,labPath,clinicalOperator,async(req,res)=>{
    const data=z.discriminatedUnion('decision',[
      z.object({decision:z.literal('approved')}).strict(),
      z.object({decision:z.literal('returned'),reason:z.string().trim().min(5).max(300)}).strict(),
    ]).safeParse(req.body);
    if(!data.success){res.status(400).json({error:{code:'INVALID_REVIEW'}});return;}
    res.json(await main.reviewAnalytes(req.params.labId as string,req.params.orderId as string,
      res.locals.account.id,data.data.decision,'reason' in data.data?data.data.reason:undefined));
  });

  router.post('/labs/:labId/orders',staff,labPath,async(req,res)=>{
    if(res.locals.account.role!=='operador_laboratorio'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const data=z.object({
      patientId:uuid,
      examCodes:z.array(examCode).min(1).max(6)
        .refine(items=>new Set(items).size===items.length),
    }).strict().safeParse(req.body);
    if(!data.success){res.status(400).json({error:{code:'INVALID_ORDER'}});return;}
    res.status(201).json(await main.createOrder(
      req.params.labId as string,data.data.patientId,
      data.data.examCodes,res.locals.account.id));
  });

  router.post('/labs/:labId/medical-requests/preview',staff,labPath,
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      const file=pdfFileName.safeParse(medicalRequestHeaders(req)?.fileName);
      if(!file.success||!Buffer.isBuffer(req.body)){
        res.status(400).json({error:{code:'INVALID_MEDICAL_REQUEST'}});return;
      }
      res.json(await main.previewMedicalRequest(
        req.params.labId as string,res.locals.account.id,file.data,req.body));
    });

  router.post('/labs/:labId/medical-requests',staff,labPath,
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      const data=medicalRequest.extend({
        patientId:uuid,
        examCodes:z.array(examCode).min(1).max(6)
          .refine(items=>new Set(items).size===items.length),
      }).safeParse({
        ...medicalRequestHeaders(req),
        patientId:req.get('x-request-patient-id'),
        examCodes:req.get('x-request-exam-codes')?.split(','),
      });
      if(!data.success||!Buffer.isBuffer(req.body)){
        res.status(400).json({error:{code:'INVALID_MEDICAL_REQUEST'}});return;
      }
      const {patientId,examCodes,...request}=data.data;
      res.status(201).json(await main.createOrderFromMedicalRequest(
        req.params.labId as string,patientId,examCodes,res.locals.account.id,request,req.body));
    });

  router.post('/labs/:labId/orders/:orderId/medical-request',staff,labPath,
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      if(!uuid.safeParse(req.params.orderId).success||!Buffer.isBuffer(req.body)){
        res.status(400).json({error:{code:'INVALID_MEDICAL_REQUEST'}});return;
      }
      const data=medicalRequest.safeParse(medicalRequestHeaders(req));
      if(!data.success){
        res.status(400).json({error:{code:'INVALID_MEDICAL_REQUEST'}});return;
      }
      res.status(201).json(await main.attachMedicalRequest(
        req.params.labId as string,req.params.orderId as string,
        res.locals.account.id,data.data,req.body));
    });
  router.get('/labs/:labId/orders/:orderId/medical-request/file',
    staff,labPath,async(req,res)=>{
      if(!uuid.safeParse(req.params.orderId).success){
        res.status(404).json({error:{code:'NOT_FOUND'}});return;
      }
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      const file=await main.downloadMedicalRequest(
        req.params.labId as string,req.params.orderId as string,
        res.locals.account.id);
      res.set('Cache-Control','private, no-store');
      res.set('X-Content-Type-Options','nosniff');
      res.set('Content-Type','application/pdf');
      res.set('Content-Disposition',
        "attachment; filename*=UTF-8''"+encodeURIComponent(file.fileName));
      res.set('Content-Length',String(file.bytes.length));
      res.send(file.bytes);
    });

  router.post('/labs/:labId/orders/:orderId/report',staff,labPath,
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      if(!uuid.safeParse(req.params.orderId).success || !Buffer.isBuffer(req.body)){
        res.status(400).json({error:{code:'INVALID_REPORT'}});return;
      }
      let input:Record<string,unknown>;
      try{
        input={
          fileName:decodeURIComponent(req.get('x-report-filename')??''),
          authorizedProfessionalName:decodeURIComponent(req.get('x-report-authorized-professional')??''),
          authorizationReference:decodeURIComponent(req.get('x-report-authorization-ref')??''),
          externallyAuthorizedAt:req.get('x-report-authorized-at'),
          patientMatchConfirmed:req.get('x-report-patient-confirmed')==='true',
        };
      }catch{
        res.status(400).json({error:{code:'INVALID_REPORT'}});return;
      }
      const data=z.object({
        fileName:z.string().trim().min(5).max(120).regex(/[.]pdf$/i)
          .refine(v=>!/[\/\\\x00-\x1f]/.test(v)),
        authorizedProfessionalName:z.string().trim().min(3).max(150),
        authorizationReference:z.string().trim().min(6).max(150),
        externallyAuthorizedAt:z.iso.datetime({offset:true}),
        patientMatchConfirmed:z.literal(true),
      }).strict().safeParse(input);
      if(!data.success){
        res.status(400).json({error:{code:'INVALID_REPORT'}});return;
      }
      res.status(201).json(await main.attachReport(
        req.params.labId as string,req.params.orderId as string,
        res.locals.account.id,data.data,req.body));
    });

  router.get('/labs/:labId/orders/:orderId/report/file',
    staff,labPath,async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      if(!uuid.safeParse(req.params.orderId).success){
        res.status(404).json({error:{code:'NOT_FOUND'}});return;
      }
      const file=await main.reportForReview(
        req.params.labId as string,req.params.orderId as string,
        res.locals.account.id);
      res.set('Cache-Control','private, no-store');
      res.set('X-Content-Type-Options','nosniff');
      res.set('Content-Type','application/pdf');
      res.set('Content-Disposition',
        "attachment; filename*=UTF-8''"+encodeURIComponent(file.fileName));
      res.set('Content-Length',String(file.bytes.length));
      res.send(file.bytes);
    });

  router.post('/labs/:labId/orders/:orderId/report/publish',staff,labPath,
    async(req,res)=>{
      if(res.locals.account.role!=='operador_laboratorio'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      if(!uuid.safeParse(req.params.orderId).success){
        res.status(404).json({error:{code:'NOT_FOUND'}});return;
      }
      const data=z.object({
        operatorReviewConfirmed:z.literal(true),
      }).strict().safeParse(req.body);
      if(!data.success){
        res.status(400).json({error:{code:'INVALID_PUBLICATION'}});return;
      }
      res.status(201).json(await main.publishReport(
        req.params.labId as string,req.params.orderId as string,
        res.locals.account.id));
    });

  router.post('/patient/reports/overview',patient,async(req,res)=>{
    const data=z.object({
      reportIds:z.array(uuid).min(1).max(4)
        .refine(items=>new Set(items).size===items.length),
    }).strict().safeParse(req.body);
    if(!data.success){
      res.status(400).json({error:{code:'INVALID_REPORT_SELECTION'}});return;
    }
    res.json(await main.getPatientReportOverview(
      res.locals.account.id,data.data.reportIds));
  });
  router.post('/patient/reports/:id/chat',patient,async(req,res)=>{
    const data=z.object({
      question:z.string().trim().min(3).max(400),
      simple:z.boolean().optional(),
    }).strict().safeParse(req.body);
    if(!uuid.safeParse(req.params.id).success || !data.success){
      res.status(400).json({error:{code:'INVALID_QUESTION'}});return;
    }
    res.json({response:await main.askPatientReport(
      res.locals.account.id,req.params.id as string,
      data.data.question,data.data.simple)});
  });
  router.get('/patient/profile',patient,async(_req,res)=>{
    res.json(await main.patientProfile(res.locals.account.id));
  });
  router.get('/patient/reports',patient,async(_req,res)=>{
    res.json(await main.patientReports(res.locals.account.id));
  });
  router.get('/patient/reports/:id/file',patient,async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    const file=await main.downloadPatientReport(
      res.locals.account.id,req.params.id as string);
    res.set('Cache-Control','private, no-store');
    res.set('X-Content-Type-Options','nosniff');
    res.set('Content-Type','application/pdf');
    res.set('Content-Disposition',
      "attachment; filename*=UTF-8''"+encodeURIComponent(file.fileName));
    res.set('Content-Length',String(file.bytes.length));
    res.send(file.bytes);
  });

  const errors:ErrorRequestHandler=(error,_req,res,next)=>{
    if(error instanceof SilEducationNotFound){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    if(error instanceof SilEducationBusy){
      res.status(429).json({error:{code:'ASSISTANT_RATE_LIMIT'}});return;
    }
    if(error instanceof SilEducationUnavailable){
      res.status(503).json({error:{code:'ASSISTANT_UNAVAILABLE'}});return;
    }
    if(error instanceof SilMainAccessDenied){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    if(error instanceof SilMainNotFound){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    if(error instanceof SilMainConflict){
      res.status(409).json({error:{code:'INVALID_STATE'}});return;
    }
    if(error instanceof DocumentInputError){
      res.status(400).json({error:{code:'INVALID_REPORT'}});return;
    }
    if((error as {type?:string}).type==='entity.too.large'){
      res.status(413).json({error:{code:'PAYLOAD_TOO_LARGE'}});return;
    }
    next(error);
  };
  router.use(errors);
  return router;
}
