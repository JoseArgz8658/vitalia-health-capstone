import { readPdfText, type PdfReadResult } from '../pdf/reader';
import { createLocalExtractor, type LocalExtractionResult } from './local-extractor';
export type PdfExtractionResult = {
  status: 'requires_review' | 'needs_ocr' | 'rejected' | 'service_error';
  reading: PdfReadResult;
  ai: LocalExtractionResult | null;
  approved: false;
  error?: { code: 'extraction_unavailable'; message: string };
};
export function createPdfExtraction(options: {
  model?: string;
  read?: typeof readPdfText;
  extract?: (text: string) => Promise<LocalExtractionResult>;
} = {}) {
  const read = options.read ?? readPdfText;
  const extract = options.extract ?? createLocalExtractor({ model: options.model });
  return async function processPdf(data: Uint8Array): Promise<PdfExtractionResult> {
    const reading = await read(data);
    if (reading.status !== 'text_ready') {
      return { status: reading.status, reading, ai: null, approved: false };
    }
    if (!reading.text?.trim()) {
      return { status: 'rejected', reading: { ...reading, status: 'rejected', text: null,
        incidents: [...reading.incidents, { code: 'empty_text', message: 'El lector no entregó texto aprovechable.' }] }, ai: null, approved: false };
    }
    try {
      const ai = await extract(reading.text);
      return { status: ai.status, reading, ai, approved: false };
    } catch {
      return { status: 'service_error', reading, ai: null, approved: false,
        error: { code: 'extraction_unavailable', message: 'No se pudo completar la extracción con Ollama local.' } };
    }
  };
}
