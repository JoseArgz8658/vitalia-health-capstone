import {Router,type ErrorRequestHandler,type RequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {ProfileError,type ProfileServices} from './service';
export function createProfileRouter(auth:Pick<AuthServices,'find'>,service:ProfileServices){
 const router=Router();
 const guard:RequestHandler=async(req,res,next)=>{
  res.set('Cache-Control','no-store');const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account)throw new ProfileError(401,'UNAUTHORIZED');
  if(Object.keys(req.query).length)throw new ProfileError(400,'INVALID_PROFILE');
  res.locals.account=account;next();
 };
 router.get('/territories',guard,async(_req,res)=>{res.json(await service.territories(res.locals.account));});
 router.get('/',guard,async(_req,res)=>{res.json(await service.get(res.locals.account));});
 router.post('/',guard,async(req,res)=>{res.json(await service.save(res.locals.account,req.body));});
 router.get('/measurements',guard,async(_req,res)=>{res.json(await service.measurements(res.locals.account));});
 router.post('/measurements',guard,async(req,res)=>{res.json(await service.recordMeasurement(res.locals.account,req.body));});
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  if(error instanceof ProfileError){res.status(error.status).json({error:{code:error.code,message:'No se pudo consultar o guardar el perfil.'}});return;}
  next(error);
 };router.use(errors);return router;
}
