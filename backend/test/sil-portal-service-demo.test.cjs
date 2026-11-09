'use strict';
const {createSilPortalActivationDemo,PortalDemoInvalidCode,PortalDemoConflict}=
  require('../dist/sil/portal-activation-demo');
const patientId='33333333-3333-4333-8333-333333333333';
const operatorId='44444444-4444-4444-8444-444444444444';
const email='prueba-portal-unique@example.invalid';

function dbMock(){
 const calls=[];
 let tokenHashes=[];
 let attempts=0;
 let recent=0;
 const db={connect:async()=>({
   query:async(sql,args=[])=>{
     calls.push({sql,args});
     if(sql.includes('FROM public.vitalia_sil_portal_access_demo access')
       &&sql.includes('FOR UPDATE OF access')
       &&sql.includes('SELECT a.email,access.status')){
       return {rows:[{email,status:'pending',givenNames:'Paciente',
        familyNames:'Nuevo',syntheticIdentifier:'DEMO-TEST99',
        birthDate:'1990-01-01'}]};
     }
     if(sql.includes('COUNT(*)::int AS total'))return {rows:[{total:recent}]};
     if(sql.includes('INSERT INTO public.vitalia_sil_portal_invitations_demo')){
       tokenHashes=args.slice(0,5);
       return {rows:[]};
     }
     if(sql.includes('SELECT a.id AS "patientId"')){
       return {rows:[{
         patientId,status:'invited',invitationId:tokenHashes[0],
         emailTokenHash:tokenHashes[2],handoffTokenHash:tokenHashes[3],
         attempts,expiresAt:new Date(Date.now()+15*60*1000),
       }]};
     }
     if(sql.includes('SET attempts=')){attempts=args[1];return {rows:[]};}
     return {rows:[]};
   },
   release:()=>{},
 })};
 return {db,calls,getAttempts:()=>attempts,setRecent:(x)=>recent=x};
}
test('el operador no recibe el token de correo y el buzón simulado es separado',async()=>{
 const fixture=dbMock();
 const service=createSilPortalActivationDemo(fixture.db);
 const reply=await service.invite(patientId,operatorId,
   {contactConfirmed:true,identityChecked:true});
 expect(reply.handoffCode).toMatch(/^[A-Za-z0-9_-]{12}$/);
 expect(reply).not.toHaveProperty('emailCode');
 expect(JSON.stringify(reply)).not.toContain('emailTokenHash');
 const mail=service.demoMailbox(email);
 expect(mail.emailCode).toMatch(/^[A-Za-z0-9_-]{12}$/);
 expect(mail.emailCode).not.toBe(reply.handoffCode);
 expect(fixture.calls.some(q=>q.sql.includes('contact_confirmed_at'))).toBe(true);
 const audit=fixture.calls.find(q=>q.sql.includes("'invitation_sent_demo'"));
 expect(audit).toBeUndefined(); // acción parametrizada, no SQL interpolado
 expect(fixture.calls.some(q=>q.args.includes('invitation_sent_demo'))).toBe(true);
 expect(JSON.stringify(fixture.calls)).not.toContain(mail.emailCode);
 expect(JSON.stringify(fixture.calls)).not.toContain(reply.handoffCode);

 const activated=await service.activate({
   email,emailCode:mail.emailCode,handoffCode:reply.handoffCode,
   password:'ContraseñaSeguraNueva2026',confirmedDetails:true,
 });
 expect(activated).toEqual({activated:true,loginRequired:true});
 expect(fixture.calls.some(q=>q.sql.includes(
   'DELETE FROM public.vitalia_sessions WHERE account_id=$1'))).toBe(true);
 expect(fixture.calls.some(q=>q.sql.includes('SET active=true')
    &&q.sql.includes("role_code='paciente'"))).toBe(true);
 expect(fixture.calls.some(q=>q.args.includes('portal_activated'))).toBe(true);
 expect(service.demoMailbox(email)).not.toHaveProperty('emailCode');
});

test('código de canal incorrecto incrementa intentos y no modifica la contraseña',async()=>{
 const fixture=dbMock();
 const service=createSilPortalActivationDemo(fixture.db);
 const invitation=await service.invite(patientId,operatorId,
   {contactConfirmed:true,identityChecked:true});
 const mail=service.demoMailbox(email);
 await expect(service.activate({
   email,emailCode:mail.emailCode,handoffCode:'Z'.repeat(12),
   password:'ContraseñaSeguraNueva2026',confirmedDetails:true,
 })).rejects.toBeInstanceOf(PortalDemoInvalidCode);
 expect(fixture.getAttempts()).toBe(1);
 expect(fixture.calls.some(q=>q.sql.includes('UPDATE public.vitalia_accounts SET password_hash')))
   .toBe(false);
 expect(invitation.handoffCode).not.toBe('Z'.repeat(12));
});

test('límite de reenvíos evita generar una cuarta invitación',async()=>{
 const fixture=dbMock();
 fixture.setRecent(3);
 const service=createSilPortalActivationDemo(fixture.db);
 await expect(service.invite(patientId,operatorId,
   {contactConfirmed:true,identityChecked:true}))
  .rejects.toBeInstanceOf(PortalDemoConflict);
 expect(fixture.calls.some(q=>
  q.sql.includes('INSERT INTO public.vitalia_sil_portal_invitations_demo')))
  .toBe(false);
});

test('alta DEMO crea ficha sin habilitar rol web ni compartir contraseñas',async()=>{
 const fixture=dbMock();
 const service=createSilPortalActivationDemo(fixture.db);
 const result=await service.provision({
   email:'paciente-alta-demo@example.invalid',
   givenNames:'Paciente',familyNames:'Inventado',
   birthDate:'1991-02-03',sexForReference:'not_specified',
 },operatorId);
 expect(result.portalStatus).toBe('pending');
 expect(result.patient.syntheticIdentifier).toMatch(/^DEMO-[A-F0-9]{12}$/);
 expect(result).not.toHaveProperty('password');
 expect(fixture.calls.some(q=>
   q.sql.includes('SET active=false')&&q.sql.includes("role_code='paciente'")))
   .toBe(true);
 expect(fixture.calls.some(q=>q.args.includes('patient_provisioned'))).toBe(true);
 expect(fixture.calls.some(q=>q.sql.includes('COMMIT'))).toBe(true);
});
