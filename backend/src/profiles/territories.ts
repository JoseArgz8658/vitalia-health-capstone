import {type Pool} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {ProfileError} from './errors';

export interface Territory {code:string;name:string}
export interface Province extends Territory {regionCode:string}
export interface Commune extends Territory {provinceCode:string}
export interface TerritoryCatalog {version:string;regions:Territory[];provinces:Province[];communes:Commune[]}
export const CATALOG_VERSION='SUBDERE-CUT-2018-v04';

// Catálogo público sin datos personales; la ruta conserva la sesión y los roles del perfil.
export async function readTerritoryCatalog(db:Pick<Pool,'query'>):Promise<TerritoryCatalog>{
 try{
  const result=await db.query<{kind:string;code:string;name:string;parent:string|null}>(`
   SELECT 'region' AS kind,code,name,NULL::text AS parent FROM public.vitalia_regions
   UNION ALL SELECT 'province',code,name,region_code FROM public.vitalia_provinces
   UNION ALL SELECT 'commune',code,name,province_code FROM public.vitalia_communes
   ORDER BY kind,name,code`);
  const regions=result.rows.filter(x=>x.kind==='region').map(x=>({code:x.code,name:x.name}));
  const provinces=result.rows.filter(x=>x.kind==='province').map(x=>({code:x.code,name:x.name,regionCode:x.parent!}));
  const communes=result.rows.filter(x=>x.kind==='commune').map(x=>({code:x.code,name:x.name,provinceCode:x.parent!}));
  if(regions.length!==16||provinces.length!==56||communes.length!==346)throw new ProfileError(503,'TERRITORIES_UNAVAILABLE');
  return {version:CATALOG_VERSION,regions,provinces,communes};
 }catch(e){
  if(e instanceof ProfileError)throw e;
  if(['42501','42P01'].includes((e as {code?:string}).code??''))throw new ProfileError(503,'TERRITORIES_UNAVAILABLE');
  throw e;
 }
}
export function createTerritoryService(db:Pick<Pool,'query'>){return async(account:AccountSummary):Promise<TerritoryCatalog>=>{
 if(!['paciente','profesional'].includes(account.role))throw new ProfileError(403,'FORBIDDEN');
 return readTerritoryCatalog(db);
};}
