import { createHash, randomBytes } from 'node:crypto';
import { type Pool } from 'pg';
import { accountRoleSchema, type AccountRole, type AccountSummary } from '../accounts/repository';

type Queryable = Pick<Pool, 'query'>;
export interface SessionGrant { token: string; expiresAt: Date }
export function isSessionToken(token: string): boolean {
  return typeof token === 'string' && /^[a-f0-9]{64}$/.test(token);
}
function tokenHash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

// Sesiones opacas de 30 minutos. Nunca se persiste el token original.
export class SessionCredentialChangedError extends Error {}

export async function issueSession(
  db: Queryable, accountId: string, mode: AccountRole = 'paciente', patientCredentialHash?:string,
): Promise<SessionGrant> {
  if (!accountRoleSchema.safeParse(mode).success) throw new Error('Modo de acceso no autorizado.');
  const token = randomBytes(32).toString('hex');
  // En la demo, la recuperación bloquea la misma cuenta antes de cambiar su clave.
  // Una autenticación que comprobó la clave anterior no puede emitir una sesión tardía.
  const result = await db.query<{ expires_at: Date }>(patientCredentialHash!==undefined
    ? `WITH verified AS MATERIALIZED (
         SELECT id FROM public.vitalia_accounts
         WHERE id=$2 AND role_code='paciente' AND password_hash=$4 FOR SHARE
       )
       INSERT INTO public.vitalia_sessions (token_hash,account_id,active_role,expires_at)
       SELECT $1,$2,$3,CURRENT_TIMESTAMP + INTERVAL '30 minutes'
       FROM public.vitalia_account_roles
       WHERE account_id=$2 AND role_code=$3 AND active AND EXISTS(SELECT 1 FROM verified)
       RETURNING expires_at` :
    `INSERT INTO public.vitalia_sessions (token_hash, account_id, active_role, expires_at)
     SELECT $1, $2, $3, CURRENT_TIMESTAMP + INTERVAL '30 minutes'
     FROM public.vitalia_account_roles WHERE account_id=$2 AND role_code=$3 AND active RETURNING expires_at`,
    [tokenHash(token), accountId, mode, ...(patientCredentialHash===undefined?[]:[patientCredentialHash])],
  );
  if(result.rows.length!==1){
    if(patientCredentialHash!==undefined)throw new SessionCredentialChangedError();
    throw new Error('No se pudo crear la sesión.');
  }
  return { token, expiresAt: result.rows[0].expires_at };
}
export async function findSessionAccount(db: Queryable, token: string): Promise<AccountSummary | null> {
  if (!isSessionToken(token)) return null;
  const result = await db.query<{
    id: string; email: string; role_code: string; created_at: Date;
  }>(
    `SELECT a.id, a.email, s.active_role AS role_code, a.created_at
     FROM public.vitalia_sessions s JOIN public.vitalia_accounts a ON a.id = s.account_id
     JOIN public.vitalia_account_roles g ON g.account_id=s.account_id AND g.role_code=s.active_role AND g.active
     WHERE (g.password_hash IS NOT NULL OR g.role_code=a.role_code) AND s.token_hash = $1 AND s.expires_at > CURRENT_TIMESTAMP`,
    [tokenHash(token)],
  );
  if (result.rows.length === 0) return null;
  const row = result.rows[0];
  const role = accountRoleSchema.safeParse(row.role_code);
  if (!role.success) return null;
  return { id: row.id, email: row.email, role: role.data, createdAt: row.created_at };
}
export async function revokeSession(db: Queryable, token: string): Promise<void> {
  if (!isSessionToken(token)) return;
  await db.query('DELETE FROM public.vitalia_sessions WHERE token_hash = $1', [tokenHash(token)]);
}
