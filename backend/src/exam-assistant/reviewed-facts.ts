import {reportFactReply,isReportFactReply} from './report-facts';
import {isCalendarDate,type Extraction} from '../ai/contract';
import type {Reply,History} from './contract';
import {questionIndices} from './knowledge';
import {educationalEvidence} from './knowledge';
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
function summarize(extraction:Extraction,indices:number[]):Reply{
 const lines=indices.map(i=>{const row=extraction.resultados[i];return `• ${row.nombre??'Indicador'}: ${row.valor??'sin valor'}${row.unidad?' '+row.unidad:''}${row.rango_referencia?' (referencia del documento: '+row.rango_referencia+')':''}.`;});
 return {kind:'education',answer:'Estos son los resultados transcritos del examen:\n'+lines.join('\n')+'\nSon datos del documento; su interpretación clínica requiere contexto y la extracción preliminar puede contener errores.',indices,definitions:[]};
}
function targeted(extraction:Extraction,indices:number[],question:string):Reply{
 const q=question.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 const evidence=educationalEvidence(extraction);
 const lines=indices.map(i=>{const row=extraction.resultados[i];const note=evidence.find(x=>x.index===i);const name=row.nombre??'Indicador';
  const fact=`${name}: ${row.valor??'sin valor'}${row.unidad?' '+row.unidad:''}${row.rango_referencia?' (referencia escrita: '+row.rango_referencia+')':''}.`;
  return /que es|que significa|explica|para que|que mide/.test(q)?`${note?(/para que|que mide/.test(q)?note.purpose:note.definition)+' ':''}${fact}`:fact;
 });
 return {kind:'education',answer:lines.join('\n')+'\nLos valores proceden del examen; no son una interpretación clínica.',indices,definitions:[]};
}
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
 const normalized=question.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
 // Consultas sobre metadatos: la extracción actual no registra de forma estructurada
 // quién atendió, solicitó o tomó la muestra. No inferir identidades.
 if(/(?:quien|kien|qien|nombre|cual).{0,45}(?:atendio|atendieron|vio|medico|doctor|doctora|profesional|tomo la muestra|solicito)|(?:medico|doctor|profesional).{0,25}(?:atendio|nombre|solicito)/.test(normalized))
  return {kind:'education',answer:'No tengo identificado en los datos extraídos quién te atendió. El examen puede incluir un profesional solicitante, pero eso no confirma quién realizó la atención.',indices:[],definitions:[]};
 if(/(?:que|cual|como se llama|nombre).{0,25}(?:laboratorio|clinica|centro medico)/.test(normalized))
  return {kind:'education',answer:'El nombre del laboratorio o centro no está disponible como dato estructurado de este examen.',indices:[],definitions:[]};
 // Consultas de valores y resúmenes: siempre se resuelven desde la extracción, no con el modelo.
 const informal=normalized.replace(/\b(?:vit\s*d|vit\s*de|vitamina\s*de)\b/g,'vitamina d').replace(/\b(?:q|k)\b/g,'que');
 const directMatches=extraction.resultados.flatMap((row,i)=>{
  const name=(row.nombre??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
  if(/vitamina\s*d|25.oh.vitamina\s*d/.test(name)&&/\bvitamina d\b/.test(informal))return [i];
  const compact=name.replace(/[^a-z0-9]/g,'');
  if(compact.length>=4&&informal.replace(/[^a-z0-9]/g,'').includes(compact))return [i];
  return [];
 });
 const targetIndices=directMatches.length?directMatches:questionIndices(question,extraction,history);
 if(targetIndices?.length&&/^(?:y\s+)?(?:mi|el|la|los|las)\s+/.test(informal)&&!/(?:significa|explica|sirve|mide|por que)/.test(informal))return targeted(extraction,targetIndices,question);
 if (targetIndices?.length === 1) {
  const index = targetIndices[0];
  const row = extraction.resultados[index];

  if (
    row.valor == null &&
    /\b(?:valor|resultado|cuanto|salio)\b/.test(informal)
  ) {
    return fieldReply(extraction, index, 'valor');
  }

  if (
    row.unidad == null &&
    /\bunidad\b/.test(informal) &&
    !/\b(?:significa|explica)\b/.test(informal)
  ) {
    return fieldReply(extraction, index, 'unidad');
  }
}
 if(targetIndices?.length&&/(?:\bvalor\b|\bresultado\b|\bcuanto\b|\bsalio\b|\bcuanto dio\b|\bme dio\b)/.test(informal)&&!/(?:normal|anormal|bien|mal|alto|bajo|grave)/.test(informal))return targeted(extraction,targetIndices,question);

 const summary=/\b(?:mis resultados|que resultados|cuales resultados|todos los resultados|lista|listado|resumen|resumeme|resume|que indicadores|cuales indicadores|que valores|resultados tuve|explicame mi examen|explica mi examen|como salieron mis examenes|como salio mi examen|que me salio|q me salio|mis examenes|mis examenes|que onda mis examenes|que tal mis examenes|que tengo en el examen)\b/.test(normalized);
 if(summary&&extraction.resultados.length)return summarize(extraction,extraction.resultados.map((_,i)=>i));
 if(targetIndices?.length&&/que es|que significa|explica|para que|que mide|q es|q significa/.test(normalized)&&/valor|resultado|cuanto|salio|dio|en mi examen|en el examen/.test(normalized))return targeted(extraction,targetIndices,question);
 if(targetIndices?.length&&/\b(?:que valor|que resultado|cual valor|cual resultado|cuanto|cuantos|cuanta|cuantas|valor de|resultado de|que mas|cuanto me salio|cuanto salio|q salio|q valor|q resultado|cuanto dio)\b/.test(normalized))return targeted(extraction,targetIndices,question);
 if(/^(?:y )?que mas\??$/.test(normalized)&&history.length){
  const last=history.at(-1)?.response.indices??[];
  const remaining=extraction.resultados.map((_,i)=>i).filter(i=>!last.includes(i));
  return summarize(extraction,remaining.length?remaining:extraction.resultados.map((_,i)=>i));
 }
 const q=question.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 if(/como me llamo|(?:cual|que).{0,20}(?:mi nombre|nombre del paciente)|nombre (?:del paciente|en el examen)|nombre completo/.test(q))return {kind:'education',answer:noName,indices:[],definitions:[]};
 // Solo consultas factuales; no intercepta definiciones ni interpretación clínica.
 const value=/cual.{0,25}(?:valor|resultado)|que (?:valor|resultado)|cuanto.{0,15}(?:dio|salio)|valor de medida/.test(q);
 const unit=/cual.{0,25}unidad|que unidad|unidad de medida/.test(q)&&!/significa|explica/.test(q);
 const reference=/cual.{0,25}(?:rango|referencia)|que (?:rango|referencia)|que dice.{0,25}referencia/.test(q)&&!/significa|explica/.test(q);
 const state=/cual.{0,25}estado|que estado|que dice.{0,25}estado/.test(q);
 if(!value&&!unit&&!reference&&!state)return null;
 const indices=questionIndices(question,extraction,history);
 if (!indices || indices.length !== 1) {
  return {
    kind: 'education',
    answer: 'Indica el nombre de un único indicador del examen para consultar su valor o unidad revisados.',
    indices: [],
    definitions: []
  };
}
 return fieldReply(extraction,indices[0],value?'valor':unit?'unidad':reference?'rango_referencia':'estado_documento');
}
export function isReviewedFactReply(reply:Reply,extraction:Extraction):boolean{
 if(isReviewedDateReply(reply,extraction)||isReportFactReply(reply,extraction))return true;
 if(reply.kind!=='education'||reply.definitions.length)return false;
 if(reply.indices.length===0&&[
  'No tengo identificado en los datos extraídos quién te atendió. El examen puede incluir un profesional solicitante, pero eso no confirma quién realizó la atención.',
  'El nombre del laboratorio o centro no está disponible como dato estructurado de este examen.'
 ].includes(reply.answer))return true;
 if(!reply.indices.length)return [noName,'Indica el nombre de un único indicador del examen para consultar su valor o unidad revisados.'].includes(reply.answer);
 if (reply.indices.length > 0) {
  const indices = reply.indices;

  if (
    new Set(indices).size !== indices.length ||
    indices.some(i =>
      !Number.isInteger(i) ||
      i < 0 ||
      i >= extraction.resultados.length
    )
  ) return false;

  if (reply.answer === summarize(extraction, indices).answer) {
    return true;
  }

  const expectedTargeted = [
    targeted(extraction, indices, ''),
    targeted(extraction, indices, '¿Qué es?'),
    targeted(extraction, indices, '¿Qué significa?'),
    targeted(extraction, indices, '¿Para qué sirve?'),
    targeted(extraction, indices, '¿Qué mide?'),
  ];

  if (expectedTargeted.some(
    expected => reply.answer === expected.answer
  )) return true;
}
 return reply.indices.length===1&&(['valor','unidad','rango_referencia','estado_documento'] as const).some(field=>reply.answer===fieldReply(extraction,reply.indices[0],field).answer);
}
