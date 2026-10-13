import {createExamAssistant,AssistantModelError,ASSISTANT_PROMPT_REVISION} from './local-model';
import {type Extraction} from '../ai/contract';
import {type History} from './contract';
const review:Extraction={examen:'Panel sintético independiente',fecha:null,resultados:[
 {nombre:'Creatinina',valor:null,unidad:'mg/dL',rango_referencia:null},
 {nombre:'Hemoglobina',valor:null,unidad:'g/dL',rango_referencia:null},
 {nombre:'Leucocitos',valor:null,unidad:null,rango_referencia:null},
 {nombre:'Glucosa',valor:null,unidad:null,rango_referencia:null},
 {nombre:'Analito Omega',valor:null,unidad:null,rango_referencia:null}]};
const cases:{id:string;question:string;kind:string;indices:number[];history?:History}[]=[
 {id:'Q01-orden-creatinina',question:'Explícame qué es la creatinina, aunque no tenga una cifra.',kind:'education',indices:[0]},
 {id:'Q02-alias',question:'¿Qué significa Hb?',kind:'education',indices:[1]},
 {id:'Q03-leucocitos',question:'¿Qué son los leucocitos de este examen?',kind:'education',indices:[2]},
 {id:'Q04-glucosa',question:'¿Qué es la glucosa que aparece aquí?',kind:'education',indices:[3]},
 {id:'Q05-seguimiento',question:'¿Para qué se mide?',kind:'education',indices:[1],history:[{question:'¿Qué es hemoglobina?',response:{kind:'education',answer:'La hemoglobina transporta oxígeno.',indices:[1],definitions:[]}}]},
 {id:'Q06-desconocido',question:'¿Qué significa Analito Omega?',kind:'insufficient',indices:[4]},
];
async function main(){
 const model=createExamAssistant();let passed=0;
 console.info(`Batería adicional de calidad. Prompt: ${ASSISTANT_PROMPT_REVISION}. No certifica veracidad médica.`);
 for(const item of cases){try{
  const result=await model({extraction:review,question:item.question,mode:'chat',history:item.history??[]});
  const answersPurpose=item.id!=='Q05-seguimiento'||/mide|medicion|cantidad|concentracion/.test(result.reply.answer.toLowerCase());
  const pass=answersPurpose&&result.reply.kind===item.kind&&JSON.stringify(result.reply.indices)===JSON.stringify(item.indices);if(pass)passed++;
  console.info(JSON.stringify({case:item.id,pass,expectedKind:item.kind,expectedIndices:item.indices,...result},null,2));
 }catch(error){console.info(JSON.stringify({case:item.id,pass:false,reason:error instanceof AssistantModelError?error.reason:'evaluation',detail:error instanceof AssistantModelError?error.detail:undefined}));}}
 console.info(`Calidad estructural y referencias: ${passed}/${cases.length}. Revisión semántica pendiente.`);
 if(passed!==cases.length)process.exitCode=1;
}
void main();
