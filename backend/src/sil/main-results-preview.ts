type Analyte = { examCode: string; analyte: string; unit: string };

const escapePattern = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Extrae únicamente filas inequívocas del PDF asociado a las muestras de la orden. */
export function suggestMainResults(text: string, barcodes: string[], analytes: Analyte[]) {
  const documentCodes = new Set(Array.from(text.matchAll(
    /(?<![\p{L}\p{N}_-])LAB-[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}(?![\p{L}\p{N}_-])/giu,
  ), match => match[0].toUpperCase()));
  if (!barcodes.length || documentCodes.size !== barcodes.length ||
      barcodes.some(code => !documentCodes.has(code))) {
    return {state: 'sample_mismatch' as const, items: []};
  }

  const lines = text.split(/\r?\n/).map(line => line.trim().normalize('NFC'));
  const items = analytes.map(row => {
    const name = escapePattern(row.analyte.normalize('NFC'));
    const candidates = lines.filter(line => new RegExp(`^${name}(?=[:\\s|]|$)`, 'iu').test(line));
    // El primer número debe estar justo después del analito y antes de su unidad.
    // Las referencias o los comentarios en la misma línea se revisan manualmente.
    const match = candidates.length === 1 && candidates[0].match(new RegExp(
      `^${name}[ \\t:|]+([+-]?\\d{1,9}(?:[.,]\\d{1,4})?)[ \\t|]*([^\\s|]+)$`, 'iu',
    ));
    // 1.234 y 1,234 pueden representar miles o decimales según el emisor.
    const suggestedValue = match && match[2] === row.unit &&
      !/^[+-]?[1-9]\d{0,2}[.,]\d{3}$/.test(match[1])
      ? Number(match[1].replace(',', '.')) : null;
    return {...row, suggestedValue};
  });
  return {state: 'text_ready' as const, items};
}
