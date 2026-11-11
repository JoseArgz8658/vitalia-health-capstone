import {type Pool} from 'pg';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';

export class CareCatalogError extends Error {
 constructor(public readonly status:number,public readonly code:string){super(code);}
}
const filters=z.object({
 communeCode:z.string().regex(/^\d{5}$/),
 clinicId:z.uuid().optional(),branchId:z.uuid().optional(),specialtyId:z.uuid().optional(),
 offset:z.union([z.number(),z.string().regex(/^(0|[1-9]\d*)$/).transform(Number)])
  .pipe(z.number().int().min(0).max(100000)).default(0),
}).strict();
interface CatalogRow {
 clinicId:string;clinicName:string;branchId:string;branchName:string;communeCode:string;
 street:string;addressNumber:string;specialtyId:string;specialtyName:string;
 membershipId:string;professionalName:string;
}
const PAGE_SIZE=30;
export function createCareCatalogService(db:Pick<Pool,'query'>){return {
 async list(account:AccountSummary,input:unknown){
  if(account.role!=='paciente')throw new CareCatalogError(403,'FORBIDDEN');
  const parsed=filters.safeParse(input);
  if(!parsed.success)throw new CareCatalogError(400,'INVALID_CARE_FILTER');
  const f=parsed.data;
  try{
   // Una sola sentencia: opciones y existencia de comuna comparten la misma instantánea.
   // No se invoca la función que lanza excepciones por profesional inelegible:
   // una credencial incompleta excluye esa opción sin bloquear todo el catálogo.
   const result=await db.query<{communeExists:boolean;items:CatalogRow[]}>(`
    WITH options AS (
     SELECT c.id AS "clinicId",c.name AS "clinicName",b.id AS "branchId",b.name AS "branchName",
      b.commune_code AS "communeCode",b.street,b.address_number AS "addressNumber",
      s.id AS "specialtyId",s.name AS "specialtyName",m.id AS "membershipId",
      concat_ws(' ',p.first_name,p.additional_names,p.first_surname,p.second_surname) AS "professionalName"
     FROM public.vitalia_clinics c
     JOIN public.vitalia_branches b ON b.clinic_id=c.id AND b.active
     JOIN public.vitalia_branch_memberships bm ON bm.clinic_id=c.id AND bm.branch_id=b.id
     JOIN public.vitalia_clinic_memberships m ON m.id=bm.membership_id AND m.clinic_id=c.id AND m.active
     JOIN public.vitalia_membership_specialties ms ON ms.membership_id=m.id AND ms.clinic_id=c.id
     JOIN public.vitalia_specialties s ON s.id=ms.specialty_id AND s.active
     JOIN public.vitalia_people p ON p.id=m.professional_person_id
     JOIN public.vitalia_professional_profiles f ON f.person_id=p.id AND f.verification_status='verified'
     JOIN public.vitalia_account_roles g ON g.account_id=p.account_id AND g.role_code='profesional' AND g.active
     JOIN public.vitalia_credential_audit a ON a.request_id=f.verification_request_id AND a.person_id=p.id
     WHERE c.active AND b.commune_code=$1
      AND ($2::uuid IS NULL OR c.id=$2) AND ($3::uuid IS NULL OR b.id=$3)
      AND ($4::uuid IS NULL OR s.id=$4)
      AND a.decision='verified' AND f.registration_reference IS NOT NULL
      AND f.registration_reference=a.after_state->>'registrationReference'
      AND f.verification_revision::text=a.after_state->>'revision'
      AND f.verification_decided_by=a.actor_id AND f.verification_decided_at=a.created_at
     ORDER BY c.name,c.id,b.name,b.id,s.name,s.id,p.first_surname,p.first_name,m.id
     LIMIT 31 OFFSET $5
    ) SELECT EXISTS(SELECT 1 FROM public.vitalia_communes WHERE code=$1) AS "communeExists",
     COALESCE((SELECT json_agg(options) FROM options),'[]'::json) AS items`,
    [f.communeCode,f.clinicId??null,f.branchId??null,f.specialtyId??null,f.offset]);
   const row=result.rows[0];
   if(!row?.communeExists)throw new CareCatalogError(400,'INVALID_CARE_COMMUNE');
   return {communeCode:f.communeCode,items:row.items.slice(0,PAGE_SIZE),
    nextOffset:row.items.length>PAGE_SIZE?f.offset+PAGE_SIZE:null};
  }catch(error){
   if(error instanceof CareCatalogError)throw error;
   if(['42P01','42703','42501'].includes((error as {code?:string})?.code??''))
    throw new CareCatalogError(503,'CARE_CATALOG_UNAVAILABLE');
   throw error;
  }
 }
};}
export type CareCatalogServices=ReturnType<typeof createCareCatalogService>;
