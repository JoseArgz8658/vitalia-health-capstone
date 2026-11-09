import {Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {createLoginAttemptLimiter} from '../auth/login-limit';
import {
  PortalDemoConflict,PortalDemoNotFound,PortalDemoInvalidCode,
  type SilPortalActivationDemo,
} from './portal-activation-demo';

const uuid=z.uuid();
const email=z.email().max(254).refine(value=>value.endsWith('@example.invalid'));
const code=z.string().regex(/^[A-Za-z0-9_-]{24}$/);
const newPatient=z.object({
  email, givenNames:z.string().trim().min(2).max(100),
  familyNames:z.string().trim().min(2).max(100),
  birthDate:z.iso.date().refine(v=>v>='1900-01-01'&&
    v<=new Date().toISOString().slice(0,10)),
  sexForReference:z.enum(['female','male','not_specified']),
  contactPhoneDemo:z.string().trim().min(6).max(20).optional(),
  syntheticConfirmed:z.literal(true),
}).strict();

export function createSilPortalRouterDemo(
  auth:Pick<AuthServices,'find'>,portal:SilPortalActivationDemo,
) {
  const router=Router();
  const allowActivate=createLoginAttemptLimiter();
  const allowMailbox=createLoginAttemptLimiter();
  router.use('/portal',(_req,res,next)=>{
    res.set('Cache-Control','no-store');
    res.set('X-Content-Type-Options','nosniff');
    if(process.env.VITALIA_SIL_DEMO!=='YES'){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    next();
  });

  // Buzón simulado SOLO en DEMO local, nunca contiene datos clínicos.
  // En producción hay que sustituirlo por un servicio de correo verificado.
  router.get('/portal/demo-mailbox',async(req,res)=>{
    if(process.env.VITALIA_SIL_DEV_MAILBOX!=='YES'){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    if(!allowMailbox(req.ip??req.socket.remoteAddress??'local')){
      res.status(429).json({error:{code:'RATE_LIMITED'}});return;
    }
    const parsed=z.object({email}).strict().safeParse(req.query);
    if(!parsed.success){res.status(400).json({error:{code:'INVALID_EMAIL'}});return;}
    res.json(portal.demoMailbox(parsed.data.email));
  });

  router.post('/portal/activate',async(req,res)=>{
    if(!allowActivate(req.ip??req.socket.remoteAddress??'local')){
      res.status(429).json({error:{code:'RATE_LIMITED'}});return;
    }
    const parsed=z.object({
      email,emailCode:code,handoffCode:code,
      password:z.string().min(12).refine(v=>Buffer.byteLength(v,'utf8')<=1024),
      confirmedDetails:z.literal(true),
    }).strict().safeParse(req.body);
    if(!parsed.success){
      res.status(400).json({error:{code:'INVALID_ACTIVATION'}});return;
    }
    res.json(await portal.activate(parsed.data));
  });

  // El resto requiere sesión de operador; un paciente o administrador
  // no puede consultar destinatarios ni crear invitaciones.
  router.use('/portal',async(req,res,next)=>{
    const parts=req.get('Authorization')?.split(' ');
    const token=parts?.length===2&&parts[0].toLowerCase()==='bearer'&&
      isSessionToken(parts[1])?parts[1]:null;
    const account=token?await auth.find(token):null;
    if(!account){res.status(401).json({error:{code:'UNAUTHORIZED'}});return;}
    if(account.role!=='operador_laboratorio'){
      res.status(403).json({error:{code:'FORBIDDEN'}});return;
    }
    res.locals.operator=account;
    next();
  });

  router.post('/portal/patients',async(req,res)=>{
    const parsed=newPatient.safeParse(req.body);
    if(!parsed.success){res.status(400).json({error:{code:'INVALID_PATIENT'}});return;}
    const {syntheticConfirmed,...input}=parsed.data;
    const result=await portal.provision(input,res.locals.operator.id);
    res.status(201).json(result);
  });
  router.get('/portal/patients/:id',async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    res.json(await portal.status(req.params.id as string,res.locals.operator.id));
  });
  router.post('/portal/patients/:id/invitations',async(req,res)=>{
    if(!uuid.safeParse(req.params.id).success){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    const parsed=z.object({
      contactConfirmed:z.literal(true),
      identityChecked:z.literal(true),
    }).strict().safeParse(req.body);
    if(!parsed.success){
      res.status(400).json({error:{code:'INVALID_CONFIRMATION'}});return;
    }
    const response=await portal.invite(req.params.id as string,
      res.locals.operator.id,parsed.data);
    res.status(201).json(response);
  });
  const errors:ErrorRequestHandler=(error,_req,res,next)=>{
    if(error instanceof PortalDemoInvalidCode){
      res.status(422).json({error:{code:'INVALID_ACTIVATION',message:
        'Los códigos no coinciden, vencieron o ya fueron utilizados.'}});return;
    }
    if(error instanceof PortalDemoConflict){
      res.status(409).json({error:{code:'PORTAL_CONFLICT',
        message:'La operación no está disponible. Revisa la ficha y el estado de acceso.'}});return;
    }
    if(error instanceof PortalDemoNotFound){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    next(error);
  };
  router.use(errors);
  return router;
}
