import type {Extraction} from '../ai/contract';
import type {Reply} from './contract';
import type {Report} from '../ai/report-fields';
const fields:{key:keyof Report;label:string;pattern:RegExp}[]=[
 {key:'medico_solicitante',label:'Médico solicitante',pattern:/medico solicitante|solicitante|quien solicito|quien pidio|quien mando|doctor.{0,15}(?:pidio|solicito)|medico.{0,15}(?:pidio|solicito)/},
 {key:'profesional_validante',label:'Profesional que validó el informe',pattern:/quien.{0,20}valido|profesional.{0,30}(?:valido|validante|firmo)|validado por|quien.{0,20}firmo/},
 {key:'registro_profesional',label:'Registro profesional del informe',pattern:/registro profesional|cedula profesional|registro sanitario/},
 {key:'fecha_nacimiento',label:'Fecha de nacimiento',pattern:/fecha de nacimiento|cuando naci/},
 {key:'hora_muestra',label:'Hora de toma de muestra',pattern:/hora.{0,25}muestra/},
 {key:'hora_emision',label:'Hora de emisión',pattern:/hora.{0,25}(?:emision|reporte)/},
 {key:'fecha_muestra',label:'Fecha de toma de muestra',pattern:/fecha.{0,25}muestra|cuando.{0,25}muestra/},
 {key:'fecha_emision',label:'Fecha de emisión',pattern:/fecha.{0,25}(?:emision|reporte)|cuando.{0,25}(?:emitio|emision)/},
 {key:'expediente',label:'Expediente',pattern:/expediente/},
 {key:'laboratorio',label:'Laboratorio',pattern:/laboratorio.{0,30}(?:hizo|realizo|examen|informe)|que laboratorio|cual.{0,15}laboratorio|nombre del laboratorio/},
 {key:'edad',label:'Edad escrita en el informe',pattern:/mi edad|que edad|cual.{0,15}edad|cuantos anos/},
 {key:'sexo',label:'Sexo escrito en el informe',pattern:/mi sexo|que sexo|cual.{0,15}sexo/},
 {key:'observaciones_originales',label:'Observaciones originales del informe',pattern:/observaciones generales|observaciones originales|que dice.{0,20}observacion/},
 {key:'nombre_paciente',label:'Nombre del paciente',pattern:/como me llamo|nombre completo|mi nombre|nombre del paciente|nombre en el examen/},
];
const clarifications = {
 author: '¿Te refieres al médico que solicitó el examen, al profesional que validó el informe o al laboratorio que lo realizó? Son datos distintos; puedo consultar los que estén registrados en este examen.',
 uploaded: 'La fecha de carga en Vitalia es distinta de la fecha de emisión del informe y de la toma de muestra. La fecha de carga todavía no está incluida en los datos disponibles para este asistente. ¿Quieres consultar la fecha de emisión o la de toma de muestra?',
} as const;
function clarification(answer:string):Reply{return {kind:'education',indices:[],definitions:[],answer};}
function render(extraction:Extraction,field:typeof fields[number]):Reply{
 const value=extraction.informe?.[field.key]??null;
 return {kind:'education',indices:[],definitions:[],answer:value===null?
  `El campo «${field.label}» no está disponible en la copia revisada de este examen.`:
  `Dato transcrito de la copia revisada — ${field.label}: «${value}».`};
}
export function reportFactReply(question:string,extraction:Extraction):Reply|null{
 const q=question.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 if(/(?:cuando|fecha|dia).{0,45}(?:subi|subieron|subio|cargue|cargaron|carga|subida)|fecha de (?:carga|subida)/.test(q))return clarification(clarifications.uploaded);
 if(/quien.{0,25}(?:hizo|realizo|tomo).{0,25}(?:examen|estudio|muestra)/.test(q))return clarification(clarifications.author);
 const field=fields.find(field=>field.pattern.test(q));
 // Las revisiones antiguas mantienen el mensaje de nombre ausente ya registrado.
 if(!field||(!extraction.informe&&field.key==='nombre_paciente'))return null;
 return render(extraction,field);
}
export function isReportFactReply(reply:Reply,extraction:Extraction):boolean{
 return reply.kind==='education'&&!reply.indices.length&&!reply.definitions.length&&(Object.values(clarifications).some(answer=>answer===reply.answer)||fields.some(field=>render(extraction,field).answer===reply.answer));
}
