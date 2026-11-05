import {professionalSetupStore} from '../auth/professional-setup';
import {Router,type ErrorRequestHandler} from 'express';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {OnboardingError,type OnboardingServices} from './service';
export function createOnboardingRouter(auth:Pick<AuthServices,'find'>,service:OnboardingServices){
 const r=Router();r.use((req,res,next)=>{res.set('Cache-Control','no-store');if(Object.keys(req.query).length)throw new OnboardingError(400,'INVALID_ONBOARDING');next();});
 r.post('/professional-password/setup',async(req,res)=>{
  const header=req.get('Authorization')?.split(' ');
  const token=header?.length===2&&header[0]==='ProfessionalSetup'?header[1]:'';
  const a=professionalSetupStore.attempt(token);if(!a)throw new OnboardingError(401,'SETUP_EXPIRED');
  if(req.body?.confirmed!==true)throw new OnboardingError(400,'INVALID_ONBOARDING');
  const {confirmed,...body}=req.body;
  const result=await service.configureProfessionalPassword(a,body);
  professionalSetupStore.consume(token);res.json(result);
 });
 r.post('/activate',async(req,res)=>{res.json(await service.activate(req.body));});
 r.use(async(req,res,next)=>{const p=req.get('Authorization')?.split(' ');const token=p?.length===2&&p[0].toLowerCase()==='bearer'&&isSessionToken(p[1])?p[1]:null;const a=token?await auth.find(token):null;if(!a)throw new OnboardingError(401,'UNAUTHORIZED');if(!['administrador','profesional'].includes(a.role)&&!(['/accept','/professional-password'].includes(req.path)&&req.method==='POST'&&a.role==='paciente'))throw new OnboardingError(403,'FORBIDDEN');res.locals.account=a;next();});
 r.post('/professional-password/change',async(req,res)=>{res.json(await service.changeProfessionalPassword(res.locals.account,req.body));});
 r.post('/professional-password',async(req,res)=>{res.json(await service.configureProfessionalPassword(res.locals.account,req.body));});
 r.post('/accept',async(req,res)=>{res.json(await service.accept(res.locals.account,req.body));});
 r.get('/context',async(_req,res)=>{res.json(await service.context(res.locals.account));});
 r.get('/:clinic',async(req,res)=>{res.json(await service.details(res.locals.account,req.params.clinic as string));});
 r.post('/:clinic/authorizations',async(req,res)=>{res.status(201).json({item:await service.record(res.locals.account,req.params.clinic as string,req.body)});});
 r.post('/:clinic/authorizations/:id/verify',async(req,res)=>{res.json({item:await service.verify(res.locals.account,req.params.clinic as string,req.params.id as string,req.body)});});
 r.post('/:clinic/authorizations/:id/revoke',async(req,res)=>{if(Object.keys(req.body??{}).length)throw new OnboardingError(400,'INVALID_ONBOARDING');await service.revokeAuthorization(res.locals.account,req.params.clinic as string,req.params.id as string);res.json({revoked:true});});
 r.post('/:clinic/specialties',async(req,res)=>{res.status(201).json({item:await service.addSpecialty(res.locals.account,req.params.clinic as string,req.body)});});
 r.post('/:clinic/invitations',async(req,res)=>{res.status(201).json(await service.invite(res.locals.account,req.params.clinic as string,req.body));});
 r.post('/:clinic/invitations/:id/revoke',async(req,res)=>{if(Object.keys(req.body??{}).length)throw new OnboardingError(400,'INVALID_ONBOARDING');await service.revoke(res.locals.account,req.params.clinic as string,req.params.id as string);res.json({revoked:true});});
 const errors:ErrorRequestHandler=(e,_req,res,next)=>{if(e instanceof OnboardingError){res.status(e.status).json({error:{code:e.code,message:'No se pudo completar la incorporación institucional.'}});return;}next(e);};r.use(errors);return r;
}
