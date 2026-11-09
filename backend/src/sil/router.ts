import express,{Router,type ErrorRequestHandler} from 'express';
import {DocumentInputError} from '../documents/file-validation';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {SilConflictError,SilNotFoundError,type SilServices} from './service';
import {SilEducationNotFound,SilEducationBusy,SilEducationUnavailable} from './patient-education';
import {silDemoIdentifier} from './identifiers';

const uuid = z.uuid();
const resultSchema = z.object({
  examCode:z.string().regex(/^[a-z0-9_]{3,40}$/),
  analyte:z.string().trim().min(1).max(100),
  numericValue:z.number().finite().min(-1000000000).max(1000000000),
}).strict();
export function createSilRouter(auth:Pick<AuthServices,'find'>,service:SilServices,
  options:{demoReviewOperatorId?:string}={}) {
  const router=Router();
  function canReview(account:{id:string;role:string}) {
    return account.role==='validador_laboratorio' ||
      (account.role==='operador_laboratorio' && process.env.VITALIA_SIL_DEMO==='YES' &&
        account.id===options.demoReviewOperatorId);
  }
  router.use(async(req,res,next)=>{
    res.set('Cache-Control','no-store');
    const parts=req.get('Authorization')?.split(' ');
    const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&
      isSessionToken(parts[1])?parts[1]:null;
    const account=token?await auth.find(token):null;
    if(!account) {res.status(401).json({error:{code:'UNAUTHORIZED'}});return;}
    // Informes publicados: el paciente solo puede leer sus propios documentos.
    const patientRoute=(req.method==='GET' &&
      (req.path==='/patient/reports' ||
       /^\/patient\/reports\/[a-f0-9-]{36}\/file$/.test(req.path))) ||
      (req.method==='POST' &&
       /^\/patient\/reports\/[a-f0-9-]{36}\/chat$/.test(req.path));
    if(patientRoute){
      if(account.role!=='paciente' || process.env.VITALIA_SIL_DEMO!=='YES'){
        res.status(403).json({error:{code:'FORBIDDEN'}});return;
      }
      res.locals.account=account;
      next();
      return;
    }
    // Un único laboratorio en este MVP, con separación real de funciones.
    if(!['administrador','operador_laboratorio','validador_laboratorio'].includes(account.role)) {
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const reportAction=req.method==='POST' &&
      (/^\/orders\/[a-f0-9-]{36}\/report(?:\/publish)?$/.test(req.path));
    const previewAction=req.method==='POST' &&
      /^\/orders\/[a-f0-9-]{36}\/results\/preview$/.test(req.path);
    if((reportAction||previewAction) && process.env.VITALIA_SIL_DEMO!=='YES'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const intakeAction=req.method==='POST' &&
      /^\/medical-requests\/(?:preview|confirm)$/.test(req.path);
    if(intakeAction && process.env.VITALIA_SIL_DEMO!=='YES'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const reviewAction=req.method==='POST' &&
      /^\/orders\/[a-f0-9-]{36}\/review$/.test(req.path);
    if((reviewAction && !canReview(account)) ||
       (!reviewAction && req.method!=='GET' && account.role!=='operador_laboratorio')) {
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    res.locals.account=account;
    next();
  });
  router.post('/patient/reports/:id/chat',async(req,res)=>{
    const data=z.object({
      question:z.string().trim().min(3).max(400),
    }).strict().safeParse(req.body);
    if(!uuid.safeParse(req.params.id).success||!data.success){
      res.status(400).json({error:{code:'INVALID_QUESTION'}});return;
    }
    const answer=await service.askPatientReport(
      res.locals.account.id,req.params.id as string,data.data.question);
    res.json({response:answer});
  });
  router.get('/patient/reports',async(_req,res)=>{
    res.json(await service.listPatientReports(res.locals.account.id));
  });
  router.get('/patient/reports/:id/file',async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    const file=await service.downloadPatientReport(
      res.locals.account.id,req.params.id as string);
    res.set('Cache-Control','private, no-store');
    res.set('X-Content-Type-Options','nosniff');
    res.set('Content-Type','application/pdf');
    res.set('Content-Disposition',"attachment; filename*=UTF-8''"+
      encodeURIComponent(file.fileName));
    res.set('Content-Length',String(file.bytes.length));
    res.send(file.bytes);
  });
  router.post('/medical-requests/preview',
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
    if(!Buffer.isBuffer(req.body)){
      res.status(400).json({error:{code:'INVALID_REQUEST_DOCUMENT'}});return;
    }
    let email:string;
    let fileName:string;
    try{
      email=decodeURIComponent(req.get('x-request-patient-email')??'')
        .toLowerCase().trim();
      fileName=decodeURIComponent(req.get('x-request-filename')??'');
    }catch{
      res.status(400).json({error:{code:'INVALID_REQUEST_DOCUMENT'}});return;
    }
    const parsed=z.object({
      email:z.email().max(254).refine(v=>v.endsWith('@example.invalid')),
      fileName:z.string().min(5).max(120).regex(/\.pdf$/i)
        .refine(v=>!/[\/\\\x00-\x1f]/.test(v)),
    }).safeParse({email,fileName});
    if(!parsed.success){
      res.status(400).json({error:{code:'INVALID_REQUEST_DOCUMENT'}});return;
    }
    const preview=await service.previewMedicalRequest(
      res.locals.account.id,parsed.data.email,parsed.data.fileName,req.body);
    res.json({preview});
  });
  router.post('/medical-requests/confirm',async(req,res)=>{
    const parsed=z.object({
      previewToken:uuid,
      patientId:uuid,
      branchCode:z.string().regex(/^[a-z0-9-]{3,50}$/),
      examCodes:z.array(z.string().regex(/^[a-z0-9_]{3,40}$/)).min(1).max(6),
      documentReference:z.string().trim().min(3).max(100),
      prescriberName:z.string().trim().min(3).max(120),
      requestDate:z.iso.date(),
      verified:z.literal(true),
    }).strict().superRefine((data,ctx)=>{
      if(new Set(data.examCodes).size!==data.examCodes.length)
        ctx.addIssue({code:'custom',message:'Prestaciones duplicadas'});
    }).safeParse(req.body);
    if(!parsed.success){
      res.status(400).json({error:{code:'INVALID_REQUEST_CONFIRMATION'}});return;
    }
    const result=await service.confirmMedicalRequest(res.locals.account.id,parsed.data);
    res.status(201).json(result);
  });
  router.get('/branches',async(_req,res)=>{
    res.json(await service.branches());
  });
  router.get('/patients/profile',async(req,res)=>{
    if(res.locals.account.role!=='operador_laboratorio' ||
       process.env.VITALIA_SIL_DEMO!=='YES'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const parsed=z.object({
      email:z.email().max(254).refine(v=>v.endsWith('@example.invalid')),
    }).strict().safeParse(req.query);
    if(!parsed.success){
      res.status(400).json({error:{code:'INVALID_PATIENT'}});return;
    }
    res.json(await service.patientProfileDemo(parsed.data.email.toLowerCase()));
  });
  router.post('/patients/profile',async(req,res)=>{
    if(res.locals.account.role!=='operador_laboratorio' ||
       process.env.VITALIA_SIL_DEMO!=='YES'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const parsed=z.object({
      email:z.email().max(254).refine(v=>v.endsWith('@example.invalid')),
      syntheticIdentifier:z.string().regex(silDemoIdentifier).optional(),
      givenNames:z.string().trim().min(2).max(100),
      familyNames:z.string().trim().min(2).max(100),
      birthDate:z.iso.date().refine(v=>v>='1900-01-01' &&
        v<=new Date().toISOString().slice(0,10)),
      sexForReference:z.enum(['female','male','not_specified']),
      contactPhoneDemo:z.string().trim().min(6).max(20).optional(),
      syntheticConfirmed:z.literal(true),
    }).strict().safeParse(req.body);
    if(!parsed.success){
      res.status(400).json({error:{code:'INVALID_PATIENT_PROFILE'}});return;
    }
    const {syntheticConfirmed,email,...profile}=parsed.data;
    res.json(await service.savePatientProfileDemo(email.toLowerCase(),profile));
  });
  router.get('/patients',async(req,res)=>{
    if(res.locals.account.role!=='operador_laboratorio'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    const parsed=z.object({email:z.email().max(254)}).strict().safeParse(req.query);
    if(!parsed.success){res.status(400).json({error:{code:'INVALID_PATIENT'}});return;}
    res.json({patient:await service.findPatientByEmail(parsed.data.email.toLowerCase())});
  });
  router.get('/catalog',async(_req,res)=>{
    res.json(await service.catalog());
  });
  router.get('/summary',async(_req,res)=>{
    const summary=await service.summary();
    res.json({...summary,permissions:{reviewResults:canReview(res.locals.account)}});
  });
  router.get('/orders',async(req,res)=>{
    const data=z.object({
      limit:z.coerce.number().int().min(1).max(50).default(20),
      offset:z.coerce.number().int().min(0).max(10000).default(0),
      status:z.enum(['registered','sampled','results_recorded','review_rejected','review_approved',
        'report_attached','report_published']).optional(),
      search:z.string().trim().min(1).max(100).optional(),
    }).strict().safeParse(req.query);
    if(!data.success) {res.status(400).json({error:{code:'INVALID_PAGE'}});return;}
    res.json(await service.listOrders(
      data.data.limit,data.data.offset,data.data.status,data.data.search));
  });
  router.post('/orders',async(req,res)=>{
    const data=z.object({
      patientId:uuid,
      examCode:z.literal('hemograma').optional(),
      examCodes:z.array(z.string().regex(/^[a-z0-9_]{3,40}$/))
        .min(1).max(6).optional(),
    }).strict().refine(v=>(v.examCode!==undefined)!==(v.examCodes!==undefined))
      .refine(v=>!v.examCodes||new Set(v.examCodes).size===v.examCodes.length)
      .safeParse(req.body);
    if(!data.success) {res.status(400).json({error:{code:'INVALID_ORDER'}});return;}
    const codes=data.data.examCodes??['hemograma'];
    const order=await service.createOrder(data.data.patientId,res.locals.account.id,codes);
    res.status(201).json({order});
  });
  router.post('/orders/:id/sample',async(req,res)=>{
    const data=z.object({
      barcode:z.string().trim().regex(/^[A-Z0-9-]{3,40}$/).optional(),
      containerCode:z.enum(['edta','serum','fluoride']),
      receiptNote:z.string().trim().max(300).optional(),
    }).strict().safeParse(req.body);
    if(!uuid.safeParse(req.params.id).success||!data.success) {
      res.status(400).json({error:{code:'INVALID_SAMPLE'}});return;
    }
    const sample=await service.registerSample(req.params.id as string,
      data.data.barcode,data.data.containerCode,res.locals.account.id,
      data.data.receiptNote);
    res.status(201).json({sample});
  });
  router.post('/orders/:id/results/preview',
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success ||
       !Buffer.isBuffer(req.body)){
      res.status(400).json({error:{code:'INVALID_PDF_PREVIEW'}});return;
    }
    const preview=await service.previewResultsFile(
      req.params.id as string,req.body,res.locals.account.id);
    res.json({preview});
  });
  router.post('/orders/:id/results',async(req,res)=>{
    const data=z.object({
      results:z.array(resultSchema).min(1).max(30),
      previewToken:uuid.optional(),
    }).strict()
      .superRefine((value,ctx)=>{
        const names=value.results.map(v=>`${v.examCode}:${v.analyte.toLowerCase()}`);
        if(new Set(names).size!==names.length)
          ctx.addIssue({code:'custom',message:'Analitos duplicados.'});
      }).safeParse(req.body);
    if(!uuid.safeParse(req.params.id).success||!data.success) {
      res.status(400).json({error:{code:'INVALID_RESULTS'}});return;
    }
    const recorded=data.data.previewToken
      ? await service.recordManualResults(req.params.id as string,
        data.data.results,res.locals.account.id,data.data.previewToken)
      : await service.recordManualResults(req.params.id as string,
        data.data.results,res.locals.account.id);
    res.status(201).json({result:recorded});
  });
  router.post('/orders/:id/simulate',async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success ||
      req.body===null || typeof req.body!=='object' ||
      Array.isArray(req.body) || Object.keys(req.body).length!==0) {
      res.status(400).json({error:{code:'INVALID_SIMULATION'}});return;
    }
    const result=await service.simulateAnalyzer(req.params.id as string,
      res.locals.account.id);
    res.status(201).json({result});
  });
  router.post('/orders/:id/review',async(req,res)=>{
    const data=z.object({
      decision:z.enum(['approve','return']),
      note:z.string().trim().max(500).default(''),
    }).strict().refine(value=>value.decision!=='return'||value.note.length>=10)
      .safeParse(req.body);
    if(!uuid.safeParse(req.params.id).success||!data.success){
      res.status(400).json({error:{code:'INVALID_REVIEW'}});return;
    }
    const review=await service.reviewOrder(req.params.id as string,
      res.locals.account.id,data.data.decision,data.data.note);
    res.status(201).json({review});
  });
  router.post('/orders/:id/report',
    express.raw({type:'application/pdf',limit:'2mb'}),async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success ||
      !Buffer.isBuffer(req.body)){
      res.status(400).json({error:{code:'INVALID_REPORT'}});return;
    }
    let input:unknown;
    try{
      input={
        fileName:decodeURIComponent(req.get('x-report-filename')??''),
        branchCode:req.get('x-report-branch-code')??'',
        authorizedProfessionalName:decodeURIComponent(
          req.get('x-report-authorized-professional')??''),
        patientIdentifierFromPdf:req.get('x-report-patient-identifier')??'',
        authorizationReference:decodeURIComponent(req.get('x-report-authorization-ref')??''),
        externallyAuthorizedAt:req.get('x-report-authorized-at'),
        patientMatchConfirmed:req.get('x-report-patient-confirmed')==='true',
      };
    }catch{
      res.status(400).json({error:{code:'INVALID_REPORT'}});return;
    }
    const parsed=z.object({
      fileName:z.string().trim().min(5).max(120).regex(/[.]pdf$/i)
        .refine(name=>!name.includes('/') && !name.includes(String.fromCharCode(92)) &&
          !Array.from(name).some(ch=>ch.charCodeAt(0)<32)),
      branchCode:z.string().regex(/^[a-z0-9-]{3,50}$/),
      authorizedProfessionalName:z.string().trim().min(3).max(120),
      patientIdentifierFromPdf:z.string().regex(silDemoIdentifier),
      authorizationReference:z.string().trim().min(3).max(120),
      externallyAuthorizedAt:z.string().min(10).max(40),
      patientMatchConfirmed:z.literal(true),
    }).strict().safeParse(input);
    if(!parsed.success || req.body.length>2*1024*1024 ||
      req.get('x-report-externally-authorized')!=='true'){
      res.status(400).json({error:{code:'INVALID_REPORT'}});return;
    }
    const report=await service.attachExternalReport(
      req.params.id as string,res.locals.account.id,parsed.data,req.body);
    res.status(201).json({report});
  });
  router.post('/orders/:id/report/publish',async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success ||
      req.body===null || typeof req.body!=='object' ||
      Array.isArray(req.body) || Object.keys(req.body).length!==0){
      res.status(400).json({error:{code:'INVALID_PUBLICATION'}});return;
    }
    const published=await service.publishExternalReport(
      req.params.id as string,res.locals.account.id);
    res.status(201).json({publication:published});
  });
  router.get('/orders/:id/medical-request/file',async(req,res)=>{
    if(!['operador_laboratorio','validador_laboratorio']
      .includes(res.locals.account.role)){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    if(!uuid.safeParse(req.params.id).success){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    const file=await service.downloadMedicalRequest(
      req.params.id as string,res.locals.account.id);
    res.set('Cache-Control','private, no-store');
    res.set('X-Content-Type-Options','nosniff');
    res.set('Content-Type','application/pdf');
    res.set('Content-Disposition',"attachment; filename*=UTF-8''"+
      encodeURIComponent(file.fileName));
    res.set('Content-Length',String(file.bytes.length));
    res.send(file.bytes);
  });
  router.get('/orders/:id',async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success) {
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    res.json(await service.getOrder(req.params.id as string));
  });
  const errors:ErrorRequestHandler=(error,_req,res,next)=>{
    if(error instanceof SilEducationNotFound) {res.status(404).json({error:{code:'NOT_FOUND'}});return;}
    if(error instanceof SilEducationBusy) {res.status(429).json({error:{code:'ASSISTANT_RATE_LIMIT'}});return;}
    if(error instanceof SilEducationUnavailable) {res.status(503).json({error:{code:'ASSISTANT_UNAVAILABLE'}});return;}
    if(error instanceof SilNotFoundError) {res.status(404).json({error:{code:'NOT_FOUND'}});return;}
    if(error instanceof SilConflictError) {res.status(409).json({error:{code:'INVALID_ORDER_STATE'}});return;}
    if(error instanceof DocumentInputError) {res.status(400).json({error:{code:'INVALID_REPORT'}});return;}
    if((error as {type?:string}).type==='entity.too.large'){
      res.status(413).json({error:{code:'PAYLOAD_TOO_LARGE'}});return;
    }
    next(error);
  };
  router.use(errors);
  return router;
}
