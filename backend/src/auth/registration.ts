import { type Pool } from 'pg';
import { z } from 'zod';
import { DuplicateEmailError, insertPatientAccount } from '../accounts/repository';
import { hashPassword } from './password';

const schema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email().max(254)),
  password: z.string().refine(value =>
    Buffer.byteLength(value, 'utf8') <= 1024 && Array.from(value).length >= 12),
}).strict();

export class RegistrationInputError extends Error {
  constructor() { super('Datos de registro inválidos.'); this.name = 'RegistrationInputError'; }
}
export class RegistrationBusyError extends Error {
  constructor() { super('Registro ocupado.'); this.name = 'RegistrationBusyError'; }
}

// Instanciar una vez al arrancar; nunca permite seleccionar un rol privilegiado.
export function createPatientRegistrar(db: Pick<Pool, 'query'>) {
  let registering = false;
  return async function registerPatient(input: unknown): Promise<void> {
    const result = schema.safeParse(input);
    if (!result.success) throw new RegistrationInputError();
    if (registering) throw new RegistrationBusyError();
    registering = true;
    try {
      const passwordHash = await hashPassword(result.data.password);
      try {
        await insertPatientAccount(db, result.data.email, passwordHash);
      } catch (error) {
        // No cambia una cuenta existente ni revela al solicitante si el correo ya estaba registrado.
        if (!(error instanceof DuplicateEmailError)) throw error;
      }
    } finally {
      registering = false;
    }
  };
}
export type PatientRegistrar = ReturnType<typeof createPatientRegistrar>;
