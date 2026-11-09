'use strict';
// Solo uso local con PostgreSQL aislado de demostración.
// Credenciales elegidas por el usuario y suministradas por variables de entorno.
// Nunca imprime contraseñas ni elimina las cuentas al reiniciarse.
const express=require('express');
const {Pool}=require('pg');
const {randomUUID}=require('node:crypto');
const {createAuthRouter}=require('../dist/auth/router');
const {createSilRouter}=require('../dist/sil/router');
const {createSilService}=require('../dist/sil/service');
const {createSilPortalRouterDemo}=require('../dist/sil/portal-router-demo');
const {createSilPortalActivationDemo}=require('../dist/sil/portal-activation-demo');
const {createCredentialAuthenticator}=require('../dist/auth/credentials');
const {hashPassword}=require('../dist/auth/password');
const {issueSession,findSessionAccount,revokeSession}=require('../dist/auth/sessions');
const {localWebCors}=require('../dist/http/local-web-cors');

async function main(){
  if(process.env.VITALIA_SIL_DEMO!=='YES' ||
     process.env.PGHOST!=='postgres' ||
     process.env.PGDATABASE!=='vitalia_dev' ||
     process.env.PGUSER!=='vitalia' ||
     !process.env.PGPASSWORD) {
    throw new Error('Solo se permite la base Docker aislada vitalia_dev.');
  }
  const operatorPassword=process.env.VITALIA_SIL_OPERATOR_PASSWORD;
  const adminPassword=process.env.VITALIA_SIL_ADMIN_PASSWORD;
  const patientPassword=process.env.VITALIA_SIL_PATIENT_PASSWORD;
  if(!operatorPassword || !adminPassword || !patientPassword ||
     operatorPassword.length<16 || adminPassword.length<16 ||
     patientPassword.length<16 ||
     new Set([operatorPassword,adminPassword,patientPassword]).size!==3) {
    throw new Error('Configura tres contraseñas locales distintas de al menos 16 caracteres.');
  }
  const db=new Pool({host:'postgres',port:5432,database:'vitalia_dev',
    user:'vitalia',password:process.env.PGPASSWORD,max:3,
    connectionTimeoutMillis:5000,statement_timeout:10000});
  let server;
  let closing=false;
  async function shutdown(){
    if(closing)return;
    closing=true;
    if(server?.listening) await new Promise(resolve=>server.close(resolve));
    await db.end();
  }
  process.once('SIGINT',()=>{void shutdown().catch(()=>{process.exitCode=1;});});
  process.once('SIGTERM',()=>{void shutdown().catch(()=>{process.exitCode=1;});});

  async function ensureAccount(email,role,password){
    const hashed=await hashPassword(password);
    const existing=await db.query(
      'SELECT id,role_code FROM public.vitalia_accounts WHERE email=$1',[email]);
    if(existing.rows.length){
      if(existing.rows[0].role_code!==role)
        throw new Error('Existe un correo con un rol distinto; no se modificará.');
      // La cuenta persiste entre reinicios. Si se cambia la clave local se actualiza el hash.
      await db.query('UPDATE public.vitalia_accounts SET password_hash=$1 WHERE id=$2',
        [hashed,existing.rows[0].id]);
      return existing.rows[0].id;
    }
    const id=randomUUID();
    await db.query(
      `INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code)
       VALUES($1,$2,$3,$4)`,[id,email,hashed,role]);
    return id;
  }

  try {
    const version=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='027_sil_catalog'");
    if(version.rows.length!==1)
      throw new Error('Falta la migración 027_sil_catalog.');
    const reviewVersion=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='031_sil_external_reports'");
    if(reviewVersion.rows.length!==1)
      throw new Error('Falta la migración 031_sil_external_reports.');
    const branchVersion=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='033_sil_branches_patient_demo'");
    if(branchVersion.rows.length!==1)
      throw new Error('Falta la migración 033_sil_branches_patient_demo.');
    const requestVersion=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='034_sil_medical_requests_demo'");
    if(requestVersion.rows.length!==1)
      throw new Error('Falta la migración 034_sil_medical_requests_demo.');
    const operatorReviewVersion=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='035_sil_retire_validator_role'");
    if(operatorReviewVersion.rows.length!==1)
      throw new Error('Falta la migración 035_sil_retire_validator_role.');
    const portalVersion=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='036_sil_portal_invites_demo'");
    if(portalVersion.rows.length!==1)
      throw new Error('Falta migración DEMO 036. Aplicar solo en vitalia_dev con la guía.');
    const operatorEmail='operador.sil@example.invalid';
    const adminEmail='admin.sil@example.invalid';
    const patientEmail='paciente.sil@example.invalid';
    const operatorId=await ensureAccount(operatorEmail,'operador_laboratorio',operatorPassword);
    await ensureAccount(adminEmail,'administrador',adminPassword);
    const patientId=await ensureAccount(
      patientEmail,'paciente',patientPassword);

    const authenticate=await createCredentialAuthenticator(db);
    const auth={
      authenticate,
      issue:(id,mode)=>issueSession(db,id,mode),
      find:(token)=>findSessionAccount(db,token),
      revoke:(token)=>revokeSession(db,token),
    };
    const app=express();
    app.disable('x-powered-by');
    app.use(localWebCors);
    app.use(express.json({limit:'32kb'}));
    app.get('/api/health',(_req,res)=>res.json({status:'ok',service:'sil-demo-only'}));
    app.use('/api/auth',createAuthRouter(auth));
    const portalDemo=createSilPortalActivationDemo(db);
    app.use('/api/sil',createSilPortalRouterDemo(auth,portalDemo));
    app.use('/api/sil',createSilRouter(auth,createSilService(db),{
      demoReviewOperatorId:operatorId,
    }));
    app.use((_req,res)=>res.status(404).json({error:{code:'NOT_FOUND'}}));
    app.use((error,_req,res,_next)=>{
      console.error('Error controlado SIL:',error.message);
      res.status(500).json({error:{code:'INTERNAL_ERROR'}});
    });
    server=app.listen(3000,'0.0.0.0');
    await new Promise((resolve,reject)=>{
      server.once('listening',resolve);
      server.once('error',reject);
    });
    console.log('Vitalia Health SIL: laboratorio de pruebas disponible.');
    console.log('Operador: '+operatorEmail);
    console.log('Administrador: '+adminEmail);
    console.log('Paciente de pruebas (UUID): '+patientId);
    console.log('Claves: configuradas localmente, no se imprimen en registros.');
    console.log('Portal DEMO: invitaciones de dos canales y buzón SIMULADO. Sin correos reales.');
    console.log('Cuentas persistentes: no se eliminan al detener Docker.');
  }catch(error){
    console.error('No pudo arrancar el laboratorio:',error.message);
    process.exitCode=1;
    await shutdown();
  }
}
main().catch(error=>{console.error('Error de inicio:',error.message);process.exitCode=1;});
