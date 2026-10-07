import { z } from 'zod';

// La aplicación valida configuración sin imprimir valores de entorno.
const schema = z.object({
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  HOST: z.string().min(1).default('127.0.0.1'),
});
export function readConfig(env: NodeJS.ProcessEnv) {
  const result = schema.safeParse(env);
  if (!result.success) throw new Error('Configuración de servidor inválida. Revisa HOST y PORT.');
  return result.data;
}
