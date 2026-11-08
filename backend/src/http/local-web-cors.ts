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
    // Los encabezados adicionales se autorizan solo para la carga PDF
    // del entorno SIL demo. No se amplía CORS para el resto de la API.
    const reportUpload = process.env.VITALIA_SIL_DEMO === 'YES' &&
      /^\/api\/sil\/orders\/[a-f0-9-]{36}\/report$/.test(req.path);
    const medicalRequestUpload=process.env.VITALIA_SIL_DEMO==='YES' &&
      req.path==='/api/sil/medical-requests/preview';
    const allowed = ['authorization', 'content-type'];
    if(medicalRequestUpload)allowed.push(
      'x-request-patient-email','x-request-filename',
    );
    if (reportUpload) allowed.push(
      'x-report-filename',
      'x-report-branch-code',
      'x-report-authorized-professional',
      'x-report-patient-identifier',
      'x-report-authorization-ref',
      'x-report-authorized-at',
      'x-report-patient-confirmed',
      'x-report-externally-authorized',
    );
    if (!['GET', 'POST'].includes(method ?? '') ||
        headers.some(h => !allowed.includes(h))) {
      res.status(403).end(); return;
    }
    res.set('Access-Control-Allow-Methods', 'GET, POST');
    res.set('Access-Control-Allow-Headers', allowed.join(', '));
    res.status(204).end(); return;
  }
  next();
};
