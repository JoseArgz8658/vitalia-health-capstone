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
const {createPatientRegistrar} = require('../dist/auth/registration');
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
  // Los campos de entrada deben estar disponibles en el árbol accesible desde el inicio.
  if(route==='' || route==='#/laboratorio' || route==='#/administracion'){
    const oldLink=page.getByRole('button',{name:'Cambiar a modo profesional',exact:true});
    assert.equal(await oldLink.count(),0);
    if(route===''){
      await page.getByRole('button',{name:'Acceso del personal de laboratorio',exact:true}).waitFor();
    }
    if(route==='#/laboratorio'){
      await page.getByRole('button',{name:'Acceso de administración',exact:true}).waitFor();
    }
  }
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
  const stage=async (account, task)=>{
    const page=await browser.newPage({viewport:{width:1440,height:1150}});
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

  return stage('uploader',async ({page,id,button,click,select,confirm})=>{
    const captures=process.env.VITALIA_JOURNEY_SCREENSHOTS;
    const operatorNav=page.getByRole('navigation',{name:'Navegación del operador'});
    const receive=operatorNav.getByRole('button',{name:'Recibir solicitud',exact:true});
    await receive.waitFor();
    const desktop=await receive.boundingBox();
    assert.ok(desktop && desktop.y>=0 && desktop.y+desktop.height<=140 && desktop.width>0,
      'Recibir solicitud debe estar en la navegación superior de escritorio.');
    if(captures)await page.screenshot({path:resolve(captures,'operador-escritorio.png')});

    // Una sesión sirve para ambos tamaños y mantiene disponible el cupo
    // de autenticación de la cuenta paciente en el mismo proceso de prueba.
    await page.setViewportSize({width:390,height:844});
    await receive.click();
    const pdfPicker = button('Seleccionar solicitud PDF');
    await pdfPicker.waitFor();
    const pickerPosition = await pdfPicker.boundingBox();
    assert.ok(pickerPosition && pickerPosition.y >= 0 &&
      pickerPosition.y + pickerPosition.height <= page.viewportSize().height,
      'El selector de PDF debe quedar visible sin desplazarse en móvil.');
    const pdfReader=button('Leer PDF y sugerir datos');
    assert.equal(await pdfReader.count(),0,'La lectura aparece al seleccionar un PDF');
    assert.equal(await button('Buscar paciente activado').count(),0);
    if(captures)await page.screenshot({path:resolve(captures,'recepcion-movil.png')});
    await page.setViewportSize({width:1440,height:1150});
    const requestChooser = page.waitForEvent('filechooser');
    await click(pdfPicker, 'Seleccionar solicitud PDF');
    await (await requestChooser).setFiles({
      name: 'solicitud-ensayo.pdf', mimeType: 'application/pdf', buffer: samplePdf,
    });
    await pdfReader.waitFor();
    await button('Buscar paciente activado').waitFor();
    assert.equal(await button('Crear orden con solicitud').count(),0);
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
    assert.equal(await id('sil-upload-order').count(),0);
    await click(page.getByText('Adjuntar informe autorizado',{exact:true}), 'Adjuntar informe autorizado');
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
    await click(id('sil-review-order-'+order.id), 'Elegir informe pendiente '+name);
    const publication=button('Publicar informe');
    assert.equal(await publication.count(),0,'Se exige revisar antes de publicar');
    const download=page.waitForEvent('download');
    const reviewResponse=page.waitForResponse(r=>r.url().endsWith(endpoint+'/file') && r.request().method()==='GET');
    await click(button('Descargar PDF para revisión'),'Descargar para revisión');
    assert.equal((await reviewResponse).status(),200);
    assert.deepEqual(readFileSync(await (await download).path()),pdf);
    await publication.waitFor();
    assert.equal(await publication.isEnabled(),false,'Se exige confirmar el cotejo');
    await confirm('Confirmo que revisé el PDF y su autorización externa');
    const posted=page.waitForResponse(r=>r.url().endsWith(endpoint+'/publish') && r.request().method()==='POST');
    await click(publication,'Publicar informe');
    assert.equal((await posted).status(),201);
    console.log('Microsoft Edge: el mismo operador descargó, revisó y publicó el PDF.');
    return reportId;
  });
}

// La interfaz administrativa se comprueba con sesión real, no con mocks.
// Solo se leen los datos sintéticos y las acciones ya autorizadas; no
// se revocan permisos necesarios para el resto del recorrido.
async function adminJourney(browser, base) {
  const page=await browser.newPage({viewport:{width:1440,height:1050}});
  try {
    const responseLabs=page.waitForResponse(r=>
      new URL(r.url()).pathname==='/api/sil/main/labs' &&
      r.request().method()==='GET',{timeout:15000});
    await signIn(page,'admin','#/administracion');
    const labsHttp=await responseLabs;
    const labData=await labsHttp.json();
    console.log('Edge admin: GET /labs HTTP '+labsHttp.status()+
      ' cantidad='+String(labData.laboratories?.length ?? 'invalida'));
    assert.equal(labsHttp.status(),200);
    assert.ok(Array.isArray(labData.laboratories) &&
      labData.laboratories.length>=2,
      'La sesión de administración debe recibir ambos laboratorios de ensayo.');
    await page.getByText('Administración de laboratorios',{exact:true})
      .waitFor({timeout:15000});
    const nav=label=>page.getByRole('button',{name:label,exact:true});
    await nav('Laboratorios').waitFor();
    await nav('Operadores y permisos').waitFor();
    await nav('Actividad').waitFor();
    assert.equal(await nav('Recibir solicitud').count(),0,
      'Administración no debe presentar acciones clínicas de operador.');
    assert.equal(await nav('Publicar informe').count(),0,
      'El administrador no puede publicar informes desde su estación.');
    // Los resúmenes de la columna secundaria pueden estar fuera del
    // viewport; comprobamos controles operativos de la administración.
    await nav('Registrar laboratorio').waitFor({timeout:10000});
    if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
      await page.screenshot({path:resolve(
        process.env.VITALIA_JOURNEY_SCREENSHOTS, 'administrador-laboratorios.png')});
    }

    const siteDirectory=page.waitForResponse(response=>
      new URL(response.url()).pathname==='/api/sil/main'+base+'/sites' &&
      response.request().method()==='GET');
    await nav('Sedes').click();
    assert.equal((await siteDirectory).status(),200);
    await nav('Nueva sede').waitFor();
    await nav('Nueva sede').click();
    await nav('Guardar sede').waitFor();
    await nav('Cancelar').click();
    if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
      await page.screenshot({path:resolve(
        process.env.VITALIA_JOURNEY_SCREENSHOTS,'administrador-sedes.png')});
    }
    await nav('Operadores y permisos').click();
    // Flutter Canvas muestra los textos en pantalla, pero no todos son
    // localizadores HTML. Comprobar controles accesibles y la respuesta real.
    const refreshStaff=nav('Actualizar operadores');
    await refreshStaff.waitFor({timeout:10000});
    const staffResponse=page.waitForResponse(r=>
      new URL(r.url()).pathname==='/api/sil/main'+base+'/staff' &&
      r.request().method()==='GET');
    await refreshStaff.click();
    const staffHttp=await staffResponse;
    assert.equal(staffHttp.status(),200);
    const staffBody=await staffHttp.json();
    const entries=staffBody.staff ?? [];
    assert.equal(entries.length,2,'La administración debe listar ambos operadores.');
    assert.deepEqual(entries.map(m=>m.email).sort(),
      ['reviewer@example.invalid','uploader@example.invalid']);
    assert.ok(entries.every(m=>m.active && m.canReviewReports),
      'Ambos operadores tienen revisión autorizada inicialmente.');
    await nav('Retirar permiso de revisión').first().waitFor();
    if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
      await page.screenshot({
        path:resolve(process.env.VITALIA_JOURNEY_SCREENSHOTS,
          'administrador-operadores.png'),
      });
      await page.setViewportSize({width:390,height:844});
      await nav('Invitar operador').waitFor();
      await page.screenshot({path:resolve(
        process.env.VITALIA_JOURNEY_SCREENSHOTS, 'administrador-movil.png')});
      await page.setViewportSize({width:1440,height:1050});
    }
    // En esta copia sintética ambos operadores tienen permiso concedido.
    // Probar el ciclo de revocación y restitución, dejando el estado original
    // para que el recorrido del operador continúe sin cambios.
    const permissionPath='/api/sil/main'+base+'/staff/review-permission';
    const permissionResponse=()=>page.waitForResponse(r=>
      new URL(r.url()).pathname===permissionPath &&
      r.request().method()==='POST');
    const confirmPermission=()=>Promise.all([
      permissionResponse(),
      nav('Confirmar permiso').click(),
    ]).then(([response])=>response);
    const revoke=nav('Retirar permiso de revisión').first();
    await (await reach(page,revoke,'Revocar revisión')).click();
    const revokedResult=await confirmPermission();
    assert.equal(revokedResult.status(),200);
    const revokedInput=revokedResult.request().postDataJSON();
    assert.equal(revokedInput.enabled,false);
    const grant=nav('Autorizar revisión');
    await (await reach(page,grant,'Restituir revisión')).waitFor();
    await grant.click();
    const grantedResult=await confirmPermission();
    assert.equal(grantedResult.status(),200);
    assert.deepEqual(grantedResult.request().postDataJSON(),{
      accountId:revokedInput.accountId,enabled:true,
    },'Solo se restituye el permiso que se revocó en el ensayo.');

    await nav('Actividad').click();
    await nav('Actualizar estado administrativo').waitFor({timeout:10000});
    assert.equal(await nav('Descargar solicitud original').count(),0,
      'La actividad administrativa no muestra documentos de órdenes.');
    assert.equal(await nav('Descargar PDF').count(),0,
      'El administrador no debe ver el portal privado del paciente.');
    if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
      await page.screenshot({
        path:resolve(process.env.VITALIA_JOURNEY_SCREENSHOTS,
          'administrador-escritorio.png'),
      });
    }
    console.log('Microsoft Edge: administración, laboratorios, permisos y actividad verificados.');
  } finally {
    await page.close();
  }
}

async function browserJourney(order, base, sampleOrder, samplePdf) {
  const {chromium}=require(process.env.VITALIA_JOURNEY_PLAYWRIGHT);
  const browser=await chromium.launch({channel:'msedge'});
  try {
    await adminJourney(browser,base);
    const publishedId=await operatorJourney(browser,order,base,sampleOrder,samplePdf);
    const page=await browser.newPage({viewport:{width:390,height:844}});
    try {
      await signIn(page,'patient');
      const patientNav=page.getByRole('navigation',{name:'Navegación del paciente'});
      await patientNav.getByRole('button',
        {name:'Mis informes',exact:true}).waitFor();
      assert.equal(await page.getByRole('button',
        {name:'Recibir solicitud',exact:true}).count(),0,
        'El paciente no debe ver la estación interna del operador.');

      const help=patientNav.getByRole('button',{name:'Ayuda',exact:true});
      // La barra solo muestra flechas si realmente hay desbordamiento.
      // No reservar espacio para una flecha inexistente: con menos pestañas
      // el botón Ayuda puede caber íntegro a 390 px.
      const forward=page.getByRole('button',
        {name:'Mostrar más secciones',exact:true});
      for(let attempt=0;attempt<4;attempt++){
        const box=await help.boundingBox({timeout:500}).catch(()=>null);
        const arrowsVisible=await forward.count()>0;
        const rightEdge=page.viewportSize().width-(arrowsVisible?48:0);
        if(box && box.x>=0 && box.x+box.width<=rightEdge){
          break;
        }
        assert.ok(arrowsVisible && await forward.isEnabled(),
          'La ayuda debe ser alcanzable desde la navegación móvil.');
        await forward.click();
      }
      await help.click();
      // La presencia del botón del diálogo verifica que abrió Ayuda.
      const understood=page.getByRole('button',{name:'Entendido',exact:true});
      await understood.waitFor({timeout:10000});
      await understood.click();

      await page.getByRole('button',{name:'Mi cuenta'}).click();
      await page.getByRole('menuitem',{name:'Mi perfil'}).click();
      // El diálogo Mi perfil expone un control de cierre accesible. El
      // contenido se valida en el API real y en los tests de widgets.
      const closeProfile=page.getByRole('button',{name:'Cerrar',exact:true});
      await closeProfile.waitFor({timeout:10000});
      await closeProfile.click();

      assert.equal(await page.getByText('Informes publicados',{exact:true}).count(),0);
      await patientNav.getByRole('button',{name:'Mis informes',exact:true}).click();
      await page.getByText('Informes publicados',{exact:true}).waitFor();
      const downloadButton=page.getByRole('button',{name:'Descargar PDF',exact:true}).first();
      assert.equal(await downloadButton.count(),0);
      await page.getByRole('button',{name:'Más opciones',exact:true}).first().click();
      await downloadButton.waitFor({timeout:20000});
      if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
        await page.setViewportSize({width:1440,height:1050});
        await downloadButton.waitFor();
        await page.screenshot({path:resolve(
          process.env.VITALIA_JOURNEY_SCREENSHOTS, 'paciente-escritorio.png')});
        await page.setViewportSize({width:390,height:844});
      }
      const downloaded=page.waitForEvent('download');
      const response=page.waitForResponse(r=>r.url().endsWith(
        '/patient/reports/'+publishedId+'/file'));
      await downloadButton.click();
      assert.equal((await response).status(),200);
      const file=await downloaded;
      assert.deepEqual(readFileSync(await file.path()),pdf);
      if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
        await page.screenshot({
          path:resolve(process.env.VITALIA_JOURNEY_SCREENSHOTS,
            'paciente-movil.png'),
        });
      }
      console.log('Microsoft Edge: paciente consultó ayuda, perfil y descargó informe publicado.');
    } finally {
      await page.close();
    }
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
    },createPatientRegistrar(db,{demoOnly:true}),...Array(17).fill(undefined),createSilMainService(db)));
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
    await admin(otherLab+'/staff',201,{email:credentials.reviewer.email.toUpperCase()});
    await admin(otherLab+'/staff/review-permission',200,{accountId:ids.reviewer,enabled:true});
    const northStaff = await (await call('admin', 'GET', base+'/staff', 200)).json();
    const southStaff = await (await call('admin', 'GET', otherLab+'/staff', 200)).json();
    assert.deepEqual(northStaff.staff.map(({email}) => email).sort(),
      [credentials.reviewer.email, credentials.uploader.email].sort());
    assert.deepEqual(southStaff.staff.map(({email}) => email), [credentials.reviewer.email]);
    assert.equal(northStaff.staff.find(({accountId}) => accountId === ids.reviewer)
      .canReviewReports, false, 'El permiso concedido en Sur no se aplica en Norte.');
    assert.equal(southStaff.staff[0].canReviewReports, true);
    await call('uploader', 'GET', base+'/staff', 403);
    await call('patient', 'GET', base+'/staff', 403);
    await call('admin', 'GET', base+'/medical-requests/pending', 403);
    const invitationPath=base+'/operator-invitations';
    const invitationEmail='operador-seguimiento@example.invalid';
    await admin(invitationPath,201,{email:invitationEmail});
    await admin(invitationPath,201,{email:invitationEmail});
    const invitations=await (await call('admin','GET',invitationPath,200)).json();
    assert.deepEqual(invitations.invitations.map(({status})=>status).sort(),['pending','revoked']);
    assert.ok(invitations.invitations.every(entry=>entry.email===invitationEmail &&
      !Object.hasOwn(entry,'code') && !Object.hasOwn(entry,'token_hash')));
    const otherInvitations=await (await call('admin','GET',otherLab+'/operator-invitations',200)).json();
    assert.deepEqual(otherInvitations.invitations,[]);
    const firstPage=await (await call('admin','GET',invitationPath+'?limit=1',200)).json();
    assert.equal(firstPage.invitations.length,1);
    assert.equal(firstPage.hasMore,true);
    await call('admin','GET',invitationPath+'?limit=51',400);
    await call('uploader','GET',invitationPath,403);
    const pendingInvitation=invitations.invitations.find(entry=>entry.status==='pending');
    const revokePath=invitationPath+'/revoke';
    const revoke={invitationId:pendingInvitation.id};
    await call('uploader','POST',revokePath,403,{json:revoke});
    await admin(otherLab+'/operator-invitations/revoke',404,revoke);
    await admin(revokePath,200,revoke);
    await admin(revokePath,404,revoke);
    const afterRevocation=await (await call('admin','GET',invitationPath,200)).json();
    assert.ok(afterRevocation.invitations.every(entry=>entry.status==='revoked'));
    const auditPath=base+'/administrative-audit';
    const northAudit=await (await call('admin','GET',auditPath,200)).json();
    assert.equal(northAudit.events.filter(event=>event.action==='operator_invited').length,2);
    assert.equal(northAudit.events.filter(event=>event.action==='operator_invitation_revoked').length,1);
    assert.ok(northAudit.events.every(event=>Object.keys(event).sort().join(',')===
      'action,actorEmail,createdAt,id'));
    const southAudit=await (await call('admin','GET',otherLab+'/administrative-audit',200)).json();
    assert.ok(southAudit.events.every(event=>event.action!=='operator_invited'));
    await call('patient','GET',auditPath,403);
    console.log('API: personal y permisos administrativos aislados por laboratorio.');
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
    const selfRegistered={email:'camino-b@example.invalid',password};
    await api('POST','/api/auth/register',202,{json:selfRegistered});
    const selfLogin=await api('POST','/api/auth/login',200,{
      json:{mode:'paciente',...selfRegistered},
    });
    const {token:selfToken}=await selfLogin.json();
    const patientCode='/api/sil/main/patient/link-code';
    const requestCode=async ()=>(await (await api('POST',patientCode,201,
      {token:selfToken,json:{}})).json()).code;
    const ownRecords='/api/sil/main/patient/reports';
    assert.deepEqual((await (await api('GET',ownRecords,200,{token:selfToken})).json()).reports,[]);
    const firstCode=await requestCode();
    const validCode=await requestCode();
    const linkPath=otherLab+'/patient-link-code';
    const verify={identityConfirmed:true,identityReference:'IDENTIDAD-FICTICIA-B'};
    await call('reviewer','POST',linkPath,404,{json:{...verify,code:firstCode}});
    await call('reviewer','POST',linkPath,400,{json:{...verify,code:validCode,identityConfirmed:false}});
    await call('uploader','POST',linkPath,403,{json:{...verify,code:validCode}});
    await call('admin','POST',linkPath,403,{json:{...verify,code:validCode}});
    await call('reviewer','POST',linkPath,200,{json:{...verify,code:validCode}});
    await call('reviewer','POST',base+'/patient-link-code',404,{json:{...verify,code:validCode}});
    const selfDirectory=await (await call('reviewer','GET',
      otherLab+'/patients?search='+encodeURIComponent(selfRegistered.email),200)).json();
    assert.deepEqual(selfDirectory.patients.map(p=>p.email),[selfRegistered.email]);
    const unlinkedDirectory=await (await call('uploader','GET',
      base+'/patients?search='+encodeURIComponent(selfRegistered.email),200)).json();
    assert.deepEqual(unlinkedDirectory.patients,[]);
    const expiringCode=await requestCode();
    await api('POST',patientCode,409,{token:selfToken,json:{}});
    await db.query(`UPDATE public.vitalia_sil_main_patient_link_codes
                    SET created_at=CURRENT_TIMESTAMP-INTERVAL '16 minutes',
                        expires_at=CURRENT_TIMESTAMP-INTERVAL '1 minute'
                    WHERE token_hash=$1`,
      [createHash('sha256').update(expiringCode).digest('hex')]);
    await call('reviewer','POST',base+'/patient-link-code',404,{json:{...verify,code:expiringCode}});
    const linkAudit=await db.query(
      `SELECT count(*)::int AS total FROM public.vitalia_sil_main_audit
       WHERE lab_id=$1 AND action='patient_identity_linked' AND details ? 'linkCodeId'`,
      [otherLab.split('/').at(-1)]);
    assert.equal(linkAudit.rows[0].total,1);
    const overviewPath='/administration-overview';
    await call('uploader','GET',overviewPath,403);
    const overview=await (await call('admin','GET',overviewPath,200)).json();
    assert.deepEqual(overview.laboratories.map(lab=>lab.id).sort(),
      [base.slice(6),otherLab.slice(6)].sort());
    await admin(base+'/staff',404,{email:'cuenta-inexistente@example.invalid'});
    await admin(base+'/staff',409,{email:credentials.uploader.email.toUpperCase()});
    const siteInput={name:'Sede Norte ficticia',address:'Avenida de Ensayo 10',
      commune:'Santiago',region:'Metropolitana de Santiago',email:'sede@example.invalid'};
    const northSites=base+'/sites';
    const southSites=otherLab+'/sites';
    await call('uploader','POST',northSites,403,{json:siteInput});
    await call('patient','GET',northSites,403);
    await call('uploader','GET',southSites,403);
    const siteCatalog=await (await call('admin','GET','/site-territories',200)).json();
    assert.equal(siteCatalog.regions.length,16);
    await call('uploader','GET','/site-territories',403);
    await admin(northSites,400,{...siteInput,commune:'Ancud'});
    const northSite=(await (await admin(northSites,201,siteInput)).json()).site;
    const southSite=(await (await admin(southSites,201,{...siteInput,name:'Sede Sur ficticia'})).json()).site;
    await admin(northSites,409,{...siteInput,name:siteInput.name.toUpperCase()});
    await admin(southSites,404,{...siteInput,siteId:northSite.id});
    const editedSite=(await (await admin(northSites,200,{
      ...siteInput,siteId:northSite.id,address:'Avenida de Ensayo 20',
    })).json()).site;
    assert.equal(editedSite.address,'Avenida de Ensayo 20');
    const visibleSites=(await (await call('patient','GET','/patient/sites',200)).json()).sites;
    assert.deepEqual(visibleSites.map(site=>site.id),[northSite.id]);
    assert.equal(visibleSites[0].email,'sede@example.invalid');
    assert.ok(!Object.hasOwn(visibleSites[0],'active'));
    await call('uploader','POST',base+'/orders',409,{json:{
      patientId:ids.patient,examCodes:['glicemia'],siteId:southSite.id,
    }});
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
    const registered=await created.json();
    const orderId=registered.order.id;
    assert.equal(registered.order.siteId,northSite.id);
    const adminOrders = await (await call('admin', 'GET', base+'/orders', 200)).json();
    assert.equal(adminOrders.orders.find(order=>order.id===orderId)?.siteName,northSite.name);
    await call('admin', 'GET', base+'/orders?patientId='+ids.patient, 403);
    await call('admin', 'GET', base+'/orders/'+orderId+'/medical-request/file', 403);
    assert.match(registered.request.documentReference,
      /^SOL-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    assert.equal(registered.request.documentReference, 'SOL-'+registered.request.id);
    assert.notEqual(registered.request.documentReference,'SOL-1002',
      'El backend debe generar una referencia interna, no aceptar la del cliente.');
    const storedRequestReference=await db.query(
      'SELECT document_reference FROM public.vitalia_sil_main_medical_requests WHERE id=$1',
      [registered.request.id]);
    assert.equal(storedRequestReference.rows[0].document_reference,
      registered.request.documentReference);
    await call('uploader','POST',intake,409,confirmation);
    assert.equal((await (await call('uploader','GET',base+'/orders',200)).json()).orders.length,1);
    const summaryPath=base+'/summary';
    const summary=(await (await call('uploader','GET',summaryPath,200)).json()).summary;
    assert.deepEqual(summary,{
      ordersTotal:1,registered:1,inReview:0,published:0,pendingRequests:0,
    },'El resumen debe contar la tabla completa del laboratorio.');
    await call('patient','GET',summaryPath,403);
    await call('admin','GET',summaryPath,403);
    await call('uploader','GET',otherLab+'/summary',403);
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
    assert.equal(savedPending.pending.siteId,northSite.id);
    assert.equal(savedPending.pending.status,'pending');
    assert.equal(savedPending.pending.patientEmail,pendingEmail);
    assert.ok(Object.hasOwn(savedPending.pending.suggestions,'suggestedPatient'));
    await call('uploader','POST',pendingPath,409,pendingUpload);
    const savedList=await (await call('uploader','GET',pendingPath,200)).json();
    assert.ok(savedList.pending.some(item=>item.id===pendingId));
    const beforeComplete=(await (await call('uploader','GET',summaryPath,200)).json()).summary;
    assert.equal(beforeComplete.pendingRequests,1,
      'Una derivación guardada debe sumar en el total del laboratorio.');
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
    // Mantener el límite real de 10 intentos/IP. El ensayo ya autentica
    // cinco cuentas iniciales, una invitada y tres roles en Edge. Verificar
    // la clave anterior/nueva con el mismo servicio de credenciales evita
    // agotar la cuota por una comprobación redundante de HTTP.
    const verifyRecovered=await createCredentialAuthenticator(db,{
      guardPatientSession:true,
    });
    assert.equal(await verifyRecovered({
      mode:'paciente',email:inviteEmail,password,
    }),null,'La contraseña anterior no debe autenticar después de la recuperación.');
    const newCredential=await verifyRecovered({
      mode:'paciente',email:inviteEmail,password:recovered.password,
    });
    assert.equal(newCredential?.email,inviteEmail);
    assert.equal(newCredential?.role,'paciente');
    const pendingPatient=(await db.query(
      'SELECT id FROM public.vitalia_accounts WHERE email=$1',[pendingEmail])).rows[0];
    assert.ok(pendingPatient?.id,'La activación debe crear cuenta paciente.');
    const pendingComplete=pendingPath+'/'+pendingId+'/complete';
    const pendingData={
      patientId:pendingPatient.id,patientEmail:pendingEmail,
      examCodes:['glicemia'],
      // Sin documentReference: el servidor asigna una ID única.
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
    assert.equal(completed.request.documentReference,'SOL-'+completed.request.id);
    assert.notEqual(completed.request.documentReference,registered.request.documentReference);
    await call('uploader','POST',pendingComplete,404,{json:pendingData});
    const pendingAfter=await (await call('uploader','GET',pendingPath,200)).json();
    assert.ok(!pendingAfter.pending.some(item=>item.id===pendingId));
    const afterComplete=(await (await call('uploader','GET',summaryPath,200)).json()).summary;
    assert.equal(afterComplete.pendingRequests,0);
    assert.ok(afterComplete.ordersTotal>=2);
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
    // Cierre de una derivación distinta, sin activar paciente ni crear orden.
    const rejectedPdf=syntheticPdf([
      'Solicitud administrativa ficticia SOL-PEND-CLOSE-01',
      'Paciente: Caso Sintético Vitalia',
      'Profesional: Persona de prueba',
      'Documento ilegible en verificación administrativa',
    ]);
    const rejectedUpload={bytes:rejectedPdf,headers:{
      'Content-Type':'application/pdf',
      'x-request-filename':'solicitud-para-cerrar.pdf',
    }};
    const rejected=(await (await call('uploader','POST',pendingPath,201,
      rejectedUpload)).json()).pending;
    const closePath=pendingPath+'/'+rejected.id+'/cancel';
    const closure={reason:'unreadable_document'};
    const beforeClosureOrders=(await db.query(
      'SELECT count(*)::int AS total FROM public.vitalia_sil_main_orders WHERE lab_id=$1',
      [base.slice(6)])).rows[0].total;
    await call('admin','POST',closePath,403,{json:closure});
    await call('reviewer','POST',
      otherLab+'/medical-requests/pending/'+rejected.id+'/cancel',404,
      {json:closure});
    await call('uploader','POST',closePath,400,{json:{
      ...closure,patientEmail:'no-enviar@example.invalid',
    }});
    const closed=(await (await call('uploader','POST',closePath,200,
      {json:closure})).json()).pending;
    assert.equal(closed.status,'cancelled');
    assert.equal(closed.reason,'unreadable_document');
    await call('uploader','POST',closePath,409,{json:closure});
    await call('uploader','POST',
      pendingPath+'/'+rejected.id+'/complete',404,{json:pendingData});
    await call('uploader','GET',pendingPath+'/'+rejected.id+'/file',404);
    const afterClosureOrders=(await db.query(
      'SELECT count(*)::int AS total FROM public.vitalia_sil_main_orders WHERE lab_id=$1',
      [base.slice(6)])).rows[0].total;
    assert.equal(afterClosureOrders,beforeClosureOrders,
      'Cerrar una derivación no debe generar órdenes.');
    const closedRow=(await db.query(
      `SELECT status,order_id,closure_reason,closed_by,closed_at
       FROM public.vitalia_sil_main_pending_requests WHERE id=$1`,
      [rejected.id])).rows[0];
    assert.equal(closedRow.status,'cancelled');
    assert.equal(closedRow.order_id,null);
    assert.equal(closedRow.closure_reason,'unreadable_document');
    assert.ok(closedRow.closed_by && closedRow.closed_at);
    const closedAudit=(await db.query(
      `SELECT details FROM public.vitalia_sil_main_audit
       WHERE action='pending_request_cancelled' AND lab_id=$1
         AND details->>'pendingId'=$2`,
      [base.slice(6),rejected.id])).rows;
    assert.equal(closedAudit.length,1);
    assert.equal(closedAudit[0].details.reason,'unreadable_document');
    const outstanding=(await (await call('uploader','GET',
      pendingPath,200)).json()).pending;
    assert.ok(!outstanding.some(p=>p.id===rejected.id));
    console.log('API: cierre pendiente transaccional y auditado sin crear orden.');

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
    if(!manual) {
      // Ensayo real de suspensión por laboratorio, después del recorrido Edge.
      const membership=base+'/staff/membership';
      await call('uploader','POST',membership,403,{json:{
        accountId:ids.uploader,active:false,
      }});
      await call('admin','POST',membership,400,{json:{
        accountId:ids.uploader,active:'false',
      }});
      const suspended=(await (await call('admin','POST',membership,200,{json:{
        accountId:ids.uploader,active:false,
      }})).json()).membership;
      assert.equal(suspended.active,false);
      assert.equal(suspended.canReviewReports,false);
      await call('uploader','GET',base+'/summary',403);
      await call('admin','POST',membership,409,{json:{
        accountId:ids.uploader,active:false,
      }});
      const restored=(await (await call('admin','POST',membership,200,{json:{
        accountId:ids.uploader,active:true,
      }})).json()).membership;
      assert.equal(restored.active,true);
      assert.equal(restored.canReviewReports,false,
        'Reactivar no debe recuperar permisos de revisión.');
      await call('uploader','GET',base+'/summary',200);
      const history=(await db.query(
        `SELECT action,details FROM public.vitalia_sil_main_audit
         WHERE lab_id=$1 AND action IN
         ('operator_membership_disabled','operator_membership_enabled')
         ORDER BY created_at`,[base.slice(6)])).rows;
      assert.deepEqual(history.map(x=>x.action),
        ['operator_membership_disabled','operator_membership_enabled']);
      assert.ok(history.every(x=>x.details.accountId===ids.uploader));
      const second=(await (await admin(northSites,201,{
        ...siteInput,name:'Segunda sede ficticia',
      })).json()).site;
      const manualOrder={patientId:ids.patient,examCodes:['glicemia']};
      await call('uploader','POST',base+'/orders',409,{json:manualOrder});
      const selected=(await (await call('uploader','POST',base+'/orders',201,
        {json:{...manualOrder,siteId:second.id}})).json()).order;
      assert.equal(selected.siteId,second.id);
      await admin(northSites+'/state',200,{siteId:northSite.id,active:false});
      await call('uploader','POST',base+'/orders',409,{json:{...manualOrder,siteId:northSite.id}});
      const historicalToken=(await issueSession(db,ids.patient,'paciente',passwordHash)).token;
      const ownSites={token:historicalToken};
      const historical=(await (await api('GET','/api/sil/main/patient/reports',200,ownSites)).json())
        .reports.find(report=>report.id===reportId);
      const matchingReports=(await (await api('GET',
        '/api/sil/main/patient/reports?offset=0&search='+historical.orderNumber,
        200,ownSites)).json()).reports;
      assert.deepEqual(matchingReports.map(report=>report.id),[reportId]);
      const nonMatching=(await (await api('GET',
        '/api/sil/main/patient/reports?offset=50',200,ownSites)).json()).reports;
      assert.deepEqual(nonMatching,[]);
      assert.equal(historical.siteName,northSite.name);
      assert.equal(historical.siteAddress,'Avenida de Ensayo 20');
      const patientSites=(await (await api('GET','/api/sil/main/patient/sites',200,ownSites)).json()).sites;
      assert.deepEqual(patientSites.map(site=>site.id),[second.id]);
      const audits=(await (await call('admin','GET',base+'/administrative-audit?limit=50',200)).json()).events;
      for(const action of ['site_created','site_updated','site_deactivated'])
        assert.ok(audits.some(event=>event.action===action));
      await admin(northSites+'/state',200,{siteId:northSite.id,active:true});
      const updatedOverview=await (await call('admin','GET',overviewPath,200)).json();
      const north=updatedOverview.laboratories.find(lab=>lab.id===base.slice(6));
      assert.equal(north.sites.find(site=>site.id===second.id).orders,1);
      assert.ok(north.sites.find(site=>site.id===northSite.id).published>=1);
      console.log('API: sedes segregadas, selección obligatoria y conservación histórica aprobadas.');
      console.log('API: suspensión y reactivación por laboratorio auditadas.');
    }
  } finally {
    if(webServer)await new Promise(done=>webServer.close(done));
    if(server)await new Promise(done=>server.close(done));
    await db.end();
  }
}

main().catch(error=>{console.error(error.message);process.exitCode=1;});
