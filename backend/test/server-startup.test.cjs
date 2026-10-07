const { spawnSync } = require('node:child_process');
test('una configuración PostgreSQL inválida impide el arranque y no muestra secretos', () => {
  const result = spawnSync(process.execPath, ['dist/server.js'], {
    cwd: process.cwd(), encoding: 'utf8', timeout: 10000,
    env: { ...process.env, PGPORT: 'inválido', PGPASSWORD: 'secreto-sintético',
      PGDATABASE: 'vitalia_test', PGUSER: 'usuario_test' },
  });
  expect(result.error).toBeUndefined();
  expect(result.status).toBe(1);
  expect(result.stdout).toBe('');
  expect(result.stderr).toContain('No se pudo iniciar Vitalia API.');
  expect(result.stderr).not.toContain('secreto-sintético');
});
