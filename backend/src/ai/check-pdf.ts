import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createPdfExtraction } from './pdf-extraction';
async function main() {
  if (process.argv.length > 2) throw new Error('Uso: node dist/ai/check-pdf.js (solo PDF ficticios incluidos)');
  const fixtures = JSON.parse(await readFile(join(__dirname, '../../test/pdf-fixtures.json'), 'utf8'));
  const processPdf = createPdfExtraction();
  let failed = false;
  for (const name of ['texto', 'imagen', 'protegido']) {
    const result = await processPdf(Buffer.from(fixtures[name], 'base64'));
    console.log(`\nPDF ficticio: ${name}`);
    console.log(JSON.stringify(result, null, 2));
    if (name === 'texto' && result.status !== 'requires_review') failed = true;
    if (name === 'imagen' && result.status !== 'needs_ocr') failed = true;
    if (name === 'protegido' && result.status !== 'rejected') failed = true;
  }
  console.log('\nFlujo aislado ejecutado. Ninguna salida constituye aprobación profesional.');
  if (failed) process.exitCode = 1;
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
