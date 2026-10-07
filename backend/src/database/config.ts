import { z } from 'zod';

const schema = z.object({
  PGHOST: z.string().default('127.0.0.1'),
  PGPORT: z.coerce.number().int().min(1).max(65535).default(5432),
  PGDATABASE: z.string().min(1).max(63),
  PGUSER: z.string().min(1).max(63),
  PGPASSWORD: z.string().min(1),
});

// Solo desarrollo local en esta fase; nunca incluye valores en los errores.
export function readDatabaseConfig(env: NodeJS.ProcessEnv) {
  const result = schema.safeParse(env);
  if (!result.success || !['127.0.0.1','localhost','::1',...(env.VITALIA_RUNTIME==='container'?['postgres']:[])].includes(result.data.PGHOST)) {
    throw new Error('Configuración PostgreSQL inválida. Revisa las variables PG en .env.');
  }
  const value = result.data;
  return {
    host: value.PGHOST, port: value.PGPORT, database: value.PGDATABASE,
    user: value.PGUSER, password: value.PGPASSWORD,
  };
}
export type DatabaseConfig = ReturnType<typeof readDatabaseConfig>;
