import { randomUUID } from 'node:crypto';
import { type Pool } from 'pg';
import { z } from 'zod';

type Queryable = Pick<Pool, 'query'>;
export type AccountRole = 'paciente' | 'profesional' | 'administrador';
export interface AccountSummary {
  id: string; email: string; role: AccountRole; createdAt: Date;
}
// Uso interno de autenticación; nunca devolver este objeto directamente desde una API.
export interface AccountCredentials extends AccountSummary { passwordHash: string }
interface AccountRow {
  id: string; email: string; role_code: AccountRole; created_at: Date; password_hash?: string;
}
const emailSchema = z.string().trim().toLowerCase().pipe(z.email().max(254));
const hashSchema = z.string().regex(/^scrypt-v1\$[a-f0-9]{32}\$[a-f0-9]{128}$/);
function normalizeEmail(email: string): string {
  const result = emailSchema.safeParse(email);
  if (!result.success) throw new Error('Correo de cuenta inválido.');
  return result.data;
}
function summary(row: AccountRow): AccountSummary {
  return { id: row.id, email: row.email, role: row.role_code, createdAt: row.created_at };
}
export class DuplicateEmailError extends Error {
  constructor() { super('El correo ya está registrado.'); this.name = 'DuplicateEmailError'; }
}

// Esta función siempre crea un paciente; el llamador no puede elegir un rol privilegiado.
export async function insertPatientAccount(
  db: Queryable, email: string, passwordHash: string,
): Promise<AccountSummary> {
  const normalized = normalizeEmail(email);
  if (!hashSchema.safeParse(passwordHash).success) throw new Error('Hash de contraseña inválido.');
  try {
    const result = await db.query<AccountRow>(
      `INSERT INTO public.vitalia_accounts (id, email, password_hash, role_code)
       VALUES ($1, $2, $3, 'paciente')
       RETURNING id, email, role_code, created_at`,
      [randomUUID(), normalized, passwordHash],
    );
    if (result.rows.length !== 1) throw new Error('No se pudo guardar la cuenta.');
    return summary(result.rows[0]);
  } catch (error) {
    const detail = error as { code?: string; constraint?: string };
    if (detail?.code === '23505' && detail.constraint === 'vitalia_accounts_email_key') {
      throw new DuplicateEmailError();
    }
    throw error;
  }
}

// Las entradas viajan como parámetros, nunca concatenadas al SQL.
export async function findAccountCredentialsByEmail(
  db: Queryable, email: string,
): Promise<AccountCredentials | null> {
  const result = await db.query<AccountRow>(
    `SELECT id, email, password_hash, role_code, created_at
     FROM public.vitalia_accounts WHERE email = $1`, [normalizeEmail(email)],
  );
  if (result.rows.length === 0) return null;
  const row = result.rows[0];
  if (!row.password_hash) throw new Error('Credenciales almacenadas inválidas.');
  return { ...summary(row), passwordHash: row.password_hash };
}
