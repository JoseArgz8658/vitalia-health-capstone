'use strict';

const assert=require('node:assert/strict');
const {chromium}=require(process.env.VITALIA_JOURNEY_PLAYWRIGHT??'playwright');
const origin='http://127.0.0.1:5174';

async function signIn(browser,width,{route,account,credential}){
  const context=await browser.newContext({viewport:{width,height:900}});
  const page=await context.newPage();
  try{
    await page.goto(origin+'/'+route);
    await page.locator('flt-semantics-placeholder').evaluate(element=>element.click());
    await page.getByText('Entorno de demostración — Datos ficticios',{exact:true}).waitFor();
    const box=await page.getByRole('textbox').first().boundingBox();
    assert.ok(box);
    await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
    await page.locator('input:focus:not([type=password])').fill(account+'@showcase.example.invalid');
    await page.keyboard.press('Tab');
    const password=process.env['SHOWCASE_'+credential+'_PASSWORD'];
    assert.ok(password);
    await page.locator('input[type=password]:focus').fill(password);
    const login=page.waitForResponse(response=>
      response.url().endsWith('/api/auth/login')&&response.request().method()==='POST');
    await page.getByRole('button',{name:'Iniciar sesión'}).click();
    assert.equal((await login).status(),200);
    return {context,page};
  }catch(error){
    await context.close();
    throw error;
  }
}

async function main(){
  const browser=await chromium.launch({channel:'msedge'});
  const roles=[
    {route:'#/administracion',account:'admin',credential:'ADMIN',
      heading:'Laboratorio Ficticio Cordillera'},
    {route:'#/laboratorio',account:'operador-003',credential:'OPERATOR',
      heading:'Panel del laboratorio'},
    {route:'',account:'paciente-001',credential:'PATIENT',heading:'Mis informes'},
  ];
  try{
    for(const width of [390,1440]){
      for(const role of roles){
        const {context,page}=await signIn(browser,width,role);
        try{
          await page.getByText(role.heading,{exact:true}).first().waitFor();
          if(role.credential==='PATIENT'){
            await page.getByText('Mis informes',{exact:true}).first().click();
            await page.getByText('Informes publicados',{exact:true}).waitFor();
            await page.getByText('Comparar informes',{exact:true}).waitFor();
          }
          console.log('Edge: '+role.credential+' '+width+' px');
        }finally{
          await context.close();
        }
      }
    }
  }finally{
    await browser.close();
  }
}
main().catch(error=>{
  console.error(error.message);
  process.exitCode=1;
});
