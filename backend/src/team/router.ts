import {Router,type ErrorRequestHandler} from 'express';
import {z} from 'zod';
import {type AuthServices} from '../auth/router';
import {isSessionToken} from '../auth/sessions';
import {TeamError,type TeamServices} from './service';
export function createTeamRouter(auth:Pick<AuthServices,'find'>,service:TeamServices){
 const r=Router();r.use(async(req,res,next)=>{res.set('Cache-Control','no-store');const p=req.get('Authorization')?.split(' ');const token=p?.length===2&&p[0].toLowerCase()==='bearer'&&isSessionToken(p[1])?p[1]:null;const a=token?await auth.find(token):null;if(!a)throw new TeamError(401,'UNAUTHORIZED');if(!['administrador','profesional'].includes(a.role))throw new TeamError(403,'FORBIDDEN');res.locals.account=a;next();});
 const page=z.object({limit:z.coerce.number().int().min(1).max(20).default(20),offset:z.coerce.number().int().min(0).max(10000).default(0)}).strict();
 r.get('/:clinic',async(req,res)=>{const p=page.safeParse(req.query);if(!p.success)throw new TeamError(400,'INVALID_TEAM');res.json(await service.list(res.locals.account,req.params.clinic as string,p.data.limit,p.data.offset));});
 r.get('/:clinic/:membership/history',async(req,res)=>{const p=page.safeParse(req.query);if(!p.success)throw new TeamError(400,'INVALID_TEAM');res.json({items:await service.history(res.locals.account,req.params.clinic as string,req.params.membership as string,p.data.limit,p.data.offset)});});
 r.post('/:clinic/:membership',async(req,res)=>{if(res.locals.account.role!=='profesional')throw new TeamError(403,'FORBIDDEN');if(Object.keys(req.query).length)throw new TeamError(400,'INVALID_TEAM');res.json(await service.update(res.locals.account,req.params.clinic as string,req.params.membership as string,req.body));});
 const errors:ErrorRequestHandler=(e,_req,res,next)=>{if(e instanceof TeamError){res.status(e.status).json({error:{code:e.code,message:'No se pudo completar la gestión del equipo.'}});return;}next(e);};r.use(errors);return r;
}
