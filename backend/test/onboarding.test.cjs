const express=require('express'),request=require('supertest');
jest.mock('../dist/auth/password',()=>({hashPassword:jest.fn(async()=> 'scrypt-v1$'+'a'.repeat(32)+'$'+'b'.repeat(128))}));
const {hashPassword}=require('../dist/auth/password');
const {createOnboardingService,authorizationInput,invitationInput,activationInput}=require('../dist/onboarding/service');
const {createOnboardingRouter}=require('../dist/onboarding/router');
const id='11111111-1111-4111-8111-111111111111',clinic='22222222-2222-4222-8222-222222222222';
const a={id,role:'administrador'},bearer='Bearer '+'a'.repeat(64);
const auth={requestId:id,nomineeEmail:'chief@example.invalid',requesterName:'Solicitante',requesterPosition:'Representante',requesterContact:'privado@example.invalid',evidenceReference:'ACTA-PRUEBA',requestedAt:'2026-01-01T00:00:00Z'};
const invite={requestId:id,email:'chief@example.invalid',authorizationId:id,branchIds:[],specialtyIds:[]};
const activation={token:'a'.repeat(64),firstName:'Persona',firstSurname:'Prueba',password:'Clave-larga-2026',confirmation:'Clave-larga-2026'};
function app(account=a){const svc=Object.fromEntries(['context','details','record','verify','revokeAuthorization','addSpecialty','invite','revoke','activate'].map(k=>[k,jest.fn(async()=>({ok:true}))]));const app=express();app.use(express.json());app.use('/api/onboarding',createOnboardingRouter({find:async()=>account},svc));return {app,svc};}
afterEach(()=>jest.clearAllMocks());
test.each(['record','verify','revokeAuthorization','addSpecialty'])('operación administrativa %s rechaza profesional antes de DB',async method=>{
 const query=jest.fn(),transaction=jest.fn();const s=createOnboardingService({query,transaction});await expect(s[method]({...a,role:'profesional'},clinic,id,{})).rejects.toMatchObject({status:403});expect(query).not.toHaveBeenCalled();expect(transaction).not.toHaveBeenCalled();
});
test.each([{verifiedBy:id},{role:'jefe_clinico'},{requesterName:' '},{nomineeEmail:'inválido'},{requestedAt:'ayer'}])('registro de autorización rechaza %j',extra=>expect(authorizationInput.safeParse({...auth,...extra}).success).toBe(false));
test.each([{actorId:id},{role:'administrador'},{clinicalRole:'jefe_clinico'},{branchIds:[id,id]},{specialtyIds:['x']},{email:'bad'}])('invitación rechaza %j',extra=>expect(invitationInput.safeParse({...invite,...extra}).success).toBe(false));
test.each([{email:'other@example.invalid'},{role:'administrador'},{password:'corta'},{confirmation:'diferente'},{token:'a'.repeat(63)},{firstName:' '},{password:'ñ'.repeat(600),confirmation:'ñ'.repeat(600)}])('activación rechaza %j',extra=>expect(activationInput.safeParse({...activation,...extra}).success).toBe(false));
test('normaliza correo y mantiene nombres proporcionados sin extraer identidad de un examen',()=>expect(authorizationInput.parse({...auth,nomineeEmail:' CHIEF@EXAMPLE.INVALID '}).nomineeEmail).toBe('chief@example.invalid'));
test('paciente no consulta contexto ni realiza operaciones',async()=>{const {app:ap,svc}=app({...a,role:'paciente'});expect((await request(ap).get('/api/onboarding/context').set('Authorization',bearer)).status).toBe(403);expect(svc.context).not.toHaveBeenCalled();});
test('solo activación es pública; usa POST, no query ni token en URL',async()=>{
 const {app:ap,svc}=app(null);
 expect((await request(ap).get('/api/onboarding/context')).status).toBe(401);
 expect((await request(ap).post('/api/onboarding/activate?token=secreto').send(activation)).status).toBe(400);expect(svc.activate).not.toHaveBeenCalled();
 const r=await request(ap).post('/api/onboarding/activate').send(activation);expect(r.status).toBe(200);expect(r.headers['cache-control']).toBe('no-store');expect(svc.activate).toHaveBeenCalledWith(activation);
});
test('API transmite actor desde sesión y clínica desde ruta',async()=>{const {app:ap,svc}=app();expect((await request(ap).post(`/api/onboarding/${clinic}/invitations`).set('Authorization',bearer).send(invite)).status).toBe(201);expect(svc.invite).toHaveBeenCalledWith(a,clinic,invite);});
test('verificación requiere confirmación explícita; no se infiere desde un registro',async()=>{const query=jest.fn(),transaction=jest.fn();await expect(createOnboardingService({query,transaction}).verify(a,clinic,id,{})).rejects.toMatchObject({status:400});expect(transaction).not.toHaveBeenCalled();});
test('fecha futura se rechaza sin acceder a base',async()=>{const transaction=jest.fn();await expect(createOnboardingService({transaction}).record(a,clinic,{...auth,requestedAt:'2999-01-01T00:00:00Z'})).rejects.toMatchObject({status:400});expect(transaction).not.toHaveBeenCalled();});
test('invitación de jefe exige autorización antes de crear token',async()=>{const query=jest.fn(async()=>({rows:[{id}]})),s=createOnboardingService({transaction:fn=>fn({query})});await expect(s.invite(a,clinic,{...invite,authorizationId:null})).rejects.toMatchObject({status:409,code:'AUTHORIZATION_REQUIRED'});expect(query.mock.calls.some(([q])=>q.startsWith('INSERT'))).toBe(false);});
test('autorización ajena, revocada o para otro correo no habilita invitación',async()=>{const query=jest.fn(async q=>({rows:q.includes('FROM public.vitalia_clinics')?[{id}]:[]})),s=createOnboardingService({transaction:fn=>fn({query})});await expect(s.invite(a,clinic,invite)).rejects.toMatchObject({status:409});const call=query.mock.calls.find(([q])=>q.includes('nominee_email=$3'));expect(call[1]).toEqual([clinic,id,invite.email]);expect(query.mock.calls.some(([q])=>q.startsWith('INSERT'))).toBe(false);});
test('token desconocido no calcula contraseña ni inicia transacción',async()=>{const query=jest.fn(async()=>({rows:[]})),transaction=jest.fn();await expect(createOnboardingService({query,transaction}).activate(activation)).rejects.toMatchObject({status:400});expect(hashPassword).not.toHaveBeenCalled();expect(transaction).not.toHaveBeenCalled();expect(query.mock.calls[0][1][0]).not.toBe(activation.token);});
test('activación simultánea se limita y libera cupo tras error',async()=>{
 let release;hashPassword.mockImplementationOnce(()=>new Promise(r=>{release=r}));
 const query=jest.fn(async()=>({rows:[{id,clinic_id:clinic}]}));const s=createOnboardingService({query,transaction:async()=>{throw {code:'42501'}}});
 const first=s.activate(activation);await new Promise(r=>setImmediate(r));
 await expect(s.activate(activation)).rejects.toMatchObject({status:429});release('hash');await expect(first).rejects.toMatchObject({status:503});
 await expect(s.activate(activation)).rejects.toMatchObject({status:503});
});
test('consulta de jefe no entrega autorizaciones institucionales ni tokens',async()=>{
 const query=jest.fn(async q=>({rows:q.includes('SELECT m.id')||q.includes('SELECT id FROM public.vitalia_clinics')?[{id}]:[]}));const s=createOnboardingService({transaction:fn=>fn({query})});const r=await s.details({...a,role:'profesional'},clinic);expect(r.authorizations).toEqual([]);expect(query.mock.calls.some(([q])=>q.includes('vitalia_institution_authorizations'))).toBe(false);expect(query.mock.calls.some(([q])=>q.includes('token_hash'))).toBe(false);
});
test('jefe ajeno no revoca una invitación',async()=>{const query=jest.fn(async()=>({rows:[]}));await expect(createOnboardingService({transaction:fn=>fn({query})}).revoke({...a,role:'profesional'},clinic,id)).rejects.toMatchObject({status:403});expect(query.mock.calls.some(([q])=>q.startsWith('UPDATE'))).toBe(false);});
test('fallo en auditoría impide informar autorización creada',async()=>{
 const query=jest.fn(async q=>{if(q.startsWith('INSERT INTO public.vitalia_onboarding_audit'))throw {code:'42501'};return {rows:[{id}]};});
 const transaction=jest.fn(fn=>fn({query}));await expect(createOnboardingService({transaction}).record(a,clinic,auth)).rejects.toMatchObject({status:503});expect(transaction).toHaveBeenCalledTimes(1);
});
test('recurso de exámenes no forma parte de incorporación',async()=>{const {app:ap}=app();expect((await request(ap).get(`/api/onboarding/${clinic}/exams`).set('Authorization',bearer)).status).toBe(404);});
