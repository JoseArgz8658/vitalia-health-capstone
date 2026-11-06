const express=require('express');const request=require('supertest');
const {normalizeRut,profileInput}=require('../dist/profiles/validation');
const {createProfileService}=require('../dist/profiles/service');
const {createProfileRouter}=require('../dist/profiles/router');
const patient={id:'11111111-1111-4111-8111-111111111111',role:'paciente'};
const valid={revision:null,firstName:'Ana',additionalNames:null,firstSurname:'Prueba',secondSurname:null,birthDate:null,phone:null,rut:null,preferredCommuneCode:null};
test.each([['12.345.678-5','12345678-5'],['123456785','12345678-5'],[' 6.000.000-k ','6000000-K'],['1-9','1-9']])('normaliza RUT %s sin verificar identidad',(input,expected)=>expect(normalizeRut(input)).toBe(expected));
test.each(['12345678-9','0-0','0012345678-5','12..345.678-5','12 345 678-5','<script>','12.345.678--5'])('rechaza RUT %s',input=>expect(normalizeRut(input)).toBeNull());
test.each([{role:'profesional'},{accountId:patient.id},{rutVerified:true},{birthDate:'2025-02-29'},{birthDate:'0000-01-01'},{birthDate:'2999-01-01'},{firstName:' '},{phone:''},{rut:'12.345.678-9'}])('rechaza campos o fechas inválidos %j',extra=>expect(profileInput.safeParse({...valid,...extra}).success).toBe(false));
test('guarda nombres normalizados y campos opcionales nulos',()=>expect(profileInput.parse({...valid,firstName:' Ana '}).firstName).toBe('Ana'));
test('perfil ajeno no puede consultarse por identificador enviado al servicio',async()=>{
 const db={transaction:jest.fn(async fn=>fn({query:jest.fn(async(sql,args)=>{expect(args).toEqual([patient.id]);return {rows:[]};})}))};
 expect(await createProfileService(db).get(patient)).toEqual({profile:null});
});
test('administrador no obtiene acceso al servicio de perfiles clínicos',async()=>{
 const db={transaction:jest.fn()};await expect(createProfileService(db).get({...patient,role:'administrador'})).rejects.toMatchObject({status:403});expect(db.transaction).not.toHaveBeenCalled();
});
test('rechaza un guardado obsoleto antes de escribir',async()=>{
 const query=jest.fn(async sql=>({rows:sql.startsWith('SELECT id FROM')?[{id:patient.id}]:[{id:'person',revision:'new-revision'}]}));
 const db={transaction:async fn=>fn({query})};
 await expect(createProfileService(db).save(patient,valid)).rejects.toMatchObject({status:409});
 expect(query.mock.calls.some(([sql])=>/^(INSERT|UPDATE)/.test(sql))).toBe(false);
});
test('faltan permisos: perfil no disponible sin exponer detalles',async()=>{
 const db={transaction:async()=>{throw {code:'42501',detail:'sensitive'};}};
 await expect(createProfileService(db).get(patient)).rejects.toMatchObject({status:503,code:'PROFILE_UNAVAILABLE'});
});
function app(account){const a=express();a.use(express.json());const service={get:jest.fn(async()=>({profile:null})),save:jest.fn(async()=>({profile:null}))};
 a.use('/api/profile',createProfileRouter({find:async()=>account},service));return {a,service};}
const bearer='Bearer '+'a'.repeat(64);
test('perfil exige sesión y no se cachea',async()=>{const {a,service}=app(patient);const res=await request(a).get('/api/profile');expect(res.status).toBe(401);expect(res.headers['cache-control']).toBe('no-store');expect(service.get).not.toHaveBeenCalled();});
test('no permite elegir otro paciente mediante query',async()=>{const {a,service}=app(patient);expect((await request(a).get('/api/profile?patientId=other').set('Authorization',bearer)).status).toBe(400);expect(service.get).not.toHaveBeenCalled();});
test('perfil deriva identidad de la sesión',async()=>{const {a,service}=app(patient);expect((await request(a).post('/api/profile').set('Authorization',bearer).send(valid)).status).toBe(200);expect(service.save).toHaveBeenCalledWith(patient,valid);});
