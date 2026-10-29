import {extractReportBlocks,ReportBlockError} from './report-blocks';
import {ollamaUrl} from '../runtime/local-services';
import {reportExtractionPrompt} from './report-prompt';
import { extractionPrompt, schema } from './prompt';
import { reviewExtraction, type ExtractionReview } from './contract';
export type ExtractionFailureReason = 'configuration'|'input'|'http'|'transport'|'timeout'|'response_limit'|'invalid_json'|'incomplete';
export class ExtractionServiceError extends Error {
  constructor(message: string, public readonly reason: ExtractionFailureReason = 'transport') { super(message); this.name = 'ExtractionServiceError'; }
}
export type LocalExtractionResult = ExtractionReview & { model: string; promptVersion: 3|4; elapsedMs: number };
async function readBounded(response: Response): Promise<string> {
  if (!response.body) throw new ExtractionServiceError('Ollama devolvió una respuesta vacía.', 'incomplete');
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
        throw new ExtractionServiceError('Respuesta de Ollama demasiado grande.', 'response_limit');
      }
      chunks.push(next.value);
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks).toString('utf8');
}
// Sin rutas HTTP, almacenamiento ni aprobación; la entrada actual es texto ficticio.
export function createLocalExtractor(options: { model?: string; fetchImpl?: typeof fetch; promptVersion?:3|4 } = {}) {
  const model = options.model ?? 'qwen3:4b-instruct';
  if (!/^[a-zA-Z0-9_.:-]+$/.test(model) || model.length > 100 || model.toLowerCase().includes('cloud')) {
    throw new ExtractionServiceError('Se requiere un identificador de modelo local.', 'configuration');
  }
  const fetchImpl = options.fetchImpl ?? fetch;
  const version=options.promptVersion??3;
  if(![3,4].includes(version))throw new ExtractionServiceError('Versión de extracción inválida.', 'configuration');
  return async function extract(text: string): Promise<LocalExtractionResult> {
    if (typeof text !== 'string' || !text.trim() || Buffer.byteLength(text, 'utf8') > 12000) {
      throw new ExtractionServiceError('El texto debe contener entre 1 y 12000 bytes.', 'input');
    }
    const started = performance.now();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), version===4?360000:120000);
    try {
      const generate = async (format: object, input: string, instruction = ''): Promise<string> => {
      const blockStarted = performance.now();
      const blockController = new AbortController();
      const abort = () => blockController.abort();
      controller.signal.addEventListener('abort', abort, {once:true});
      if (controller.signal.aborted) abort();
      const blockTimer = setTimeout(abort,180000);
      try {
      const response = await fetchImpl(ollamaUrl('chat'), {
        method: 'POST', redirect: 'error', signal: blockController.signal,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model, stream: false, format,
          options: { temperature: 0, seed: 42, num_ctx: 4096, num_predict: version===4?2048:1600 },
          messages: [{ role: 'system', content: (version===4?reportExtractionPrompt:extractionPrompt)+instruction }, { role: 'user', content: `${version===3?'DOCUMENTO FICTICIO':'DOCUMENTO'}:\n${input}` }],
        }),
      });
      if (!response.ok) throw new ExtractionServiceError(`Ollama respondió HTTP ${response.status}.`, 'http');
      const responseText = await readBounded(response);
      let body;
      try { body = JSON.parse(responseText); } catch { throw new ExtractionServiceError('Formato de transporte inválido.', 'invalid_json'); }
      console.info(JSON.stringify({event:'ollama_extraction_block',elapsedMs:Math.round(performance.now()-blockStarted),done:body.done,doneReason:body.done_reason,outputChars:typeof body.message?.content==='string'?body.message.content.length:null,evalCount:body.eval_count,evalDuration:body.eval_duration}));
      if (body.done !== true || body.done_reason === 'length' || typeof body.message?.content !== 'string') {
        throw new ExtractionServiceError('Respuesta de Ollama incompleta o inválida.', 'incomplete');
      }
      return body.message.content;
      } catch(error) {
        if(blockController.signal.aborted)throw new ExtractionServiceError('Límite de tiempo de extracción.', 'timeout');
        throw error;
      } finally {clearTimeout(blockTimer);controller.signal.removeEventListener('abort',abort);}
      };
      const raw = version===4 ? await extractReportBlocks(text,generate) : await generate(schema,text);
      return {
  ...reviewExtraction(raw, version === 4, text),
  model,
  promptVersion: version,
  elapsedMs: Math.round(performance.now() - started)
};
    } catch (error) {
      const failure = error instanceof ExtractionServiceError ? error : new ExtractionServiceError(
        'No se pudo obtener una respuesta válida de Ollama local.',
        controller.signal.aborted ? 'timeout' : error instanceof SyntaxError ? 'invalid_json' : error instanceof ReportBlockError ? 'incomplete' : 'transport');
      console.warn(JSON.stringify({event: 'document_extraction_failure', reason: failure.reason, promptVersion: version, elapsedMs: Math.round(performance.now() - started)}));
      throw failure;
    } finally { clearTimeout(timer); }
  };
}
