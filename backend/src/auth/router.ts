import { Router } from 'express';
import { type AccountSummary } from '../accounts/repository';
import { CredentialCheckBusyError } from './credentials';
import { type SessionGrant, isSessionToken } from './sessions';
import { createLoginAttemptLimiter } from './login-limit';

export interface AuthServices {
  authenticate(input: unknown): Promise<AccountSummary | null>;
  issue(accountId: string): Promise<SessionGrant>;
  find(token: string): Promise<AccountSummary | null>;
  revoke(token: string): Promise<void>;
}
function bearer(header: string | undefined): string | null {
  const parts = header?.split(' ');
  if (!parts || parts.length !== 2 || parts[0].toLowerCase() !== 'bearer'
    || !isSessionToken(parts[1])) return null;
  return parts[1];
}
function safeUser(user: AccountSummary): AccountSummary {
  return { id: user.id, email: user.email, role: user.role, createdAt: user.createdAt };
}
export function createAuthRouter(services: AuthServices) {
  const router = Router();
  const allow = createLoginAttemptLimiter();
  router.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
  router.post('/login', async (req, res) => {
    if (!allow(req.ip ?? req.socket.remoteAddress ?? 'local')) {
      res.set('Retry-After', '900').status(429).json({
        error: { code: 'TOO_MANY_ATTEMPTS', message: 'Espera antes de volver a intentar.' },
      });
      return;
    }
    let user: AccountSummary | null;
    try { user = await services.authenticate(req.body); }
    catch (error) {
      if (!(error instanceof CredentialCheckBusyError)) throw error;
      res.set('Retry-After', '1').status(503).json({
        error: { code: 'AUTH_BUSY', message: 'Intenta nuevamente en unos momentos.' },
      });
      return;
    }
    if (!user) {
      res.status(401).json({ error: { code: 'INVALID_CREDENTIALS', message: 'Correo o contraseña incorrectos.' } });
      return;
    }
    const grant = await services.issue(user.id);
    res.status(200).json({ token: grant.token, expiresAt: grant.expiresAt, user: safeUser(user) });
  });
  router.get('/me', async (req, res) => {
    const token = bearer(req.get('Authorization'));
    const user = token ? await services.find(token) : null;
    if (!user) {
      res.status(401).json({ error: { code: 'UNAUTHORIZED', message: 'Sesión no válida.' } });
      return;
    }
    res.json({ user: safeUser(user) });
  });
  router.post('/logout', async (req, res) => {
    const token = bearer(req.get('Authorization'));
    if (!token) {
      res.status(401).json({ error: { code: 'UNAUTHORIZED', message: 'Sesión no válida.' } });
      return;
    }
    await services.revoke(token);
    res.status(204).end();
  });
  return router;
}
