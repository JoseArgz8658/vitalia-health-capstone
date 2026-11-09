import express,{Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {DocumentInputError} from '../documents/file-validation';
import {
  SilMainAccessDenied,SilMainNotFound,SilMainConflict,type SilMainServices
} from './main-service';

const uuid=z.uuid();
const examCode=z.string().regex(/^[a-z0-9_]{3,40}$/);
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
    if(!['administrador','operador_laboratorio','profesional'].includes(
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

  router.post('/labs/:labId/staff',administrator,labPath,async(req,res)=>{
    const data=z.object({
      accountId:uuid,
      kind:z.enum(['operator','validator']),
    }).strict().safeParse(req.body);
    if(!data.success){
      res.status(400).json({error:{code:'INVALID_STAFF'}});return;
    }
    res.status(201).json(await main.grantStaff(
      req.params.labId as string,data.data.accountId,data.data.kind,
      res.locals.account.id));
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
    }).strict().safeParse(req.query);
    if(!data.success){res.status(400).json({error:{code:'INVALID_PAGE'}});return;}
    res.json(await main.listOrders(
      req.params.labId as string,res.locals.account.id,res.locals.account.role,
      data.data.limit,data.data.offset));
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

  router.post('/labs/:labId/orders/:orderId/report/publish',staff,labPath,
    async(req,res)=>{
      if(res.locals.account.role!=='profesional'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      if(!uuid.safeParse(req.params.orderId).success){
        res.status(404).json({error:{code:'NOT_FOUND'}});return;
      }
      const data=z.object({
        professionalReviewConfirmed:z.literal(true),
      }).strict().safeParse(req.body);
      if(!data.success){
        res.status(400).json({error:{code:'INVALID_PUBLICATION'}});return;
      }
      res.status(201).json(await main.publishReport(
        req.params.labId as string,req.params.orderId as string,
        res.locals.account.id));
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
