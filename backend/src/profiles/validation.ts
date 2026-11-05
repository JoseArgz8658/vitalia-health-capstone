import {z} from 'zod';

// Valida el dígito, no la existencia del RUT ni la identidad de su titular.
export function normalizeRut(input:string):string|null{
 const value=input.trim().toUpperCase();
 if(!/^(?:[1-9]\d{0,7}|[1-9]\d{0,1}(?:\.\d{3}){1,2})-?[0-9K]$/.test(value))return null;
 const compact=value.replace(/[.\-]/g,'');const body=compact.slice(0,-1),dv=compact.slice(-1);
 let sum=0,multiplier=2;
 for(const digit of [...body].reverse()){sum+=Number(digit)*multiplier;multiplier=multiplier===7?2:multiplier+1;}
 const result=11-sum%11,expected=result===11?'0':result===10?'K':String(result);
 return dv===expected?`${body}-${dv}`:null;
}
const required=z.string().trim().min(1).max(150);
const optional=z.string().trim().min(1).max(150).nullable();
const birthDate=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value=>{
 const date=new Date(value+'T00:00:00Z');
 return !Number.isNaN(date.getTime())&&date.getUTCFullYear()>0&&date.toISOString().slice(0,10)===value&&value<=new Date().toISOString().slice(0,10);
}).nullable();
export const profileInput=z.object({
 revision:z.string().max(100).nullable(),firstName:required,additionalNames:optional,
 firstSurname:required,secondSurname:optional,birthDate,
 phone:z.string().trim().min(1).max(40).nullable(),
 rut:z.string().max(20).transform(value=>normalizeRut(value)).refine(value=>value!==null).nullable(),
 preferredCommuneCode:z.string().regex(/^\d{5}$/).nullable(),
}).strict();
