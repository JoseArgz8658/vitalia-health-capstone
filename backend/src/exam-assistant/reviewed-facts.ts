import {reportFactReply,isReportFactReply} from './report-facts';
import {isCalendarDate,type Extraction} from '../ai/contract';
import type {Reply,History} from './contract';
import {questionIndices} from './knowledge';
// El esquema conserva una fecha, sin distinguir el evento.
export function reviewedDateReply(extraction:Extraction):Reply|null{
 if(!extraction.fecha||!isCalendarDate(extraction.fecha))return null;
 return {kind:'education',answer:`La fecha registrada en la copia revisada de este examen es ${extraction.fecha}.`,indices:[],definitions:[]};
}
export function isReviewedDateReply(reply:Reply,extraction:Extraction):boolean{
 const expected=reviewedDateReply(extraction);
 return expected!==null&&reply.kind==='education'&&reply.answer===expected.answer&&reply.indices.length===0&&reply.definitions.length===0;
}

const noName='El nombre del paciente no está incluido en los datos revisados disponibles para este asistente.';
function fieldReply(extraction:Extraction,index:number,field:'valor'|'unidad'|'rango_referencia'|'estado_documento'):Reply{
 const row=extraction.resultados[index];
 const answer=field==='rango_referencia'||field==='estado_documento'
  ? row[field]==null?'Ese campo no está disponible en la copia revisada del indicador.':`Texto transcrito del indicador «${row.nombre??'Indicador sin nombre'}» — ${field==='rango_referencia'?'referencia':'estado escrito en el informe'}: «${row[field]}».`
  : field==='valor'
  ? row.valor===null?'No hay un valor revisado disponible para este indicador.':`El valor revisado de «${row.nombre??'Indicador sin nombre'}» es «${row.valor}»; unidad registrada: «${row.unidad??'no disponible'}».`
  : row.unidad===null?'No hay una unidad revisada disponible para este indicador.':`La unidad revisada de «${row.nombre??'Indicador sin nombre'}» es «${row.unidad}».`;
 return {kind:'education',answer,indices:[index],definitions:[]};
}
export function reviewedFactReply(question:string,extraction:Extraction,history:History):Reply|null{
 const report=reportFactReply(question,extraction);if(report)return report;
 const q=question.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 if(/como me llamo|(?:cual|que).{0,20}(?:mi nombre|nombre del paciente)|nombre (?:del paciente|en el examen)|nombre completo/.test(q))return {kind:'education',answer:noName,indices:[],definitions:[]};
 // Solo consultas factuales; no intercepta definiciones ni interpretación clínica.
 const value=/cual.{0,25}(?:valor|resultado)|que (?:valor|resultado)|cuanto.{0,15}(?:dio|salio)|valor de medida/.test(q);
 const unit=/cual.{0,25}unidad|que unidad|unidad de medida/.test(q)&&!/significa|explica/.test(q);
 const reference=/cual.{0,25}(?:rango|referencia)|que (?:rango|referencia)|que dice.{0,25}referencia/.test(q)&&!/significa|explica/.test(q);
 const state=/cual.{0,25}estado|que estado|que dice.{0,25}estado/.test(q);
 if(!value&&!unit&&!reference&&!state)return null;
 const indices=questionIndices(question,extraction,history);
 if(!indices||indices.length!==1)return {kind:'education',answer:'Indica el nombre de un único indicador del examen para consultar su valor o unidad revisados.',indices:[],definitions:[]};
 return fieldReply(extraction,indices[0],value?'valor':unit?'unidad':reference?'rango_referencia':'estado_documento');
}
export function isReviewedFactReply(reply:Reply,extraction:Extraction):boolean{
 if(isReviewedDateReply(reply,extraction)||isReportFactReply(reply,extraction))return true;
 if(reply.kind!=='education'||reply.definitions.length)return false;
 if(!reply.indices.length)return [noName,'Indica el nombre de un único indicador del examen para consultar su valor o unidad revisados.'].includes(reply.answer);
 return reply.indices.length===1&&(['valor','unidad','rango_referencia','estado_documento'] as const).some(field=>reply.answer===fieldReply(extraction,reply.indices[0],field).answer);
}
