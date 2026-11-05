import {Router,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {CredentialVerificationError,type CredentialVerificationServices} from './service';
export function createCredentialVerificationRouter(auth:Pick<AuthServices,'find'>,service:CredentialVerificationServices){
 const r=Router();r.use(async(req,res,next)=>{res.set('Cache-Control','no-store');if(Object.keys(req.query).length)throw new CredentialVerificationError(400,'INVALID_CREDENTIAL_VERIFICATION');const p=req.get('Authorization')?.split(' ');const token=p?.length===2&&p[0].toLowerCase()==='bearer'&&isSessionToken(p[1])?p[1]:null;const a=token?await auth.find(token):null;if(!a)throw new CredentialVerificationError(401,'UNAUTHORIZED');if(!['administrador','profesional'].includes(a.role))throw new CredentialVerificationError(403,'FORBIDDEN');res.locals.account=a;next();});
 r.get('/:clinic/:member',async(req,res)=>{res.json(await service.details(res.locals.account,req.params.clinic as string,req.params.member as string));});
 r.post('/:clinic/:member/requests',async(req,res)=>{res.json(await service.request(res.locals.account,req.params.clinic as string,req.params.member as string,req.body));});
 r.post('/:clinic/:member/requests/:request/decision',async(req,res)=>{if(res.locals.account.role!=='administrador')throw new CredentialVerificationError(403,'FORBIDDEN');res.json(await service.decide(res.locals.account,req.params.clinic as string,req.params.member as string,req.params.request as string,req.body));});
 const errors:ErrorRequestHandler=(e,_req,res,next)=>{if(e instanceof CredentialVerificationError){res.status(e.status).json({error:{code:e.code,message:'No se pudo completar la verificación profesional.'}});return;}next(e);};r.use(errors);return r;
}
