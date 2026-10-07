import {Router,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {type ReviewServices,ReviewForbiddenError,ReviewNotFoundError} from './service';
export function createPatientReviewRouter(auth:Pick<AuthServices,'find'>,services:ReviewServices){
 const router=Router();
 router.get('/:id/review',async(req,res)=>{
  res.set('Cache-Control','no-store');
  const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account){res.status(401).json({error:{code:'UNAUTHORIZED',message:'Sesión no válida.'}});return;}
  if(account.role!=='paciente')throw new ReviewForbiddenError();
  if(Object.keys(req.query).length){res.status(400).json({error:{code:'INVALID_REQUEST',message:'Solicitud inválida.'}});return;}
  res.json(await services.getPatient(account,req.params.id as string));
 });
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  if(error instanceof ReviewForbiddenError||error instanceof ReviewNotFoundError){
   res.status(error instanceof ReviewForbiddenError?403:404).json({error:{code:error instanceof ReviewForbiddenError?'FORBIDDEN':'NOT_FOUND',message:'Documento no disponible para esta cuenta.'}});return;
  }next(error);
 };
 router.use(errors);return router;
}
