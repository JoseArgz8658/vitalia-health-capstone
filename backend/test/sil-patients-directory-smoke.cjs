// Comprobación de solo lectura contra PostgreSQL aislado de la DEMO.
// No inserta registros ni modifica contraseñas, resultados o documentos.
const assert=require('node:assert/strict');
const {Pool}=require('pg');
const {createSilService}=require('../dist/sil/service');

async function main(){
 if(process.env.VITALIA_SIL_DEMO!=='YES' ||
    process.env.PGDATABASE!=='vitalia_dev' ||
    process.env.PGHOST!=='postgres'){
   throw new Error('Solo se permite en el contenedor SIL DEMO aislado.');
 }
 const pool=new Pool({
  host:process.env.PGHOST,
  port:Number(process.env.PGPORT||5432),
  database:process.env.PGDATABASE,
  user:process.env.PGUSER,
  password:process.env.PGPASSWORD,
  max:1,
 });
 try{
  const sil=createSilService(pool);
  const page=await sil.listPatientsDemo(20,0);
  assert.ok(Number.isInteger(page.total)&&page.total>=0);
  assert.ok(page.patients.length<=20);
  assert.ok(page.patients.every(p=>
    typeof p.email==='string' && p.email.endsWith('@example.invalid')));
  const completed=await sil.listPatientsDemo(20,0,'','complete');
  const incomplete=await sil.listPatientsDemo(20,0,'','incomplete');
  assert.equal(completed.total+incomplete.total,page.total);
  const withOrders=await sil.listPatientsDemo(20,0,'','all','with');
  const withoutOrders=await sil.listPatientsDemo(20,0,'','all','without');
  assert.equal(withOrders.total+withoutOrders.total,page.total);
  const missing=await sil.listPatientsDemo(20,0,'__paciente_no_existente_que_nunca_debe_coincidir__');
  assert.equal(missing.total,0);
  console.log(
   'Directorio SIL DEMO: SQL y filtros correctos. Total cuentas ficticias: '+
   page.total+'. Máximo 20 por página. Sin escritura.');
 }finally{
  await pool.end();
 }
}
main().catch(()=>{
 console.error('Falló la prueba de lectura del directorio SIL DEMO.');
 process.exitCode=1;
});
