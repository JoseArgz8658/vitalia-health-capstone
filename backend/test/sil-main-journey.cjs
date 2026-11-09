'use strict';

const assert = require('node:assert/strict');
const {createHash, randomUUID} = require('node:crypto');
const {spawnSync} = require('node:child_process');
const {readFileSync, readdirSync} = require('node:fs');
const {resolve} = require('node:path');
const express = require('express');
const {Pool} = require('pg');
const {createApp} = require('../dist/app');
const {createCredentialAuthenticator} = require('../dist/auth/credentials');
const {hashPassword} = require('../dist/auth/password');
const {findSessionAccount, issueSession, revokeSession} = require('../dist/auth/sessions');
const {createSilMainService} = require('../dist/sil/main-service');

const origin = 'http://127.0.0.1:3119';
const password = 'SoloPrueba-2026!';
const pdf = Buffer.from('%PDF-1.4\n% Informe sintetico para el ensayo\n%%EOF\n');
const migrations = resolve(__dirname, '../database/migrations');

async function prepare(db) {
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
  const migrated = spawnSync(process.execPath,
    [resolve(__dirname,'../dist/database/migrate-main-sil.js'),'--rehearse'],
    {stdio:'inherit',timeout:30000});
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
      const select=async (control)=>{
        await click(id(control),control);
        await page.getByRole('menuitem',{name:new RegExp(name)}).click({timeout:7000});
      };
      try {
        return await task({page,id,button,checkbox,click,select});
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

  const reportId=await stage('uploader',async ({page,id,button,checkbox,click,select})=>{
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
      await click(input,key);
      await page.keyboard.insertText(value);
      assert.equal(await input.inputValue(),value,key);
    }
    const authorized=checkbox('El informe ya fue autorizado fuera de Vitalia');
    const matched=checkbox('Confirmé que el PDF corresponde al paciente de la orden');
    await click(authorized,'Autorización externa');
    await click(matched,'Paciente de la orden');
    assert.equal(await authorized.getAttribute('aria-checked'),'true');
    assert.equal(await matched.getAttribute('aria-checked'),'true');
    console.log('Microsoft Edge: datos de autorización y paciente comprobados.');
    const response=page.waitForResponse(r=>r.url().endsWith(endpoint) && r.request().method()==='POST');
    const [uploaded]=await Promise.all([response,click(button('Adjuntar para revisión'),'Adjuntar para revisión')]);
    assert.equal(uploaded.status(),201,'Carga del PDF desde la estación');
    console.log('Microsoft Edge: se adjuntó el PDF desde la estación del operador.');
    return (await uploaded.json()).report.id;
  });

  await stage('reviewer',async ({page,button,checkbox,click,select})=>{
    await select('sil-review-order');
    const publication=button('Publicar informe');
    assert.equal(await publication.isEnabled(),false,'Se exige revisar antes de publicar');
    const download=page.waitForEvent('download');
    const response=page.waitForResponse(r=>r.url().endsWith(endpoint+'/file') && r.request().method()==='GET');
    await click(button('Descargar PDF para revisión'),'Descargar para revisión');
    assert.equal((await response).status(),200);
    assert.deepEqual(readFileSync(await (await download).path()),pdf);
    await click(checkbox('Confirmo que revisé el PDF y su autorización externa'),'Confirmar revisión');
    const posted=page.waitForResponse(r=>r.url().endsWith(endpoint+'/publish') && r.request().method()==='POST');
    await click(publication,'Publicar informe');
    assert.equal((await posted).status(),201);
    console.log('Microsoft Edge: otro operador descargó, revisó y publicó el PDF.');
  });
  return reportId;
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
  const db=new Pool({connectionTimeoutMillis:5000});
  let server, webServer;
  try {
    await prepare(db);
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
    await call('uploader','GET',path+'/file',404);
    const publish=(actor,status)=>call(actor,'POST',path+'/publish',status,{json:{operatorReviewConfirmed:true}});
    await publish('uploader',409);
    await admin(base+'/staff/review-permission',200,{accountId:ids.reviewer,enabled:true});
    await publish('reviewer',409);
    const pending=await call('reviewer','GET',path+'/file',200);
    assert.deepEqual(Buffer.from(await pending.arrayBuffer()),pdf);
    await admin(base+'/staff/review-permission',200,{accountId:ids.reviewer,enabled:false});
    await publish('reviewer',403);
    await admin(base+'/staff/review-permission',200,{accountId:ids.reviewer,enabled:true});
    await call('reviewer','GET',path+'/file',200);
    await publish('reviewer',201);
    await publish('reviewer',409);
    await call('other','GET',patientFile,404);
    const patient=await call('patient','GET',patientFile,200);
    assert.deepEqual(Buffer.from(await patient.arrayBuffer()),pdf);
    const audit=await db.query(`SELECT action,actor_id FROM public.vitalia_sil_main_audit
      WHERE order_id=$1 ORDER BY created_at,id`,[orderId]);
    for(const [action,actor] of [
      ['report_attached','uploader'],['report_review_accessed','reviewer'],
      ['report_published','reviewer'],['report_downloaded','patient'],
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
      await browserJourney((await browserOrder.json()).order,base);
    }
  } finally {
    if(webServer)await new Promise(done=>webServer.close(done));
    if(server)await new Promise(done=>server.close(done));
    await db.end();
  }
}

main().catch(error=>{console.error(error.message);process.exitCode=1;});
