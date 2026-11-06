import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {readTerritoryCatalog} from '../profiles/territories';
export class InstitutionError extends Error{constructor(public status:number,public code:string){super(code);}}
const text=(max:number)=>z.string().trim().min(1).max(max);
export const clinicInput=z.object({requestId:z.uuid(),name:text(150),contactPhone:text(40).nullable()}).strict();
export const branchInput=z.object({requestId:z.uuid(),name:text(150),communeCode:z.string().regex(/^\d{5}$/),street:text(200),addressNumber:text(40),floor:text(40).nullable(),unit:text(40).nullable(),contactPhone:text(40).nullable()}).strict();
function admin(a:AccountSummary){if(a.role!=='administrador')throw new InstitutionError(403,'FORBIDDEN');}
function uuid(x:string){if(!z.uuid().safeParse(x).success)throw new InstitutionError(400,'INVALID_INSTITUTION');}
function paging(limit:number,offset:number){if(!Number.isInteger(limit)||limit<1||limit>20||!Number.isInteger(offset)||offset<0||offset>10000)throw new InstitutionError(400,'INVALID_INSTITUTION');}
function translate(e:unknown):never{
 if(e instanceof InstitutionError)throw e;
 const code=(e as {code?:string})?.code;
 if(['42501','42P01'].includes(code??''))throw new InstitutionError(503,'INSTITUTION_UNAVAILABLE');
 if(['23503','23514','22001'].includes(code??''))throw new InstitutionError(400,'INVALID_INSTITUTION');
 if(code==='23505')throw new InstitutionError(409,'INSTITUTION_CONFLICT');throw e;
}
const clinicCols='id,name,active,contact_phone AS "contactPhone"';
const branchCols='b.id,b.clinic_id AS "clinicId",b.commune_code AS "communeCode",c.name AS "communeName",b.name,b.street,b.address_number AS "addressNumber",b.floor,b.unit,b.contact_phone AS "contactPhone",b.active';
const branchFrom='FROM public.vitalia_branches b JOIN public.vitalia_communes c ON c.code=b.commune_code';
export function createInstitutionService(db:DocumentDatabase){return {
 async territories(a:AccountSummary){admin(a);try{return await readTerritoryCatalog(db);}catch(e){if((e as {status?:number}).status===503)throw new InstitutionError(503,'INSTITUTION_UNAVAILABLE');throw e;}},
 async list(a:AccountSummary,limit=20,offset=0){admin(a);paging(limit,offset);try{return (await db.query(`SELECT ${clinicCols} FROM public.vitalia_clinics ORDER BY name,id LIMIT $1 OFFSET $2`,[limit,offset])).rows;}catch(e){translate(e);}},
 async branches(a:AccountSummary,id:string,limit=20,offset=0){admin(a);uuid(id);paging(limit,offset);try{
  if(!(await db.query('SELECT id FROM public.vitalia_clinics WHERE id=$1',[id])).rows.length)throw new InstitutionError(404,'INSTITUTION_NOT_FOUND');
  return (await db.query(`SELECT ${branchCols} ${branchFrom} WHERE b.clinic_id=$1 ORDER BY b.name,b.id LIMIT $2 OFFSET $3`,[id,limit,offset])).rows;
 }catch(e){translate(e);}},
 async create(a:AccountSummary,input:unknown){admin(a);const p=clinicInput.safeParse(input);if(!p.success)throw new InstitutionError(400,'INVALID_INSTITUTION');const v=p.data;
  try{return await db.transaction(async tx=>{
   await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-institution-'+v.requestId]);
   const inserted=await tx.query('INSERT INTO public.vitalia_clinics(id,name,contact_phone) VALUES($1,$2,$3) ON CONFLICT(id) DO NOTHING RETURNING id',[v.requestId,v.name,v.contactPhone]);
   const result=(await tx.query(`SELECT ${clinicCols} FROM public.vitalia_clinics WHERE id=$1`,[v.requestId])).rows[0];
   if(!result||result.name!==v.name||result.contactPhone!==v.contactPhone)throw new InstitutionError(409,'INSTITUTION_CONFLICT');
   if(inserted.rows.length)await tx.query(`INSERT INTO public.vitalia_institution_audit(id,actor_id,clinic_id,action) VALUES($1,$2,$3,'clinic_created')`,[randomUUID(),a.id,v.requestId]);
   return {item:result,created:inserted.rows.length===1};
  });}catch(e){translate(e);}
 },
 async createBranch(a:AccountSummary,id:string,input:unknown){admin(a);uuid(id);const p=branchInput.safeParse(input);if(!p.success)throw new InstitutionError(400,'INVALID_INSTITUTION');const v=p.data;
  try{return await db.transaction(async tx=>{
   await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-institution-'+v.requestId]);
   const clinic=(await tx.query('SELECT id,active FROM public.vitalia_clinics WHERE id=$1',[id])).rows[0];
   if(!clinic)throw new InstitutionError(404,'INSTITUTION_NOT_FOUND');if(!clinic.active)throw new InstitutionError(409,'INSTITUTION_INACTIVE');
   const inserted=await tx.query(`INSERT INTO public.vitalia_branches(id,clinic_id,commune_code,name,street,address_number,floor,unit,contact_phone)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(id) DO NOTHING RETURNING id`,[v.requestId,id,v.communeCode,v.name,v.street,v.addressNumber,v.floor,v.unit,v.contactPhone]);
   const item=(await tx.query(`SELECT ${branchCols} ${branchFrom} WHERE b.id=$1`,[v.requestId])).rows[0];
   if(!item||item.clinicId!==id||item.communeCode!==v.communeCode||item.name!==v.name||item.street!==v.street||item.addressNumber!==v.addressNumber||item.floor!==v.floor||item.unit!==v.unit||item.contactPhone!==v.contactPhone)throw new InstitutionError(409,'INSTITUTION_CONFLICT');
   if(inserted.rows.length)await tx.query(`INSERT INTO public.vitalia_institution_audit(id,actor_id,clinic_id,branch_id,action) VALUES($1,$2,$3,$4,'branch_created')`,[randomUUID(),a.id,id,v.requestId]);
   return {item,created:inserted.rows.length===1};
  });}catch(e){translate(e);}
 }
};}
export type InstitutionServices=ReturnType<typeof createInstitutionService>;
