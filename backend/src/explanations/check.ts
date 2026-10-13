import {createExplanationGenerator} from './local-generator';
async function main(){
 try{
  const generate=createExplanationGenerator();
  const result=await generate({examen:'Hemograma ficticio de explicación',fecha:'29-09-2026',resultados:[
   {nombre:'Hemoglobina',valor:'14,2',unidad:'g/dL',rango_referencia:'13,0–17,0 g/dL'},
   {nombre:'Indicador Alfa',valor:null,unidad:'mmol/L',rango_referencia:null}]});
  console.info(JSON.stringify(result,null,2));
  console.info('Comprobación ficticia. Las definiciones proceden del catálogo; la explicación no está aprobada por un profesional.');
 }catch{process.exitCode=1;console.error('No se obtuvo una explicación válida. Comprueba Ollama local y qwen3:4b-instruct. No se aceptó contenido libre o incompleto.');}
}
void main();
