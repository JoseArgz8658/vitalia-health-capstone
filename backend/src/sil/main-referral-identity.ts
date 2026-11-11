/**
 * Lectura determinista de campos ROTULADOS de una derivación PDF.
 * Devuelve sugerencias (nunca confirma identidad, no es OCR ni diagnóstico).
 * Un campo ausente o contradictorio es null: no deducimos datos del paciente.
 */
export type ReferralIdentitySuggestions = {
  fullName:string|null;
  identifier:string|null;
  birthDate:string|null;
  email:string|null;
  phone:string|null;
  sex:string|null;
};

const blank=():ReferralIdentitySuggestions=>({
  fullName:null,identifier:null,birthDate:null,email:null,phone:null,sex:null,
});
const compact=(text:string)=>text.replace(/\s+/g,' ').trim();
const unique=(items:string[])=>{
  const values=[...new Set(items.map(compact).filter(Boolean))];
  return values.length===1?values[0]:null;
};
function labeled(text:string,labels:string,max=120):string[]{
  // ^ y | marcan la frontera de un campo; nunca recoger texto sin rótulo.
  const rx=new RegExp('(?:^|\\|)\\s*(?:'+labels+')\\s*:\\s*([^|]{1,'+max+'})','gimu');
  return [...text.matchAll(rx)].map(hit=>compact(hit[1]));
}
function dateValue(value:string):string|null{
  const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(value) ||
    /^(\d{2})[\/-](\d{2})[\/-](\d{4})$/.exec(value);
  if(!m)return null;
  const iso=m[1].length===4?value:
    m[3]+'-'+m[2]+'-'+m[1];
  const parsed=new Date(iso+'T00:00:00Z');
  if(!Number.isFinite(parsed.getTime())||
      parsed.toISOString().slice(0,10)!==iso||
      iso<'1900-01-01'||iso>new Date().toISOString().slice(0,10))
    return null;
  return iso;
}
export function suggestReferralIdentity(text:string):ReferralIdentitySuggestions{
  if(!text.trim())return blank();
  const fields=text.replace(/\r?\n/g,'|').replace(/\s*\|\s*/g,'|');
  const fullNames=labeled(fields,
    'nombre(?:\\s+completo)?(?:\\s+del?\\s+paciente)?|paciente(?:\\s+nombre)?',100)
    .filter(value=>/^[\p{L}\p{M}.'’\- ]{5,100}$/u.test(value)&&value.trim().split(/\s+/).length>=2);
  const names=unique(labeled(fields,'nombres?',90)
    .filter(value=>/^[\p{L}\p{M}.'’\- ]+$/u.test(value)));
  const lastNames=unique(labeled(fields,'apellidos?',90)
    .filter(value=>/^[\p{L}\p{M}.'’\- ]+$/u.test(value)));
  const fullName=unique(fullNames.length?fullNames:
    names&&lastNames?[names+' '+lastNames]:[]);

  const identifier=unique(labeled(fields,
    '(?:rut|run|r\\.u\\.t\\.|documento(?:\\s+de\\s+identidad)?|identificador\\s+paciente)',32)
    .filter(v=>/^[0-9]{6,9}-?[0-9kK]$|^[0-9]{1,3}(?:\.[0-9]{3}){2}-[0-9kK]$/u.test(v)));
  const dates=labeled(fields,'fecha\\s+de\\s+nacimiento|nacimiento|f\\.\\s*nac\\.?',25)
    .map(dateValue).filter((v):v is string=>v!==null);
  const birthDate=unique(dates);
  const emails=labeled(fields,
    '(?:correo(?:\\s+electr[oó]nico)?|e-?mail)(?:\\s+del?\\s+paciente)?',100)
    .map(v=>v.toLowerCase())
    .filter(v=>/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)&&v.length<=100);
  const phones=labeled(fields,'tel[eé]fono(?:\\s+del?\\s+paciente)?|celular',35)
    .filter(v=>/^\+?[0-9 ()-]{7,35}$/.test(v));
  const sex=unique(labeled(fields,'sexo(?:\\s+del?\\s+paciente)?',20)
    .map(v=>v.toLowerCase())
    .filter(v=>['f','m','femenino','masculino','mujer','hombre'].includes(v)));
  return {
    fullName,identifier,birthDate,email:unique(emails),
    phone:unique(phones),sex,
  };
}
