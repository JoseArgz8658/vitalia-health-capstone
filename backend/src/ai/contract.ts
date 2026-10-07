import { z } from 'zod';
const nullableText = z.string().min(1).max(500).refine(value => value.trim().length > 0).nullable();
export const extractionSchema = z.object({
  examen: nullableText, fecha: nullableText,
  resultados: z.array(z.object({
    nombre: nullableText, valor: nullableText, unidad: nullableText, rango_referencia: nullableText,
  }).strict()).max(100),
}).strict();
export type Extraction = z.infer<typeof extractionSchema>;
export type Incident = { code: 'invalid_json' | 'invalid_structure' | 'invalid_date' | 'not_extracted' | 'no_results'; path: string; message: string };
export type ExtractionReview = {
  status: 'rejected' | 'requires_review'; raw: string; extraction: Extraction | null;
  incidents: Incident[]; approved: false;
};
export function isCalendarDate(value: string): boolean {
  const match = /^(\d{2})-(\d{2})-(\d{4})$/.exec(value);
  if (!match) return false;
  const [, day, month, year] = match.map(Number);
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(0, 0, 0, 0);
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}
export function reviewExtraction(raw: string): ExtractionReview {
  let value: unknown;
  try { value = JSON.parse(raw); } catch {
    return { status: 'rejected', raw, extraction: null, approved: false,
      incidents: [{ code: 'invalid_json', path: '', message: 'La respuesta no es JSON válido.' }] };
  }
  const parsed = extractionSchema.safeParse(value);
  if (!parsed.success) {
    return { status: 'rejected', raw, extraction: null, approved: false,
      incidents: parsed.error.issues.map(issue => ({ code: 'invalid_structure', path: issue.path.join('.'), message: issue.message })) };
  }
  const extraction = parsed.data;
  const incidents: Incident[] = [];
  for (const key of ['examen', 'fecha'] as const) {
    if (extraction[key] === null) incidents.push({ code: 'not_extracted', path: key, message: 'Campo no extraído; comprobar el documento original.' });
  }
  if (extraction.fecha !== null && !isCalendarDate(extraction.fecha)) {
    incidents.push({ code: 'invalid_date', path: 'fecha', message: 'Fecha inválida; no se corrige ni se acepta automáticamente.' });
  }
  extraction.resultados.forEach((row, index) => {
    for (const key of ['nombre', 'valor', 'unidad', 'rango_referencia'] as const) {
      if (row[key] === null) incidents.push({ code: 'not_extracted', path: `resultados[${index}].${key}`, message: 'Campo no extraído; podría estar presente en el original.' });
    }
  });
  if (!extraction.resultados.length) incidents.push({ code: 'no_results', path: 'resultados', message: 'No se extrajeron resultados; comprobar el original.' });
  // Incluso sin incidencias, la salida requiere contraste profesional con el original.
  return { status: 'requires_review', raw, extraction, incidents, approved: false };
}
