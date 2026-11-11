import {type Pool} from 'pg';
import {type createSilPatientReportOverview} from './patient-report-overview';
import {type Extraction} from '../ai/contract';
import {educationalEvidence,questionIndices} from '../exam-assistant/knowledge';
import {gate,normalize,validateReply} from '../exam-assistant/contract';
import {createExamAssistant,type ExamAssistant} from '../exam-assistant/local-model';

/**
 * Asistente educativo exclusivo del SIL local de prueba.
 * El modelo recibe solo las prestaciones de la orden publicada.
 * Las cifras y las observaciones salen del lector de documentos, fuera del modelo.
 */
export class SilEducationNotFound extends Error {}
export class SilEducationBusy extends Error {}
export class SilEducationUnavailable extends Error {}

const educationNotice =
  'Información registrada y orientación educativa sobre la orden. ' +
  'Las cifras detectadas deben cotejarse con el PDF original. ' +
  'Para interpretar tus resultados, consulta al profesional que solicitó los exámenes.';

export function createSilPatientEducation(
  db:Pick<Pool,'query'>,
  model:ExamAssistant=createExamAssistant(),
  overview?:ReturnType<typeof createSilPatientReportOverview>,
  source:'demo'|'main'='demo',
) {
  const recent=new Map<string,number[]>();
  const busy=new Set<string>();
  return {
    async ask(patientId:string,reportId:string,question:string,simple=false) {
      // Filtrar por cuenta propietaria y por publicación ANTES de invocar IA.
      const sql=source==='main'
        ? `SELECT c.code,c.name,
             COALESCE((SELECT jsonb_agg(a.analyte ORDER BY a.analyte)
               FROM public.vitalia_sil_exam_analytes a
               WHERE a.exam_code=c.code), '[]'::jsonb) AS analytes,
             m.prescriber_name AS "prescriberName",
             m.request_date::text AS "requestDate",
             m.document_reference AS "documentReference"
           FROM public.vitalia_sil_main_reports r
           JOIN public.vitalia_sil_main_orders o
             ON o.id=r.order_id AND o.lab_id=r.lab_id AND o.patient_id=r.patient_id
           JOIN public.vitalia_sil_main_patients p
             ON p.lab_id=r.lab_id AND p.patient_id=r.patient_id AND p.active
           JOIN public.vitalia_sil_main_laboratories l ON l.id=r.lab_id AND l.active
           LEFT JOIN public.vitalia_sil_main_medical_requests m
             ON m.order_id=o.id AND m.lab_id=r.lab_id AND m.patient_id=r.patient_id
           JOIN public.vitalia_sil_main_order_exams e ON e.order_id=o.id
           JOIN public.vitalia_sil_exam_catalog c ON c.code=e.exam_code
           WHERE r.id=$1 AND r.patient_id=$2
             AND r.published_at IS NOT NULL AND o.status='report_published'
           ORDER BY c.name`
        : `SELECT c.code,c.name,m.prescriber_name AS "prescriberName",
             m.request_date::text AS "requestDate",m.document_reference AS "documentReference"
           FROM public.vitalia_sil_external_reports r
           JOIN public.vitalia_sil_orders o ON o.id=r.order_id
           JOIN public.vitalia_sil_order_exams e ON e.order_id=o.id
           JOIN public.vitalia_sil_exam_catalog c ON c.code=e.exam_code
           LEFT JOIN public.vitalia_sil_medical_requests_demo m
             ON m.order_id=o.id AND m.patient_id=r.patient_id
           WHERE r.id=$1 AND r.patient_id=$2
             AND r.published_at IS NOT NULL AND o.status='report_published'
           ORDER BY c.name`;
      const rows=await db.query<{
        name:string;code:string;analytes?:string[];
        prescriberName:string|null;requestDate:string|null;
        documentReference:string|null
      }>(sql,[reportId,patientId]);
      if(!rows.rows.length)throw new SilEducationNotFound();
      const labels=rows.rows.map(item=>item.name);
      // El informe SIL principal conoce sus analitos específicos, no solo
      // sus prestaciones. No se leen otras órdenes ni documentos del paciente.
      // Conservar los nombres de prestaciones en la respuesta administrativa.
      const analyteLabels=source==='main'
        ? [...new Set(rows.rows.flatMap(row=>Array.isArray(row.analytes)
            ? row.analytes.filter((name):name is string=>typeof name==='string')
            : []))].slice(0,20)
        : [];
      const educationLabels=analyteLabels.length?analyteLabels:labels;
      const normalized=normalize(question).trim()
        .replace(/^([¿¡]?\s*)q\s+/,'$1que ')
        .replace(/\bxq\b/g,'por que').replace(/\bpa q\b/g,'para que');
      const result=(answer:string,source:'catalogo'|'modelo_local'|'politica'|'informe')=>({
        answer,source,notice:educationNotice,approved:false,
      });
      const extraction:Extraction={
        examen:labels.join(', '),fecha:null,
        resultados:educationLabels.slice(0,20).map(name=>({
          nombre:name,valor:null,unidad:null,rango_referencia:null,
        })),
      };
      if(/[^\s@]+@[^\s@]+|\b\d{1,2}\.?\d{3}\.?\d{3}-[\dk]\b|\b\d{8,}\b/.test(normalized)){
        return result('Reformula tu pregunta sin correos, identificadores ni otros datos personales.','politica');
      }
      const blocked=gate(normalized,extraction,[]);
      if(blocked?.kind==='restricted'){
        return result(blocked.answer,'politica');
      }
      if(/\b(?:otr[oa]s? (?:pacientes?|informes?|examenes?|personas?|documentos?|pruebas?)|historial completo)\b/.test(normalized)){
        return result('Puedo ayudarte con el informe que tienes abierto.','politica');
      }
      if(/\b(?:estadisticas?|promedio|evolucion|tendencia|compara(?:r|n|cion)?)\b/.test(normalized)
        && !/\b(?:rango|referencia|normal|anormal)\b/.test(normalized)){
        return result('Abre «Resumen de informes» y elige dos o más documentos. Allí verás los valores detectados y su promedio cuando el examen, la unidad y el laboratorio coincidan.','informe');
      }
      const wantsObservation=/\b(?:observaci[oó]n(?:es)?|motivo de (?:la )?derivacion)\b/.test(normalized);
      const wantsMeasurements=/\b(?:mis resultados|mis cifras|que (?:resultado|valor) (?:tengo|obtuve)|cuanto (?:me )?salio|resultados? (?:de este|del) (?:examen|informe))\b/.test(normalized)
        && !/\b(?:normal|anormal|alt[oa]s?|baj[oa]s?|grave|diabetes|rango|referencia|riesgo)\b/.test(normalized);
      if(overview&&(wantsObservation||wantsMeasurements)){
        const {reports:[document]}=await overview(patientId,[reportId]);
        if(wantsObservation){
          return result(document.observation
            ? 'En la solicitud '+document.reference+' aparece este texto: «'+document.observation+'». '+(document.observationExplanation??'')+' Coteja la transcripción con el laboratorio.'
            : 'No encontré una observación claramente rotulada en la solicitud asociada.','informe');
        }
        if(!document.measurements.length){
          return result('No pude reconocer cifras con su unidad en este informe. Pulsa «Descargar PDF» para consultar el original.','informe');
        }
        return result([
          'Cifras detectadas en el PDF de la orden '+document.orderNumber+':',
          ...document.measurements.map(item=>'• '+item.analyte+': '+String(item.value).replace('.',',')+' '+item.unit+'.'
            +(item.explanation?' '+item.explanation:'')),
          'Confirma las cifras en el PDF original.',
        ].join('\n'),'informe');
      }
      const referral=rows.rows[0];
      if(/\bquien\b.{0,42}\b(?:pidio|solicito|derivo|indico|ordeno|mando)\b|\b(?:medico|profesional) (?:solicitante|derivador)\b/.test(normalized)){
        return result(referral.prescriberName
          ? 'Profesional que figura en la solicitud: '+referral.prescriberName+'.'
          : 'En esta orden no figura quién solicitó el examen. El laboratorio puede ayudarte a confirmarlo.','informe');
      }
      if(/\b(?:fecha de (?:la )?(?:solicitud|derivacion)|cuando (?:se |me )?(?:pidio|pidieron|derivaron|solicito|solicitaron))\b/.test(normalized)){
        return result(referral.requestDate
          ? 'Fecha que figura en la solicitud: '+referral.requestDate.split('-').reverse().join('/')+'.'
          : 'En esta orden no figura la fecha de la solicitud.','informe');
      }
      if(/^[¿¡\s]*(?:(?:que|cuales) (?:datos|informacion)(?:\s+(?:tengo|hay|aparecen|puedo ver|tiene (?:este|el) informe))?|que (?:dice|trae) (?:el|mi|este) informe)[?.!\s]*$/.test(normalized)){
        const lines=[
          'En este informe puedes ver:',
          '• Exámenes: '+labels.join(', ')+'.',
          ...(referral.prescriberName?['• Profesional indicado en la solicitud: '+referral.prescriberName+'.']:[]),
          ...(referral.documentReference?['• Referencia de la solicitud: '+referral.documentReference+'.']:[]),
          '• Resultados: pulsa «Descargar PDF» para ver las cifras.',
        ];
        return result(lines.join('\n'),'informe');
      }
      if(/(?:cuales|que|mis)\s+(?:son\s+)?(?:examenes|pruebas|prestaciones)|que me pidieron/.test(normalized)) {
        return result('Esta orden registra las prestaciones: '+labels.join(', ')+
          '. Para consultar los valores y observaciones, abre el PDF publicado.','catalogo');
      }
      const conceptual=/^(?:[¿¡]\s*)?(?:que (?:es|son|significa[n]?|se entiende por)|explica(?:me)?|para que (?:sirve[n]?|se usa[n]?))\s+/;
      const personal=/\b(?:mi[s]?|me|mio|mia|estoy|tengo|salio|cuanto[s]?)\b/;
      if(conceptual.test(normalized)&&!personal.test(normalized)){
        if(/\b(?:rango[s]?|intervalo[s]?) (?:de )?referencia\b/.test(normalized)){
          return result('Un intervalo de referencia es una guía que acompaña una medición. Puede variar según el examen y el método que use el laboratorio.','catalogo');
        }
        if(/\b(?:unidad(?:es)? (?:de )?medida|unidades de un resultado)\b/.test(normalized)){
          return result('Una unidad indica cómo se expresa una medición. Por ejemplo, puede indicar una cantidad por volumen o una proporción.','catalogo');
        }
      }
      // Preguntas como «las plaquetas, ¿qué cantidad mide?» piden el
      // significado de la medición, no el resultado numérico del paciente.
      // Responder desde notas verificadas antes de la ruta de cifras, sin IA.
      const targeted=questionIndices(normalized,extraction,[]);
      const notes=educationalEvidence(extraction);
      const conceptualTarget=/\b(?:que (?:es|son|mide[n]?|significa[n]?|cantidad mide)|para que (?:sirve[n]?|se mide[n]?)|explica(?:me)?(?: que (?:mide|es))?)\b/.test(normalized);
      const numericPersonal=/\b(?:cuant[oa]s?|valor(?:es)?|cifra(?:s)?|resultado(?:s)?|salio|obtuve|tengo)\b/.test(normalized)
        && !/\bque cantidad mide\b/.test(normalized);
      if(targeted?.length && conceptualTarget && !numericPersonal) {
        const selected=notes.filter(note=>targeted.includes(note.index));
        if(selected.length===targeted.length){
          return result(selected.map(note=>'• '+educationLabels[note.index]+': '+note.purpose).join('\n'),'catalogo');
        }
      }
      if(/\b(?:cuanto|cuantos|cuanta|cuantas|valor|valores|numero|cifra|resultado numerico|resultado de mi|me salio|salio|porcentaje|nivel|rango|referencia|normal|anormal|alt[oa]s?|baj[oa]s?|elevad[oa]s?|grave|diabetes|diagnostic|tratamiento|dosis|medicamento|debo tomar|que hago|estoy bien|estoy mal)\b/.test(normalized)) {
        return result(
          'Las cifras de tu examen están en el PDF publicado. Aquí puedo explicar qué mide una prestación y qué significan las unidades o los intervalos de referencia.',
          'politica');
      }
      const plainRequest=/\b(?:no (?:lo )?entiendo|no entendi|palabras (?:simples|sencillas)|mas (?:simple|facil|sencillo)|paso a paso|lectura facil)\b/.test(normalized);
      const known=notes;
      const targets=targeted;
      if(plainRequest||(simple&&targets?.length)){
        const notes=targets?known.filter(note=>targets.includes(note.index)):known;
        if(notes.length&&(targets||plainRequest)){
          const lines=notes.map(note=>'• '+educationLabels[note.index]+': '+note.purpose.replace(/\bglucosa\b/g,'azúcar'));
          if(notes.length<(targets?.length??extraction.resultados.length)){
            lines.push('Puedo explicar estas pruebas. Dime el nombre de otra si quieres preguntar por ella.');
          }
          lines.push('Para ver tus cifras, pulsa «Descargar PDF».');
          return result(lines.join('\n'),'catalogo');
        }
        if(plainRequest)return result('Puedes preguntarme qué pruebas aparecen, para qué sirven o quién las pidió. Para ver tus resultados, pulsa «Descargar PDF».','politica');
      }
      if(blocked?.kind==='out_of_scope')return result(blocked.answer,'politica');

      // Presupuesto por paciente, incluso si cambia de informe, y cupo global acotado.
      const now=Date.now();
      for(const [id,requests] of recent){
        if(now-requests[requests.length-1]>=15*60_000)recent.delete(id);
      }
      const timestamps=(recent.get(patientId)??[]).filter(t=>now-t<15*60_000);
      if(timestamps.length>=12||busy.has(patientId)||busy.size>=2||
        (!recent.has(patientId)&&recent.size>=1000))throw new SilEducationBusy();
      timestamps.push(now);
      recent.set(patientId,timestamps);
      busy.add(patientId);
      try {
        // Normalizar solo las abreviaciones; conservar el texto original en las
        // preguntas que ya vienen escritas en lenguaje natural.
        const promptQuestion=normalized===normalize(question).trim()?question:normalized;
        const generated=await model({extraction,question:promptQuestion,mode:'chat',history:[],catalogOnly:true,plainLanguage:simple});
        const reply=validateReply(generated.reply,extraction,'chat');
        return result(reply.answer,generated.model==='backend-policy'?'politica':
          generated.model==='knowledge-fast-path'?'catalogo':'modelo_local');
      }catch {
        // Una explicación general aún puede servirse desde el catálogo si
        // todas las prestaciones tienen una nota educativa verificada.
        const summary=/^(?:[¿¡]\s*)?(?:explica(?:me)?|resume|que miden|para que sirven)\b/.test(normalized)
          && /\b(?:estas|ambas|las|los)\s+(?:pruebas|prestaciones|examenes)\b/.test(normalized);
        const notes=summary?known:[];
        if(notes.length===extraction.resultados.length){
          return result(notes.map(note=>note.definition).join('\n\n'),'catalogo');
        }
        throw new SilEducationUnavailable();
      }finally{
        busy.delete(patientId);
      }
    },
  };
}
