import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';

const email=z.string().trim().toLowerCase().pipe(z.email().max(254));
const inputSchema=z.object({patientEmail:email,professionalEmail:email}).strict();
export class AssignmentInputError extends Error {}
export class AssignmentNotFoundError extends Error {}
export class AssignmentForbiddenError extends Error {}
function role(account:AccountSummary,expected:string){if(account.role!==expected)throw new AssignmentForbiddenError();}
function pagination(limit:number,offset:number){
 if(!z.number().int().min(1).max(20).safeParse(limit).success||!z.number().int().min(0).max(10000).safeParse(offset).success)throw new AssignmentInputError();
}
const columns=`x.id,x.active,x.created_at,x.updated_at,x.deactivated_at,
 p.email AS patient_email,r.email AS professional_email`;
const join=`FROM public.vitalia_patient_assignments x
 JOIN public.vitalia_accounts p ON p.id=x.patient_id AND p.role_code='paciente'
 JOIN public.vitalia_accounts r ON r.id=x.professional_id AND r.role_code='profesional'`;
interface Row {id:string;active:boolean;created_at:Date;updated_at:Date;deactivated_at:Date|null;patient_email:string;professional_email:string}
function summary(row:Row){return {id:row.id,active:row.active,patientEmail:row.patient_email,
 professionalEmail:row.professional_email,createdAt:row.created_at,updatedAt:row.updated_at,deactivatedAt:row.deactivated_at};}
export function createAssignmentService(db:DocumentDatabase){
 return {
  async listAdmin(account:AccountSummary,limit=20,offset=0){
   role(account,'administrador');pagination(limit,offset);
   const result=await db.query<Row>(`SELECT ${columns} ${join}
    ORDER BY x.created_at DESC,x.id DESC LIMIT $1 OFFSET $2`,[limit,offset]);
   return result.rows.map(summary);
  },
  async listProfessional(account:AccountSummary,limit=20,offset=0){
   role(account,'profesional');pagination(limit,offset);
   const result=await db.query<{id:string;email:string;assignment_id:string}>(`SELECT p.id,p.email,x.id AS assignment_id ${join}
    WHERE x.professional_id=$1 AND x.active=true ORDER BY p.email,p.id LIMIT $2 OFFSET $3`,[account.id,limit,offset]);
   return result.rows.map(row=>({id:row.id,email:row.email,assignmentId:row.assignment_id}));
  },
  async assign(account:AccountSummary,input:unknown){
   role(account,'administrador');const parsed=inputSchema.safeParse(input);
   if(!parsed.success)throw new AssignmentInputError();
   return db.transaction(async tx=>{
    const found=await tx.query<{id:string;role_code:string}>(`SELECT id,role_code FROM public.vitalia_accounts
     WHERE (email=$1 AND role_code='paciente') OR (email=$2 AND role_code='profesional')`,
     [parsed.data.patientEmail,parsed.data.professionalEmail]);
    const patient=found.rows.find(row=>row.role_code==='paciente');
    const professional=found.rows.find(row=>row.role_code==='profesional');
    if(!patient||!professional)throw new AssignmentNotFoundError();
    const saved=await tx.query<{id:string}>(`INSERT INTO public.vitalia_patient_assignments AS x
     (id,patient_id,professional_id,created_by,updated_by) VALUES ($1,$2,$3,$4,$4)
     ON CONFLICT(professional_id,patient_id) DO UPDATE
     SET active=true,updated_by=$4,updated_at=CURRENT_TIMESTAMP,deactivated_at=NULL
     WHERE x.active=false RETURNING id`,[randomUUID(),patient.id,professional.id,account.id]);
    if(saved.rows.length)await tx.query(`INSERT INTO public.vitalia_assignment_audit (id,assignment_id,actor_id,action)
     VALUES ($1,$2,$3,'activate')`,[randomUUID(),saved.rows[0].id,account.id]);
    const result=await tx.query<Row>(`SELECT ${columns} ${join}
     WHERE x.patient_id=$1 AND x.professional_id=$2`,[patient.id,professional.id]);
    if(result.rows.length!==1)throw new AssignmentNotFoundError();
    return {changed:saved.rows.length===1,assignment:summary(result.rows[0])};
   });
  },
  async deactivate(account:AccountSummary,id:string){
   role(account,'administrador');if(!z.uuid().safeParse(id).success)throw new AssignmentNotFoundError();
   return db.transaction(async tx=>{
    const changed=await tx.query<{id:string}>(`UPDATE public.vitalia_patient_assignments
     SET active=false,updated_by=$2,updated_at=CURRENT_TIMESTAMP,deactivated_at=CURRENT_TIMESTAMP
     WHERE id=$1 AND active=true RETURNING id`,[id,account.id]);
    if(changed.rows.length)await tx.query(`INSERT INTO public.vitalia_assignment_audit (id,assignment_id,actor_id,action)
     VALUES ($1,$2,$3,'deactivate')`,[randomUUID(),id,account.id]);
    const found=await tx.query<Row>(`SELECT ${columns} ${join} WHERE x.id=$1`,[id]);
    if(found.rows.length!==1)throw new AssignmentNotFoundError();
    return {changed:changed.rows.length===1,assignment:summary(found.rows[0])};
   });
  },
 };
}
export type AssignmentServices=ReturnType<typeof createAssignmentService>;
