import {createHash} from 'node:crypto';
import {type Pool} from 'pg';
import {createLoginAttemptLimiter} from '../auth/login-limit';
import {readPdfText} from '../pdf/reader';
import {SilEducationBusy,SilEducationNotFound} from './patient-education';
import {normalize} from '../exam-assistant/contract';
import {educationalEvidence} from '../exam-assistant/knowledge';

type Analyte={examCode:string;analyte:string;unit:string};
type PublishedRow={
  id:string;orderNumber:string;laboratory:string;authorizedAt:Date;
  pdf:Buffer;sha:string;requestPdf:Buffer|null;requestSha:string|null;
  reference:string|null;analytes:Analyte[];
};

const escape=(text:string)=>text.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
const printable=(text:string)=>text.replace(/[\u0000-\u001f\u007f\p{Cf}]/gu,' ').trim();
const synonyms:Record<string,string[]>={
  glucosa:['glicemia','glucemia','glucosa en sangre'],
  hba1c:['hemoglobina glicosilada','hemoglobina glucosilada','hemoglobina glicosilada (hba1c)'],
};

function readMeasurements(text:string,analytes:Analyte[]){
  const lines=text.split(/\r?\n/).map(line=>normalize(line).trim());
  return analytes.flatMap(item=>{
    const analyte=normalize(item.analyte);
    const labels=[analyte,...(synonyms[analyte]??[])].map(escape).join('|');
    const unit=escape(normalize(item.unit)).replace(/\//g,'\\s*/\\s*');
    // Requiere que analito, valor y unidad sean columnas contiguas de la misma fila.
    const pattern=new RegExp(
      '^(?:'+labels+')[ \\t:|]+([+-]?\\d{1,9}(?:[.,]\\d{1,4})?)[ \\t|]+'
      +unit+'(?=$|[ \\t|])');
    const values=new Set(lines.flatMap(line=>{
      const match=pattern.exec(line);
      return match?[Number(match[1].replace(',','.'))]:[];
    }));
    if(values.size!==1)return [];
    const evidence=educationalEvidence({
      examen:item.analyte,fecha:null,
      resultados:[{nombre:item.analyte,valor:null,unidad:null,rango_referencia:null}],
    });
    return [{...item,value:[...values][0],explanation:evidence[0]?.purpose??null}];
  });
}

export function readSilReferralObservation(text:string):string|null{
  const notes=[...new Set([...text.matchAll(
    /(?:^|\|)[ \t]*(?:observaci[oó]n(?:es)?(?: de la solicitud| m[eé]dic[ao]s?)?|motivo de (?:la )?derivaci[oó]n)[ \t]*:[ \t]*([^\r\n|]{1,500})(?=$|\|)/gimu,
  )].map(match=>printable(match[1])).filter(Boolean))];
  return notes.length===1?notes[0]:null;
}

function explainReferralObservation(observation:string|null):string|null{
  if(!observation)return null;
  const text=normalize(observation);
  if(/\b(?:control|seguimiento)\b/.test(text)){
    return 'En una solicitud, «control» o «seguimiento» suele indicar que el equipo quiere revisar cambios con el tiempo.';
  }
  if(/\b(?:ayuno|en ayunas)\b/.test(text)){
    return '«Ayuno» se refiere a un periodo sin comer antes de un examen. Confirma con el laboratorio la preparación que corresponde a tu solicitud.';
  }
  return null;
}

export function createSilPatientReportOverview(db:Pick<Pool,'query'>,read=readPdfText,source:'demo'|'main'='demo'){
  const busy=new Set<string>();
  const allow=createLoginAttemptLimiter();
  async function textFrom(pdf:Buffer|null,sha:string|null){
    if(!pdf||!sha||pdf.length>2*1024*1024||
      createHash('sha256').update(pdf).digest('hex')!==sha)return '';
    try{
      const result=await read(pdf);
      return result.status==='text_ready'?(result.text??''):'';
    }catch{return '';}
  }
  return async(patientId:string,reportIds:string[])=>{
    if(busy.has(patientId)||busy.size>=2||!allow(patientId))throw new SilEducationBusy();
    busy.add(patientId);
    try{
      const sql=source==='main'
        ? `SELECT r.id,'VH-' || lpad(o.order_number::text,6,'0') AS "orderNumber",
             r.issuing_laboratory AS laboratory,r.externally_authorized_at AS "authorizedAt",
             r.pdf_data AS pdf,r.pdf_sha256 AS sha,
             m.pdf_data AS "requestPdf",m.pdf_sha256 AS "requestSha",
             m.document_reference AS reference,
             COALESCE((SELECT jsonb_agg(jsonb_build_object(
               'examCode',e.exam_code,'analyte',a.analyte,'unit',a.unit)
               ORDER BY e.exam_code,a.analyte)
               FROM public.vitalia_sil_main_order_exams e
               JOIN public.vitalia_sil_exam_analytes a ON a.exam_code=e.exam_code
               WHERE e.order_id=o.id),'[]'::jsonb) AS analytes
           FROM public.vitalia_sil_main_reports r
           JOIN public.vitalia_sil_main_orders o
             ON o.id=r.order_id AND o.lab_id=r.lab_id AND o.patient_id=r.patient_id
           JOIN public.vitalia_sil_main_patients p
             ON p.lab_id=r.lab_id AND p.patient_id=r.patient_id AND p.active
           JOIN public.vitalia_sil_main_laboratories l ON l.id=r.lab_id AND l.active
           LEFT JOIN public.vitalia_sil_main_medical_requests m
             ON m.order_id=o.id AND m.lab_id=r.lab_id
             AND m.patient_id=r.patient_id AND m.human_review_confirmed
           WHERE r.patient_id=$1 AND r.id=ANY($2::uuid[])
             AND r.published_at IS NOT NULL AND o.status='report_published'
           ORDER BY r.externally_authorized_at,r.id`
        : `SELECT r.id,'VH-' || lpad(o.order_number::text,6,'0') AS "orderNumber",
           r.issuing_laboratory AS laboratory,r.externally_authorized_at AS "authorizedAt",
           r.pdf_data AS pdf,r.pdf_sha256 AS sha,
           m.pdf_data AS "requestPdf",m.pdf_sha256 AS "requestSha",m.document_reference AS reference,
           COALESCE((SELECT jsonb_agg(jsonb_build_object(
             'examCode',e.exam_code,'analyte',a.analyte,'unit',a.unit) ORDER BY e.exam_code,a.analyte)
             FROM public.vitalia_sil_order_exams e
             JOIN public.vitalia_sil_exam_analytes a ON a.exam_code=e.exam_code
             WHERE e.order_id=o.id),'[]'::jsonb) AS analytes
          FROM public.vitalia_sil_external_reports r
          JOIN public.vitalia_sil_orders o ON o.id=r.order_id AND o.patient_id=r.patient_id
          LEFT JOIN public.vitalia_sil_medical_requests_demo m ON m.order_id=o.id
            AND m.patient_id=r.patient_id AND m.request_review_confirmed
          WHERE r.patient_id=$1 AND r.id=ANY($2::uuid[]) AND r.published_at IS NOT NULL
            AND o.status='report_published'
          ORDER BY r.externally_authorized_at,r.id`;
      const found=await db.query<PublishedRow>(sql,[patientId,reportIds]);
      if(found.rows.length!==reportIds.length)throw new SilEducationNotFound();

      const reports=[];
      const groups=new Map<string,{
        analyte:string;unit:string;laboratory:string;
        measurements:{orderNumber:string;authorizedAt:Date;value:number}[];
      }>();
      const seen=new Set<string>();
      for(const row of found.rows){
        const measurements=readMeasurements(await textFrom(row.pdf,row.sha),row.analytes);
        const observation=readSilReferralObservation(await textFrom(row.requestPdf,row.requestSha));
        reports.push({id:row.id,orderNumber:row.orderNumber,laboratory:row.laboratory,
          authorizedAt:row.authorizedAt,measurements,observation,
          observationExplanation:explainReferralObservation(observation),reference:row.reference});
        for(const item of measurements){
          const key=JSON.stringify([row.laboratory,item.examCode,item.analyte,item.unit]);
          const dedup=JSON.stringify([key,row.sha]);
          if(seen.has(dedup))continue;
          seen.add(dedup);
          const group=groups.get(key)??{analyte:item.analyte,unit:item.unit,
            laboratory:row.laboratory,measurements:[]};
          group.measurements.push({orderNumber:row.orderNumber,authorizedAt:row.authorizedAt,value:item.value});
          groups.set(key,group);
        }
      }
      const statistics=[...groups.values()].filter(group=>group.measurements.length>1).map(group=>{
        const values=group.measurements.map(item=>item.value);
        return {...group,count:values.length,minimum:Math.min(...values),
          maximum:Math.max(...values),mean:values.reduce((sum,value)=>sum+value,0)/values.length};
      });
      return {reports,statistics};
    }finally{
      busy.delete(patientId);
    }
  };
}
