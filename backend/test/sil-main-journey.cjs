'use strict';

const assert = require('node:assert/strict');
const {createHash, randomUUID} = require('node:crypto');
const {spawnSync} = require('node:child_process');
const {readFileSync, readdirSync, writeFileSync} = require('node:fs');
const {resolve} = require('node:path');
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

function syntheticPdf() {
  const stream = 'BT /F1 18 Tf 50 740 Td (Vitalia - informe ficticio) Tj ET';
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
  await page.getByRole('textbox').first().click();
  await page.keyboard.insertText(account+'@example.invalid');
  await page.keyboard.press('Tab');
  await page.keyboard.insertText(password);
  const response=page.waitForResponse(r=>r.url().endsWith('/api/auth/login') && r.request().method()==='POST');
  await page.getByRole('button',{name:'Iniciar sesión'}).click();
  assert.equal((await response).status(),200,'Acceso desde Edge de '+account);
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

async function operatorJourney(browser, order, base) {
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
      const select=async (control)=>{
        await click(id(control),control);
        await page.getByRole('menuitem',{name:new RegExp(name)}).click({timeout:7000});
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
    await select('sil-upload-order');
    const choose=page.waitForEvent('filechooser');
    await click(button('Elegir archivo PDF (máx. 2 MiB)'),'Elegir archivo PDF');
    await (await choose).setFiles({name:'informe-operador.pdf',mimeType:'application/pdf',buffer:pdf});
    await button('informe-operador.pdf').waitFor({timeout:10000});
    console.log('Microsoft Edge: orden y archivo seleccionados.');
    for(const [key,value] of [
      ['sil-report-professional','Profesional Ficticio'],
      ['sil-report-reference','AUT-OPERADOR-EDGE'],
      ['sil-report-date','2024-01-01'],
    ]){
      const input=id(key).locator('input[data-semantics-role="text-field"]');
      await reach(page,input,key);
      const box=await input.boundingBox();
      await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
      const focused=page.locator('input:focus');
      await focused.fill(value,{timeout:7000});
      assert.equal(await focused.inputValue(),value,key);
    }
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

async function browserJourney(order, base) {
  const {chromium}=require(process.env.VITALIA_JOURNEY_PLAYWRIGHT);
  const browser=await chromium.launch({channel:'msedge'});
  try {
    const publishedId=await operatorJourney(browser,order,base);
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
    const passwordHash=await hashPassword(password);
    for(const [name,role] of Object.entries(roles)){
      ids[name]=randomUUID();
      await db.query('INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,$3,$4)',
        [ids[name],name+'@example.invalid',passwordHash,role]);
    }

    process.env.VITALIA_SIL_MAIN_MODE='YES';
    const host=express();
    const web=process.env.VITALIA_JOURNEY_WEB;
    host.use(createApp({
      authenticate:await createCredentialAuthenticator(db),
      issue:(id,mode)=>issueSession(db,id,mode),
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
        json:{mode,email:name+'@example.invalid',password},
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
    const created=await call('uploader','POST',base+'/orders',201,{json:{
      patientId:ids.patient,examCodes:['glicemia'],
    }});
    const orderId=(await created.json()).order.id;
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
      if(manual){
        writeFileSync(fixture,pdf,{flag:'wx'});
        console.log('\nSIL temporal listo en http://localhost:5173/#/laboratorio');
        console.log('Orden disponible: VH-'+String(ready.orderNumber).padStart(6,'0'));
        console.log('Adjunta el PDF con uploader@example.invalid.');
        console.log('Con esa misma cuenta, descarga el PDF de revisión, confirma y publica.');
        console.log('Consulta el informe con patient@example.invalid en http://localhost:5173/.');
        console.log('Contraseña de estas cuentas ficticias: '+password);
        console.log('PDF para adjuntar: '+fixture);
        const input=createInterface({input:process.stdin,output:process.stdout});
        try {
          await input.question('Pulsa Enter para cerrar el ensayo.\n');
        } finally {
          input.close();
        }
      } else {
        await browserJourney(ready,base);
      }
    }
  } finally {
    if(webServer)await new Promise(done=>webServer.close(done));
    if(server)await new Promise(done=>server.close(done));
    await db.end();
  }
}

main().catch(error=>{console.error(error.message);process.exitCode=1;});
