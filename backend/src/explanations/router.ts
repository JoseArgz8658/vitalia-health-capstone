import {Router,type RequestHandler,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {z} from 'zod';
import {type ExplanationServices,ExplanationForbiddenError,ExplanationNotFoundError,ExplanationPendingReviewError,
 ExplanationBusyError,ExplanationInputError,ExplanationUnavailableError} from './service';
export function createExplanationRouter(auth:Pick<AuthServices,'find'>,service:ExplanationServices){
 const router=Router();
 const guard:RequestHandler=async(req,res,next)=>{
  res.set('Cache-Control','no-store');const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account){res.status(401).json({error:{code:'UNAUTHORIZED',message:'Sesión no válida.'}});return;}
  if(account.role!=='paciente')throw new ExplanationForbiddenError();
  if(Object.keys(req.query).length)throw new ExplanationInputError();
  res.locals.account=account;next();
 };
 router.get('/:id/explanation',guard,async(req,res)=>res.json(await service.get(res.locals.account,req.params.id as string)));
 router.post('/:id/explanation',guard,async(req,res)=>{
  if(!z.object({}).strict().safeParse(req.body??{}).success)throw new ExplanationInputError();
  const result=await service.request(res.locals.account,req.params.id as string);
  res.status(result.status==='generating'?202:200).json(result);
 });
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  const status=error instanceof ExplanationForbiddenError?403:error instanceof ExplanationNotFoundError?404:
   error instanceof ExplanationPendingReviewError?409:error instanceof ExplanationInputError?400:
   error instanceof ExplanationBusyError||error instanceof ExplanationUnavailableError?503:null;
  if(status){res.status(status).json({error:{code:'EXPLANATION_UNAVAILABLE',message:status===409?'Se requiere una revisión profesional aprobada.':
   status===400?'Solicitud inválida o examen fuera de los límites de esta versión.':status===503?'No se pudo generar la explicación ahora. Actualiza el estado antes de repetir.':'Documento no disponible para esta cuenta.'}});return;}
  next(error);
 };
 router.use(errors);return router;
}
