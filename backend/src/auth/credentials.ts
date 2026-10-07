import { randomBytes } from 'node:crypto';
import { type Pool } from 'pg';
import { z } from 'zod';
import { type AccountSummary, findAccountCredentialsByEmail } from '../accounts/repository';
import { hashPassword, verifyPassword } from './password';

const inputSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email().max(254)),
  password: z.string().min(1).refine(value => Buffer.byteLength(value, 'utf8') <= 1024),
}).strict();

export class CredentialCheckBusyError extends Error {
  constructor() { super('Comprobación de credenciales ocupada.'); this.name = 'CredentialCheckBusyError'; }
}

// Crear una sola instancia al iniciar el servidor; todavía no genera sesiones.
export async function createCredentialAuthenticator(db: Pick<Pool, 'query'>) {
  const dummyHash = await hashPassword(randomBytes(32).toString('hex'));
  let checking = false;

  return async function authenticate(input: unknown): Promise<AccountSummary | null> {
    const parsed = inputSchema.safeParse(input);
    if (!parsed.success) return null;
    // Limita los cálculos scrypt concurrentes; no sustituye un límite de intentos.
    if (checking) throw new CredentialCheckBusyError();
    checking = true;
    try {
      const account = await findAccountCredentialsByEmail(db, parsed.data.email);
      // Una cuenta inexistente también ejecuta scrypt; no garantiza tiempos idénticos.
      const matches = await verifyPassword(parsed.data.password, account?.passwordHash ?? dummyHash);
      if (!account || !matches) return null;
      return {
        id: account.id, email: account.email, role: account.role, createdAt: account.createdAt,
      };
    } finally {
      checking = false;
    }
  };
}
