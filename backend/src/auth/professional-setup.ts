import {createHash,randomBytes} from 'node:crypto';
import {type AccountSummary} from '../accounts/repository';
// Capacidad efímera: nunca se persiste ni se acepta como sesión clínica.
export function createProfessionalSetupStore(now:()=>number=Date.now){
 const entries=new Map<string,{account:AccountSummary,expiresAt:number,attempts:number}>();
 const digest=(s:string)=>createHash('sha256').update(s).digest('hex');
 function clean(){for(const [key,value] of entries)if(value.expiresAt<=now())entries.delete(key);}
 return {
  issue(account:AccountSummary){clean();if(entries.size>=100)return null;
   const token=randomBytes(32).toString('hex'),expiresAt=now()+5*60*1000;
   entries.set(digest(token),{account:{...account,role:'paciente'},expiresAt,attempts:5});
   return {token,expiresAt:new Date(expiresAt)};
  },
  attempt(token:string){clean();if(!/^[a-f0-9]{64}$/.test(token))return null;
   const key=digest(token),value=entries.get(key);if(!value)return null;
   value.attempts--;if(value.attempts===0)entries.delete(key);
   return {...value.account};
  },
  consume(token:string){entries.delete(digest(token));},
 };
}
export const professionalSetupStore=createProfessionalSetupStore();
