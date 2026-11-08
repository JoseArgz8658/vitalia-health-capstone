import {type Pool} from 'pg';
import {readPdfText,type PdfReadResult} from '../pdf/reader';
import {createLocalExtractor,type LocalExtractionResult} from '../ai/local-extractor';
import {identifyDocument} from '../documents/file-validation';
import {SilConflictError,SilNotFoundError} from './service';

type PreviewState='ready'|'needs_manual'|'needs_ocr'|'analysis_unavailable'|'identity_mismatch';
type PreviewItem={
  examCode:string;
  analyte:string;
  unit:string;
  suggestedValue:number|null;
  warning:string|null;
};

/**
 * Carga PDF de prueba -> propuesta temporal de resultados.
 * No registra resultados, no recibe muestras ni publica informes.
 * Todo valor persistente requiere confirmación explícita por un operador.
 */
export function createSilResultsFilePreview(db:Pick<Pool,'query'>,options:{
  read?:typeof readPdfText;
  extract?:(text:string)=>Promise<LocalExtractionResult>;
}={}) {
  const read=options.read??readPdfText;
  const extract=options.extract??createLocalExtractor();
  return async(orderId:string,bytes:Buffer):Promise<{
    state:PreviewState;items:PreviewItem[];warnings:string[];
    generatedBy:'ai_draft'|'none';confirmed:false;
  }>=>{
    if(bytes.length<8||bytes.length>2*1024*1024)throw new SilConflictError();
    identifyDocument(bytes,'application/pdf','resultados-demo.pdf');

    const found=await db.query<{status:string;identifier:string|null}>(
      `SELECT o.status,p.synthetic_identifier AS identifier
       FROM public.vitalia_sil_orders o
       LEFT JOIN public.vitalia_sil_patient_profiles_demo p ON p.patient_id=o.patient_id
       WHERE o.id=$1 AND o.synthetic=true`,[orderId]);
    if(!found.rows.length)throw new SilNotFoundError();
    if(found.rows[0].status!=='sampled')throw new SilConflictError();

    const expected=await db.query<{examCode:string;analyte:string;unit:string}>(
      `SELECT e.exam_code AS "examCode",a.analyte,a.unit
       FROM public.vitalia_sil_order_exams e
       JOIN public.vitalia_sil_exam_analytes a ON a.exam_code=e.exam_code
       WHERE e.order_id=$1 ORDER BY e.exam_code,a.analyte`,[orderId]);
    if(!expected.rows.length||expected.rows.length>30)throw new SilConflictError();
    const items:PreviewItem[]=expected.rows.map(row=>({
      ...row,suggestedValue:null,warning:'Valor pendiente de revisión manual.',
    }));
    const base=(state:PreviewState,warnings:string[])=>({
      state,items,warnings,generatedBy:'none' as const,confirmed:false as const,
    });

    let reading:PdfReadResult;
    try{reading=await read(bytes);}catch{
      return base('needs_manual',['El lector PDF no pudo procesar el archivo; ingresa los resultados manualmente.']);
    }
    if(reading.status!=='text_ready'||!reading.text){
      return base(reading.status==='needs_ocr'?'needs_ocr':'needs_manual',[
        'El PDF no contiene texto utilizable. No se han registrado resultados.',
      ]);
    }
    const text=reading.text;
    const identifier=found.rows[0].identifier;
    // El entorno de demo no acepta exámenes reales ni atribuye un documento
    // a una cuenta solo por el correo ingresado.
    const demoIds=[...new Set(text.match(/\bDEMO-[0-9]{3,12}\b/gi)??[])];
    if(!identifier||!demoIds.includes(identifier)||demoIds.some(id=>id!==identifier)){
      return base('identity_mismatch',[
        'El identificador ficticio del PDF no corresponde a la ficha del paciente. No se utilizó la IA.',
      ]);
    }

    let extracted:LocalExtractionResult;
    try{extracted=await extract(text);}catch{
      return base('analysis_unavailable',[
        'No fue posible ejecutar la extracción de IA. Puedes registrar los valores manualmente.',
      ]);
    }
    if(extracted.status!=='requires_review'||!extracted.extraction){
      return base('needs_manual',[
        'La IA no generó una extracción estructurada revisable. Completa los valores manualmente.',
      ]);
    }
    const normalized=(value:string)=>value.normalize('NFD')
      .replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'').trim();
    const equivalent=(expected:string,detected:string)=>{
      const a=normalized(expected),b=normalized(detected);
      if(a===b)return true;
      const aliases:Record<string,string[]>={
        'glucosa':['glicemia','glucemia','glucosaensangre'],
        'hba1c':['hemoglobinaglicosilada','hemoglobinaglucosilada',
          'hemoglobinaglicosiladahba1c','hemoglobinaa1c'],
      };
      return (aliases[a]??[]).includes(b);
    };
    const parseValue=(raw:string|null):number|null=>{
      if(raw===null)return null;
      const text=raw.trim();
      if(!/^[+-]?\d{1,9}(?:[.,]\d{1,4})?$/.test(text))return null;
      const num=Number(text.replace(',','.'));
      return Number.isFinite(num)&&num>=-1e9&&num<=1e9?num:null;
    };
    const normalizedUnit=(unit:string)=>unit.replace(/\s+/g,'').toLowerCase()
      .replace(/[μµ]/g,'u');
    const rows=extracted.extraction.resultados;
    const warnings:string[]=[];
    for(const item of items){
      const matches=rows.map((row,index)=>({row,index})).filter(
        ({row})=>row.nombre!==null&&equivalent(item.analyte,row.nombre));
      if(matches.length!==1){
        item.warning=matches.length?'Hay más de un resultado candidato; revisa manualmente.':
          'La IA no identificó este analito; completa el valor manualmente.';
        continue;
      }
      const {row,index}=matches[0];
      const value=parseValue(row.valor);
      if(value===null){
        item.warning='No se identificó un valor numérico claro; revisa manualmente.';
        continue;
      }
      if(row.unidad===null||normalizedUnit(row.unidad)!==normalizedUnit(item.unit)){
        item.warning='La unidad extraída no coincide con el catálogo; revisa manualmente.';
        continue;
      }
      if(extracted.incidents.some(incident=>
        incident.path.startsWith(`resultados[${index}]`))) {
        item.warning='La IA informó una incidencia para este resultado; revisa manualmente.';
        continue;
      }
      // Un número aislado en el documento no prueba que corresponda a este analito.
      // Exigimos que nombre y cifra aparezcan juntos en al menos una línea de texto.
      const names=[item.analyte,row.nombre].filter(
        (name):name is string=>name!==null);
      const compact=(raw:string)=>raw.normalize('NFD').replace(/[\u0300-\u036f]/g,'')
        .toLowerCase().replace(/[^a-z0-9.,+-]/g,'');
      const regexEscape=(value:string)=>value.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
      const valueToken=new RegExp(
        `(^|[^0-9.,])${regexEscape(row.valor!)}(?=$|[^0-9.,])`);
      const sourceContainsPair=text.split(/\r?\n/).some(line=>
        names.some(name=>compact(line).includes(compact(name)))&&
        valueToken.test(line));
      if(!sourceContainsPair){
        item.warning='No se pudo comprobar el analito junto a su cifra en el PDF. Revisa manualmente.';
        continue;
      }
      item.suggestedValue=value;
      item.warning=null;
    }
    if(extracted.incidents.length)warnings.push(
      `La extracción reportó ${extracted.incidents.length} incidencia(s). Revisa el PDF original.`);
    if(items.some(item=>item.warning))warnings.push(
      'Los valores incompletos o dudosos quedaron vacíos para corrección manual.');
    return {state:items.every(item=>item.warning===null)?'ready':'needs_manual',
      items,warnings,generatedBy:'ai_draft',confirmed:false};
  };
}
