import {z} from 'zod';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {ProfileError} from './errors';

export const measurementInput=z.object({
 requestId:z.uuid(),
 measuredAt:z.iso.datetime().transform(value=>new Date(value).toISOString()).refine(value=>Date.parse(value)<=Date.now()),
 weightKg:z.number().finite().positive().nullable(),
 heightCm:z.number().finite().positive().nullable(),
}).strict().refine(value=>value.weightKg!==null||value.heightCm!==null);
interface Row{id:string;measured_at:Date;weight_kg:string|null;height_cm:string|null;source:string;recorded_by:string}
function publicMeasurement(row:Row){return {id:row.id,measuredAt:new Date(row.measured_at).toISOString(),
 weightKg:row.weight_kg===null?null:Number(row.weight_kg),heightCm:row.height_cm===null?null:Number(row.height_cm),source:row.source};}
function patient(account:AccountSummary){if(account.role!=='paciente')throw new ProfileError(403,'FORBIDDEN');}
function failure(error:unknown):never{
 if(error instanceof ProfileError)throw error;
 const code=(error as {code?:string})?.code;
 if(code==='23503'||code==='23514')throw new ProfileError(400,'INVALID_MEASUREMENT');
 if(code==='42501'||code==='42P01')throw new ProfileError(503,'PROFILE_UNAVAILABLE');
 throw error;
}
export function createMeasurementService(db:DocumentDatabase){
 const person=async(tx:Pick<DocumentDatabase,'query'>,account:AccountSummary)=>{
  const result=await tx.query<{id:string}>(`SELECT p.id FROM public.vitalia_people p
   JOIN public.vitalia_patient_profiles pp ON pp.person_id=p.id WHERE p.account_id=$1`,[account.id]);
  return result.rows[0]?.id??null;
 };
 return {
  async measurements(account:AccountSummary){
   patient(account);
   try{return await db.transaction(async tx=>{
    const id=await person(tx,account);
    if(!id)return {measurements:[],profileRequired:true};
    const rows=await tx.query<Row>(`SELECT id,measured_at,weight_kg,height_cm,source,recorded_by FROM public.vitalia_patient_measurements
     WHERE patient_person_id=$1 ORDER BY measured_at DESC,id DESC LIMIT 20`,[id]);
    return {measurements:rows.rows.map(publicMeasurement),profileRequired:false};
   });}catch(error){failure(error);}
  },
  async recordMeasurement(account:AccountSummary,input:unknown){
   patient(account);const parsed=measurementInput.safeParse(input);if(!parsed.success)throw new ProfileError(400,'INVALID_MEASUREMENT');
   const value=parsed.data;
   try{return await db.transaction(async tx=>{
    await tx.query('SELECT pg_advisory_xact_lock(hashtext($1),hashtext($2))',['vitalia-measurements',account.id]);
    const id=await person(tx,account);if(!id)throw new ProfileError(409,'PROFILE_REQUIRED');
    await tx.query(`INSERT INTO public.vitalia_patient_measurements(id,patient_person_id,measured_at,weight_kg,height_cm,source,recorded_by)
     VALUES($1,$2,$3,$4,$5,'patient_reported',$6) ON CONFLICT(id) DO NOTHING`,
     [value.requestId,id,value.measuredAt,value.weightKg,value.heightCm,account.id]);
    const result=await tx.query<Row>(`SELECT id,measured_at,weight_kg,height_cm,source,recorded_by FROM public.vitalia_patient_measurements
     WHERE id=$1 AND patient_person_id=$2`,[value.requestId,id]);
    const row=result.rows[0],saved=row?publicMeasurement(row):null;
    if(!row||!saved||saved.measuredAt!==new Date(value.measuredAt).toISOString()||saved.weightKg!==value.weightKg||saved.heightCm!==value.heightCm||row.source!=='patient_reported'||row.recorded_by!==account.id)
     throw new ProfileError(409,'MEASUREMENT_CONFLICT');
    return {measurement:saved};
   });}catch(error){failure(error);}
  }
 };
}
