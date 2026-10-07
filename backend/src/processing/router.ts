import {Router,type RequestHandler,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {DocumentNotFoundError} from '../documents/service';
import {type ProcessingServices} from './service';

export function createProcessingRouter(auth:Pick<AuthServices,'find'>,services:ProcessingServices){
 const router=Router();
 const guard:RequestHandler=async(req,res,next)=>{
  res.set('Cache-Control','no-store');
  const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account){res.status(401).json({error:{code:'UNAUTHORIZED',message:'Sesión no válida.'}});return;}
  if(account.role!=='paciente'){res.status(403).json({error:{code:'FORBIDDEN',message:'Acceso no autorizado.'}});return;}
  if(!z.uuid().safeParse(req.params.id).success)throw new DocumentNotFoundError();
  res.locals.account=account;next();
 };
 router.get('/:id/processing',guard,async(req,res)=>{
  res.json({processing:await services.get(res.locals.account,req.params.id as string)});
 });
 router.post('/:id/processing',guard,async(req,res)=>{
  if(Object.keys(req.query).length||!z.object({}).strict().safeParse(req.body??{}).success){
   res.status(400).json({error:{code:'INVALID_REQUEST',message:'Solicitud inválida.'}});return;
  }
  const result=await services.request(res.locals.account,req.params.id as string);
  res.status(result.created?202:200).json({processing:result.processing});
 });
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  if(error instanceof DocumentNotFoundError){res.status(404).json({error:{code:'NOT_FOUND',message:'Documento no disponible.'}});return;}
  next(error);
 };
 router.use(errors);return router;
}
