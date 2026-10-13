import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { readPdfText } from './reader';
async function main(){
 if(process.argv.length>2)throw new Error('Uso: node dist/pdf/check.js (solo documentos ficticios incluidos)');
 const fixtures=JSON.parse(await readFile(join(__dirname,'../../test/pdf-fixtures.json'),'utf8'));
 for(const name of ['texto','imagen','protegido']){
  const result=await readPdfText(Buffer.from(fixtures[name],'base64'));
  console.log(`\nPDF ficticio: ${name}`);console.log(JSON.stringify(result,null,2));
 }
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
