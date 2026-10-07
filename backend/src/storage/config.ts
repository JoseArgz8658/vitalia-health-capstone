import { z } from 'zod';

export interface StorageConfig { region: string; bucket: string }
export function readStorageConfig(env: NodeJS.ProcessEnv): StorageConfig {
  const parsed = z.object({
    AWS_REGION: z.string().regex(/^[a-z]{2}(?:-[a-z]+)+-\d$/),
    S3_BUCKET: z.string().min(3).max(63)
      .regex(/^[a-z0-9][a-z0-9-]*[a-z0-9]$/)
      .refine(value => !value.startsWith('xn--') &&
        !value.startsWith('sthree-') && !value.startsWith('amzn-s3-demo-') &&
        !['-s3alias', '--ol-s3', '.mrap', '--x-s3', '--table-s3'].some(s => value.endsWith(s))),
  }).safeParse(env);
  if (!parsed.success) throw new Error('Configura AWS_REGION y S3_BUCKET en .env.');
  return { region: parsed.data.AWS_REGION, bucket: parsed.data.S3_BUCKET };
}
