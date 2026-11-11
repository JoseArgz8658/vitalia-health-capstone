import {Router,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {CareCatalogError,type CareCatalogServices} from './catalog';

export function createCareCatalogRouter(auth:Pick<AuthServices,'find'>,service:CareCatalogServices){
 const router=Router();
 router.get('/catalog',async(req,res)=>{
  res.set('Cache-Control','no-store');
  const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account)throw new CareCatalogError(401,'UNAUTHORIZED');
  if(account.role!=='paciente')throw new CareCatalogError(403,'FORBIDDEN');
  res.json(await service.list(account,req.query));
 });
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  if(error instanceof CareCatalogError){res.status(error.status).json({error:{code:error.code,
   message:error.status===400?'Revisa la comuna y los filtros de atención.':'No se pudo consultar la atención disponible.'}});return;}
  next(error);
 };
 router.use(errors);return router;
}
