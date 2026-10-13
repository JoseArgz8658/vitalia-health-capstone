import { createLocalExtractor } from './local-extractor';
const sample = `Examen: Perfil ficticio de comprobación
Fecha: 31-11-2026
Indicador de prueba: [ilegible] mmol/L. Referencia: 2,0–5,0 mmol/L.`;
async function main() {
  if (process.argv.length > 3) throw new Error('Uso: node dist/ai/check.js [modelo-local]');
  const result = await createLocalExtractor({ model: process.argv[2] ?? 'qwen3:4b-instruct' })(sample);
  console.log('Texto ficticio enviado:\n' + sample);
  console.log(JSON.stringify(result, null, 2));
  console.log('Comprobación ejecutada; esta salida no está aprobada por un profesional.');
  if (result.status === 'rejected') process.exitCode = 1;
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
