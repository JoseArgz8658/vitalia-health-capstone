const {spawnSync}=require('node:child_process');
const {verifyProfilesLocations}=require('../dist/database/profiles-locations-verification');

test('la comprobación revierte si falta migración y no inserta datos',async()=>{
 const client={query:jest.fn(async()=>({rows:[]}))};
 await expect(verifyProfilesLocations(client)).rejects.toThrow('Falta migración 012.');
 expect(client.query.mock.calls.at(-1)[0]).toBe('ROLLBACK');
 expect(client.query.mock.calls.some(([sql])=>sql.startsWith('INSERT'))).toBe(false);
});
test('la comprobación revierte si un dato sintético falla durante su creación',async()=>{
 const original=new Error('Fallo sintético');
 const client={query:jest.fn(async(sql)=>{
  if(sql.startsWith('SELECT version'))return {rows:[{version:'012_profiles_locations'}]};
  if(sql.startsWith('INSERT'))throw original;
  return {rows:[]};
 })};
 await expect(verifyProfilesLocations(client)).rejects.toBe(original);
 expect(client.query.mock.calls.at(-1)[0]).toBe('ROLLBACK');
});
test('no revierte una transacción que no llegó a abrirse',async()=>{
 const client={query:jest.fn().mockRejectedValue(new Error('Sin conexión'))};
 await expect(verifyProfilesLocations(client)).rejects.toThrow('Sin conexión');
 expect(client.query).toHaveBeenCalledTimes(1);
});
test.each(['migrate-profiles-locations','verify-profiles-locations'])('%s rechaza configuración inválida sin mostrar credenciales',file=>{
 const result=spawnSync(process.execPath,[`dist/database/${file}.js`],{
  cwd:process.cwd(),encoding:'utf8',env:{...process.env,PGPORT:'inválido',PGPASSWORD:'no-mostrar-secreto'}
 });
 expect(result.status).toBe(1);expect(result.stderr).not.toContain('no-mostrar-secreto');
 expect(result.stderr).toContain(file.startsWith('migrate')?'No se pudo aplicar':'No se pudo verificar');
});
