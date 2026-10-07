import {
  S3Client, HeadBucketCommand, GetPublicAccessBlockCommand,
  GetBucketOwnershipControlsCommand, GetBucketPolicyStatusCommand,
  PutObjectCommand, GetObjectCommand, DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { type StorageConfig } from './config';

export function createStorageClient(config: StorageConfig): S3Client {
  // La cadena de proveedores del SDK carga el perfil local o las credenciales temporales.
  return new S3Client({ region: config.region, maxAttempts: 2 });
}
function objectKey(key: string): void {
  if (!/^patients\/[0-9a-f-]{36}\/documents\/[0-9a-f-]{36}$/.test(key)) {
    throw new Error('Clave de documento inválida.');
  }
}
export async function checkPrivateBucket(client: S3Client, config: StorageConfig): Promise<void> {
  const options = { abortSignal: AbortSignal.timeout(15000) };
  await client.send(new HeadBucketCommand({ Bucket: config.bucket }), options);
  const result = await client.send(new GetPublicAccessBlockCommand({ Bucket: config.bucket }), options);
  const block = result.PublicAccessBlockConfiguration;
  if (!block?.BlockPublicAcls || !block.IgnorePublicAcls ||
      !block.BlockPublicPolicy || !block.RestrictPublicBuckets) {
    throw new Error('El bucket no tiene todos los bloqueos públicos habilitados.');
  }
  const ownership = await client.send(new GetBucketOwnershipControlsCommand({ Bucket: config.bucket }), options);
  if (!ownership.OwnershipControls?.Rules?.some(rule => rule.ObjectOwnership === 'BucketOwnerEnforced')) {
    throw new Error('El bucket debe tener ACL deshabilitadas.');
  }
  try {
    const policy = await client.send(new GetBucketPolicyStatusCommand({ Bucket: config.bucket }), options);
    if (policy.PolicyStatus?.IsPublic !== false) throw new Error('No se confirmó política privada.');
  } catch (error) {
    if ((error as { name?: string }).name !== 'NoSuchBucketPolicy') throw error;
  }
}
// Servicio interno: las rutas futuras comprobarán identidad y propiedad antes de usarlo.
export async function putPrivateDocument(client: S3Client, config: StorageConfig,
  key: string, body: Uint8Array, contentType: string): Promise<void> {
  objectKey(key);
  if (body.byteLength < 1 || body.byteLength > 10 * 1024 * 1024 ||
      !['application/pdf', 'image/jpeg', 'image/png'].includes(contentType)) {
    throw new Error('Archivo fuera de los límites de almacenamiento.');
  }
  await client.send(new PutObjectCommand({
    Bucket: config.bucket, Key: key, Body: body, ContentType: contentType,
    ContentLength: body.byteLength, ServerSideEncryption: 'AES256', IfNoneMatch: '*',
  }), { abortSignal: AbortSignal.timeout(30000) });
}
export async function readPrivateDocument(client: S3Client, config: StorageConfig, key: string) {
  objectKey(key);
  return client.send(new GetObjectCommand({ Bucket: config.bucket, Key: key }),
    { abortSignal: AbortSignal.timeout(15000) });
}
export async function deletePrivateDocument(client: S3Client, config: StorageConfig, key: string): Promise<void> {
  objectKey(key);
  await client.send(new DeleteObjectCommand({ Bucket: config.bucket, Key: key }),
    { abortSignal: AbortSignal.timeout(15000) });
}
