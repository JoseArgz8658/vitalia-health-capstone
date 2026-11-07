'use strict';
// Ejecución manual exclusiva sobre la base de datos aislada de pruebas.
// No usar datos reales. Todos los registros sintéticos se eliminan al finalizar.
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {Pool} = require('pg');
const {createSilService,SilConflictError,SilNotFoundError} = require('../dist/sil/service');

async function main() {
  if (process.env.VITALIA_SIL_TEST_DATABASE !== 'YES' ||
      process.env.PGHOST !== 'postgres' ||
      process.env.PGDATABASE !== 'vitalia_dev' ||
      process.env.PGUSER !== 'vitalia' ||
      !process.env.PGPASSWORD) {
    throw new Error('Configuración aislada de prueba obligatoria.');
  }
  const db = new Pool({host:'postgres',port:5432,database:'vitalia_dev',
    user:'vitalia',password:process.env.PGPASSWORD,max:2,
    connectionTimeoutMillis:5000,statement_timeout:10000});
  const patientId = randomUUID(), actorId = randomUUID();
  let orderId=null;
  let success=false, clean=false;
  try {
    const target=await db.query('SELECT current_database() AS db, current_user AS actor');
    assert.equal(target.rows[0].db,'vitalia_dev');
    assert.equal(target.rows[0].actor,'vitalia');
    const version=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='026_sil_orders'");
    assert.equal(version.rowCount,1,'Migración 026 ausente');
    await db.query(
      `INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code)
       VALUES($1,$2,'synthetic-test-only','paciente'),
             ($3,$4,'synthetic-test-only','administrador')`,
      [patientId,'sil-ci-'+patientId+'@example.invalid',
       actorId,'sil-ci-'+actorId+'@example.invalid']);
    const sil=createSilService(db);
    await assert.rejects(sil.createOrder(actorId,actorId),SilNotFoundError);
    const order=await sil.createOrder(patientId,actorId);
    orderId=order.id;
    assert.equal(order.status,'registered');
    await assert.rejects(
      sil.recordResults(orderId,[{analyte:'Hemoglobina',numericValue:13.2,unit:'g/dL'}]),
      SilConflictError);
    const sample=await sil.registerSample(orderId,'TEST-'+randomUUID().slice(0,30));
    assert.equal(sample.orderId,orderId);
    await assert.rejects(sil.registerSample(orderId,'TEST-'+randomUUID().slice(0,30)),SilConflictError);
    const recorded=await sil.recordResults(orderId,[
      {analyte:'Hemoglobina',numericValue:13.2,unit:'g/dL',referenceMin:12,referenceMax:16},
      {analyte:'Hematocrito',numericValue:40,unit:'%',referenceMin:35,referenceMax:48},
    ]);
    assert.equal(recorded.count,2);
    await assert.rejects(
      sil.recordResults(orderId,[{analyte:'Hemoglobina',numericValue:14,unit:'g/dL'}]),
      SilConflictError);
    const complete=await sil.getOrder(orderId);
    assert.equal(complete.order.patientId,patientId);
    assert.equal(complete.order.status,'results_recorded');
    assert.equal(complete.order.synthetic,true);
    assert.equal(complete.sample.barcode,sample.barcode);
    assert.equal(complete.results.length,2);
    success=true;
    console.log('PRUEBA SIL: orden, muestra, 2 resultados y transiciones correctas.');
  } finally {
    try {
      // Borrar solamente registros identificados por UUID creados por esta ejecución.
      if (orderId) {
        await db.query('DELETE FROM public.vitalia_sil_results WHERE order_id=$1',[orderId]);
        await db.query('DELETE FROM public.vitalia_sil_samples WHERE order_id=$1',[orderId]);
        await db.query('DELETE FROM public.vitalia_sil_orders WHERE id=$1',[orderId]);
      }
      // La migración 017 crea roles automáticamente por trigger; primero eliminar dependientes.
      await db.query('DELETE FROM public.vitalia_account_roles WHERE account_id=ANY($1::uuid[])',[[patientId,actorId]]);
      await db.query('DELETE FROM public.vitalia_accounts WHERE id=ANY($1::uuid[])',[[patientId,actorId]]);
      const remaining=await db.query(
        `SELECT
          (SELECT COUNT(*)::int FROM public.vitalia_sil_orders WHERE id=$1) AS orders,
          (SELECT COUNT(*)::int FROM public.vitalia_accounts WHERE id=ANY($2::uuid[])) AS accounts`,
        [orderId||'00000000-0000-0000-0000-000000000000',[patientId,actorId]]);
      assert.equal(remaining.rows[0].orders,0);
      assert.equal(remaining.rows[0].accounts,0);
      clean=true;
    } finally {
      await db.end();
    }
  }
  if (!success || !clean) throw new Error('Prueba o limpieza incompleta.');
  console.log('LIMPIEZA SIL: registros sintéticos eliminados.');
}
main().catch(err=>{console.error('PRUEBA SIL FALLIDA:',err.message);process.exitCode=1;});
