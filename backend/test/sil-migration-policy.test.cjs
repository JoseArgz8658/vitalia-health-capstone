const {test,expect,describe}=require('@jest/globals');
const {readdirSync}=require('node:fs');
const {join}=require('node:path');
const {silDemoMigrationPlan,silMainRehearsedPlan,SIL_MAIN_LAST_REHEARSED}
  =require('../dist/database/sil-migration-policy');

const files=readdirSync(join(__dirname,'../database/migrations'))
  .filter(name=>/^\d{3}_[a-z_]+\.sql$/.test(name));

describe('Política de migraciones SIL',()=>{
  test('el migrador general jamás admite la base principal vitalia',()=>{
    expect(()=>silDemoMigrationPlan(files,'vitalia',false)).toThrow();
    expect(()=>silDemoMigrationPlan(files,'vitalia',true)).toThrow();
    expect(()=>silDemoMigrationPlan(files,'otra_base',false)).toThrow();
  });

  test('la demo conserva su ruta histórica solo en vitalia_dev',()=>{
    const old=silDemoMigrationPlan(files,'vitalia_dev',false);
    const portal=silDemoMigrationPlan(files,'vitalia_dev',true);
    expect(old.at(-1)).toBe('035_sil_retire_validator_role.sql');
    expect(old.some(name=>name.startsWith('036_'))).toBe(false);
    expect(portal.at(-1)).toBe('037_sil_patient_recovery_demo.sql');
  });

  test('el plan principal comienza en perfiles 012 y termina exactamente en 032',()=>{
    const plan=silMainRehearsedPlan(files);
    expect(plan).toHaveLength(21);
    expect(plan[0]).toBe('012_profiles_locations.sql');
    expect(plan.at(-1)).toBe('032_sil_audit_download.sql');
    expect(SIL_MAIN_LAST_REHEARSED).toBe('032_sil_audit_download');
    expect(plan.some(name=>/^(033|034|035|036|037|038)_/.test(name))).toBe(false);
  });

  test('rechaza migraciones incompletas o con numeración ambigua',()=>{
    expect(()=>silMainRehearsedPlan(files.filter(x=>!x.startsWith('017_')))).toThrow();
    expect(()=>silMainRehearsedPlan([...files,'012_another.sql'])).toThrow();
    expect(()=>silDemoMigrationPlan([...files,'026_another.sql'],'vitalia_dev',false)).toThrow();
    expect(()=>silMainRehearsedPlan([...files,'bad_name.sql'])).toThrow();
  });
});
