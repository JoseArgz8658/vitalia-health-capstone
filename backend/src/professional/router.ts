import {Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {ProfessionalForbiddenError,ProfessionalNotFoundError,ProfessionalInputError,type ProfessionalServices} from './service';
export function createProfessionalRouter(auth:Pick<AuthServices,'find'>,services:ProfessionalServices){
 const router=Router();
 router.use(async(req,res,next)=>{
  res.set('Cache-Control','no-store');
  const parts=req.get('Authorization')?.split(' ');
  const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&isSessionToken(parts[1])?parts[1]:null;
  const account=token?await auth.find(token):null;
  if(!account){res.status(401).json({error:{code:'UNAUTHORIZED',message:'Sesión no válida.'}});return;}
  if(account.role!=='profesional')throw new ProfessionalForbiddenError();
  res.locals.account=account;next();
 });
 router.get('/patients/:patientId/documents',async(req,res)=>{
  const parsed=z.object({limit:z.coerce.number().int().min(1).max(20).default(20),offset:z.coerce.number().int().min(0).max(10000).default(0)}).strict().safeParse(req.query);
  if(!parsed.success)throw new ProfessionalInputError();
  res.json({documents:await services.list(res.locals.account,req.params.patientId as string,parsed.data.limit,parsed.data.offset)});
 });
 router.get('/patients/:patientId/documents/:id/extraction',async(req,res)=>{
  if(Object.keys(req.query).length)throw new ProfessionalInputError();
  res.json(await services.extraction(res.locals.account,req.params.patientId as string,req.params.id as string));
 });
 let downloads=0;
 router.get('/patients/:patientId/documents/:id/file',async(req,res)=>{
  if(downloads>=2){res.set('Retry-After','2').status(503).json({error:{code:'DOWNLOAD_BUSY',message:'Intenta nuevamente en unos momentos.'}});return;}
  downloads++;
  try{
   if(Object.keys(req.query).length)throw new ProfessionalInputError();
   const {item,body}=await services.download(res.locals.account,req.params.patientId as string,req.params.id as string);
   res.set('X-Content-Type-Options','nosniff');res.set('Content-Type',item.contentType);
   res.set('Content-Disposition',"attachment; filename*=UTF-8''"+encodeURIComponent(item.originalName));
   res.set('Content-Length',String(body.length));res.send(body);
  }finally{downloads--;}
 });
 const errors:ErrorRequestHandler=(error,_req,res,next)=>{
  const status=error instanceof ProfessionalForbiddenError?403:error instanceof ProfessionalNotFoundError?404:error instanceof ProfessionalInputError?400:null;
  if(status){res.status(status).json({error:{code:status===403?'FORBIDDEN':status===404?'NOT_FOUND':'INVALID_INPUT',message:status===403?'Acceso no autorizado.':status===404?'Paciente o documento no disponible.':'Solicitud inválida.'}});return;}
  next(error);
 };
 router.use(errors);return router;
}
