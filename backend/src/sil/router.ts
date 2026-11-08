import {Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {SilConflictError,SilNotFoundError,type SilServices} from './service';

const uuid = z.uuid();
const resultSchema = z.object({
  examCode:z.string().regex(/^[a-z0-9_]{3,40}$/),
  analyte:z.string().trim().min(1).max(100),
  numericValue:z.number().finite().min(-1000000000).max(1000000000),
}).strict();
export function createSilRouter(auth:Pick<AuthServices,'find'>,service:SilServices) {
  const router=Router();
  router.use(async(req,res,next)=>{
    res.set('Cache-Control','no-store');
    const parts=req.get('Authorization')?.split(' ');
    const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&
      isSessionToken(parts[1])?parts[1]:null;
    const account=token?await auth.find(token):null;
    if(!account) {res.status(401).json({error:{code:'UNAUTHORIZED'}});return;}
    // Un único laboratorio en este MVP, con separación real de funciones.
    if(!['administrador','operador_laboratorio','validador_laboratorio'].includes(account.role)) {
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    if(req.method!=='GET' && account.role!=='operador_laboratorio') {
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    res.locals.account=account;
    next();
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
    res.json(await service.summary());
  });
  router.get('/orders',async(req,res)=>{
    const data=z.object({
      limit:z.coerce.number().int().min(1).max(50).default(20),
      offset:z.coerce.number().int().min(0).max(10000).default(0),
      status:z.enum(['registered','sampled','results_recorded']).optional(),
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
      barcode:z.string().trim().regex(/^[A-Z0-9-]{3,40}$/),
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
  router.post('/orders/:id/results',async(req,res)=>{
    const data=z.object({results:z.array(resultSchema).min(1).max(30)}).strict()
      .superRefine((value,ctx)=>{
        const names=value.results.map(v=>`${v.examCode}:${v.analyte.toLowerCase()}`);
        if(new Set(names).size!==names.length)
          ctx.addIssue({code:'custom',message:'Analitos duplicados.'});
      }).safeParse(req.body);
    if(!uuid.safeParse(req.params.id).success||!data.success) {
      res.status(400).json({error:{code:'INVALID_RESULTS'}});return;
    }
    const recorded=await service.recordManualResults(req.params.id as string,
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
  router.get('/orders/:id',async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success) {
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    res.json(await service.getOrder(req.params.id as string));
  });
  const errors:ErrorRequestHandler=(error,_req,res,next)=>{
    if(error instanceof SilNotFoundError) {res.status(404).json({error:{code:'NOT_FOUND'}});return;}
    if(error instanceof SilConflictError) {res.status(409).json({error:{code:'INVALID_ORDER_STATE'}});return;}
    next(error);
  };
  router.use(errors);
  return router;
}
