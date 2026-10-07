import {ollamaUrl} from '../runtime/local-services';
import { extractionPrompt, schema } from './prompt';
import { reviewExtraction, type ExtractionReview } from './contract';
export class ExtractionServiceError extends Error {
  constructor(message: string) { super(message); this.name = 'ExtractionServiceError'; }
}
export type LocalExtractionResult = ExtractionReview & { model: string; promptVersion: 3; elapsedMs: number };
async function readBounded(response: Response): Promise<string> {
  if (!response.body) throw new ExtractionServiceError('Ollama devolvió una respuesta vacía.');
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.byteLength;
      if (size > 128 * 1024) {
        await reader.cancel();
        throw new ExtractionServiceError('Respuesta de Ollama demasiado grande.');
      }
      chunks.push(next.value);
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks).toString('utf8');
}
// Sin rutas HTTP, almacenamiento ni aprobación; la entrada actual es texto ficticio.
export function createLocalExtractor(options: { model?: string; fetchImpl?: typeof fetch } = {}) {
  const model = options.model ?? 'qwen3:4b-instruct';
  if (!/^[a-zA-Z0-9_.:-]+$/.test(model) || model.length > 100 || model.toLowerCase().includes('cloud')) {
    throw new ExtractionServiceError('Se requiere un identificador de modelo local.');
  }
  const fetchImpl = options.fetchImpl ?? fetch;
  return async function extract(text: string): Promise<LocalExtractionResult> {
    if (typeof text !== 'string' || !text.trim() || Buffer.byteLength(text, 'utf8') > 12000) {
      throw new ExtractionServiceError('El texto debe contener entre 1 y 12000 bytes.');
    }
    const started = performance.now();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 120000);
    try {
      const response = await fetchImpl(ollamaUrl('chat'), {
        method: 'POST', redirect: 'error', signal: controller.signal,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model, stream: false, format: schema,
          options: { temperature: 0, seed: 42, num_ctx: 4096, num_predict: 1600 },
          messages: [{ role: 'system', content: extractionPrompt }, { role: 'user', content: `DOCUMENTO FICTICIO:\n${text}` }],
        }),
      });
      if (!response.ok) throw new ExtractionServiceError(`Ollama respondió HTTP ${response.status}.`);
      const body = JSON.parse(await readBounded(response));
      if (body.done !== true || body.done_reason === 'length' || typeof body.message?.content !== 'string') {
        throw new ExtractionServiceError('Respuesta de Ollama incompleta o inválida.');
      }
      return { ...reviewExtraction(body.message.content), model, promptVersion: 3, elapsedMs: Math.round(performance.now() - started) };
    } catch (error) {
      if (error instanceof ExtractionServiceError) throw error;
      throw new ExtractionServiceError(controller.signal.aborted ? 'Ollama excedió el tiempo de espera.' : 'No se pudo obtener una respuesta válida de Ollama local.');
    } finally { clearTimeout(timer); }
  };
}
