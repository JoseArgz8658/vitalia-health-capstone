import {Router,type RequestHandler,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {AssistantAccessError,type ExamAssistantServices} from './service';
export function createExamAssistantRouter(auth:Pick<AuthServices,'find'>,service:ExamAssistantServices){
 const router=Router();const guard:RequestHandler=async(req,res,next)=>{
  res.set('Cache-Control','no-store');const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;if(!account)throw new AssistantAccessError(401);
  if(account.role!=='paciente')throw new AssistantAccessError(403);if(Object.keys(req.query).length)throw new AssistantAccessError(400);
  res.locals.account=account;next();
 };
 router.get('/:id/assistant',guard,async(req,res)=>res.json(await service.get(res.locals.account,req.params.id as string)));
 router.post('/:id/assistant',guard,async(req,res)=>res.json(await service.request(res.locals.account,req.params.id as string,req.body)));
 router.get('/:id/assistant/explanation',guard,async(req,res)=>res.json(await service.getExplanation(res.locals.account,req.params.id as string)));
 router.post('/:id/assistant/explanation',guard,async(req,res)=>res.json(await service.explain(res.locals.account,req.params.id as string,req.body)));
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  if(error instanceof AssistantAccessError){res.status(error.status).json({error:{code:'ASSISTANT_UNAVAILABLE',message:
   error.status===401?'Sesión no válida.':error.status===409?'Se requiere revisión aprobada, no reutilices una solicitud para otra pregunta y comprueba el límite de conversación.':
   error.status===503?'Asistente ocupado o respuesta no aceptada. Actualiza la conversación antes de repetir.':'Solicitud o documento no disponible para esta cuenta.'}});return;}next(error);
 };router.use(errors);return router;
}
