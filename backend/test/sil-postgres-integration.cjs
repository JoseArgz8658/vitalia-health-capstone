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
  let simulatedOrderId=null;
  let multiOrderId=null;
  let success=false, clean=false;
  try {
    const target=await db.query('SELECT current_database() AS db, current_user AS actor');
    assert.equal(target.rows[0].db,'vitalia_dev');
    assert.equal(target.rows[0].actor,'vitalia');
    const version=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='026_sil_orders'");
    assert.equal(version.rowCount,1,'Migración 026 ausente');
    const catalogVersion=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='027_sil_catalog'");
    assert.equal(catalogVersion.rowCount,1,'Migración 027 ausente');
    const orderNumberVersion=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='028_sil_order_numbers'");
    assert.equal(orderNumberVersion.rowCount,1,'Migración 028 ausente');
    const traceVersion=await db.query(
      "SELECT 1 FROM public.vitalia_schema_migrations WHERE version='029_sil_traceability'");
    assert.equal(traceVersion.rowCount,1,'Migración 029 ausente');
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
      sil.recordManualResults(orderId,[{examCode:'hemograma',
        analyte:'Hemoglobina',numericValue:13.2}],actorId),SilConflictError);
    const sample=await sil.registerSample(
      orderId,'TEST-'+randomUUID().slice(0,30),'edta',actorId);
    assert.equal(sample.orderId,orderId);
    assert.equal(sample.status,'sampled');
    await assert.rejects(sil.registerSample(
      orderId,'TEST-'+randomUUID().slice(0,30),'edta',actorId),SilConflictError);
    const recorded=await sil.recordManualResults(orderId,[
      {examCode:'hemograma',analyte:'Hemoglobina',numericValue:13.2},
      {examCode:'hemograma',analyte:'Hematocrito',numericValue:40},
      {examCode:'hemograma',analyte:'Eritrocitos',numericValue:4.7},
      {examCode:'hemograma',analyte:'Leucocitos',numericValue:7.2},
      {examCode:'hemograma',analyte:'Plaquetas',numericValue:250},
    ],actorId);
    assert.equal(recorded.count,5);
    await assert.rejects(sil.recordManualResults(orderId,[
      {examCode:'hemograma',analyte:'Hemoglobina',numericValue:14},
    ],actorId),SilConflictError);
    const complete=await sil.getOrder(orderId);
    assert.equal(complete.order.patientId,patientId);
    assert.equal(complete.order.status,'results_recorded');
    assert.equal(complete.order.synthetic,true);
    assert.equal(complete.sample.barcode,sample.barcode);
    assert.equal(complete.sample.containerCode,'edta');
    assert.equal(complete.sample.receivedBy,'sil-ci-'+actorId+'@example.invalid');
    assert.equal(complete.results.length,5);
    assert.ok(complete.results.every(v=>v.entryMethod==='manual'));
    assert.deepEqual(complete.audit.map(v=>v.action),[
      'order_created','sample_received','results_manual']);
    console.log('PRUEBA SIL: orden, tubo EDTA, 5 resultados manuales y auditoría.');
    // Segundo circuito, independiente: el simulador genera cinco resultados ficticios.
    const simulatedOrder=await sil.createOrder(patientId,actorId);
    simulatedOrderId=simulatedOrder.id;
    await assert.rejects(sil.simulateAnalyzer(simulatedOrderId,actorId),SilConflictError);
    await sil.registerSample(simulatedOrderId,'SIM-'+randomUUID().slice(0,30),'edta',actorId);
    const simulated=await sil.simulateAnalyzer(simulatedOrderId,actorId);
    assert.equal(simulated.count,5);
    assert.equal(simulated.simulated,true);
    assert.equal(simulated.analyzerId,'simulador-hemograma-v1');
    const simulatedRead=await sil.getOrder(simulatedOrderId);
    assert.equal(simulatedRead.order.status,'results_recorded');
    assert.equal(simulatedRead.results.length,5);
    assert.equal(simulatedRead.order.synthetic,true);
    await assert.rejects(sil.simulateAnalyzer(simulatedOrderId,actorId),SilConflictError);
    console.log('PRUEBA ANALIZADOR: muestra, 5 resultados sintéticos y segundo intento rechazado.');

    const multi=await sil.createOrder(patientId,actorId,['hemograma','perfil_lipidico']);
    multiOrderId=multi.id;
    assert.deepEqual(multi.examCodes,['hemograma','perfil_lipidico']);
    assert.match(multi.orderNumber,/^VH-[0-9]{6,}$/);
    const summaryBefore=await sil.summary();
    assert.ok(summaryBefore.summary.total>=3);
    assert.ok(summaryBefore.summary.pendingSample>=1);
    const firstTube=await sil.registerSample(multiOrderId,
      'MULTI-E-'+randomUUID().slice(0,30),'edta',actorId);
    assert.equal(firstTube.status,'registered');
    await assert.rejects(sil.simulateAnalyzer(multiOrderId,actorId),SilConflictError);
    const secondTube=await sil.registerSample(multiOrderId,
      'MULTI-S-'+randomUUID().slice(0,30),'serum',actorId);
    assert.equal(secondTube.status,'sampled');
    const multiRecorded=await sil.simulateAnalyzer(multiOrderId,actorId);
    assert.equal(multiRecorded.count,9);
    const multiRead=await sil.getOrder(multiOrderId);
    assert.equal(multiRead.exams.length,2);
    assert.equal(multiRead.samples.length,2);
    assert.equal(multiRead.requiredContainers.length,2);
    assert.deepEqual(multiRead.audit.map(v=>v.action),[
      'order_created','sample_received','sample_received','results_simulated']);
    assert.equal(multiRead.results.length,9);
    assert.equal(multiRead.results.filter(v=>v.examCode==='perfil_lipidico').length,4);
    await assert.rejects(sil.simulateAnalyzer(multiOrderId,actorId),SilConflictError);
    const page=await sil.listOrders(20,0);
    assert.ok(page.orders.some(item=>item.id===multiOrderId));
    const match=await sil.listOrders(20,0,'results_recorded',
      'sil-ci-'+patientId+'@example.invalid');
    assert.ok(match.orders.some(item=>item.id===multiOrderId));
    assert.ok(match.total>=1);
    const selected=await sil.getOrder(multiOrderId);
    assert.equal(selected.order.orderNumber,multi.orderNumber);
    const catalog=await sil.catalog();
    assert.equal(catalog.exams.length,6);
    console.log('PRUEBA CATÁLOGO: 6 prestaciones, orden combinada y 9 analitos.');

    success=true;
  } finally {
    try {
      // Borrar solamente registros identificados por UUID creados por esta ejecución.
      for(const id of [orderId,simulatedOrderId,multiOrderId].filter(Boolean)) {
        await db.query('DELETE FROM public.vitalia_sil_audit WHERE order_id=$1',[id]);
        await db.query('DELETE FROM public.vitalia_sil_results WHERE order_id=$1',[id]);
        await db.query('DELETE FROM public.vitalia_sil_samples WHERE order_id=$1',[id]);
        await db.query('DELETE FROM public.vitalia_sil_order_exams WHERE order_id=$1',[id]);
        await db.query('DELETE FROM public.vitalia_sil_orders WHERE id=$1',[id]);
      }
      // La migración 017 crea roles automáticamente por trigger; primero eliminar dependientes.
      await db.query('DELETE FROM public.vitalia_account_roles WHERE account_id=ANY($1::uuid[])',[[patientId,actorId]]);
      await db.query('DELETE FROM public.vitalia_accounts WHERE id=ANY($1::uuid[])',[[patientId,actorId]]);
      const remaining=await db.query(
        `SELECT
          (SELECT COUNT(*)::int FROM public.vitalia_sil_orders WHERE id=ANY($1::uuid[])) AS orders,
          (SELECT COUNT(*)::int FROM public.vitalia_accounts WHERE id=ANY($2::uuid[])) AS accounts`,
        [[orderId,simulatedOrderId,multiOrderId].filter(Boolean),[patientId,actorId]]);
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
