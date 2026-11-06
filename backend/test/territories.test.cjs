const request=require('supertest');const express=require('express');
const {createTerritoryService,CATALOG_VERSION}=require('../dist/profiles/territories');
const {validateTerritorialCatalog,loadTerritorialCatalog}=require('../dist/database/territorial-catalog');
const {createProfileRouter}=require('../dist/profiles/router');
const {profileInput}=require('../dist/profiles/validation');
const data=require('../database/catalogs/chile-cut-2018.json');
const patient={id:'11111111-1111-4111-8111-111111111111',role:'paciente'};
const clone=()=>structuredClone(data);
function rows(d=data){return [...d.regions.map(x=>({kind:'region',...x,parent:null})),...d.provinces.map(x=>({kind:'province',code:x.code,name:x.name,parent:x.regionCode})),...d.communes.map(x=>({kind:'commune',code:x.code,name:x.name,parent:x.provinceCode}))];}
test('catálogo oficial conserva códigos con ceros, Ñuble y jerarquía completa',()=>{
 expect(validateTerritorialCatalog(data)).toEqual(data);
 expect(data.regions).toHaveLength(16);expect(data.provinces).toHaveLength(56);expect(data.communes).toHaveLength(346);
 expect(data.communes.find(x=>x.code==='01101').name).toBe('Iquique');
 expect(data.communes.find(x=>x.name==='Quilicura').code).toBe('13125');
 expect(data.regions.find(x=>x.code==='16').name).toBe('Ñuble');
});
test.each(['duplicate','parent','missing','unexpected','version'])('rechaza catálogo alterado: %s',change=>{
 const d=clone();if(change==='duplicate')d.communes[1].code=d.communes[0].code;
 if(change==='parent')d.provinces[0].regionCode='16';if(change==='missing')d.communes.pop();
 if(change==='unexpected')d.person='sensitive';if(change==='version')d.version='latest';
 expect(()=>validateTerritorialCatalog(d)).toThrow();
});
test('servicio devuelve solo códigos/nombres/relaciones y no consulta identidades',async()=>{
 const query=jest.fn(async()=>({rows:rows()}));const result=await createTerritoryService({query})(patient);
 expect(result).toEqual(data);expect(query).toHaveBeenCalledTimes(1);expect(query.mock.calls[0][0]).not.toMatch(/vitalia_people|accounts|identifiers/);
});
test.each(['administrador','other'])('catálogo no concede acceso a %s',async role=>{
 const query=jest.fn();await expect(createTerritoryService({query})({...patient,role})).rejects.toMatchObject({status:403});expect(query).not.toHaveBeenCalled();
});
test.each(['empty','permission','missing_table'])('catálogo no disponible: %s',async scenario=>{
 const query=async()=>{if(scenario==='empty')return {rows:[]};throw {code:scenario==='permission'?'42501':'42P01',detail:'private'};};
 await expect(createTerritoryService({query})(patient)).rejects.toMatchObject({status:503,code:'TERRITORIES_UNAVAILABLE'});
});
function fakeDb(initial={}){
 const state=Object.fromEntries(['vitalia_regions','vitalia_provinces','vitalia_communes'].map(x=>[x,structuredClone(initial[x]??[])]));
 const query=jest.fn(async(sql,args)=>{
  if(sql.includes('vitalia_schema_migrations'))return {rows:[{version:'012_profiles_locations'}]};
  for(const table of Object.keys(state)){
   if(sql.startsWith('SELECT code,name')&&sql.includes(table))return {rows:state[table]};
   if(sql.startsWith('INSERT INTO public.'+table)){state[table].push(...JSON.parse(args[0]));return {rows:[]};}
  }return {rows:[]};
 });return {query,state};
}
test('carga aditiva e idempotente, sin UPDATE DELETE ni migración nueva',async()=>{
 const db=fakeDb();expect(await loadTerritorialCatalog(db,data)).toBe('loaded');
 expect(await loadTerritorialCatalog(db,data)).toBe('unchanged');
 expect(db.state.vitalia_communes).toHaveLength(346);
 expect(db.query.mock.calls.some(([sql])=>/^(UPDATE|DELETE|DROP|ALTER)/.test(sql))).toBe(false);
});
test('dato territorial distinto revierte y nunca se sobrescribe',async()=>{
 const db=fakeDb({vitalia_regions:[{code:'01',name:'No corresponde'}]});
 await expect(loadTerritorialCatalog(db,data)).rejects.toThrow();
 expect(db.query).toHaveBeenLastCalledWith('ROLLBACK');expect(db.query.mock.calls.some(([sql])=>sql.startsWith('INSERT'))).toBe(false);
});
test('requisito 012 y fallo de inserción se revierten',async()=>{
 for(const mode of ['no_migration','write_error']){
  const db=fakeDb();const base=db.query.getMockImplementation();db.query.mockImplementation(async(sql,args)=>{
   if(mode==='no_migration'&&sql.includes('vitalia_schema_migrations'))return {rows:[]};
   if(mode==='write_error'&&sql.startsWith('INSERT'))throw Error('error');return base(sql,args);
  });await expect(loadTerritorialCatalog(db,data)).rejects.toThrow();expect(db.query).toHaveBeenLastCalledWith('ROLLBACK');
 }
});
test('código de comuna solo de cinco dígitos o null; no acepta identidad regional del cliente',()=>{
 const p={revision:null,firstName:'Ana',additionalNames:null,firstSurname:'Prueba',secondSurname:null,birthDate:null,phone:null,rut:null,preferredCommuneCode:'01101'};
 expect(profileInput.safeParse(p).success).toBe(true);expect(profileInput.safeParse({...p,preferredCommuneCode:null}).success).toBe(true);
 for(const x of ['1101','01101 OR 1=1','abcde'])expect(profileInput.safeParse({...p,preferredCommuneCode:x}).success).toBe(false);
 expect(profileInput.safeParse({...p,regionCode:'01'}).success).toBe(false);
});
test('ruta catálogo requiere sesión, rechaza parámetros y no cachea',async()=>{
 const app=express(),service={territories:jest.fn(async()=>data)};app.use('/api/profile',createProfileRouter({find:async()=>patient},service));
 expect((await request(app).get('/api/profile/territories')).status).toBe(401);
 const bearer='Bearer '+'a'.repeat(64);
 expect((await request(app).get('/api/profile/territories?patientId=other').set('Authorization',bearer)).status).toBe(400);
 const r=await request(app).get('/api/profile/territories').set('Authorization',bearer);expect(r.status).toBe(200);expect(r.headers['cache-control']).toBe('no-store');expect(r.body.version).toBe(CATALOG_VERSION);
 expect(service.territories).toHaveBeenCalledTimes(1);expect(service.territories).toHaveBeenCalledWith(patient);
});
