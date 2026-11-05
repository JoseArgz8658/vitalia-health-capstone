import {Router,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {CareUploadError,type CareUploadServices} from './upload';
export function createCareUploadRouter(auth:Pick<AuthServices,'find'>,service:CareUploadServices){
 const router=Router();
 router.get('/context',async(req,res)=>{
  res.set('Cache-Control','no-store');const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;if(!account)throw new CareUploadError(401,'UNAUTHORIZED');
  if(Object.keys(req.query).length)throw new CareUploadError(400,'INVALID_CARE_CONTACT');
  res.json(await service.context(account));
 });
 const errors:ErrorRequestHandler=(e,_req,res,next)=>{
  if(e instanceof CareUploadError){res.status(e.status).json({error:{code:e.code,message:'No se pudieron consultar los datos para la atención.'}});return;}next(e);
 };router.use(errors);return router;
}
