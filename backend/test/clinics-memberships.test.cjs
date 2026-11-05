const {verifyClinicsMemberships}=require('../dist/database/clinics-memberships-verification');
const {applyAdditionalMigration}=require('../dist/database/additional-migration');
const fs=require('fs'),path=require('path');
const sql=fs.readFileSync(path.join(__dirname,'../database/migrations/013_clinics_memberships.sql'),'utf8');
test('verificador exige 013 y revierte sin insertar si falta',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(verifyClinicsMemberships({query})).rejects.toThrow('Falta migración 013');
 expect(query).toHaveBeenLastCalledWith('ROLLBACK');expect(query.mock.calls.some(([q])=>q.startsWith('INSERT'))).toBe(false);
});
test('verificador revierte si no puede preparar datos sintéticos',async()=>{
 const query=jest.fn(async q=>{if(q.startsWith('SELECT version'))return {rows:[{version:'013_clinics_memberships'}]};if(q.startsWith('INSERT'))throw Error('insertion failed');return {rows:[]};});
 await expect(verifyClinicsMemberships({query})).rejects.toThrow('insertion failed');expect(query).toHaveBeenLastCalledWith('ROLLBACK');
});
test('fallo al iniciar verificación no intenta revertir transacción inexistente',async()=>{
 const query=jest.fn(async()=>{throw Error('connection');});await expect(verifyClinicsMemberships({query})).rejects.toThrow('connection');expect(query).toHaveBeenCalledTimes(1);
});
test('aplicación 013 requiere 012 sin ejecutar DDL cuando falta',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(applyAdditionalMigration({query},'013_clinics_memberships',sql,'012_profiles_locations')).rejects.toThrow();
 expect(query.mock.calls.some(([q])=>q===sql)).toBe(false);expect(query).toHaveBeenLastCalledWith('ROLLBACK');
});
test('aplicación 013 revierte ante DDL fallido y no registra versión',async()=>{
 const query=jest.fn(async(q,args)=>{if(q===sql)throw Error('DDL');if(q.startsWith('SELECT version'))return {rows:[{version:'012_profiles_locations'}]};return {rows:[]};});
 await expect(applyAdditionalMigration({query},'013_clinics_memberships',sql,'012_profiles_locations')).rejects.toThrow('DDL');
 expect(query.mock.calls.some(([q])=>q.startsWith('INSERT INTO public.vitalia_schema_migrations'))).toBe(false);expect(query).toHaveBeenLastCalledWith('ROLLBACK');
});
