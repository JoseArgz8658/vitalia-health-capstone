import {z} from 'zod';
import {extractionSchema,type Extraction} from '../ai/contract';
export const CATALOG_VERSION=1;
export const PROMPT_VERSION=1;
const cbc='https://medlineplus.gov/spanish/pruebas-de-laboratorio/conteo-sanguineo-completo/';
export const catalog={
 hemoglobina:{aliases:['hemoglobina','hb','hgb'],text:'La hemoglobina es una proteína de los glóbulos rojos que transporta oxígeno por el cuerpo.',source:cbc},
 plaquetas:{aliases:['plaquetas','recuento de plaquetas'],text:'Las plaquetas son componentes de la sangre que participan en la coagulación y ayudan a detener el sangrado.',source:cbc},
 leucocitos:{aliases:['leucocitos','globulos blancos','recuento de leucocitos'],text:'Los leucocitos, o glóbulos blancos, son células que forman parte de las defensas del organismo.',source:'https://medlineplus.gov/spanish/pruebas-de-laboratorio/conteo-de-globulos-blancos/'},
 glucosa:{aliases:['glucosa','glucosa en sangre','glucemia'],text:'La glucosa es un azúcar presente en la sangre que el cuerpo utiliza como fuente de energía.',source:'https://medlineplus.gov/spanish/bloodglucose.html'},
 desconocido:{aliases:[],text:'No hay información suficiente en el catálogo de esta versión para explicar este indicador sin inventar su significado.',source:null},
} as const;
export const conceptSchema=z.enum(['hemoglobina','plaquetas','leucocitos','glucosa','desconocido']);
export type Concept=z.infer<typeof conceptSchema>;
export const selectionsSchema=z.object({items:z.array(z.object({index:z.number().int().min(0).max(19),concept:conceptSchema}).strict()).min(1).max(20)}).strict();
export function expectedConcept(name:string|null):Concept{
 const normal=(name??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim().replace(/\s+/g,' ');
 for(const [key,value] of Object.entries(catalog))if((value.aliases as readonly string[]).includes(normal))return key as Concept;
 return 'desconocido';
}
export function renderExplanation(input:Extraction,selections:unknown){
 const extraction=extractionSchema.parse(input),parsed=selectionsSchema.parse(selections);
 if(parsed.items.length!==extraction.resultados.length)throw new Error('Cantidad de conceptos inválida.');
 const items=parsed.items.map((item,index)=>{
  const row=extraction.resultados[index];
  if(item.index!==index||(item.concept!=='desconocido'&&item.concept!==expectedConcept(row.nombre)))throw new Error('Concepto incompatible con los datos revisados.');
  const entry=catalog[item.concept];
  return {index,name:row.nombre,value:row.valor,unit:row.unidad,reference:row.rango_referencia,
   concept:item.concept,explanation:entry.text,source:entry.source};
 });
 return {exam:extraction.examen,date:extraction.fecha,items,
  notice:'Información general elaborada con asistencia de IA y un catálogo limitado. No interpreta tu estado de salud, no diagnostica ni recomienda tratamientos. La aprobación profesional corresponde a los datos, no a esta explicación.',
  approved:false as const};
}
export type Explanation=ReturnType<typeof renderExplanation>;
