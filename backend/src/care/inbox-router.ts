import {Router,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {CareInboxError,type CareInboxServices} from './inbox';
export function createCareInboxRouter(auth:Pick<AuthServices,'find'>,service:CareInboxServices){
 const router=Router();
 router.use(async(req,res,next)=>{
  res.set('Cache-Control','no-store');const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const a=token?await auth.find(token):null;if(!a)throw new CareInboxError(401,'UNAUTHORIZED');
  if(a.role!=='profesional')throw new CareInboxError(403,'FORBIDDEN');res.locals.account=a;next();
 });
 router.get('/',async(req,res)=>{res.json(await service.list(res.locals.account,req.query));});
 router.get('/:id',async(req,res)=>{
  if(Object.keys(req.query).length)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  res.json(await service.details(res.locals.account,req.params.id as string));
 });
 router.post('/:id/begin',async(req,res)=>{
  if(Object.keys(req.query).length)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  res.json(await service.begin(res.locals.account,req.params.id as string,req.body));
 });
 router.get('/:id/review',async(req,res)=>{
  if(Object.keys(req.query).length)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  res.json(await service.review(res.locals.account,req.params.id as string));
 });
 router.post('/:id/review',async(req,res)=>{
  if(Object.keys(req.query).length)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  res.status(201).json({review:await service.approve(res.locals.account,req.params.id as string,req.body)});
 });
 router.get('/:id/referral-options',async(req,res)=>{
  res.json(await service.referralOptions(res.locals.account,req.params.id as string,req.query));
 });
 router.post('/:id/referrals',async(req,res)=>{
  if(Object.keys(req.query).length)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  res.status(201).json(await service.refer(res.locals.account,req.params.id as string,req.body));
 });
 let downloads=0;
 router.get('/:id/file',async(req,res)=>{
  if(Object.keys(req.query).length)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  if(downloads>=2){res.set('Retry-After','2');throw new CareInboxError(503,'DOWNLOAD_BUSY');}
  downloads++;
  try{
   const {item,body}=await service.download(res.locals.account,req.params.id as string);
   res.set('X-Content-Type-Options','nosniff');res.set('Content-Type',item.contentType);
   res.set('Content-Disposition',"attachment; filename*=UTF-8''"+encodeURIComponent(item.originalName));
   res.set('Content-Length',String(body.length));res.send(body);
  }finally{downloads--;}
 });
 const errors:ErrorRequestHandler=(e,_req,res,next)=>{
  if(e instanceof CareInboxError){res.status(e.status).json({error:{code:e.code,message:
   e.status===400?'Revisa fechas, resultados, observaciones y confirmación del original.':e.status===404?'Atención no disponible.':e.status===409?'La atención cambió. Actualiza antes de continuar.':'No se pudo acceder a la atención.'}});return;}next(e);
 };router.use(errors);return router;
}
