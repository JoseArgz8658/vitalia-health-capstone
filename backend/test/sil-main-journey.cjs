'use strict';

const assert = require('node:assert/strict');
const {createHash, randomUUID} = require('node:crypto');
const {spawnSync} = require('node:child_process');
const {readFileSync, readdirSync, writeFileSync} = require('node:fs');
const {dirname,resolve} = require('node:path');
const {createInterface} = require('node:readline/promises');
const express = require('express');
const {Pool} = require('pg');
const {createApp} = require('../dist/app');
const {createCredentialAuthenticator} = require('../dist/auth/credentials');
const {hashPassword} = require('../dist/auth/password');
const {findSessionAccount, issueSession, revokeSession} = require('../dist/auth/sessions');
const {createSilMainService} = require('../dist/sil/main-service');

const origin = 'http://127.0.0.1:3119';
const password = 'SoloPrueba-2026!';
const pdf = syntheticPdf();
const browserRequestPdf = syntheticPdf([
  'Referencia: SOL-1004','Profesional solicitante: Persona Ficticia',
  'Fecha de solicitud: 2024-01-01','Glicemia',
]);

function syntheticPdf(lines=['Vitalia - informe ficticio']) {
  const stream = 'BT /F1 18 Tf 50 740 Td '+
    lines.map(line=>'('+line+') Tj').join(' 0 -28 Td ')+' ET';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,
  ];
  let content = '%PDF-1.4\n';
  const offsets = [];
  for (const [index, object] of objects.entries()) {
    offsets.push(content.length);
    content += `${index+1} 0 obj\n${object}\nendobj\n`;
  }
  const start = content.length;
  content += `xref\n0 ${offsets.length+1}\n0000000000 65535 f \n`;
  for (const offset of offsets) content += `${String(offset).padStart(10,'0')} 00000 n \n`;
  content += `trailer\n<< /Size ${offsets.length+1} /Root 1 0 R >>\nstartxref\n${start}\n%%EOF\n`;
  return Buffer.from(content,'ascii');
}
const migrations = resolve(__dirname, '../database/migrations');

async function prepare(db, container) {
  const target = await db.query(`SELECT current_database() AS db, current_user AS actor,
    NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public') AS empty`);
  assert.deepEqual(target.rows[0], {db:'vitalia_restored', actor:'vitalia_restore', empty:true},
    'El ensayo exige una base temporal vacía.');
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query(`CREATE TABLE public.vitalia_schema_migrations (
      version text PRIMARY KEY, checksum text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now())`);
    const files = readdirSync(migrations).sort();
    for (const file of files.filter(name => /^0(?:0[1-9]|1[01])_/.test(name))) {
      const sql = readFileSync(resolve(migrations,file),'utf8');
      await client.query(sql);
      await client.query('INSERT INTO public.vitalia_schema_migrations VALUES ($1,$2)',
        [file.slice(0,-4),createHash('sha256').update(sql.replace(/\r\n/g,'\n')).digest('hex')]);
    }
    // Se recrea solo la forma del esquema legado para este ensayo sintético.
    await client.query(readFileSync(resolve(migrations,'025_preliminary_assistant.sql'),'utf8'));
    await client.query("INSERT INTO public.vitalia_schema_migrations VALUES ('012_preliminary_assistant',repeat('a',64))");
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
  const script = 'dist/database/migrate-main-sil.js';
  const migrated = container
    ? spawnSync('docker',[
      'run','--rm','--pull=never','--network','container:'+container,
      '--mount','type=bind,source='+resolve(__dirname,'../dist')+',target=/app/dist,readonly',
      '--mount','type=bind,source='+resolve(__dirname,'../database')+',target=/app/database,readonly',
      '-e','PGHOST=127.0.0.1','-e','PGPORT=5432','-e','PGUSER=vitalia_restore',
      '-e','PGDATABASE=vitalia_restored','-e','PGPASSWORD','-e','VITALIA_ISOLATED_REHEARSAL=YES',
      '--workdir','/app','--entrypoint','node','vitalia-backend:local',script,'--rehearse',
    ],{stdio:'inherit',timeout:45000})
    : spawnSync(process.execPath,[resolve(__dirname,'../'+script),'--rehearse'],
      {stdio:'inherit',timeout:30000});
  if (migrated.error) throw migrated.error;
  assert.equal(migrated.status,0,'Falló el migrador del ensayo.');
}

async function api(method, path, status, {token, json, bytes, headers={}} = {}) {
  const response = await fetch(origin+path,{
    method, signal:AbortSignal.timeout(8000),
    headers:{
      ...(token ? {Authorization:'Bearer '+token} : {}),
      ...(json ? {'Content-Type':'application/json'} : {}),
      ...headers,
    },
    body:json ? JSON.stringify(json) : bytes,
  });
  assert.equal(response.status,status,method+' '+path);
  return response;
}

async function signIn(page, account, route='') {
  await page.goto('http://localhost:5173/'+route,{waitUntil:'domcontentloaded'});
  // En escritorio el control de accesibilidad está fuera del área visible.
  await page.locator('flt-semantics-placeholder').evaluate(button=>button.click(),
    undefined,{timeout:30000});
  const email=page.getByRole('textbox').first();
  const box=await email.boundingBox({timeout:10000});
  assert.ok(box,'Campo de correo visible');
  await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
  const emailInput=page.locator('input:focus:not([type="password"])');
  await emailInput.fill(account+'@example.invalid',{timeout:10000});
  await page.keyboard.press('Tab');
  const passwordInput=page.locator('input[type="password"]:focus');
  await passwordInput.fill(password,{timeout:10000});
  const response=page.waitForResponse(r=>r.url().endsWith('/api/auth/login') && r.request().method()==='POST');
  const [login]=await Promise.all([
    response,page.getByRole('button',{name:'Iniciar sesión'}).click(),
  ]);
  assert.equal(login.status(),200,'Acceso desde Edge de '+account);
  console.log('Microsoft Edge: inició sesión '+account+'.');
}

async function reach(page, locator, description) {
  // Flutter desplaza su propia vista y crea nodos accesibles al entrar en pantalla.
  await page.mouse.move(455,550);
  for(let attempt=0;attempt<14;attempt++){
    const rect=await locator.boundingBox({timeout:400}).catch(()=>null);
    if(rect && rect.y>=50 && rect.y+rect.height<=page.viewportSize().height-5)return locator;
    await page.mouse.wheel(0,rect && rect.y<50 ? -280 : 410);
    await page.waitForTimeout(170);
  }
  throw new Error('Control de operador fuera de alcance: '+description);
}

async function operatorJourney(browser, order, base, sampleOrder, samplePdf) {
  const name='VH-'+String(order.orderNumber).padStart(6,'0');
  const endpoint='/api/sil/main'+base+'/orders/'+order.id+'/report';
  const stage=async (account, task, viewport={width:1440,height:1150})=>{
    const page=await browser.newPage({viewport});
    try {
      await signIn(page,account,'#/laboratorio');
      await page.getByRole('button',{name:'Cerrar sesión'}).waitFor();
      page.on('response', response=>{
        const url=new URL(response.url());
        if(url.pathname.startsWith('/api/sil/main/')){
          console.log('Edge '+account+': '+response.request().method()+' '+url.pathname+' '+response.status());
        }
      });
      const id=value=>page.locator('[flt-semantics-identifier="'+value+'"]');
      const button=label=>page.getByRole('button',{name:label,exact:true});
      const checkbox=label=>page.getByRole('checkbox',{name:label,exact:true});
      const click=async (locator,label)=>(await reach(page,locator,label)).click();
      const confirm=async label=>{
        const control=checkbox(label);
        await reach(page,control,label);
        if(await control.getAttribute('aria-checked')==='true')return;
        const box=await control.boundingBox();
        // CheckboxListTile ubica la casilla al inicio de la fila.
        await page.mouse.click(box.x+Math.min(24,box.width/2),box.y+box.height/2);
        await control.and(page.locator('[aria-checked="true"]')).waitFor({timeout:5000});
        console.log('Microsoft Edge: confirmación marcada: '+label);
      };
      const select=async (control, orderName=name)=>{
        await click(id(control),control);
        await page.getByRole('menuitem',{name:new RegExp(orderName)}).click({timeout:7000});
      };
      try {
        return await task({page,id,button,click,select,confirm});
      } catch(error) {
        for(const message of [
          'Selecciona orden, PDF y confirma autorización y paciente.',
          'Indica una fecha válida de autorización externa.',
          'Comprueba el PDF (máximo 2 MiB) y su autorización.',
          'No fue posible conectar con el laboratorio.',
        ]){
          const seen=await page.getByText(message,{exact:true}).count();
          if(seen)console.log('Edge '+account+': '+message);
        }
        throw new Error('Estación de '+account+': '+error.message);
      }
    } finally {
      await page.close();
    }
  };

  const captures=process.env.VITALIA_JOURNEY_SCREENSHOTS;
  await stage('uploader',async ({page,button})=>{
    const receive=button('Recibir solicitud');
    await receive.waitFor();
    const mobile=await receive.boundingBox();
    assert.ok(mobile && mobile.x>=0 && mobile.x+mobile.width<=390,'Recepción visible en móvil');
    await receive.click();
    const pdfReader=button('Leer PDF y sugerir datos');
    await pdfReader.waitFor();
    assert.equal(await pdfReader.isEnabled(),false,'Primero se debe seleccionar un PDF');
    if(captures)await page.screenshot({path:resolve(captures,'recepcion-movil.png')});
  },{width:390,height:844});

  return stage('uploader',async ({page,id,button,click,select,confirm})=>{
    const receive=button('Recibir solicitud');
    await receive.waitFor();
    const desktop=await receive.boundingBox();
    assert.ok(desktop && desktop.x+desktop.width<=226,'Navegación lateral visible en escritorio');
    if(captures)await page.screenshot({path:resolve(captures,'operador-escritorio.png')});
    await click(receive,'Recibir solicitud');
    await button('Leer PDF y sugerir datos').waitFor();
    await button('Buscar paciente activado').waitFor();
    if(captures)await page.screenshot({path:resolve(captures,'recepcion-escritorio.png')});
    console.log('Microsoft Edge: navegación y recepción verificadas a 390 y 1440 px.');
    await click(button('Órdenes'),'Órdenes');
    const sampleFolio='VH-'+String(sampleOrder.orderNumber).padStart(6,'0');
    await click(button('Abrir '+sampleFolio),'Abrir orden desde la lista');
    const clinical='/api/sil/main'+base+'/orders/'+sampleOrder.id+'/clinical/results';
    const chooseResults=page.waitForEvent('filechooser');
    const preview=page.waitForResponse(r=>r.url().endsWith(clinical+'/preview') && r.request().method()==='POST');
    await click(button('Leer PDF de resultados'),'Leer PDF de resultados');
    await (await chooseResults).setFiles({
      name:'resultados-ficticios.pdf',mimeType:'application/pdf',buffer:samplePdf,
    });
    assert.equal((await preview).status(),200);
    await page.getByText('Sugerencia del PDF: 91.2',{exact:true}).waitFor();
    await click(button('Cotejé el PDF. Completar campos vacíos'),'Completar sugerencias');
    const saved=page.waitForResponse(r=>r.url().endsWith(clinical) && r.request().method()==='POST');
    await click(button('Guardar resultados para revisión'),'Guardar resultados');
    const recorded=await saved;
    assert.equal(recorded.status(),201);
    assert.equal(recorded.request().postDataJSON().values[0].numericValue,91.2);
    console.log('Microsoft Edge: el operador cotejó y guardó la sugerencia del PDF.');
    const requestDownload=page.waitForEvent('download');
    await click(button('Descargar solicitud original'),'Descargar solicitud original');
    const requestFile=await requestDownload;
    assert.deepEqual(readFileSync(await requestFile.path()),browserRequestPdf);
    assert.equal(requestFile.suggestedFilename(),
      'solicitud-VH-'+String(sampleOrder.orderNumber).padStart(6,'0')+'.pdf');
    await click(button('Ver historial de la orden'),'Ver historial de la orden');
    const closeHistory=button('Cerrar historial');
    await closeHistory.waitFor();
    await page.getByText('Resultados registrados',{exact:true}).waitFor();
    await page.getByText('Solicitud descargada',{exact:true}).waitFor();
    await page.getByText(/uploader@example[.]invalid/).first().waitFor();
    await closeHistory.click();
    await closeHistory.waitFor({state:'hidden'});
    console.log('Microsoft Edge: el operador consultó el evento real de la orden.');
    await click(button('Órdenes'),'Órdenes');
    await select('sil-upload-order');
    const choose=page.waitForEvent('filechooser');
    await click(button('Elegir archivo PDF (máx. 2 MiB)'),'Elegir archivo PDF');
    await (await choose).setFiles({name:'informe-operador.pdf',mimeType:'application/pdf',buffer:pdf});
    await button('informe-operador.pdf').waitFor({timeout:10000});
    console.log('Microsoft Edge: orden y archivo seleccionados.');
    for(const [key,value] of [
      ['sil-report-professional','Profesional Ficticio'],
      ['sil-report-reference','AUT-OPERADOR-EDGE'],
    ]){
      const input=id(key).locator('input[data-semantics-role="text-field"]');
      await reach(page,input,key);
      await input.focus();
      const focused=input.and(page.locator(':focus'));
      await focused.waitFor({timeout:7000});
      // Flutter activa el editor web al finalizar el cambio de foco.
      await focused.evaluate(()=>new Promise(done=>requestAnimationFrame(()=>requestAnimationFrame(done))));
      await focused.pressSequentially(value,{delay:18});
      if(await focused.inputValue()!==value){
        await focused.press('Control+a');
        await focused.pressSequentially(value,{delay:18});
      }
      assert.equal(await focused.inputValue(),value,key);
    }
    await click(button('Elegir fecha de autorización'),'Elegir fecha de autorización');
    await button('Usar fecha').click();
    await confirm('El informe ya fue autorizado fuera de Vitalia');
    await confirm('Confirmé que el PDF corresponde al paciente de la orden');
    console.log('Microsoft Edge: datos de autorización y paciente comprobados.');
    const response=page.waitForResponse(r=>r.url().endsWith(endpoint) && r.request().method()==='POST');
    const refresh=page.waitForResponse(r=>new URL(r.url()).pathname===('/api/sil/main'+base+'/orders')
      && r.request().method()==='GET');
    const [uploaded]=await Promise.all([
      response,click(button('Adjuntar para revisión'),'Adjuntar para revisión'),refresh,
    ]);
    assert.equal(uploaded.status(),201,'Carga del PDF desde la estación');
    const reportId=(await uploaded.json()).report.id;
    console.log('Microsoft Edge: se adjuntó el PDF desde la estación del operador.');

    await page.getByRole('button',{name:/^Revisión interna/}).click();
    await select('sil-review-order');
    const publication=button('Publicar informe');
    await reach(page,publication,'Publicar informe');
    assert.equal(await publication.isEnabled(),false,'Se exige revisar antes de publicar');
    const download=page.waitForEvent('download');
    const reviewResponse=page.waitForResponse(r=>r.url().endsWith(endpoint+'/file') && r.request().method()==='GET');
    await click(button('Descargar PDF para revisión'),'Descargar para revisión');
    assert.equal((await reviewResponse).status(),200);
    assert.deepEqual(readFileSync(await (await download).path()),pdf);
    await confirm('Confirmo que revisé el PDF y su autorización externa');
    const posted=page.waitForResponse(r=>r.url().endsWith(endpoint+'/publish') && r.request().method()==='POST');
    await click(publication,'Publicar informe');
    assert.equal((await posted).status(),201);
    console.log('Microsoft Edge: el mismo operador descargó, revisó y publicó el PDF.');
    return reportId;
  });
}

async function browserJourney(order, base, sampleOrder, samplePdf) {
  const {chromium}=require(process.env.VITALIA_JOURNEY_PLAYWRIGHT);
  const browser=await chromium.launch({channel:'msedge'});
  try {
    const publishedId=await operatorJourney(browser,order,base,sampleOrder,samplePdf);
    const page=await browser.newPage({viewport:{width:390,height:844}});
    await signIn(page,'patient');
    const downloadButton=page.getByRole('button',{name:'Descargar PDF',exact:true}).first();
    await downloadButton.waitFor({timeout:20000});
    const downloaded=page.waitForEvent('download');
    const response=page.waitForResponse(r=>r.url().endsWith('/patient/reports/'+publishedId+'/file'));
    await downloadButton.click();
    assert.equal((await response).status(),200);
    const file=await downloaded;
    assert.deepEqual(readFileSync(await file.path()),pdf);
    console.log('Microsoft Edge: el paciente descargó el informe publicado desde la estación.');
  } finally {
    await browser.close();
  }
}

function demoAccounts(manual) {
  const raw=process.env.VITALIA_JOURNEY_DEMO_PASSWORDS;
  delete process.env.VITALIA_JOURNEY_DEMO_PASSWORDS;
  if(raw===undefined)return {};
  if(!manual)throw new Error('Los accesos del DEMO requieren el modo manual.');
  const emails={
    admin:'admin.sil@example.invalid',
    uploader:'operador.sil@example.invalid',
    patient:'paciente.sil@example.invalid',
  };
  let passwords;
  try {
    passwords=JSON.parse(raw);
  } catch {
    throw new Error('No se pudieron leer las contraseñas del ensayo.');
  }
  return Object.fromEntries(Object.entries(emails).map(([key,email])=>{
    const value=passwords?.[key];
    if(typeof value!=='string'||value.length===0||Buffer.byteLength(value,'utf8')>1024){
      throw new Error('Ingresa una contraseña válida para '+email+'.');
    }
    return [key,{email,password:value}];
  }));
}

async function main() {
  if(process.env.VITALIA_ISOLATED_REHEARSAL!=='YES' ||
    process.env.PGHOST!=='127.0.0.1' ||
    process.env.PGUSER!=='vitalia_restore' ||
    process.env.PGDATABASE!=='vitalia_restored') {
    throw new Error('Se requiere PostgreSQL aislado, vacío y accesible por loopback.');
  }
  const container=process.env.VITALIA_JOURNEY_DB_CONTAINER;
  if(container && (!/^vitalia-edge-qa-[a-f0-9]{12}$/.test(container) || process.env.PGPORT!=='55439')){
    throw new Error('El contenedor local debe pertenecer al ensayo de Edge.');
  }
  const manual=process.env.VITALIA_JOURNEY_MANUAL==='YES';
  const demo=demoAccounts(manual);
  const fixture=process.env.VITALIA_JOURNEY_FIXTURE;
  if(manual && (!process.env.VITALIA_JOURNEY_WEB || !fixture)){
    throw new Error('El ensayo manual requiere una compilación web y una ruta para el PDF ficticio.');
  }
  const db=new Pool({connectionTimeoutMillis:5000});
  let server, webServer;
  try {
    await prepare(db,container);
    const roles={
      admin:'administrador', uploader:'operador_laboratorio',
      reviewer:'operador_laboratorio', patient:'paciente', other:'paciente',
    };
    const ids={};
    const credentials=Object.fromEntries(Object.keys(roles).map(name=>[
      name,demo[name]??{email:name+'@example.invalid',password},
    ]));
    const passwordHash=await hashPassword(password);
    for(const [name,role] of Object.entries(roles)){
      ids[name]=randomUUID();
      await db.query('INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,$3,$4)',
        [ids[name],credentials[name].email,demo[name]?await hashPassword(credentials[name].password):passwordHash,role]);
    }

    process.env.VITALIA_SIL_MAIN_MODE='YES';
    const host=express();
    const web=process.env.VITALIA_JOURNEY_WEB;
    host.use(createApp({
      authenticate:await createCredentialAuthenticator(db,{guardPatientSession:process.env.VITALIA_SIL_MAIN_MODE==='YES'}),
      issue:(id,mode,hash)=>issueSession(db,id,mode,hash),
      find:token=>findSessionAccount(db,token),
      revoke:token=>revokeSession(db,token),
    },...Array(18).fill(undefined),createSilMainService(db)));
    server=await new Promise((accept,reject)=>{
      const listener=host.listen(3119,'127.0.0.1',()=>accept(listener));
      listener.once('error',reject);
    });

    const tokens={};
    for(const [name,mode] of Object.entries(roles)){
      const login=await api('POST','/api/auth/login',200,{
        json:{mode,...credentials[name]},
      });
      const {token}=await login.json();
      tokens[name]=token;
      const me=await api('GET','/api/auth/me',200,{token});
      assert.equal((await me.json()).user.role,mode);
    }
    const call=(actor,method,path,status,data)=>api(method,'/api/sil/main'+path,status,
      {token:tokens[actor],...data});
    const admin=(path,status,json)=>call('admin','POST',path,status,{json});
    const lab=async name=>(await (await admin('/labs',201,{displayName:name})).json()).laboratory.id;
    const base='/labs/'+await lab('Laboratorio sintético Norte');
    const otherLab='/labs/'+await lab('Laboratorio sintético Sur');
    await admin(base+'/staff',201,{accountId:ids.uploader});
    await admin(base+'/staff',201,{accountId:ids.reviewer});
    await admin(otherLab+'/staff',201,{accountId:ids.reviewer});
    await admin(otherLab+'/staff/review-permission',200,{accountId:ids.reviewer,enabled:true});
    await call('uploader','POST',base+'/patients',201,{json:{
      patientId:ids.patient,identityEvidenceReference:'verificacion-ficticia',identityVerified:true,
    }});
    const directory=await call('uploader','GET',base+'/patients?search='+encodeURIComponent(credentials.patient.email.toUpperCase())+'&limit=1',200);
    const linked=await directory.json();
    assert.deepEqual(linked.patients.map(patient=>patient.id),[ids.patient]);
    assert.equal(linked.hasMore,false);
    const otherDirectory=await call('reviewer','GET',otherLab+'/patients',200);
    assert.deepEqual((await otherDirectory.json()).patients,[]);
    await call('uploader','GET',otherLab+'/patients',403);
    const requestPdf=syntheticPdf([
      'Referencia: SOL-1002','Profesional solicitante: Persona Ficticia',
      'Fecha de solicitud: 2024-01-01','Glicemia',
    ]);
    const intake=base+'/medical-requests';
    const requestFile={bytes:requestPdf,headers:{
      'Content-Type':'application/pdf','x-request-filename':'solicitud.pdf',
    }};
    await call('uploader','POST',otherLab+'/medical-requests/preview',403,requestFile);
    const preview=await (await call('uploader','POST',intake+'/preview',200,requestFile)).json();
    assert.equal(preview.state,'text_ready');
    assert.equal(preview.suggestedDocumentReference,'SOL-1002');
    assert.equal(preview.suggestedPrescriberName,'Persona Ficticia');
    assert.equal(preview.suggestedRequestDate,'2024-01-01');
    assert.ok(preview.suggestedExams.some(exam=>exam.code==='glicemia'));
    assert.equal((await (await call('uploader','GET',base+'/orders',200)).json()).orders.length,0);
    const confirmation={bytes:requestPdf,headers:{
      ...requestFile.headers,
      'x-request-patient-id':ids.patient,'x-request-exam-codes':'glicemia',
      'x-request-reference':'SOL-1002','x-request-prescriber':'Persona Ficticia',
      'x-request-date':'2024-01-01','x-request-identity-confirmed':'true',
      'x-request-reviewed':'true',
    }};
    await call('uploader','POST',intake,400,{...confirmation,headers:{
      ...confirmation.headers,'x-request-reviewed':'false',
    }});
    await call('uploader','POST',intake,404,{...confirmation,headers:{
      ...confirmation.headers,'x-request-patient-id':ids.other,
    }});
    const created=await call('uploader','POST',intake,201,confirmation);
    const orderId=(await created.json()).order.id;
    await call('uploader','POST',intake,409,confirmation);
    assert.equal((await (await call('uploader','GET',base+'/orders',200)).json()).orders.length,1);
    const requestPath='/orders/'+orderId+'/medical-request/file';
    await call('patient','GET',base+requestPath,403);
    await call('uploader','GET',otherLab+requestPath,403);
    await call('reviewer','GET',otherLab+requestPath,404);
    const original=await call('uploader','GET',base+requestPath,200);
    assert.deepEqual(Buffer.from(await original.arrayBuffer()),requestPdf);
    console.log('API: lectura, confirmación y registro atómico de solicitud verificados.');
    const clinical=base+'/orders/'+orderId+'/clinical';
    assert.equal((await (await call('uploader','GET',clinical,200)).json()).hasMedicalRequest,true);
    const sample=code=>({json:{containerCode:code}});
    const values={json:{values:[{examCode:'glicemia',analyte:'Glucosa',numericValue:91.2}]}};
    await call('uploader','GET',otherLab+'/orders/'+orderId+'/clinical',403);
    await call('reviewer','GET',otherLab+'/orders/'+orderId+'/clinical',404);
    await call('uploader','POST',clinical+'/results',409,values);
    await call('uploader','POST',clinical+'/samples',409,sample('edta'));
    const resultsPreview=clinical+'/results/preview';
    const resultsPdf=(barcode,...lines)=>({bytes:syntheticPdf([
      'Vitalia - resultados ficticios','Muestra: '+barcode,...lines,
    ]),headers:{'Content-Type':'application/pdf'}});
    const wrongBarcode='LAB-'+randomUUID().toUpperCase();
    await call('uploader','POST',resultsPreview,409,resultsPdf(wrongBarcode,'Glucosa 91,2 mg/dL'));
    const {barcode}=await (await call('uploader','POST',clinical+'/samples',201,sample('fluoride'))).json();
    const matching=resultsPdf(barcode,'Glucosa 91,2 mg/dL');
    await call('patient','POST',resultsPreview,403,matching);
    await call('uploader','POST',otherLab+'/orders/'+orderId+'/clinical/results/preview',403,matching);
    await call('reviewer','POST',otherLab+'/orders/'+orderId+'/clinical/results/preview',404,matching);
    const resultPreview=async file=>(await call('uploader','POST',resultsPreview,200,file)).json();
    assert.deepEqual(await resultPreview(matching),{
      state:'text_ready',items:[{examCode:'glicemia',analyte:'Glucosa',unit:'mg/dL',suggestedValue:91.2}],
    });
    for(const file of [
      resultsPdf(wrongBarcode,'Glucosa 91,2 mg/dL'),
      resultsPdf(barcode,'Muestra: '+wrongBarcode,'Glucosa 91,2 mg/dL'),
    ]){
      assert.deepEqual(await resultPreview(file),{state:'sample_mismatch',items:[]});
    }
    for(const lines of [
      ['Glucosa 5 mmol/L'],
      ['Glucosa 90 mg/dL','Glucosa 91 mg/dL'],
      ['Glucosa 1.234 mg/dL'],
      ['Glucosa 90 mg/dL 70-110'],
    ]){
      assert.equal((await resultPreview(resultsPdf(barcode,...lines))).items[0].suggestedValue,null);
    }
    assert.equal((await (await call('uploader','GET',clinical,200)).json()).results,null);
    console.log('API: vista previa de resultados sin persistencia, con muestras y unidades cotejadas.');
    await call('uploader','POST',clinical+'/samples',409,sample('fluoride'));
    await call('uploader','POST',clinical+'/results',201,values);
    await call('uploader','POST',resultsPreview,409,matching);
    await call('uploader','POST',clinical+'/review',403,{json:{decision:'approved'}});
    await admin(base+'/staff/review-permission',200,{accountId:ids.uploader,enabled:true});
    await call('uploader','POST',clinical+'/review',200,{json:{decision:'returned',reason:'Revisar valor transcrito'}});
    await call('uploader','POST',clinical+'/results',201,{json:{values:[
      {examCode:'glicemia',analyte:'Glucosa',numericValue:93.1},
    ]}});
    await call('uploader','POST',clinical+'/review',200,{json:{decision:'approved'}});
    const recorded=await (await call('uploader','GET',clinical,200)).json();
    assert.equal(recorded.results.status,'approved');
    assert.equal(recorded.results.values[0].numericValue,93.1);
    console.log('API: muestras, resultados por analito, devolución, corrección y aprobación verificados.');
    const path=base+'/orders/'+orderId+'/report';
    const attached=await call('uploader','POST',path,201,{bytes:pdf,headers:{
      'Content-Type':'application/pdf','X-Report-Filename':'informe-sintetico.pdf',
      'X-Report-Authorized-Professional':'Profesional Ficticio',
      'X-Report-Authorization-Ref':'AUT-FICTICIA',
      'X-Report-Authorized-At':'2024-01-01T12:00:00Z','X-Report-Patient-Confirmed':'true',
    }});
    const reportId=(await attached.json()).report.id;
    const patientFile='/patient/reports/'+reportId+'/file';
    await call('patient','GET',patientFile,404);
    await call('reviewer','GET',path+'/file',403);
    await call('reviewer','GET',otherLab+'/orders/'+orderId+'/report/file',404);
    await admin(base+'/staff/review-permission',200,{accountId:ids.uploader,enabled:true});
    const publish=(actor,status)=>call(actor,'POST',path+'/publish',status,{json:{operatorReviewConfirmed:true}});
    await publish('uploader',409);
    await admin(base+'/staff/review-permission',200,{accountId:ids.reviewer,enabled:true});
    await publish('reviewer',409);
    await call('reviewer','GET',path+'/file',200);
    await publish('uploader',409); // La revisión de otra cuenta no habilita esta publicación.
    const pending=await call('uploader','GET',path+'/file',200);
    assert.deepEqual(Buffer.from(await pending.arrayBuffer()),pdf);
    await admin(base+'/staff/review-permission',200,{accountId:ids.uploader,enabled:false});
    await publish('uploader',403);
    await admin(base+'/staff/review-permission',200,{accountId:ids.uploader,enabled:true});
    await publish('uploader',201);
    await publish('uploader',409);
    await call('other','GET',patientFile,404);
    const patient=await call('patient','GET',patientFile,200);
    assert.deepEqual(Buffer.from(await patient.arrayBuffer()),pdf);
    const historyPath=clinical+'/audit';
    await api('GET','/api/sil/main'+historyPath,401);
    await call('patient','GET',historyPath,403);
    await call('uploader','GET',otherLab+'/orders/'+orderId+'/clinical/audit',403);
    await call('reviewer','GET',otherLab+'/orders/'+orderId+'/clinical/audit',404);
    const historyResponse=await call('uploader','GET',historyPath,200);
    assert.equal(historyResponse.headers.get('cache-control'),'private, no-store');
    const {events,hasOlder}=await historyResponse.json();
    assert.equal(hasOlder,false);
    assert.ok(events.length>1);
    assert.ok(events.every((event,index)=>index===0||event.createdAt<=events[index-1].createdAt));
    assert.ok(events.some(event=>event.action==='results_recorded'&&event.staffEmail===credentials.uploader.email));
    assert.ok(events.some(event=>event.action==='report_downloaded'&&event.staffEmail===null));
    assert.ok(events.every(event=>Object.keys(event).sort().join(',')==='action,createdAt,staffEmail'));
    console.log('API: historial de la orden verificado con aislamiento por laboratorio y datos mínimos.');
    const audit=await db.query(`SELECT action,actor_id FROM public.vitalia_sil_main_audit
      WHERE order_id=$1 ORDER BY created_at,id`,[orderId]);
    for(const [action,actor] of [
      ['report_attached','uploader'],['report_review_accessed','uploader'],
      ['report_published','uploader'],['report_downloaded','patient'],
    ]){
      assert.ok(audit.rows.some(row=>row.action===action && row.actor_id===ids[actor]),action);
    }
    await api('POST','/api/auth/logout',204,{token:tokens.patient});
    await call('patient','GET',patientFile,401);
    // El operador recibe una derivación y la guarda SIN una cuenta paciente.
    const pendingEmail='patient-invited@example.invalid';
    const pendingPdf=syntheticPdf([
      'Paciente: Ana María Pérez Soto','RUT: 12.345.678-5',
      'Fecha de nacimiento: 12/04/1990',
      'Correo electrónico: patient-invited@example.invalid',
      'Teléfono: +56 9 1234 5678',
      'Sexo: Femenino',
      'Referencia: SOL-PEND-0042',
      'Profesional solicitante: Persona Ficticia',
      'Fecha de solicitud: 2024-01-01','Glicemia',
    ]);
    const pendingPath=base+'/medical-requests/pending';
    const pendingUpload={bytes:pendingPdf,headers:{
      'Content-Type':'application/pdf',
      'x-request-filename':'derivacion-pendiente.pdf',
      'x-request-patient-email':pendingEmail,
    }};
    // La sesión del paciente fue revocada arriba: debe recibir 401, no 403.
    await call('patient','POST',pendingPath,401,pendingUpload);
    await call('uploader','POST',otherLab+'/medical-requests/pending',403,pendingUpload);
    const savedPending=await (await call('uploader','POST',pendingPath,201,pendingUpload)).json();
    const pendingId=savedPending.pending.id;
    assert.equal(savedPending.pending.status,'pending');
    assert.equal(savedPending.pending.patientEmail,pendingEmail);
    assert.ok(Object.hasOwn(savedPending.pending.suggestions,'suggestedPatient'));
    await call('uploader','POST',pendingPath,409,pendingUpload);
    const savedList=await (await call('uploader','GET',pendingPath,200)).json();
    assert.ok(savedList.pending.some(item=>item.id===pendingId));
    await call('patient','GET',pendingPath,401);
    await call('reviewer','GET',otherLab+'/medical-requests/pending/'+pendingId+'/file',404);
    const savedPdf=await call('uploader','GET',
      pendingPath+'/'+pendingId+'/file',200);
    assert.deepEqual(Buffer.from(await savedPdf.arrayBuffer()),pendingPdf);
    const pendingBeforeActivation=await db.query(
      'SELECT status,order_id FROM public.vitalia_sil_main_pending_requests WHERE id=$1',
      [pendingId]);
    assert.equal(pendingBeforeActivation.rows[0].status,'pending');
    assert.equal(pendingBeforeActivation.rows[0].order_id,null);
    const pendingOrdersBefore=await db.query(
      'SELECT count(*)::int AS total FROM public.vitalia_sil_main_orders WHERE lab_id=$1',[base.slice(6)]);
    assert.ok(pendingOrdersBefore.rows[0].total>=1);
    console.log('API: derivación con identidad sugerida guardada sin cuenta ni orden.');


    const inviteEmail='patient-invited@example.invalid';
    const inviteInput={email:inviteEmail,identityReference:'verificacion-ficticia-invitacion',identityConfirmed:true};
    const oldInvite=await (await call('uploader','POST',base+'/patient-invitations',201,{json:inviteInput})).json();
    const invite=await (await call('uploader','POST',base+'/patient-invitations',201,{json:inviteInput})).json();
    await api('POST','/api/sil/main/patients/activate',403,{json:{email:inviteEmail,code:oldInvite.code,password}});
    const activation={email:inviteEmail,code:invite.code,password};
    await api('POST','/api/sil/main/patients/activate',201,{json:activation});
    await call('uploader','POST',base+'/patient-invitations',409,{json:inviteInput});
    await api('POST','/api/sil/main/patients/activate',403,{json:activation});
    const invited=await (await api('POST','/api/auth/login',200,{json:{
      mode:'paciente',email:inviteEmail,password,
    }})).json();
    const recovery=await (await api('POST','/api/sil/main/patient/recovery/key',201,{
      token:invited.token,json:{currentPassword:password},
    })).json();
    const recovered={email:inviteEmail,recoveryKey:recovery.recoveryKey,password:'ClaveNueva-SoloPrueba-2026!'};
    await api('POST','/api/sil/main/patient/recovery/complete',204,{json:recovered});
    await api('POST','/api/sil/main/patient/recovery/complete',422,{json:recovered});
    await api('GET','/api/auth/me',401,{token:invited.token});
    await api('POST','/api/auth/login',401,{json:{mode:'paciente',email:inviteEmail,password}});
    await api('POST','/api/auth/login',200,{json:{
      mode:'paciente',email:inviteEmail,password:recovered.password,
    }});
    const pendingPatient=(await db.query(
      'SELECT id FROM public.vitalia_accounts WHERE email=$1',[pendingEmail])).rows[0];
    assert.ok(pendingPatient?.id,'La activación debe crear cuenta paciente.');
    const pendingComplete=pendingPath+'/'+pendingId+'/complete';
    const pendingData={
      patientId:pendingPatient.id,patientEmail:pendingEmail,
      examCodes:['glicemia'],
      documentReference:'SOL-PEND-0042',
      prescriberName:'Persona Ficticia',
      requestDate:'2024-01-01',
      patientIdentityConfirmed:true,humanReviewConfirmed:true,
    };
    await call('uploader','POST',pendingComplete,400,{json:{
      ...pendingData,patientIdentityConfirmed:false,
    }});
    // Bloquear reutilización de la derivación para otro correo,
    // antes incluso de comprobar si existe la cuenta del paciente.
    await call('uploader','POST',pendingComplete,409,{json:{
      ...pendingData,patientEmail:'equivocado@example.invalid',
    }});
    await call('reviewer','POST',otherLab+'/medical-requests/pending/'+pendingId+'/complete',404,{
      json:pendingData,
    });
    const completed=await (await call('uploader','POST',pendingComplete,201,{
      json:pendingData,
    })).json();
    assert.equal(completed.pending.status,'completed');
    assert.equal(completed.order.patientId,pendingPatient.id);
    await call('uploader','POST',pendingComplete,404,{json:pendingData});
    const pendingAfter=await (await call('uploader','GET',pendingPath,200)).json();
    assert.ok(!pendingAfter.pending.some(item=>item.id===pendingId));
    const pendingSaved=await db.query(
      'SELECT status,order_id FROM public.vitalia_sil_main_pending_requests WHERE id=$1',
      [pendingId]);
    assert.equal(pendingSaved.rows[0].status,'completed');
    assert.equal(pendingSaved.rows[0].order_id,completed.order.id);
    const completedPdf=await call('uploader','GET',
      base+'/orders/'+completed.order.id+'/medical-request/file',200);
    assert.deepEqual(Buffer.from(await completedPdf.arrayBuffer()),pendingPdf);
    const pendingAudit=await db.query(
      "SELECT action FROM public.vitalia_sil_main_audit WHERE lab_id=$1 AND action LIKE 'pending_request_%'",
      [base.slice(6)]);
    assert.ok(pendingAudit.rows.some(row=>row.action==='pending_request_saved'));
    assert.ok(pendingAudit.rows.some(row=>row.action==='pending_request_downloaded'));
    assert.ok(pendingAudit.rows.some(row=>row.action==='pending_request_completed'));
    console.log('API: derivación pendiente recuperada, activación y orden atómica aprobadas.');

    console.log('API: activación y recuperación del paciente de un solo uso verificadas.');
    console.log('API y PostgreSQL: recorrido con credenciales y sesiones reales aprobado.');
    if(web){
      const site=express();
      site.use(express.static(resolve(web)));
      webServer=await new Promise((accept,reject)=>{
        const listener=site.listen(5173,'127.0.0.1',()=>accept(listener));
        listener.once('error',reject);
      });
      const browserOrder=await call('uploader','POST',base+'/orders',201,{json:{
        patientId:ids.patient,examCodes:['glicemia'],
      }});
      const {order:ready}=await browserOrder.json();
      const {order:sampleOrder}=await (await call('uploader','POST',base+'/orders',201,{json:{
        patientId:ids.patient,examCodes:['glicemia'],
      }})).json();
      const queryOrders=async (actor,labPath,query,status=200)=>(await call(actor,'GET',
        labPath+'/orders?'+new URLSearchParams(query),status)).json();
      const page1=await queryOrders('uploader',base,{limit:1});
      const page2=await queryOrders('uploader',base,{limit:1,offset:1});
      assert.equal(page1.hasMore,true);
      assert.notEqual(page1.orders[0].id,page2.orders[0].id);
      const folio='VH-'+String(sampleOrder.orderNumber).padStart(6,'0');
      const found=await queryOrders('uploader',base,{
        search:folio.toLowerCase(),status:'registered',patientId:ids.patient,
      });
      assert.deepEqual(found.orders.map(order=>order.id),[sampleOrder.id]);
      const email=await queryOrders('uploader',base,{search:credentials.patient.email.toUpperCase()});
      assert.ok(email.orders.some(order=>order.id===sampleOrder.id));
      assert.deepEqual((await queryOrders('uploader',base,{search:folio,status:'report_published'})).orders,[]);
      assert.deepEqual((await queryOrders('uploader',base,{patientId:ids.other})).orders,[]);
      assert.deepEqual((await queryOrders('reviewer',otherLab,{search:folio})).orders,[]);
      await queryOrders('uploader',otherLab,{search:folio},403);
      await queryOrders('admin',base,{search:credentials.patient.email},403);
      await queryOrders('uploader',base,{status:'missing'},400);
      console.log('API: búsqueda, filtros y paginación de órdenes verificados.');
      const samplePath=base+'/orders/'+sampleOrder.id;
      assert.equal((await (await call('uploader','GET',samplePath+'/clinical',200)).json()).hasMedicalRequest,false);
      await call('uploader','POST',samplePath+'/medical-request',201,{
        bytes:browserRequestPdf,headers:{
          ...requestFile.headers,'x-request-reference':'SOL-1004',
          'x-request-prescriber':'Persona Ficticia','x-request-date':'2024-01-01',
          'x-request-identity-confirmed':'true','x-request-reviewed':'true',
        },
      });
      const {barcode:sampleCode}=await (await call('uploader','POST',
        base+'/orders/'+sampleOrder.id+'/clinical/samples',201,sample('fluoride'))).json();
      const samplePdf=resultsPdf(sampleCode,'Glucosa 91,2 mg/dL').bytes;
      if(manual){
        writeFileSync(fixture,pdf,{flag:'wx'});
        const newRequest=resolve(dirname(fixture),'solicitud-ficticia.pdf');
        writeFileSync(newRequest,syntheticPdf([
          'Referencia: SOL-1003','Profesional solicitante: Persona Ficticia',
          'Fecha de solicitud: 2024-01-01','Glicemia',
        ]),{flag:'wx'});
        const resultsFixture=resolve(dirname(fixture),'resultados-ficticios.pdf');
        writeFileSync(resultsFixture,samplePdf,{flag:'wx'});
        console.log('PDF para crear una orden desde Recibir solicitud: '+newRequest);
        console.log('Orden para probar la lectura de resultados: VH-'+String(sampleOrder.orderNumber).padStart(6,'0'));
        console.log('PDF para Muestras y resultados > Leer PDF de resultados: '+resultsFixture);
        console.log('\nSIL temporal listo en http://localhost:5173/#/laboratorio');
        console.log('Orden disponible: VH-'+String(ready.orderNumber).padStart(6,'0'));
        console.log('Adjunta el PDF con '+credentials.uploader.email+'.');
        console.log('Con esa misma cuenta, descarga el PDF de revisión, confirma y publica.');
        console.log('Consulta el informe con '+credentials.patient.email+' en http://localhost:5173/.');
        if(demo.admin){
          console.log('Acceso de administración de prueba: '+credentials.admin.email+'.');
          console.log('Usa las contraseñas del DEMO que ingresaste en PowerShell.');
        } else {
          console.log('Contraseña de estas cuentas ficticias: '+password);
        }
        console.log('PDF para adjuntar: '+fixture);
        const input=createInterface({input:process.stdin,output:process.stdout});
        try {
          await input.question('Pulsa Enter para cerrar el ensayo.\n');
        } finally {
          input.close();
        }
      } else {
        await browserJourney(ready,base,sampleOrder,samplePdf);
      }
    }
  } finally {
    if(webServer)await new Promise(done=>webServer.close(done));
    if(server)await new Promise(done=>server.close(done));
    await db.end();
  }
}

main().catch(error=>{console.error(error.message);process.exitCode=1;});
