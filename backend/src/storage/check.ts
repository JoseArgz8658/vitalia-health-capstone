import { type S3Client } from '@aws-sdk/client-s3';
import { readStorageConfig } from './config';
import { createStorageClient, checkPrivateBucket } from './s3';

async function main(): Promise<void> {
  let client: S3Client | undefined;
  try {
    const config = readStorageConfig(process.env);
    client = createStorageClient(config);
    await checkPrivateBucket(client, config);
    console.info('Conexión a S3 correcta. Bloqueo público y ACL deshabilitadas comprobados.');
  } catch (error) {
    process.exitCode = 1;
    const name = String((error as { name?: string }).name ?? '');
    console.error('No se pudo comprobar S3. Revisa configuración, perfil AWS y permisos.');
    if (/^[A-Za-z0-9_]{2,60}$/.test(name)) console.error('Código técnico:', name);
  } finally { client?.destroy(); }
}
void main();
