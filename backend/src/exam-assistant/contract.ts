import {questionIndices,educationalEvidence} from './knowledge';
import {z} from 'zod';
import {type Extraction} from '../ai/contract';
export const ASSISTANT_VERSION=2;
export const notice='Contenido generado por IA, no aprobado por un profesional. Puede contener errores. Explica conceptos del examen; no establece diagnósticos ni recomienda tratamientos.';
export const replySchema=z.object({kind:z.enum(['education','insufficient','out_of_scope','restricted']),
 answer:z.string().trim().min(1).max(2500),indices:z.array(z.number().int().min(0).max(19)).max(20),
 definitions:z.array(z.object({index:z.number().int().min(0).max(19),text:z.string().trim().min(1).max(700),known:z.boolean()}).strict()).max(20)}).strict();
export type Reply=z.infer<typeof replySchema>;
export type Mode='chat'|'explanation';
export type History={question:string;response:Reply}[];
export function normalize(value:string){return value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/\p{Cf}/gu,'').toLowerCase();}
export function synthetic(name:string|null){return name===null||/^(indicador|analito)\s+(alfa|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|omicron|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega|[a-z])\b|fictici|sintetic|ignora|instruccion|prompt|receta|system|assistant/i.test(normalize(name));}
const restricted=/diagnos|disease|prescrib|dosage|dose|treatment|should i|recommend|pill|medication|what should|diagnostic|que enfermedad|tengo (?:anemia|diabetes|cancer|insuficiencia|enfermedad|infeccion)|estoy (?:bien|mal|sano|enferm)|es (?:grave|peligroso)|(?:debo|puedo|cuanto|que dosis).{0,40}(?:tomar|medic|pastilla|comer|hacer)|receta|tratamiento|dosificacion|dosis|recomiend|me aconsej|curarme|que hago|urgencia|emergencia/;
const otherExam=/other (?:exam|document|patient)|compare|otro (?:examen|documento|paciente)|otra (?:prueba|persona)|compara|comparar|examen anterior|mis otros|otros resultados|historial completo/;
const injected=/ignore|instructions|systemprompt|ignora|instrucciones|prompt|system|jailbreak|olvida.{0,15}reglas|hazte pasar|clave|contrasena|token|sql|administrador/;
export function fixed(kind:Reply['kind'],indices:number[]=[]):Reply{
 return {kind,indices,definitions:[],answer:kind==='restricted'?'Este asistente no determina enfermedades, prescribe ni recomienda tratamientos.':
  kind==='out_of_scope'?'Solo puedo responder sobre el examen abierto. No consulto otros documentos ni temas ajenos.':
  'Los datos de este examen no permiten responder esa pregunta con suficiente certeza.'};
}
export function gate(question:string,extraction:Extraction,history:History):Reply|null{
 const q=normalize(question).replace(/^[¿¡\s]+/,'');
 if(restricted.test(q)||injected.test(q))return fixed('restricted');
 if(/futbol|clima|pelicula|politica|videojuego|bolsa de valores|criptomoneda/.test(q))return fixed('out_of_scope');
 if(otherExam.test(q))return fixed('out_of_scope');
 const relevant=extraction.resultados.map((row,index)=>({row,index})).filter(({row})=>row.nombre&&q.includes(normalize(row.nombre).trim()));
 if(relevant.length&&relevant.every(({row})=>synthetic(row.nombre))&&!/unidad|rango|referencia|valor|fecha/.test(q))return fixed('insufficient',relevant.map(x=>x.index));
 const exam=normalize(extraction.examen??'').trim();
 const aliasReference=questionIndices(question,extraction,[])!==null;
 const fieldReference=extraction.resultados.some(row=>[row.unidad,row.valor].some(value=>{
  const token=normalize(value??'').replace(/[\s/]/g,'').replace(/μ/g,'µ');
  return token.length>=2&&q.replace(/[\s/]/g,'').replace(/μ/g,'µ').includes(token);
 }));
 const generic=/examen|resultado|indicador|valor|unidad|rango|referencia|fecha|laboratorio|hemograma/.test(q);
 const followup=history.length>0&&/^(y |por que|para que|como|que significa|explica|eso|entonces|puedes aclarar)/.test(q);
 if(!relevant.length&&!fieldReference&&!aliasReference&&!generic&&!(exam.length>3&&q.includes(exam))&&!followup)return fixed('out_of_scope');
 return null;
}
export class ContentPolicyError extends Error {
 constructor(public readonly category:'numeric_text'|'external_link'|'classification_term'|'clinical_or_instruction_term'){super('Contenido no aceptable.');}
}
// Controles conservadores: no prueban la veracidad semántica del conocimiento del modelo.
export function validateReply(value:unknown,extraction:Extraction,mode:Mode):Reply{
 const reply=replySchema.parse(value);
 if(new Set(reply.indices).size!==reply.indices.length||reply.indices.some(i=>i>=extraction.resultados.length))throw new Error('Referencias inválidas.');
 if(reply.kind!=='education')return fixed(reply.kind,reply.indices);
 const forbidden=/\p{N}|take |you have|\b(?:tienes|padeces|sufres|presentas)\b|bebe |beber |come |comer |consume |consumir |evita |evitar |realiza |haz |hazte |aumenta |reduce |suspende |visita |contacta |busca ayuda|descansa |duerme |prescrib|recommend|should|treatment|diagnos|https?:|www\.|diagnostic|(?:tienes|padeces|presentas|sufres).{0,30}(?:anemia|diabetes|cancer|enfermedad|infeccion)|debes|deberias|te recomiendo|se recomienda|toma |tomar |medicamento|pastilla|tratamiento|dosis|dosificacion|urgencias|hospital|llama |consulta (?:a |con |un )|acude |(?:indica|sugiere|compatible).{0,40}(?:anemia|diabetes|cancer|infeccion|enfermedad)|compatible con|sugiere|podria indicar|indica que|signo de|riesgo de|probabilidad de|normal|anormal|elevado|bajo|alto|fuera del rango/u;
 const checkText=(text:string)=>{const value=normalize(text);if(!forbidden.test(value))return;
  const category=/\p{N}/u.test(value)?'numeric_text':/https?:|www\./.test(value)?'external_link':/normal|anormal|elevado|bajo|alto|fuera del rango/.test(value)?'classification_term':'clinical_or_instruction_term';
  throw new ContentPolicyError(category);
 };
 if(!reply.indices.length)throw new Error('Referencias inválidas.');
 checkText(reply.answer);
 if(mode==='chat'&&reply.definitions.length)throw new Error('Formato de conversación inválido.');
 if(mode==='explanation'){
  if(reply.definitions.length!==extraction.resultados.length||reply.indices.length!==extraction.resultados.length)throw new Error('Explicación parcial.');
  reply.definitions.forEach((item,index)=>{
   if(item.index!==index||reply.indices[index]!==index)throw new Error('Definición inválida.');
   checkText(item.text);
   if(synthetic(extraction.resultados[index].nombre)){item.known=false;item.text='No hay información suficiente para explicar este indicador sin inventar su significado.';}
   else if(!item.known)item.text='El modelo no identifica con suficiente certeza el significado de este indicador.';
  });
 }
 return reply;
}
export function explanationView(extraction:Extraction,reply:Reply){
 return {exam:extraction.examen,date:extraction.fecha,approved:false,notice,
  items:extraction.resultados.map((row,index)=>{
   const item=reply.definitions[index];
   const note=educationalEvidence(extraction).find(entry=>entry.index===index&&entry.definition===item?.text&&item.known);return {index,name:row.nombre,value:row.valor,unit:row.unidad,reference:row.rango_referencia,
    concept:item?.known?'medical_general':'desconocido',explanation:item?.text??'No hay información suficiente para explicar este indicador sin inventar su significado.',source:note?.source??null};
  })};
}
