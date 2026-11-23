'use strict';

const assert=require('node:assert/strict');

const origin=process.env.SHOWCASE_URL??'http://127.0.0.1:5174';
const url=new URL(origin);
if(url.protocol!=='http:'||url.hostname!=='127.0.0.1'||!['5174','55475'].includes(url.port)){
  throw new Error('El recorrido se ejecuta exclusivamente contra el showcase local.');
}
const prefix='/api/sil/main';
const email=name=>name+'@showcase.example.invalid';
async function api(path,{method='GET',token,data,status=200}={}){
  const response=await fetch(origin+path,{
    method,signal:AbortSignal.timeout(15000),
    headers:{...(token?{Authorization:'Bearer '+token}:{}),
      ...(data?{'Content-Type':'application/json'}:{})},
    body:data?JSON.stringify(data):undefined,
  });
  assert.equal(response.status,status,method+' '+path);
  return response;
}
async function login(name,mode,role){
  const password=process.env['SHOWCASE_'+role+'_PASSWORD'];
  assert.ok(password,'Configura la contraseña local de '+role);
  const response=await api('/api/auth/login',{method:'POST',data:{email:email(name),mode,password}});
  return (await response.json()).token;
}
async function main(){
  const admin=await login('admin','administrador','ADMIN');
  const all=await login('operador-003','operador_laboratorio','OPERATOR');
  const selected=await login('operador-001','operador_laboratorio','OPERATOR');
  const multiple=await login('operador-002','operador_laboratorio','OPERATOR');
  const patient=await login('paciente-001','paciente','PATIENT');
  const otherPatient=await login('paciente-002','paciente','PATIENT');
  const get=async(path,token)=>(await api(prefix+path,{token})).json();
  const overview=await get('/administration-overview',admin);
  assert.equal(overview.laboratories.length,2);
  const lab=overview.laboratories.find(item=>item.name.includes('Cordillera'));
  const other=overview.laboratories.find(item=>item.id!==lab.id);
  assert.equal(lab.sites.length,3);
  assert.equal(lab.operators,7);
  const base='/labs/'+lab.id;
  await api(prefix+'/labs/'+other.id+'/orders',{token:all,status:403});
  await api(prefix+'/administration-overview',{token:patient,status:403});

  const patients=new Set();
  for(let offset=0;offset<120;offset+=20){
    const page=await get(base+'/patients?limit=20&offset='+offset,all);
    assert.equal(page.patients.length,20);
    assert.equal(page.hasMore,offset<100);
    page.patients.forEach(person=>patients.add(person.patientId??person.id));
  }
  assert.equal(patients.size,120);
  const searched=await get(base+'/patients?search='+encodeURIComponent(email('paciente-120')),all);
  assert.equal(searched.patients.length,1);

  const {sites}=await get(base+'/sites',selected);
  assert.equal(sites.length,1);
  assert.equal((await get(base+'/sites',multiple)).sites.length,2);
  const orderPage=await get(base+'/orders?limit=50',selected);
  assert.ok(orderPage.orders.length>0);
  assert.ok(orderPage.orders.every(order=>order.siteId===sites[0].id));
  const {summary}=await get(base+'/summary',all);
  assert.equal(summary.ordersTotal,600);
  assert.equal(summary.pendingRequests,60);
  assert.equal(summary.ordersTotal,summary.published+summary.registered+summary.inReview);
  const restricted=(await get(base+'/summary',selected)).summary;
  assert.ok(restricted.ordersTotal<summary.ordersTotal);
  const full=(await get(base+'/orders?status=report_published&limit=50',all)).orders;
  const unassigned=full.find(order=>order.siteId!==sites[0].id);
  assert.ok(unassigned);
  await api(prefix+base+'/orders/'+unassigned.id+'/medical-request/file',{
    token:selected,status:404,
  });
  const pending=await get(base+'/medical-requests/pending?limit=20',all);
  assert.equal(pending.pending.length,20);

  const profile=await get('/patient/profile',patient);
  assert.equal(profile.profile.hasProfile,true);
  const first=await get('/patient/reports?offset=0',patient);
  assert.equal(first.total,54);
  const last=await get('/patient/reports?offset=50',patient);
  assert.equal(last.reports.length,4);
  assert.ok(last.reports.every(report=>!first.reports.some(item=>item.id===report.id)));
  const found=await get('/patient/reports?search=Glicemia',patient);
  assert.equal(found.total,54);
  const report=first.reports[0];
  const file=await api(prefix+'/patient/reports/'+report.id+'/file',{token:patient});
  assert.match(file.headers.get('content-type'),/application\/pdf/);
  assert.equal(Buffer.from(await file.arrayBuffer()).subarray(0,8).toString(),'%PDF-1.4');
  await api(prefix+'/patient/reports/'+report.id+'/file',{token:otherPatient,status:404});
  const comparison=await (await api(prefix+'/patient/reports/overview',{
    method:'POST',token:patient,data:{reportIds:[report.id,last.reports[0].id]},
  })).json();
  assert.equal(comparison.reports.length,2);
  assert.ok(comparison.reports.every(item=>item.measurements.some(value=>value.unit==='mg/dL')));
  console.log('Showcase: navegación API, permisos, 120 pacientes, indicadores, PDF e historial verificados.');
}
main().catch(error=>{
  console.error(error);
  process.exitCode=1;
});
