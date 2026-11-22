import {z} from 'zod';

const googleResponse=z.object({
  result:z.object({
    verdict:z.object({
      validationGranularity:z.string(),
      addressComplete:z.boolean().optional(),
    }),
    address:z.object({
      addressComponents:z.array(z.object({
        componentType:z.string(),
        componentName:z.object({text:z.string()}),
        confirmationLevel:z.string().optional(),
        inferred:z.boolean().optional(),
        replaced:z.boolean().optional(),
      })),
    }),
  }),
});

type SiteAddress={address:string;commune:string;region:string};

function normalize(value:string){
  return value.normalize('NFD').replace(/\p{M}/gu,'')
    .toLowerCase().trim().replace(/\s+/g,' ');
}

export async function verifySiteAddress(input:SiteAddress,key:string|undefined,request=fetch){
  if(!key?.trim())return {status:'not_configured'};
  try {
    const response=await request('https://addressvalidation.googleapis.com/v1:validateAddress',{
      method:'POST',
      headers:{'Content-Type':'application/json','X-Goog-Api-Key':key.trim()},
      signal:AbortSignal.timeout(5000),
      body:JSON.stringify({address:{
        regionCode:'CL',administrativeArea:input.region,locality:input.commune,
        addressLines:[input.address],
      }}),
    });
    if(!response.ok)return {status:'unavailable'};
    const parsed=googleResponse.safeParse(await response.json());
    if(!parsed.success)return {status:'unavailable'};
    const {verdict,address}=parsed.data.result;
    const confirmed=address.addressComponents.filter(component=>
      component.confirmationLevel==='CONFIRMED'&&!component.inferred&&!component.replaced);
    const matches=(types:string[],expected:string)=>confirmed.some(component=>
      types.includes(component.componentType)&&
      normalize(component.componentName.text)===normalize(expected));
    const territorialMatch=matches(['locality','administrative_area_level_3'],input.commune)
      && matches(['administrative_area_level_1'],input.region);
    const street=confirmed.find(component=>component.componentType==='route')?.componentName.text;
    const number=confirmed.find(component=>component.componentType==='street_number')?.componentName.text;
    const exactStreet=street&&number&&
      normalize(input.address)===normalize(street+' '+number);
    const verified=territorialMatch&&exactStreet&&verdict.addressComplete
      && ['PREMISE','SUB_PREMISE'].includes(verdict.validationGranularity);
    return {status:verified?'verified':'needs_review'};
  } catch {
    return {status:'unavailable'};
  }
}
