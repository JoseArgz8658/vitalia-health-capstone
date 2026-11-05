import {type PoolClient} from 'pg';
import {z} from 'zod';
import {CATALOG_VERSION} from '../profiles/territories';
const name=z.string().trim().min(1).max(150);
const region=z.object({code:z.string().regex(/^\d{2}$/),name}).strict();
const province=z.object({code:z.string().regex(/^\d{3}$/),name,regionCode:z.string().regex(/^\d{2}$/)}).strict();
const commune=z.object({code:z.string().regex(/^\d{5}$/),name,provinceCode:z.string().regex(/^\d{3}$/)}).strict();
const schema=z.object({version:z.literal(CATALOG_VERSION),regions:z.array(region).length(16),provinces:z.array(province).length(56),communes:z.array(commune).length(346)}).strict();
export function validateTerritorialCatalog(input:unknown){
 const data=schema.parse(input);
 for(const rows of [data.regions,data.provinces,data.communes])if(new Set(rows.map(x=>x.code)).size!==rows.length)throw new Error('Código territorial duplicado.');
 const regions=new Set(data.regions.map(x=>x.code)),provinces=new Set(data.provinces.map(x=>x.code));
 if(data.provinces.some(x=>!regions.has(x.regionCode)||!x.code.startsWith(x.regionCode))||data.communes.some(x=>!provinces.has(x.provinceCode)||!x.code.startsWith(x.provinceCode)))throw new Error('Jerarquía territorial inválida.');
 return data;
}
export async function loadTerritorialCatalog(client:Pick<PoolClient,'query'>,input:unknown):Promise<'loaded'|'unchanged'>{
 const data=validateTerritorialCatalog(input);let started=false;
 try{
  await client.query('BEGIN');started=true;
  await client.query('SELECT pg_advisory_xact_lock(hashtext($1))',['vitalia-territorial-catalog']);
  const base=await client.query('SELECT version FROM public.vitalia_schema_migrations WHERE version=$1',['012_profiles_locations']);
  if(base.rows.length!==1)throw new Error('Falta migración 012.');
  // Impide cambios externos durante la comparación y la inserción del catálogo.
  await client.query('LOCK TABLE public.vitalia_regions,public.vitalia_provinces,public.vitalia_communes IN SHARE ROW EXCLUSIVE MODE');
  let inserted=false;
  const entries=[
   {table:'vitalia_regions',rows:data.regions,parent:undefined},
   {table:'vitalia_provinces',rows:data.provinces,parent:'regionCode'},
   {table:'vitalia_communes',rows:data.communes,parent:'provinceCode'},
  ] as const;
  for(const entry of entries){
   const column=entry.parent==='regionCode'?'region_code':entry.parent==='provinceCode'?'province_code':null;
   const existing=await client.query<{code:string;name:string;parent?:string}>(`SELECT code,name${column?','+column+' AS parent':''} FROM public.${entry.table}`);
   const expected=new Map(entry.rows.map(x=>[x.code,x]));
   for(const row of existing.rows){
    const candidate=expected.get(row.code);
    if(!candidate||candidate.name!==row.name||(entry.parent&&(candidate as unknown as Record<string,string>)[entry.parent]!==row.parent))throw new Error('Catálogo existente distinto; no se sobrescribe.');
   }
   const missing=entry.rows.filter(x=>!existing.rows.some(y=>y.code===x.code));
   if(missing.length){
    inserted=true;
    const values=missing.map(x=>({code:x.code,name:x.name,parent:entry.parent?(x as unknown as Record<string,string>)[entry.parent]:null}));
    await client.query(`INSERT INTO public.${entry.table}(code,name${column?','+column:''})
     SELECT code,name${column?',parent':''} FROM jsonb_to_recordset($1::jsonb) AS x(code text,name text,parent text)`,[JSON.stringify(values)]);
   }
  }
  await client.query('COMMIT');return inserted?'loaded':'unchanged';
 }catch(e){if(started)await client.query('ROLLBACK').catch(()=>{});throw e;}
}
