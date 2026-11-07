'use strict';
// Solo demostración local con datos sintéticos. No iniciar contra la base principal.
// No necesita S3, procesamiento, Ollama ni modificar los contenedores actuales.
const express=require('express');
const {Pool}=require('pg');
const {randomUUID,randomBytes}=require('node:crypto');
const {createAuthRouter}=require('../dist/auth/router');
const {createSilRouter}=require('../dist/sil/router');
const {createSilService}=require('../dist/sil/service');
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
   throw new Error('La demostración solo puede ejecutarse con la base Docker de pruebas.');
 }
 const db=new Pool({host:'postgres',port:5432,database:'vitalia_dev',user:'vitalia',
   password:process.env.PGPASSWORD,max:3,connectionTimeoutMillis:5000,
   statement_timeout:10000});
 const adminId=randomUUID(),patientId=randomUUID();
 const adminEmail='sil-demo-'+adminId+'@example.invalid';
 const patientEmail='sil-demo-'+patientId+'@example.invalid';
 const password=randomBytes(20).toString('hex');
 let server,closing=false,seeded=false;
 async function cleanup(){
   if(closing)return;closing=true;
   if(server?.listening) await new Promise(resolve=>server.close(resolve));
   try{
     // Solo borrar órdenes, sesiones y cuentas de estos UUID generados por el script.
     const ids=[adminId,patientId];
     const orders=await db.query(
       'SELECT id FROM public.vitalia_sil_orders WHERE created_by=$1 AND patient_id=$2',
       [adminId,patientId]);
     for(const row of orders.rows){
       await db.query('DELETE FROM public.vitalia_sil_results WHERE order_id=$1',[row.id]);
       await db.query('DELETE FROM public.vitalia_sil_samples WHERE order_id=$1',[row.id]);
       await db.query('DELETE FROM public.vitalia_sil_orders WHERE id=$1',[row.id]);
     }
     await db.query('DELETE FROM public.vitalia_sessions WHERE account_id=ANY($1::uuid[])',[ids]);
     await db.query('DELETE FROM public.vitalia_account_roles WHERE account_id=ANY($1::uuid[])',[ids]);
     await db.query('DELETE FROM public.vitalia_accounts WHERE id=ANY($1::uuid[])',[ids]);
     console.log('LIMPIEZA: registros de demostración eliminados.');
   }catch(error){
     console.error('ERROR DE LIMPIEZA: revisar solo cuentas sil-demo y sus registros.',error.message);
     process.exitCode=1;
   }finally{await db.end();}
 }
 async function terminate(){try{await cleanup();}finally{process.exit(process.exitCode||0);}}
 process.once('SIGINT',terminate);
 process.once('SIGTERM',terminate);
 try {
   const target=await db.query('SELECT current_database() AS name');
   if(target.rows[0]?.name!=='vitalia_dev')throw new Error('Base inesperada.');
   const hash=await hashPassword(password);
   await db.query(
     `INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code)
      VALUES ($1,$2,$3,'administrador'),($4,$5,$3,'paciente')`,
     [adminId,adminEmail,hash,patientId,patientEmail]);
   seeded=true;
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
   app.use('/api/sil',createSilRouter(auth,createSilService(db)));
   app.use((_req,res)=>res.status(404).json({error:{code:'NOT_FOUND'}}));
   app.use((err,_req,res,_next)=>{
     console.error('Fallo de demostración:',err.message);
     res.status(500).json({error:{code:'INTERNAL_ERROR'}});
   });
   server=app.listen(3000,'0.0.0.0');
   await new Promise((resolve,reject)=>{
     server.once('listening',resolve);
     server.once('error',reject);
   });
   console.log('VITALIA SIL DEMO LISTA (solo laboratorio ficticio)');
   console.log('API local: http://127.0.0.1:3101');
   console.log('Administrador: '+adminEmail);
   console.log('Contraseña temporal: '+password);
   console.log('UUID paciente ficticio: '+patientId);
   console.log('Para cerrar y limpiar: docker stop vitalia-sil-demo');
 }catch(err){
   console.error('No se pudo iniciar la demostración:',err.message);
   process.exitCode=1;
   await cleanup();
 }
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
