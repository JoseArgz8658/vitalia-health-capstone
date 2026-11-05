import {Router,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {CareInboxError} from './inbox';
import {type CareHistoryServices} from './history';
export function createCareHistoryRouter(auth:Pick<AuthServices,'find'>,service:CareHistoryServices){
 const router=Router();
 router.get('/:id/care',async(req,res)=>{
  res.set('Cache-Control','no-store');const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const a=token?await auth.find(token):null;if(!a)throw new CareInboxError(401,'UNAUTHORIZED');
  res.json(await service.get(a,req.params.id as string,req.query));
 });
 const errors:ErrorRequestHandler=(e,_req,res,next)=>{
  if(e instanceof CareInboxError){res.status(e.status).json({error:{code:e.code,message:'Seguimiento no disponible.'}});return;}
  if(['42501','42P01','42703'].includes((e as {code?:string})?.code??'')){res.status(503).json({error:{code:'CARE_UNAVAILABLE',message:'Seguimiento temporalmente no disponible.'}});return;}next(e);
 };router.use(errors);return router;
}
