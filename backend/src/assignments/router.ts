import {Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {type AssignmentServices,AssignmentInputError,AssignmentForbiddenError,AssignmentNotFoundError} from './service';
export function createAssignmentRouter(auth:Pick<AuthServices,'find'>,services:AssignmentServices){
 const router=Router();
 router.use(async(req,res,next)=>{
  res.set('Cache-Control','no-store');
  const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account){res.status(401).json({error:{code:'UNAUTHORIZED',message:'Sesión no válida.'}});return;}
  if(!['administrador','profesional'].includes(account.role))throw new AssignmentForbiddenError();
  res.locals.account=account;next();
 });
 router.get('/',async(req,res)=>{
  const parsed=z.object({limit:z.coerce.number().int().min(1).max(20).default(20),offset:z.coerce.number().int().min(0).max(10000).default(0)}).strict().safeParse(req.query);
  if(!parsed.success)throw new AssignmentInputError();
  const {limit,offset}=parsed.data,account=res.locals.account;
  if(account.role==='administrador')res.json({assignments:await services.listAdmin(account,limit,offset)});
  else res.json({patients:await services.listProfessional(account,limit,offset)});
 });
 router.post('/',async(req,res)=>{
  if(Object.keys(req.query).length)throw new AssignmentInputError();
  const result=await services.assign(res.locals.account,req.body);
  res.status(result.changed?201:200).json({assignment:result.assignment});
 });
 router.post('/:id/deactivate',async(req,res)=>{
  if(Object.keys(req.query).length||!z.object({}).strict().safeParse(req.body??{}).success)throw new AssignmentInputError();
  const result=await services.deactivate(res.locals.account,req.params.id as string);
  res.json({assignment:result.assignment});
 });
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  const status=error instanceof AssignmentForbiddenError?403:error instanceof AssignmentInputError?400:error instanceof AssignmentNotFoundError?404:null;
  if(status){res.status(status).json({error:{code:status===403?'FORBIDDEN':status===400?'INVALID_INPUT':'NOT_FOUND',message:status===403?'Acceso no autorizado.':status===400?'Revisa los correos y la solicitud.':'Cuenta o asignación no disponible.'}});return;}
  next(error);
 };
 router.use(errors);return router;
}
