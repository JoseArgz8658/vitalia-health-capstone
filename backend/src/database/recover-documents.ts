import { type Pool, type PoolClient } from 'pg';
import { type S3Client } from '@aws-sdk/client-s3';
import { readDatabaseConfig } from './config';
import { createDatabasePool } from './pool';
import { readStorageConfig } from '../storage/config';
import { createStorageClient, checkPrivateBucket, deletePrivateDocument } from '../storage/s3';
import { previewRecovery, applyRecovery } from '../documents/recovery';

async function main(): Promise<void> {
  let pool: Pool | undefined;
  let client: PoolClient | undefined;
  let storage: S3Client | undefined;
  let failed = false;
  try {
    const args = process.argv.slice(2);
    if (args.length > 1 || (args.length === 1 && args[0] !== '--apply')) {
      throw new Error('Argumentos inválidos.');
    }
    pool = createDatabasePool(readDatabaseConfig(process.env));
    client = await pool.connect();
    if (args.length === 0) {
      const candidates = await previewRecovery(client);
      console.info('Cargas incompletas antiguas candidatas:', candidates.length);
      console.info('Solo consulta. No se modificó PostgreSQL ni S3.');
    } else {
      const config = readStorageConfig(process.env);
      storage = createStorageClient(config);
      await checkPrivateBucket(storage, config);
      const activeStorage = storage;
      const result = await applyRecovery(client, key => deletePrivateDocument(activeStorage, config, key));
      console.info('Recuperación:', JSON.stringify(result));
      if (result.failed) { failed = true; process.exitCode = 1; }
    }
  } catch {
    failed = true; process.exitCode = 1;
    console.error('No se pudo revisar o recuperar documentos. Revisa migración, PostgreSQL, S3 y permisos.');
  } finally {
    storage?.destroy();
    client?.release(failed);
    if (pool) { try { await pool.end(); } catch { process.exitCode = 1; } }
  }
}
void main();
