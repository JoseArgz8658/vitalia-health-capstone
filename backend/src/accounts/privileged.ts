import {randomUUID} from 'node:crypto';
import {type Pool} from 'pg';
import {z} from 'zod';
import {DuplicateEmailError,type AccountSummary} from './repository';
import {hashPassword} from '../auth/password';

const roleSchema=z.enum(['administrador','profesional']);
const emailSchema=z.string().trim().toLowerCase().pipe(z.email().max(254));
const inputSchema=z.object({
 email:emailSchema,role:roleSchema,
 password:z.string().refine(value=>Array.from(value).length>=12&&Buffer.byteLength(value,'utf8')<=1024),
 confirmation:z.string(),
}).strict().refine(value=>value.password===value.confirmation);
export class PrivilegedInputError extends Error {
 constructor(){super('Correo, rol o contraseña inválidos. La contraseña debe tener al menos 12 caracteres y coincidir con la confirmación.');}
}
export function parsePrivilegedArguments(args:string[]){
 if(args.length!==4||args[0]!=='--role'||args[2]!=='--email')throw new PrivilegedInputError();
 const result=z.object({role:roleSchema,email:emailSchema}).safeParse({role:args[1],email:args[3]});
 if(!result.success)throw new PrivilegedInputError();
 return result.data;
}
// Herramienta interna del operador de DB. Nunca conectar al registro público.
export async function createPrivilegedAccount(db:Pick<Pool,'query'>,input:unknown):Promise<AccountSummary>{
 const result=inputSchema.safeParse(input);
 if(!result.success)throw new PrivilegedInputError();
 const {email,role,password}=result.data;
 const passwordHash=await hashPassword(password);
 try{
  const saved=await db.query<{id:string;email:string;role_code:'administrador'|'profesional';created_at:Date}>(
   `INSERT INTO public.vitalia_accounts (id,email,password_hash,role_code)
    VALUES ($1,$2,$3,$4) RETURNING id,email,role_code,created_at`,
   [randomUUID(),email,passwordHash,role]);
  if(saved.rows.length!==1)throw new Error('Cuenta no guardada.');
  const row=saved.rows[0];
  return {id:row.id,email:row.email,role:row.role_code,createdAt:row.created_at};
 }catch(error){
  const detail=error as {code?:string;constraint?:string};
  if(detail.code==='23505'&&detail.constraint==='vitalia_accounts_email_key')throw new DuplicateEmailError();
  throw error;
 }
}
