import {z} from 'zod';
export const REPORT_FIELDS = ["nombre_paciente", "edad", "sexo", "fecha_nacimiento", "expediente", "medico_solicitante", "fecha_muestra", "hora_muestra", "fecha_emision", "hora_emision", "laboratorio", "observaciones_originales", "profesional_validante", "registro_profesional"] as const;
const text=z.string().min(1).max(500).refine(v=>v.trim().length>0).nullable();
export const reportSchema=z.object({
 nombre_paciente:text,
 edad:text,
 sexo:text,
 fecha_nacimiento:text,
 expediente:text,
 medico_solicitante:text,
 fecha_muestra:text,
 hora_muestra:text,
 fecha_emision:text,
 hora_emision:text,
 laboratorio:text,
 observaciones_originales:z.string().min(1).max(2000).nullable(),
 profesional_validante:text,
 registro_profesional:text,
}).strict();
export type Report=z.infer<typeof reportSchema>;
