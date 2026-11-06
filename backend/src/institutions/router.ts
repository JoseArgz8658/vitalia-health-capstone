import {Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {InstitutionError,type InstitutionServices} from './service';
export function createInstitutionRouter(auth:Pick<AuthServices,'find'>,service:InstitutionServices){
 const r=Router();r.use(async(req,res,next)=>{
  res.set('Cache-Control','no-store');const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account)throw new InstitutionError(401,'UNAUTHORIZED');if(account.role!=='administrador')throw new InstitutionError(403,'FORBIDDEN');
  res.locals.account=account;next();
 });
 const page=z.object({limit:z.coerce.number().int().min(1).max(20).default(20),offset:z.coerce.number().int().min(0).max(10000).default(0)}).strict();
 r.get('/territories',async(req,res)=>{if(Object.keys(req.query).length)throw new InstitutionError(400,'INVALID_INSTITUTION');res.json(await service.territories(res.locals.account));});
 r.get('/',async(req,res)=>{const p=page.safeParse(req.query);if(!p.success)throw new InstitutionError(400,'INVALID_INSTITUTION');res.json({items:await service.list(res.locals.account,p.data.limit,p.data.offset)});});
 r.get('/:id/branches',async(req,res)=>{const p=page.safeParse(req.query);if(!p.success)throw new InstitutionError(400,'INVALID_INSTITUTION');res.json({items:await service.branches(res.locals.account,req.params.id as string,p.data.limit,p.data.offset)});});
 r.post('/',async(req,res)=>{if(Object.keys(req.query).length)throw new InstitutionError(400,'INVALID_INSTITUTION');const v=await service.create(res.locals.account,req.body);res.status(v.created?201:200).json({item:v.item});});
 r.post('/:id/branches',async(req,res)=>{if(Object.keys(req.query).length)throw new InstitutionError(400,'INVALID_INSTITUTION');const v=await service.createBranch(res.locals.account,req.params.id as string,req.body);res.status(v.created?201:200).json({item:v.item});});
 const errors:ErrorRequestHandler=(e,_req,res,next)=>{if(e instanceof InstitutionError){res.status(e.status).json({error:{code:e.code,message:'No se pudo completar la gestión institucional.'}});return;}next(e);};r.use(errors);return r;
}
