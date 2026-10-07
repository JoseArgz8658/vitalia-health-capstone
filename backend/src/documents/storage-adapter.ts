import { type S3Client } from '@aws-sdk/client-s3';
import { type StorageConfig } from '../storage/config';
import { putPrivateDocument, readPrivateDocument, deletePrivateDocument } from '../storage/s3';
import { type DocumentStorage } from './service';
import { MAX_FILE_BYTES } from './file-validation';

export function s3DocumentStorage(client: S3Client, config: StorageConfig): DocumentStorage {
  return {
    put: (key, body, contentType) => putPrivateDocument(client, config, key, body, contentType),
    remove: key => deletePrivateDocument(client, config, key),
    async read(key) {
      const result = await readPrivateDocument(client, config, key);
      const stream = result.Body;
      if (!stream) throw new Error('Objeto sin contenido.');
      const chunks: Buffer[] = [];
      let length = 0;
      try {
        for await (const chunk of stream as unknown as AsyncIterable<Uint8Array>) {
          length += chunk.length;
          if (length > MAX_FILE_BYTES) throw new Error('Objeto supera el límite.');
          chunks.push(Buffer.from(chunk));
        }
        return Buffer.concat(chunks);
      } finally {
        if ('destroy' in stream && typeof stream.destroy === 'function') stream.destroy();
      }
    },
  };
}
