import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createDocumentExtraction} from './document-extraction';
async function main(){
 if(process.argv.length>2)throw new Error('Uso: node dist/ai/check-documents.js (solo documentos ficticios incluidos)');
 const pdfs=JSON.parse(await readFile(join(__dirname,'../../test/pdf-fixtures.json'),'utf8'));
 const images=JSON.parse(await readFile(join(__dirname,'../../test/ocr-fixtures.json'),'utf8'));
 const processDocument=createDocumentExtraction();
 const cases=[
  {name:'PDF con texto',source:'pdf' as const,data:pdfs.texto,expected:'requires_review'},
  {name:'PDF escaneado',source:'pdf' as const,data:images.pdf,expected:'requires_review'},
  {name:'Imagen PNG',source:'png' as const,data:images.png,expected:'requires_review'},
  {name:'Imagen JPEG',source:'jpeg' as const,data:images.jpeg,expected:'requires_review'},
  {name:'PDF protegido',source:'pdf' as const,data:pdfs.protegido,expected:'rejected'},
 ];
 let failed=false;
 for(const item of cases){
  console.log(`\nDocumento ficticio: ${item.name}`);
  const result=await processDocument(Buffer.from(item.data,'base64'),item.source);
  console.log(JSON.stringify(result,null,2));
  if(result.status!==item.expected)failed=true;
 }
 console.log('\nFlujo unificado aislado ejecutado. Todas las extracciones requieren revisión del original.');
 if(failed)process.exitCode=1;
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
