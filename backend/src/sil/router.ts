import {Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {SilConflictError,SilNotFoundError,type SilServices} from './service';

const uuid = z.uuid();
const resultSchema = z.object({
  analyte:z.string().trim().min(1).max(100),
  numericValue:z.number().finite().min(-1000000000).max(1000000000),
  unit:z.string().trim().min(1).max(30),
  referenceMin:z.number().finite().nullable().optional(),
  referenceMax:z.number().finite().nullable().optional(),
}).strict().refine(v=>v.referenceMin==null||v.referenceMax==null||
  v.referenceMin<=v.referenceMax);
export function createSilRouter(auth:Pick<AuthServices,'find'>,service:SilServices) {
  const router=Router();
  router.use(async(req,res,next)=>{
    res.set('Cache-Control','no-store');
    const parts=req.get('Authorization')?.split(' ');
    const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&
      isSessionToken(parts[1])?parts[1]:null;
    const account=token?await auth.find(token):null;
    if(!account) {res.status(401).json({error:{code:'UNAUTHORIZED'}});return;}
    // MVP con un único laboratorio ficticio; sin delegación entre instituciones.
    if(account.role!=='administrador') {
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    res.locals.account=account;
    next();
  });
  router.post('/orders',async(req,res)=>{
    const data=z.object({patientId:uuid,examCode:z.literal('hemograma')}).strict().safeParse(req.body);
    if(!data.success) {res.status(400).json({error:{code:'INVALID_ORDER'}});return;}
    const order=await service.createOrder(data.data.patientId,res.locals.account.id);
    res.status(201).json({order});
  });
  router.post('/orders/:id/sample',async(req,res)=>{
    const data=z.object({barcode:z.string().trim().regex(/^[A-Z0-9-]{3,40}$/)}).strict().safeParse(req.body);
    if(!uuid.safeParse(req.params.id).success||!data.success) {
      res.status(400).json({error:{code:'INVALID_SAMPLE'}});return;
    }
    const sample=await service.registerSample(req.params.id as string,data.data.barcode);
    res.status(201).json({sample});
  });
  router.post('/orders/:id/results',async(req,res)=>{
    const data=z.object({results:z.array(resultSchema).min(1).max(30)}).strict()
      .superRefine((value,ctx)=>{
        const names=value.results.map(v=>v.analyte.toLowerCase());
        if(new Set(names).size!==names.length)
          ctx.addIssue({code:'custom',message:'Analitos duplicados.'});
      }).safeParse(req.body);
    if(!uuid.safeParse(req.params.id).success||!data.success) {
      res.status(400).json({error:{code:'INVALID_RESULTS'}});return;
    }
    const recorded=await service.recordResults(req.params.id as string,data.data.results);
    res.status(201).json({result:recorded});
  });
  router.post('/orders/:id/simulate',async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success ||
      req.body===null || typeof req.body!=='object' ||
      Array.isArray(req.body) || Object.keys(req.body).length!==0) {
      res.status(400).json({error:{code:'INVALID_SIMULATION'}});return;
    }
    const result=await service.simulateAnalyzer(req.params.id as string);
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
