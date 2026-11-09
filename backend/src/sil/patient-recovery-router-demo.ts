import {Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {createLoginAttemptLimiter} from '../auth/login-limit';
import {isSessionToken} from '../auth/sessions';
import {SilRecoveryBusy,SilRecoveryRejected,type SilPatientRecoveryDemo} from './patient-recovery-demo';

export function createSilPatientRecoveryRouterDemo(
  auth:Pick<AuthServices,'find'>,recovery:SilPatientRecoveryDemo,
){
  const router=Router();
  const allowGenerate=createLoginAttemptLimiter();
  const allowRecover=createLoginAttemptLimiter();
  router.use((_req,res,next)=>{
    res.set('Cache-Control','no-store');
    if(process.env.VITALIA_SIL_DEMO!=='YES'){
      res.status(404).json({error:{code:'NOT_FOUND'}});return;
    }
    next();
  });
  router.post('/key',async(req,res)=>{
    const bearer=/^Bearer ([a-f0-9]{64})$/i.exec(req.get('Authorization')??'');
    const token=bearer?.[1]??'';
    const account=isSessionToken(token)?await auth.find(token):null;
    if(!account){res.status(401).json({error:{code:'UNAUTHORIZED'}});return;}
    if(account.role!=='paciente'){res.status(403).json({error:{code:'FORBIDDEN'}});return;}
    if(!allowGenerate(account.id)){res.status(429).json({error:{code:'RATE_LIMITED'}});return;}
    const data=z.object({
      currentPassword:z.string().min(1).refine(value=>Buffer.byteLength(value,'utf8')<=1024),
    }).strict().safeParse(req.body);
    if(!data.success){res.status(400).json({error:{code:'INVALID_RECOVERY'}});return;}
    res.status(201).json(await recovery.generate(account,data.data.currentPassword));
  });
  router.post('/complete',async(req,res)=>{
    if(!allowRecover(req.ip??req.socket.remoteAddress??'local')){
      res.status(429).json({error:{code:'RATE_LIMITED'}});return;
    }
    const data=z.object({
      email:z.string().trim().toLowerCase().pipe(z.email().max(254))
        .refine(value=>value.endsWith('@example.invalid')),
      recoveryKey:z.string().regex(/^[A-Za-z0-9_-]{43}$/),
      password:z.string().refine(value=>[...value].length>=12 && Buffer.byteLength(value,'utf8')<=1024),
    }).strict().safeParse(req.body);
    if(!data.success){res.status(400).json({error:{code:'INVALID_RECOVERY'}});return;}
    await recovery.recover(data.data.email,data.data.recoveryKey,data.data.password);
    res.status(204).end();
  });
  const errors:ErrorRequestHandler=(error,_req,res,next)=>{
    if(error instanceof SilRecoveryRejected){
      res.status(422).json({error:{code:'RECOVERY_REJECTED'}});return;
    }
    if(error instanceof SilRecoveryBusy){
      res.set('Retry-After','1').status(503).json({error:{code:'RECOVERY_BUSY'}});return;
    }
    next(error);
  };
  router.use(errors);
  return router;
}
