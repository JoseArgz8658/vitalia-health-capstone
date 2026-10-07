import { type RequestHandler } from 'express';

// Origen fijo para la revisión local; no habilita comodines ni credenciales.
export const localWebCors: RequestHandler = (req, res, next) => {
  const origin = req.get('Origin');
  if (!origin) { next(); return; }
  res.vary('Origin');
  if (origin !== 'http://localhost:5173') {
    res.status(403).json({ error: { code: 'ORIGIN_DENIED', message: 'Origen no autorizado.' } });
    return;
  }
  res.set('Access-Control-Allow-Origin', origin);
  if (req.method === 'OPTIONS') {
    const method = req.get('Access-Control-Request-Method');
    const headers = (req.get('Access-Control-Request-Headers') ?? '')
      .toLowerCase().split(',').map(h => h.trim()).filter(Boolean);
    if (!['GET', 'POST'].includes(method ?? '') ||
        headers.some(h => !['authorization', 'content-type'].includes(h))) {
      res.status(403).end(); return;
    }
    res.set('Access-Control-Allow-Methods', 'GET, POST');
    res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    res.status(204).end(); return;
  }
  next();
};
