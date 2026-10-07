import { Router } from 'express';
import { createLoginAttemptLimiter } from './login-limit';
import { type PatientRegistrar, RegistrationInputError, RegistrationBusyError } from './registration';

export function createRegistrationRouter(register: PatientRegistrar) {
  const router = Router();
  const allow = createLoginAttemptLimiter();
  router.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
  router.post('/register', async (req, res) => {
    if (!allow(req.ip ?? req.socket.remoteAddress ?? 'local')) {
      res.set('Retry-After', '900').status(429).json({
        error: { code: 'TOO_MANY_ATTEMPTS', message: 'Espera antes de volver a intentar.' },
      });
      return;
    }
    try { await register(req.body); }
    catch (error) {
      if (error instanceof RegistrationInputError) {
        res.status(400).json({ error: {
          code: 'INVALID_REGISTRATION',
          message: 'Revisa el correo y la contraseña: se requieren al menos 12 caracteres.',
        } });
        return;
      }
      if (error instanceof RegistrationBusyError) {
        res.set('Retry-After', '1').status(503).json({
          error: { code: 'REGISTRATION_BUSY', message: 'Intenta nuevamente en unos momentos.' },
        });
        return;
      }
      throw error;
    }
    res.status(202).json({ message: 'Solicitud de registro procesada.' });
  });
  return router;
}
