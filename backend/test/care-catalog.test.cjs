const request=require('supertest');
const {createApp}=require('../dist/app');
const {createCareCatalogService}=require('../dist/care/catalog');
const account={id:'11111111-1111-4111-8111-111111111111',role:'paciente',email:'paciente@example.invalid'};
const token='a'.repeat(64);
test.each(['profesional','administrador'])('%s no consulta catálogo de paciente',async role=>{
 const query=jest.fn();await expect(createCareCatalogService({query}).list({...account,role},{communeCode:'13125'})).rejects.toMatchObject({status:403});expect(query).not.toHaveBeenCalled();
});
test.each([{}, {communeCode:'Quilicura'},{communeCode:'13125',patientId:account.id},{communeCode:'13125',offset:-1},
 {communeCode:['13125','13101']},{communeCode:'13125',offset:'1.5'},{communeCode:'13125',clinicId:'x'},
 {communeCode:'13125',offset:'100001'},{communeCode:'13125',offset:''},{communeCode:'13125',offset:null},{communeCode:'13125',specialtyId:['x']}])('filtro inválido no consulta BD %j',async input=>{
 const query=jest.fn();await expect(createCareCatalogService({query}).list(account,input)).rejects.toMatchObject({status:400});expect(query).not.toHaveBeenCalled();
});
test('comuna válida sin profesionales es resultado vacío, no error',async()=>{
 const query=jest.fn(async()=>({rows:[{communeExists:true,items:[]}]}));
 expect(await createCareCatalogService({query}).list(account,{communeCode:'13125'})).toEqual({communeCode:'13125',items:[],nextOffset:null});
 expect(query.mock.calls[0][1]).toEqual(['13125',null,null,null,0]);
});
test('comuna inexistente no se presenta como falta de disponibilidad',async()=>{
 await expect(createCareCatalogService({query:async()=>({rows:[{communeExists:false,items:[]}]})}).list(account,{communeCode:'99999'})).rejects.toMatchObject({status:400,code:'INVALID_CARE_COMMUNE'});
});
test('página acotada y continuación explícita sin truncar silenciosamente',async()=>{
 const items=Array.from({length:31},(_,i)=>({membershipId:String(i)}));
 const query=jest.fn(async()=>({rows:[{communeExists:true,items}]}));
 const result=await createCareCatalogService({query}).list(account,{communeCode:'13125',offset:'30'});
 expect(result.items).toHaveLength(30);expect(result.nextOffset).toBe(60);expect(query.mock.calls[0][1].at(-1)).toBe(30);
});
test.each(['42P01','42703','42501'])('esquema/permisos %s devuelve indisponibilidad',async code=>{
 await expect(createCareCatalogService({query:async()=>{throw {code,message:'secreto'};}}).list(account,{communeCode:'13125'})).rejects.toMatchObject({status:503,code:'CARE_CATALOG_UNAVAILABLE'});
});
function app(a=account){const service={list:jest.fn(async()=>({items:[],nextOffset:null}))},auth={find:jest.fn(async()=>a)};
 return {app:createApp(auth,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,service),service,auth};}
test.each([undefined,'Bearer x',`Basic ${token}`])('sesión inválida %s no consulta catálogo',async header=>{
 const a=app();let r=request(a.app).get('/api/care/catalog?communeCode=13125');if(header)r=r.set('Authorization',header);
 const result=await r;expect(result.status).toBe(401);expect(result.headers['cache-control']).toBe('no-store');expect(a.auth.find).not.toHaveBeenCalled();expect(a.service.list).not.toHaveBeenCalled();
});
test.each([null,{...account,role:'profesional'},{...account,role:'administrador'}])('sesión expirada o rol incorrecto %j',async a=>{
 const x=app(a);expect((await request(x.app).get('/api/care/catalog?communeCode=13125').set('Authorization',`Bearer ${token}`)).status).toBe(a?403:401);expect(x.service.list).not.toHaveBeenCalled();
});
test('ruta utiliza cuenta de sesión y no almacena respuesta en caché',async()=>{
 const x=app();const r=await request(x.app).get('/api/care/catalog?communeCode=13125').set('Authorization',`Bearer ${token}`);
 expect(r.status).toBe(200);expect(r.headers['cache-control']).toBe('no-store');expect(x.service.list).toHaveBeenCalledWith(account,{communeCode:'13125'});
});
const {verifyCareCatalog}=require('../dist/database/care-catalog-verification');
test('verificador sin 020 revierte sin insertar',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(verifyCareCatalog({query})).rejects.toThrow('Falta migración 020.');
 expect(query.mock.calls.at(-1)[0]).toBe('ROLLBACK');expect(query.mock.calls.some(([q])=>q.startsWith('INSERT'))).toBe(false);
});
test('verificador con error de datos revierte y conserva causa',async()=>{
 const error=new Error('Fallo sintético'),query=jest.fn(async q=>{if(q.startsWith('SELECT version'))return {rows:[{}]};if(q.startsWith('SELECT lpad'))return {rows:[{code:'99998'},{code:'99999'}]};if(q.startsWith('INSERT'))throw error;return {rows:[]};});
 await expect(verifyCareCatalog({query})).rejects.toBe(error);expect(query.mock.calls.at(-1)[0]).toBe('ROLLBACK');
});
test('verificador sin conexión no intenta rollback',async()=>{
 const query=jest.fn().mockRejectedValue(new Error('Sin conexión'));await expect(verifyCareCatalog({query})).rejects.toThrow('Sin conexión');expect(query).toHaveBeenCalledTimes(1);
});
test('CLI no expone secretos con configuración inválida',()=>{
 const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['dist/database/verify-care-catalog.js'],{cwd:process.cwd(),encoding:'utf8',env:{...process.env,PGPORT:'inválido',PGPASSWORD:'no-exponer-clave'}});
 expect(r.status).toBe(1);expect(r.stderr).not.toContain('no-exponer-clave');
});
