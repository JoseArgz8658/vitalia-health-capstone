const {verifySiteAddress}=require('../dist/sil/site-address-validation');

const submitted={address:'Calle Ficticia 123',commune:'Conchalí',region:'Metropolitana de Santiago'};
const component=(componentType,text)=>({
  componentType,componentName:{text},confirmationLevel:'CONFIRMED',
});

function provider({commune='Conchalí',number='123',granularity='PREMISE'}={}){
  return jest.fn(async()=>new Response(JSON.stringify({result:{
    verdict:{validationGranularity:granularity,addressComplete:true},
    address:{addressComponents:[
      component('route','Calle Ficticia'),
      component('street_number',number),
      component('locality',commune),
      component('administrative_area_level_1',submitted.region),
    ]},
  }})));
}

test('envía solo la dirección chilena y confirma calle, número y territorio',async()=>{
  const request=provider();
  await expect(verifySiteAddress(submitted,'test-key',request)).resolves.toEqual({status:'verified'});
  const [url,options]=request.mock.calls[0];
  expect(url).toBe('https://addressvalidation.googleapis.com/v1:validateAddress');
  expect(JSON.parse(options.body)).toEqual({address:{
    regionCode:'CL',administrativeArea:submitted.region,locality:submitted.commune,
    addressLines:[submitted.address],
  }});
});

test.each([{commune:'Estación Central'},{number:'124'},{granularity:'ROUTE'}])(
  'pide revisar cuando Google devuelve otra dirección o una coincidencia aproximada (%j)',
  async data=>{
    await expect(verifySiteAddress(submitted,'test-key',provider(data)))
      .resolves.toEqual({status:'needs_review'});
  },
);

test('degrada sin inventar una verificación cuando falta la clave o falla el proveedor',async()=>{
  const request=jest.fn(async()=>new Response('',{status:503}));
  await expect(verifySiteAddress(submitted,undefined,request)).resolves.toEqual({status:'not_configured'});
  expect(request).not.toHaveBeenCalled();
  await expect(verifySiteAddress(submitted,'test-key',request)).resolves.toEqual({status:'unavailable'});
});
