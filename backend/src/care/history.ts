import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {CareInboxError} from './inbox';
export function createCareHistoryService(db:DocumentDatabase){return {
 async get(a:AccountSummary,id:string,input:unknown){
  if(a.role!=='paciente')throw new CareInboxError(403,'FORBIDDEN');
  if(!z.uuid().safeParse(id).success)throw new CareInboxError(404,'CARE_NOT_FOUND');
  const parsed=z.object({offset:z.string().regex(/^(0|[1-9]\d*)$/).transform(Number).pipe(z.number().int().max(100000)).optional().default(0)}).strict().safeParse(input);
  if(!parsed.success)throw new CareInboxError(400,'INVALID_CARE_INPUT');
  return db.transaction(async tx=>{
   const owned=await tx.query("SELECT id FROM public.vitalia_documents WHERE id=$1 AND patient_id=$2 AND status='stored' FOR SHARE",[id,a.id]);
   if(!owned.rows.length)throw new CareInboxError(404,'CARE_NOT_FOUND');
   const rows=(await tx.query(`SELECT c.id,c.previous_care_id AS "previousCareId",c.kind,c.status,c.created_at AS "createdAt",
    cl.name AS "clinicName",b.name AS "branchName",b.street,b.address_number AS "addressNumber",co.name AS "communeName",
    s.name AS "specialtyName",concat_ws(' ',p.first_name,p.additional_names,p.first_surname,p.second_surname) AS "professionalName",
    r.reason AS "referralReason"
    FROM public.vitalia_exam_care c JOIN public.vitalia_clinics cl ON cl.id=c.clinic_id
    JOIN public.vitalia_clinic_memberships m ON m.id=c.responsible_membership_id JOIN public.vitalia_people p ON p.id=m.professional_person_id
    JOIN public.vitalia_specialties s ON s.id=c.specialty_id LEFT JOIN public.vitalia_branches b ON b.id=c.branch_id
    LEFT JOIN public.vitalia_communes co ON co.code=b.commune_code
    LEFT JOIN public.vitalia_exam_referrals r ON r.target_care_id=c.id
    WHERE c.document_id=$1 AND c.patient_id=$2 ORDER BY c.created_at,c.id LIMIT 31 OFFSET $3`,[id,a.id,parsed.data.offset])).rows;
   return {items:rows.slice(0,30),nextOffset:rows.length>30?parsed.data.offset+30:null};
  });
 }
};}
export type CareHistoryServices=ReturnType<typeof createCareHistoryService>;
