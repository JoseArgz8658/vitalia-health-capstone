export class DocumentInputError extends Error {}
export const MAX_FILE_BYTES = 10 * 1024 * 1024;

// Identifica firmas básicas, no reemplaza un parser completo ni un análisis antimalware.
export function identifyDocument(body: Buffer, declared: string, name: string): string {
  if (!body.length || body.length > MAX_FILE_BYTES) throw new DocumentInputError('Tamaño inválido.');
  let detected: string | undefined;
  if (body.subarray(0, 5).toString('ascii') === '%PDF-' &&
      body.subarray(Math.max(0, body.length - 1024)).includes(Buffer.from('%%EOF'))) {
    detected = 'application/pdf';
  } else if (body.length >= 24 &&
      body.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
      body.subarray(12, 16).toString('ascii') === 'IHDR') {
    detected = 'image/png';
  } else if (body.length >= 4 && body[0] === 255 && body[1] === 216 &&
      body[2] === 255 && body[body.length - 2] === 255 && body[body.length - 1] === 217) {
    detected = 'image/jpeg';
  }
  const extensions: Record<string, RegExp> = {
    'application/pdf': /\.pdf$/i, 'image/png': /\.png$/i, 'image/jpeg': /\.jpe?g$/i,
  };
  if (!detected || detected !== declared || !extensions[detected].test(name)) {
    throw new DocumentInputError('Tipo de archivo incompatible.');
  }
  return detected;
}
