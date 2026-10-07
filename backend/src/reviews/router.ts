import {Router,type ErrorRequestHandler,type RequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {type ReviewServices,ReviewForbiddenError,ReviewNotFoundError,ReviewInputError,ReviewConflictError} from './service';
export function createReviewRouter(auth:Pick<AuthServices,'find'>,services:ReviewServices){
 const router=Router();
 const guard:RequestHandler=async(req,res,next)=>{
  res.set('Cache-Control','no-store');
  const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account){res.status(401).json({error:{code:'UNAUTHORIZED',message:'Sesión no válida.'}});return;}
  if(account.role!=='profesional')throw new ReviewForbiddenError();
  res.locals.account=account;next();
 };
 router.get('/patients/:patientId/documents/:id/review',guard,async(req,res)=>{
  if(Object.keys(req.query).length)throw new ReviewInputError();
  res.json(await services.get(res.locals.account,req.params.patientId as string,req.params.id as string));
 });
 router.post('/patients/:patientId/documents/:id/review',guard,async(req,res)=>{
  if(Object.keys(req.query).length)throw new ReviewInputError();
  res.status(201).json({review:await services.approve(res.locals.account,req.params.patientId as string,req.params.id as string,req.body)});
 });
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  const status=error instanceof ReviewForbiddenError?403:error instanceof ReviewNotFoundError?404:error instanceof ReviewInputError?400:error instanceof ReviewConflictError?409:null;
  if(status){res.status(status).json({error:{code:status===403?'FORBIDDEN':status===404?'NOT_FOUND':status===409?'REVIEW_CONFLICT':'INVALID_REVIEW',message:status===409?'Ya existe una revisión o cambió el procesamiento. Actualiza la consulta.':status===400?'Revisa fechas, resultados, observaciones y confirmación del original.':status===404?'Paciente o documento no disponible.':'Acceso no autorizado.'}});return;}
  next(error);
 };
 router.use(errors);return router;
}
