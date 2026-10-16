import { z } from 'zod';
import {reportSchema} from './report-fields';
const nullableText = z.string().min(1).max(500).refine(value => value.trim().length > 0).nullable();
export const extractionSchema = z.object({
  examen: nullableText, fecha: nullableText, informe: reportSchema.optional(),
  resultados: z.array(z.object({
    nombre: nullableText, valor: nullableText, unidad: nullableText, rango_referencia: nullableText, estado_documento: nullableText.optional(),
  }).strict()).max(100),
}).strict();
export type Extraction = z.infer<typeof extractionSchema>;
export type Incident = { code: 'invalid_json' | 'invalid_structure' | 'invalid_date' | 'not_extracted' | 'no_results' | 'not_in_source'; path: string; message: string };
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
function sourceContainsNumericValue(source: string, value: string): boolean {
  const normalizedValue = value.normalize('NFKC').trim();

  if (!/^(?:[<>]=?\s*)?[+-]?\d[\d.,]*$/.test(normalizedValue)) {
    return false;
  }

  const compactValue = normalizedValue.replace(/\s+/g, '');
  const escaped = compactValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  const pattern = new RegExp(
    `(^|[^\\d.,<>])${escaped}(?=$|[^\\d.,])`
  );

  return pattern.test(
    source.normalize('NFKC').replace(/([<>]=?)\s+(?=[+-]?\d)/g, '$1')
  );
}

function sourceHasDifferentAnalyteValue(
  source: string,
  name: string,
  value: string
): boolean {
  const normalizedName = name.normalize('NFKC').trim().toLowerCase();
  const normalizedValue = value.normalize('NFKC').trim().replace(/\s+/g, '');

  if (!normalizedName || !/^(?:[<>]=?)?[+-]?\d[\d.,]*$/.test(normalizedValue)) {
    return false;
  }

  const escapeRegex = (text: string) =>
    text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  const namePattern = escapeRegex(normalizedName);

  const linePattern = new RegExp(
    `^\\s*${namePattern}(?:\\s*:\\s*|[ \\t]{2,})([<>]=?\\s*)?([+-]?\\d[\\d.,]*)` +
    `(?=$|\\s|[^\\d.,])`,
    'i'
  );

  let foundDifferentValue = false;

  for (const line of source.normalize('NFKC').split(/\r?\n/)) {
    const match = line.toLowerCase().match(linePattern);

    if (!match) continue;

    const sourceValue = `${(match[1] || '').replace(/\s+/g, '')}${match[2]}`;

    if (sourceValue === normalizedValue) {
      return false;
    }

    foundDifferentValue = true;
  }

  return foundDifferentValue;
}
function normalizeSourceText(text: string): string {
  return text.normalize('NFKC').replace(/[\u2010-\u2015\u2212]/g, '-').replace(/\s+/g, ' ').trim().toLowerCase();
}
export function reviewExtraction(raw: string, requireReport=false, sourceText?: string): ExtractionReview {
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
  if(requireReport&&(!extraction.informe||extraction.resultados.some(row=>row.estado_documento===undefined)))return {status:'rejected',raw,extraction:null,incidents:[{code:'invalid_structure',path:'informe',message:'Faltan los campos del informe ampliado.'}],approved:false};

  const incidents: Incident[] = [];
  for (const key of ['examen', 'fecha'] as const) {
    if (extraction[key] === null) incidents.push({ code: 'not_extracted', path: key, message: 'Campo no extraído; comprobar el documento original.' });
  }
  if (extraction.fecha !== null && !isCalendarDate(extraction.fecha)) {
    incidents.push({ code: 'invalid_date', path: 'fecha', message: 'Fecha inválida; no se corrige ni se acepta automáticamente.' });
  }
  if(extraction.informe){
    for(const key of ['fecha_nacimiento','fecha_muestra','fecha_emision'] as const){
      const date=extraction.informe[key];
      if(date!==null&&!isCalendarDate(date))incidents.push({code:'invalid_date',path:`informe.${key}`,message:'Fecha inválida; comprobar el documento original.'});
    }
  }
  const normalizedSource = sourceText?.trim() ? normalizeSourceText(sourceText) : null;
  extraction.resultados.forEach((row, index) => {
    if (sourceText?.trim() && row.valor !== null) {
      const valueExists = sourceContainsNumericValue(sourceText, row.valor);
      const wrongAssociation = valueExists && row.nombre !== null &&
        sourceHasDifferentAnalyteValue(sourceText, row.nombre, row.valor);

      if (!valueExists || wrongAssociation) {
        incidents.push({
          code: 'not_in_source',
          path: `resultados[${index}].valor`,
          message: wrongAssociation
            ? 'El valor aparece en el documento, pero no coincide con el asociado a este analito; requiere verificación humana.'
            : 'El valor numérico no se encontró literalmente en el documento original; requiere verificación humana.'
        });
      }
    }
    for (const key of ['nombre', 'valor', 'unidad', 'rango_referencia'] as const) {
      if (row[key] === null) incidents.push({ code: 'not_extracted', path: `resultados[${index}].${key}`, message: 'Campo no extraído; podría estar presente en el original.' });
    }
    if (normalizedSource !== null && row.rango_referencia !== null &&
        !normalizedSource.includes(normalizeSourceText(row.rango_referencia))) {
      incidents.push({
        code: 'not_in_source',
        path: `resultados[${index}].rango_referencia`,
        message: 'El rango de referencia no se encontró literalmente en el documento original; requiere verificación humana.'
      });
    }
  });
  if (!extraction.resultados.length) incidents.push({ code: 'no_results', path: 'resultados', message: 'No se extrajeron resultados; comprobar el original.' });
  // Incluso sin incidencias, la salida requiere contraste profesional con el original.
  return { status: 'requires_review', raw, extraction, incidents, approved: false };
}
