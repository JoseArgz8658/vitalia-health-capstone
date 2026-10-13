import {type Extraction} from '../ai/contract';
import {type History} from './contract';
function normalize(value:string){return value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/\p{Cf}/gu,'').toLowerCase();}
export const KNOWLEDGE_VERSION=2;
const entries=[
 {aliases:['hemoglobina','hb','hgb'],definition:'Proteína de los glóbulos rojos que transporta oxígeno.',purpose:'La prueba mide la cantidad de hemoglobina en sangre; no mide directamente la cantidad de oxígeno.',source:'https://medlineplus.gov/spanish/ency/article/003645.htm'},
 {aliases:['plaquetas','recuento de plaquetas'],definition:'Componentes de la sangre que participan en la coagulación y ayudan a detener el sangrado.',purpose:'El recuento mide la cantidad de plaquetas en sangre.',source:'https://medlineplus.gov/spanish/pruebas-de-laboratorio/conteo-sanguineo-completo/'},
 {aliases:['creatinina','creatinina en sangre','creatinina serica'],definition:'Producto de desecho relacionado con la creatina y la actividad muscular, que los riñones eliminan.',purpose:'La prueba mide la cantidad de creatinina en sangre u orina y aporta información sobre la función de los riñones.',source:'https://medlineplus.gov/spanish/ency/article/003610.htm'},
 {aliases:['leucocitos','globulos blancos','recuento de leucocitos','globulos blancos (leucocitos)'],definition:'Células que forman parte del sistema inmunitario y de las defensas del organismo.',purpose:'La prueba cuenta los glóbulos blancos en sangre.',source:'https://medlineplus.gov/spanish/pruebas-de-laboratorio/conteo-de-globulos-blancos/'},
 {aliases:['glucosa','glucosa en sangre','glucemia','glucosa en ayunas','glicemia','glicemia en ayunas'],definition:'Azúcar presente en sangre que el cuerpo utiliza como fuente de energía.',purpose:'La prueba mide la cantidad de glucosa en sangre.',source:'https://medlineplus.gov/spanish/bloodglucose.html'},
 {"aliases": ["eritrocitos", "globulos rojos", "globulos rojos (eritrocitos)"], "definition": "Células de la sangre que llevan oxígeno a los tejidos mediante la hemoglobina.", "purpose": "El recuento mide la cantidad de glóbulos rojos en sangre.", "source": "https://medlineplus.gov/spanish/pruebas-de-laboratorio/conteo-de-globulos-rojos/"},
 {"aliases": ["hematocrito", "hct"], "definition": "Proporción del volumen de la sangre ocupada por los glóbulos rojos.", "purpose": "La prueba mide qué parte del volumen de sangre corresponde a glóbulos rojos.", "source": "https://medlineplus.gov/spanish/pruebas-de-laboratorio/hematocrito/"},
 {"aliases": ["vcm", "volumen corpuscular medio", "vcm (volumen corpuscular medio)"], "definition": "Medida del tamaño promedio de los glóbulos rojos.", "purpose": "La prueba mide el volumen promedio de los glóbulos rojos.", "source": "https://medlineplus.gov/spanish/pruebas-de-laboratorio/prueba-de-sangre-de-vcm/"},
 {"aliases": ["urea", "urea en sangre"], "definition": "Sustancia de desecho formada en el hígado al procesar productos de la descomposición de proteínas; se elimina por la orina.", "purpose": "La prueba mide la cantidad de urea en sangre. No es la misma medición que el nitrógeno ureico.", "source": "https://medlineplus.gov/spanish/ency/article/000372.htm"},
 {"aliases": ["colesterol total"], "definition": "Cantidad total de colesterol en la sangre. El colesterol es una sustancia que el cuerpo utiliza para formar células y otras sustancias.", "purpose": "La prueba mide la cantidad total de colesterol en sangre.", "source": "https://medlineplus.gov/spanish/pruebas-de-laboratorio/niveles-de-colesterol/"},
 {"aliases": ["trigliceridos"], "definition": "Tipo de grasa presente en la sangre que el cuerpo utiliza como reserva de energía.", "purpose": "La prueba mide la cantidad de triglicéridos en sangre.", "source": "https://medlineplus.gov/spanish/triglycerides.html"},
 {"aliases": ["colesterol hdl", "hdl"], "definition": "Colesterol transportado por partículas HDL, que ayudan a llevar colesterol hacia el hígado.", "purpose": "La prueba mide el colesterol transportado por partículas HDL.", "source": "https://medlineplus.gov/spanish/hdlthegoodcholesterol.html"},
 {"aliases": ["colesterol ldl", "ldl"], "definition": "Colesterol transportado por partículas LDL, que lo llevan hacia las células del cuerpo.", "purpose": "La prueba mide o estima el colesterol transportado por partículas LDL.", "source": "https://medlineplus.gov/spanish/ldlthebadcholesterol.html"},
 {"aliases": ["tgp (alt)", "alt", "tgp", "alanina aminotransferasa"], "definition": "Enzima presente principalmente en el hígado que participa en procesos químicos de las células.", "purpose": "La prueba mide la actividad de esta enzima en sangre.", "source": "https://medlineplus.gov/spanish/pruebas-de-laboratorio/panel-metabolico-completo-pmc/"},
 {"aliases": ["tgo (ast)", "ast", "tgo", "aspartato aminotransferasa"], "definition": "Enzima presente en el hígado y en otros tejidos, como los músculos.", "purpose": "La prueba mide la actividad de esta enzima en sangre.", "source": "https://medlineplus.gov/spanish/pruebas-de-laboratorio/prueba-de-ast/"},
 {"aliases": ["bilirrubina total", "bilirrubina"], "definition": "Sustancia producida al descomponerse los glóbulos rojos; el hígado la procesa para eliminarla.", "purpose": "La prueba mide la cantidad total de bilirrubina en sangre.", "source": "https://medlineplus.gov/spanish/pruebas-de-laboratorio/examen-de-bilirrubina-en-sangre/"},
];
function entryFor(name:string|null){const key=normalize(name??'').trim();return entries.find(entry=>entry.aliases.includes(key));}
// Se aportan únicamente conceptos que ya existen en el examen abierto.
export function educationalEvidence(extraction:Extraction){
 return extraction.resultados.flatMap((row,index)=>{const entry=entryFor(row.nombre);return entry?[{index,definition:entry.definition,purpose:entry.purpose,source:entry.source}]:[];});
}
export function questionIndices(question:string,extraction:Extraction,history:History):number[]|null{
 const q=normalize(question);
 const matches=extraction.resultados.flatMap((row,index)=>{
  const names=[row.nombre,...(entryFor(row.nombre)?.aliases??[])].filter((x):x is string=>Boolean(x));
  return names.some(name=>{const key=normalize(name).trim();return key.length>1&&new RegExp(`(?:^|[^a-z0-9])${key.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}(?:$|[^a-z0-9])`).test(q);})?[index]:[];
 });
 if(matches.length)return matches;
 const unitMatches=extraction.resultados.flatMap((row,index)=>{const unit=normalize(row.unidad??'').replace(/\s/g,'');return unit.length>1&&q.replace(/\s/g,'').includes(unit)?[index]:[];});
 if(unitMatches.length)return unitMatches;
 if(/^[¿¡\s]*(?:y |por que|para que|como|que significa|explica|eso|entonces|puedes aclarar)/.test(q)&&! /rango|referencia|examen|resultados|indicadores/.test(q)){
  const prior=history.at(-1);if(prior?.response.kind==='education'&&prior.response.indices.length)return [...prior.response.indices];
 }
 return null;
}

export function applyEducationalNotes(extraction:Extraction,reply:import('./contract').Reply,mode:import('./contract').Mode,question:string,history:History){
 const evidence=educationalEvidence(extraction);
 if(!['education','insufficient'].includes(reply.kind))return {reply,noteIndices:[] as number[]};
 if(mode==='explanation'&&evidence.length){
  const definitions=extraction.resultados.map((_,index)=>{
   const note=evidence.find(item=>item.index===index);
   return note?{index,text:note.definition,known:true}:reply.definitions.find(item=>item.index===index)??{index,text:'No hay información suficiente para explicar este indicador sin inventar su significado.',known:false};
  });
  return {reply:{kind:'education' as const,answer:'Estos son los conceptos presentes en el examen.',indices:definitions.map(item=>item.index),definitions},noteIndices:evidence.map(item=>item.index)};
 }
 const targets=questionIndices(question,extraction,history);
 if(mode==='chat'&&targets?.length===1&&/para que.*(?:mide|medir|prueba|sirve)|finalidad|que mide/.test(normalize(question))){
  const note=evidence.find(item=>item.index===targets[0]);
  if(note)return {reply:{kind:'education' as const,answer:note.purpose,indices:targets,definitions:[]},noteIndices:targets};
 }
 return {reply,noteIndices:[] as number[]};
}
