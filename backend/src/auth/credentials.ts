import { randomBytes } from 'node:crypto';
import { type Pool } from 'pg';
import { z } from 'zod';
import { type AccountSummary, findAccountCredentialsByEmail } from '../accounts/repository';
import { hashPassword, verifyPassword } from './password';

const inputSchema = z.object({
  mode: z.enum(['paciente','profesional','administrador']).default('paciente'),
  email: z.string().trim().toLowerCase().pipe(z.email().max(254)),
  password: z.string().min(1).refine(value => Buffer.byteLength(value, 'utf8') <= 1024),
}).strict();

export type CredentialResult=AccountSummary & {professionalPasswordRequired?:true};

export class CredentialCheckBusyError extends Error {
  constructor() { super('Comprobación de credenciales ocupada.'); this.name = 'CredentialCheckBusyError'; }
}

// Crear una sola instancia al iniciar el servidor; todavía no genera sesiones.
export async function createCredentialAuthenticator(db: Pick<Pool, 'query'>) {
  const dummyHash = await hashPassword(randomBytes(32).toString('hex'));
  let checking = false;

  return async function authenticate(input: unknown): Promise<CredentialResult | null> {
    const parsed = inputSchema.safeParse(input);
    if (!parsed.success) return null;
    // Limita los cálculos scrypt concurrentes; no sustituye un límite de intentos.
    if (checking) throw new CredentialCheckBusyError();
    checking = true;
    try {
      const account = await findAccountCredentialsByEmail(db, parsed.data.email);
      const granted = account ? await db.query<{role_code:string,password_hash:string|null}>(
        'SELECT role_code,password_hash FROM public.vitalia_account_roles WHERE account_id=$1 AND role_code=$2 AND active',
        [account.id,parsed.data.mode]) : {rows:[]};
      const role = granted.rows.find(row=>row.role_code===parsed.data.mode);
      // La credencial original solo abre su modo; la excepción provisional obliga a configurar, sin sesión clínica.
      let setupOnly=false;
      let selectedHash = role?.password_hash ?? (account?.role===parsed.data.mode ? account.passwordHash : null);
      if(account?.role==='paciente'&&role&&parsed.data.mode==='profesional'&&!selectedHash){
        const patient=await db.query("SELECT role_code FROM public.vitalia_account_roles WHERE account_id=$1 AND role_code='paciente' AND active",[account.id]);
        if(patient.rows.length){selectedHash=account.passwordHash;setupOnly=true;}
      }
      const matches = await verifyPassword(parsed.data.password, selectedHash ?? dummyHash);
      if (!account || !role || !selectedHash || !matches) return null;
      return {
        id: account.id, email: account.email, role: parsed.data.mode, createdAt: account.createdAt,
        ...(setupOnly?{professionalPasswordRequired:true as const}:{}),
      };
    } finally {
      checking = false;
    }
  };
}
