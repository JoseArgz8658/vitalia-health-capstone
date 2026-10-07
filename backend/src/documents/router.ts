import { Router, type ErrorRequestHandler, type RequestHandler } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { type AuthServices } from '../auth/router';
import { isSessionToken } from '../auth/sessions';
import { type AccountSummary } from '../accounts/repository';
import { type DocumentServices, DocumentNotFoundError } from './service';
import { DocumentInputError, MAX_FILE_BYTES } from './file-validation';

export function createDocumentRouter(auth: Pick<AuthServices, 'find'>, services: DocumentServices) {
  const router = Router();
  router.use(async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    const parts = req.get('Authorization')?.split(' ');
    const token = parts?.length === 2 && parts[0].toLowerCase() === 'bearer' &&
      isSessionToken(parts[1]) ? parts[1] : null;
    const account = token ? await auth.find(token) : null;
    if (!account) {
      res.status(401).json({ error: { code: 'UNAUTHORIZED', message: 'Sesión no válida.' } }); return;
    }
    if (account.role !== 'paciente') {
      res.status(403).json({ error: { code: 'FORBIDDEN', message: 'Acceso no autorizado.' } }); return;
    }
    res.locals.account = account;
    next();
  });
  // Limita memoria de cargas simultáneas antes de recibir el cuerpo multipart.
  let active = 0;
  const capacity: RequestHandler = (_req, res, next) => {
    if (active >= 2) {
      res.set('Retry-After', '2').status(503).json({
        error: { code: 'UPLOAD_BUSY', message: 'Intenta nuevamente en unos momentos.' } }); return;
    }
    active++;
    let released = false;
    const release = () => { if (!released) { released = true; active--; } };
    res.once('finish', release); res.once('close', release);
    next();
  };
  const parse = multer({ storage: multer.memoryStorage(), limits: {
    fileSize: MAX_FILE_BYTES, files: 1, fields: 3, parts: 4, fieldSize: 1024,
  } }).single('file');
  router.post('/', capacity, parse, async (req, res) => {
    if (!req.file) throw new DocumentInputError('Falta archivo.');
    const item = await services.upload(res.locals.account as AccountSummary, {
      metadata: req.body, name: req.file.originalname, contentType: req.file.mimetype,
      body: req.file.buffer,
    });
    res.status(201).json({ document: item });
  });
  router.get('/', async (req, res) => {
    const parsed = z.object({
      limit: z.coerce.number().int().min(1).max(100).default(20),
      offset: z.coerce.number().int().min(0).max(10000).default(0),
    }).strict().safeParse(req.query);
    if (!parsed.success) throw new DocumentInputError('Paginación inválida.');
    res.json({ documents: await services.list(res.locals.account, parsed.data.limit, parsed.data.offset) });
  });
  router.get('/:id/file', capacity, async (req, res) => {
    if (!z.uuid().safeParse(req.params.id).success) throw new DocumentNotFoundError();
    const { item, body } = await services.download(res.locals.account, req.params.id as string);
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Content-Type', item.contentType);
    // Descarga adjunta: no incrusta documentos recibidos dentro de la aplicación.
    res.set('Content-Disposition', "attachment; filename*=UTF-8''" + encodeURIComponent(item.originalName));
    res.set('Content-Length', String(body.length));
    res.send(body);
  });
  const errors: ErrorRequestHandler = (error, _req, res, next) => {
    if (res.headersSent) { next(error); return; }
    if (error instanceof multer.MulterError || error instanceof DocumentInputError) {
      const large = error instanceof multer.MulterError && error.code === 'LIMIT_FILE_SIZE';
      res.status(large ? 413 : 400).json({ error: {
        code: large ? 'FILE_TOO_LARGE' : 'INVALID_DOCUMENT',
        message: large ? 'El archivo supera 10 MiB.' : 'Revisa el archivo y los datos del examen.',
      } }); return;
    }
    if (error instanceof DocumentNotFoundError) {
      res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Documento no disponible.' } }); return;
    }
    next(error);
  };
  router.use(errors);
  return router;
}
