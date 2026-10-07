import { createHash, randomBytes } from 'node:crypto';
import { type Pool } from 'pg';
import { type AccountRole, type AccountSummary } from '../accounts/repository';

type Queryable = Pick<Pool, 'query'>;
export interface SessionGrant { token: string; expiresAt: Date }
export function isSessionToken(token: string): boolean {
  return typeof token === 'string' && /^[a-f0-9]{64}$/.test(token);
}
function tokenHash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

// Sesiones opacas de 30 minutos. Nunca se persiste el token original.
export async function issueSession(db: Queryable, accountId: string): Promise<SessionGrant> {
  const token = randomBytes(32).toString('hex');
  const result = await db.query<{ expires_at: Date }>(
    `INSERT INTO public.vitalia_sessions (token_hash, account_id, expires_at)
     VALUES ($1, $2, CURRENT_TIMESTAMP + INTERVAL '30 minutes') RETURNING expires_at`,
    [tokenHash(token), accountId],
  );
  if (result.rows.length !== 1) throw new Error('No se pudo crear la sesión.');
  return { token, expiresAt: result.rows[0].expires_at };
}
export async function findSessionAccount(db: Queryable, token: string): Promise<AccountSummary | null> {
  if (!isSessionToken(token)) return null;
  const result = await db.query<{
    id: string; email: string; role_code: AccountRole; created_at: Date;
  }>(
    `SELECT a.id, a.email, a.role_code, a.created_at
     FROM public.vitalia_sessions s JOIN public.vitalia_accounts a ON a.id = s.account_id
     WHERE s.token_hash = $1 AND s.expires_at > CURRENT_TIMESTAMP`,
    [tokenHash(token)],
  );
  if (result.rows.length === 0) return null;
  const row = result.rows[0];
  return { id: row.id, email: row.email, role: row.role_code, createdAt: row.created_at };
}
export async function revokeSession(db: Queryable, token: string): Promise<void> {
  if (!isSessionToken(token)) return;
  await db.query('DELETE FROM public.vitalia_sessions WHERE token_hash = $1', [tokenHash(token)]);
}
