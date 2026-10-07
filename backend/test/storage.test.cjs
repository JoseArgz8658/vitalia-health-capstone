const { readStorageConfig } = require('../dist/storage/config');
const { checkPrivateBucket, putPrivateDocument, readPrivateDocument, deletePrivateDocument } = require('../dist/storage/s3');
const cfg = { region: 'sa-east-1', bucket: 'vitalia-dev-prueba' };
const key = 'patients/11111111-1111-4111-8111-111111111111/documents/22222222-2222-4222-8222-222222222222';
function mockBucket(overrides = {}) {
  return { send: jest.fn(async command => {
    switch (command.constructor.name) {
      case 'GetPublicAccessBlockCommand': return { PublicAccessBlockConfiguration: {
        BlockPublicAcls: true, IgnorePublicAcls: true, BlockPublicPolicy: true, RestrictPublicBuckets: true,
        ...overrides } };
      case 'GetBucketOwnershipControlsCommand': return { OwnershipControls: { Rules: [{ ObjectOwnership: 'BucketOwnerEnforced' }] } };
      case 'GetBucketPolicyStatusCommand': return { PolicyStatus: { IsPublic: false } };
      default: return {};
    }
  }) };
}
test('configuración exige región y bucket sin secretos', () => {
  expect(readStorageConfig({ AWS_REGION: cfg.region, S3_BUCKET: cfg.bucket })).toEqual(cfg);
  expect(() => readStorageConfig({})).toThrow();
  expect(() => readStorageConfig({ AWS_REGION: 'bad', S3_BUCKET: 'https://bucket' })).toThrow();
});
test('comprobación solo consulta y acepta bucket bloqueado', async () => {
  const client = mockBucket();
  await checkPrivateBucket(client, cfg);
  expect(client.send.mock.calls.map(c => c[0].constructor.name)).toEqual([
    'HeadBucketCommand', 'GetPublicAccessBlockCommand',
    'GetBucketOwnershipControlsCommand', 'GetBucketPolicyStatusCommand']);
});
test('rechaza cada bloqueo público desactivado', async () => {
  for (const name of ['BlockPublicAcls', 'IgnorePublicAcls', 'BlockPublicPolicy', 'RestrictPublicBuckets']) {
    await expect(checkPrivateBucket(mockBucket({ [name]: false }), cfg)).rejects.toThrow();
  }
});
test('rechaza ACL habilitadas', async () => {
  const client = mockBucket();
  client.send.mockImplementation(async c => {
    if (c.constructor.name === 'GetPublicAccessBlockCommand') return {
      PublicAccessBlockConfiguration: { BlockPublicAcls: true, IgnorePublicAcls: true,
        BlockPublicPolicy: true, RestrictPublicBuckets: true } };
    return {};
  });
  await expect(checkPrivateBucket(client, cfg)).rejects.toThrow();
});
test('acepta ausencia de política, no oculta errores de permisos', async () => {
  for (const name of ['NoSuchBucketPolicy', 'AccessDenied']) {
    const client = mockBucket();
    const previous = client.send.getMockImplementation();
    client.send.mockImplementation(c => c.constructor.name === 'GetBucketPolicyStatusCommand'
      ? Promise.reject(Object.assign(new Error(), { name })) : previous(c));
    if (name === 'NoSuchBucketPolicy') await checkPrivateBucket(client, cfg);
    else await expect(checkPrivateBucket(client, cfg)).rejects.toThrow();
  }
});
test('carga con cifrado, sin ACL pública y sin sobrescribir', async () => {
  const client = mockBucket();
  await putPrivateDocument(client, cfg, key, Buffer.from('synthetic'), 'application/pdf');
  expect(client.send.mock.calls[0][0].input).toMatchObject({
    Bucket: cfg.bucket, Key: key, ServerSideEncryption: 'AES256', IfNoneMatch: '*' });
  expect(client.send.mock.calls[0][0].input.ACL).toBeUndefined();
});
test('rechaza clave arbitraria, cuerpo vacío y MIME no permitido antes de llamar S3', async () => {
  const client = mockBucket();
  await expect(putPrivateDocument(client, cfg, '../public', Buffer.from('x'), 'application/pdf')).rejects.toThrow();
  await expect(putPrivateDocument(client, cfg, key, Buffer.alloc(0), 'application/pdf')).rejects.toThrow();
  await expect(putPrivateDocument(client, cfg, key, Buffer.from('x'), 'text/html')).rejects.toThrow();
  expect(client.send).not.toHaveBeenCalled();
});
test('lectura y borrado usan únicamente la clave interna', async () => {
  const client = mockBucket();
  await readPrivateDocument(client, cfg, key);
  await deletePrivateDocument(client, cfg, key);
  expect(client.send.mock.calls.map(c => c[0].constructor.name)).toEqual(['GetObjectCommand', 'DeleteObjectCommand']);
});
