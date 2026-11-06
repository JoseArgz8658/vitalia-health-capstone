import {isDeepStrictEqual} from 'node:util';
import {type Extraction,isCalendarDate} from '../ai/contract';
// Política compartida: cotejo documental, no interpretación ni diagnóstico.
export function reviewedExtractionValid(reviewed:Extraction,original:Extraction,observations:string):boolean{
 if(!reviewed.resultados.length||(reviewed.fecha!==null&&!isCalendarDate(reviewed.fecha)))return false;
 if(original.informe&&!reviewed.informe)return false;
 if(reviewed.informe){
  if(reviewed.resultados.some(row=>row.estado_documento===undefined))return false;
  for(const key of ['fecha_nacimiento','fecha_muestra','fecha_emision'] as const){
   const date=reviewed.informe[key];if(date!==null&&!isCalendarDate(date))return false;
  }
 }
 const missing=reviewed.examen===null||reviewed.fecha===null||
  (reviewed.informe&&Object.values(reviewed.informe).some(field=>field===null))||
  reviewed.resultados.some(row=>Object.values(row).some(field=>field===null));
 return !((missing||!isDeepStrictEqual(original,reviewed))&&!observations);
}
