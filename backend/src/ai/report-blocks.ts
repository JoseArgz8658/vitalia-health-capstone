import {extractionSchema} from './contract';
import {reportExtractionSchema} from './report-prompt';
export class ReportBlockError extends Error {}
type Generate = (schema: object, text: string, instruction: string) => Promise<string>;
// Cortar únicamente en encabezados explícitos, nunca a mitad de una tabla.
export function reportSections(text: string): string[] {
 const headings=[...text.matchAll(/^\s*\d{1,2}[.)]\s+[^\n\r\d]{4,100}\r?$/gm)];
 if(headings.length<2)return [text];
 const sections=headings.map((heading,index)=>text.slice(heading.index,headings[index+1]?.index??text.length));
 // No perder resultados anteriores al primer encabezado, aunque el formato sea irregular.
 return [text.slice(0,headings[0].index),...sections].filter(part=>part.trim());
}
export async function extractReportBlocks(text:string,generate:Generate):Promise<string>{
 const props=reportExtractionSchema.properties;
 const metadataSchema={type:'object',additionalProperties:false,required:['examen','fecha','informe'],properties:{examen:props.examen,fecha:props.fecha,informe:props.informe}};
 const resultsSchema={type:'object',additionalProperties:false,required:['resultados'],properties:{resultados:props.resultados}};
 let metadata:unknown;
 try {metadata=JSON.parse(await generate(metadataSchema,text,'Extrae exclusivamente los datos generales y el objeto informe. No extraigas resultados en esta solicitud.'));}
 catch(error){if(error instanceof SyntaxError)throw new ReportBlockError('Formato de bloque inválido.');throw error;}
 const metaSchema=extractionSchema.omit({resultados:true}).required({informe:true});
 const parsed=metaSchema.safeParse(metadata);
 if(!parsed.success)throw new ReportBlockError('Datos generales incompletos.');
 const rows:unknown[]=[];
 for(const section of reportSections(text)){
  let value:unknown;
  try {value=JSON.parse(await generate(resultsSchema,section,'Extrae exclusivamente todos los resultados escritos en este bloque, en su orden. No repitas datos generales. Si no hay resultados, devuelve resultados vacío.'));}
  catch(error){if(error instanceof SyntaxError)throw new ReportBlockError('Formato de bloque inválido.');throw error;}
  const part=extractionSchema.pick({resultados:true}).safeParse(value);
  if(!part.success||part.data.resultados.some(row=>row.estado_documento===undefined))throw new ReportBlockError('Resultados de bloque incompletos.');
  rows.push(...part.data.resultados);
  if(rows.length>100)throw new ReportBlockError('Límite de resultados excedido.');
 }
 return JSON.stringify({...parsed.data,resultados:rows});
}
