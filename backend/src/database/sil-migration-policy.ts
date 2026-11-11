/**
 * Política explícita de migraciones para los dos entornos históricos.
 * No concede permisos para alterar Vitalia principal: el cambio de esquema
 * exige un procedimiento separado, ensayado y aprobado.
 */
export const SIL_MAIN_LAST_REHEARSED = '032_sil_audit_download';

const migrationName = /^\d{3}_[a-z_]+\.sql$/;

export function silDemoMigrationPlan(files: string[], database: string,
  portalDemo: boolean): string[] {
  if (database !== 'vitalia_dev') {
    throw new Error('El migrador general solo admite la base aislada vitalia_dev. '
      + 'Vitalia principal necesita su migrador controlado y ensayado.');
  }
  if (!files.every(file => migrationName.test(file))) {
    throw new Error('Nombre de migración inesperado.');
  }
  const ordered = [...files].sort();
  if (ordered[0] !== '001_accounts.sql') {
    throw new Error('Migraciones base incompletas.');
  }
  const main = ordered.filter(file => {
    const num = Number(file.slice(0, 3));
    return num <= 35 || (portalDemo && num <= 37);
  });
  if (new Set(main.map(file => file.slice(0, 3))).size !== main.length) {
    throw new Error('Secuencia de migraciones ambigua.');
  }
  return main;
}

export function silMainRehearsedPlan(files: string[]): string[] {
  if (!files.every(file => migrationName.test(file))) {
    throw new Error('Nombre de migración inesperado.');
  }
  const byNumber = new Map<string, string>();
  for (const file of files) {
    const number = Number(file.slice(0, 3));
    if (number > 32) continue;
    const key = file.slice(0, 3);
    if (byNumber.has(key)) throw new Error('Migraciones duplicadas: ' + key);
    byNumber.set(key, file);
  }
  const expected = Array.from({length: 32}, (_, i) =>
    String(i + 1).padStart(3, '0'));
  for (const number of expected) {
    if (!byNumber.has(number)) throw new Error('Falta migración ' + number);
  }
  if (byNumber.get('012') !== '012_profiles_locations.sql' ||
    byNumber.get('025') !== '025_preliminary_assistant.sql' ||
    byNumber.get('032') !== '032_sil_audit_download.sql') {
    throw new Error('Historial SIL no corresponde al ensayo aprobado.');
  }
  // La 012 original (preliminary_assistant) no se reescribe ni se reaplica;
  // su versión histórica permanece en el ledger de Vitalia principal.
  return expected.slice(11).map(number => byNumber.get(number)!);
}
