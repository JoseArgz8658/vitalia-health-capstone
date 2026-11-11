'use strict';
// Prueba exclusiva en vitalia_dev. Inserta cuentas sintéticas únicas y las
// elimina junto con sus órdenes/solicitudes al terminar.
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Pool}=require('pg');
const {createSilMedicalRequestIntake}=require('../dist/sil/medical-request-intake');
const {createSilService,SilConflictError}=require('../dist/sil/service');

async function main(){
  if(process.env.VITALIA_SIL_TEST_DATABASE!=='YES'||
     process.env.PGHOST!=='postgres'||
     process.env.PGDATABASE!=='vitalia_dev'||
     process.env.PGUSER!=='vitalia'||!process.env.PGPASSWORD)
    throw Error('SOLO base PostgreSQL aislada de pruebas.');
  const db=new Pool({
    host:'postgres',port:5432,database:'vitalia_dev',user:'vitalia',
    password:process.env.PGPASSWORD,max:2,
    connectionTimeoutMillis:5000,statement_timeout:10000,
  });
  const actorId=randomUUID(),patientId=randomUUID();
  const email='sil-solicitud-'+patientId+'@example.invalid';
  const demoIdentifier='DEMO-'+patientId.replaceAll('-','').slice(0,12).toUpperCase();
  let orderId=null,clean=false,success=false;
  try{
    const version=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='034_sil_medical_requests_demo'");
    assert.equal(version.rowCount,1,'Falta migración 034');
    await db.query(
      `INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code)
       VALUES($1,$2,'synthetic-test-only','paciente'),
             ($3,$4,'synthetic-test-only','operador_laboratorio')`,
      [patientId,email,actorId,'sil-op-'+actorId+'@example.invalid']);
    await db.query(
      `INSERT INTO public.vitalia_sil_patient_profiles_demo(
         patient_id,synthetic_identifier,given_names,family_names,birth_date,
         sex_for_reference)
       VALUES($1,$2,'Paciente Prueba','Vitalia Demo','1990-01-01','not_specified')`,
      [patientId,demoIdentifier]);
    const fakePdf=Buffer.from('%PDF-1.4\nDocumento ficticio sin firma\n%%EOF');
    const source=`Solicitud de exámenes ficticia
       ID: ${demoIdentifier}
       Paciente: Paciente Prueba Vitalia Demo
       Nacimiento: 1990-01-01
       Solicita Glicemia y Hemoglobina glicosilada (HbA1c).
       Profesional Ficticio. Solicitud SOL-DEMO-001.`;
    const read=async()=>({
      status:'text_ready',text:source,pageCount:1,incidents:[],
    });
    const intake=createSilMedicalRequestIntake(db,{read});
    const preview=await intake.preview(actorId,email,'solicitud-ficticia.pdf',fakePdf);
    assert.equal(preview.state,'requires_operator_review');
    assert.equal(preview.confirmed,false);
    assert.equal(preview.identity.identifierMatches,true);
    assert.deepEqual(preview.suggestedExams.map(x=>x.code),['glicemia','hba1c']);
    assert.ok(preview.previewToken);
    const input={
      previewToken:preview.previewToken,patientId,
      branchCode:'perez-las-condes',
      examCodes:['glicemia','hba1c'],
      documentReference:'SOL-DEMO-001',
      prescriberName:'Profesional Ficticio',
      requestDate:'2026-11-01',verified:true,
    };
    const confirmed=await intake.confirm(actorId,input);
    orderId=confirmed.order.id;
    assert.equal(confirmed.order.status,'registered');
    const sil=createSilService(db);
    const details=await sil.getOrder(orderId);
    assert.equal(details.medicalRequest.documentReference,'SOL-DEMO-001');
    assert.equal(details.medicalRequest.branchCode,'perez-las-condes');
    assert.deepEqual(details.exams.map(x=>x.code),['glicemia','hba1c']);
    const original=await sil.downloadMedicalRequest(orderId,actorId);
    assert.equal(original.fileName,'solicitud-ficticia.pdf');
    assert.deepEqual(original.bytes,fakePdf);
    const history=await sil.getOrder(orderId);
    assert.deepEqual(history.audit.map(x=>x.action),
      ['order_created','medical_request_received','medical_request_accessed']);
    const second=await intake.preview(actorId,email,'solicitud-ficticia.pdf',fakePdf);
    await assert.rejects(intake.confirm(actorId,{
      ...input,previewToken:second.previewToken,
    }),SilConflictError);
    success=true;
    console.log('PRUEBA SOLICITUD: paciente verificado, 2 prestaciones y orden vinculada.');
    console.log('PRUEBA AUDITORÍA: PDF original recuperable y acceso registrado.');
    console.log('PRUEBA DUPLICADOS: misma solicitud rechazada.');
  }finally{
    try{
      if(orderId){
        await db.query('DELETE FROM public.vitalia_sil_medical_requests_demo WHERE order_id=$1',[orderId]);
        await db.query('DELETE FROM public.vitalia_sil_audit WHERE order_id=$1',[orderId]);
        await db.query('DELETE FROM public.vitalia_sil_order_exams WHERE order_id=$1',[orderId]);
        await db.query('DELETE FROM public.vitalia_sil_orders WHERE id=$1',[orderId]);
      }
      await db.query('DELETE FROM public.vitalia_sil_patient_profiles_demo WHERE patient_id=$1',[patientId]);
      await db.query('DELETE FROM public.vitalia_account_roles WHERE account_id=ANY($1::uuid[])',
        [[actorId,patientId]]);
      await db.query('DELETE FROM public.vitalia_accounts WHERE id=ANY($1::uuid[])',
        [[actorId,patientId]]);
      const remain=await db.query(
        'SELECT COUNT(*)::int AS total FROM public.vitalia_accounts WHERE id=ANY($1::uuid[])',
        [[actorId,patientId]]);
      assert.equal(remain.rows[0].total,0);
      clean=true;
    }finally{await db.end();}
  }
  if(!success||!clean)throw Error('Prueba o limpieza incompleta');
  console.log('LIMPIEZA SOLICITUD: registros sintéticos eliminados.');
}
main().catch(error=>{
  console.error('PRUEBA SOLICITUD FALLIDA:',error.message);process.exitCode=1;
});
