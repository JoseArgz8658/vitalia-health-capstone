import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {readOcr} from './reader';
async function main(){
 if(process.argv.length>2)throw new Error('Uso: node dist/ocr/check.js (solo documentos ficticios incluidos)');
 const fixtures=JSON.parse(await readFile(join(__dirname,'../../test/ocr-fixtures.json'),'utf8'));
 let failed=false;
 for(const source of ['png','jpeg','pdf'] as const){
  const result=await readOcr(Buffer.from(fixtures[source],'base64'),source);
  console.log(`\nDocumento ficticio: ${source}`);console.log(JSON.stringify(result,null,2));
  if(result.status!=='requires_review')failed=true;
 }
 console.log('\nEl texto OCR requiere contraste con el original. No se ha enviado a la IA.');
 if(failed)process.exitCode=1;
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
