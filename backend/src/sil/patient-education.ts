import {type Pool} from 'pg';
import {type Extraction} from '../ai/contract';
import {educationalEvidence} from '../exam-assistant/knowledge';
import {gate,normalize,validateReply} from '../exam-assistant/contract';
import {createExamAssistant,type ExamAssistant} from '../exam-assistant/local-model';

/**
 * Asistente educativo exclusivo del SIL local de prueba.
 * Contexto: únicamente prestaciones registradas en una orden publicada.
 * NUNCA utiliza los bytes del PDF ni afirma que extrajo valores de él.
 */
export class SilEducationNotFound extends Error {}
export class SilEducationBusy extends Error {}
export class SilEducationUnavailable extends Error {}

const educationNotice =
  'Orientación educativa sobre las prestaciones de la orden. ' +
  'No lee ni interpreta los valores del PDF, no diagnostica ni indica tratamientos. ' +
  'Consulta el informe original para conocer tus cifras.';

export function createSilPatientEducation(
  db:Pick<Pool,'query'>,
  model:ExamAssistant=createExamAssistant(),
) {
  const recent=new Map<string,number[]>();
  const busy=new Set<string>();
  return {
    async ask(patientId:string,reportId:string,question:string) {
      // Filtrar por cuenta propietaria y por publicación ANTES de invocar IA.
      const rows=await db.query<{name:string;code:string}>(
        `SELECT c.code,c.name
         FROM public.vitalia_sil_external_reports r
         JOIN public.vitalia_sil_orders o ON o.id=r.order_id
         JOIN public.vitalia_sil_order_exams e ON e.order_id=o.id
         JOIN public.vitalia_sil_exam_catalog c ON c.code=e.exam_code
         WHERE r.id=$1 AND r.patient_id=$2
           AND r.published_at IS NOT NULL AND o.status='report_published'
         ORDER BY c.name`,[reportId,patientId]);
      if(!rows.rows.length)throw new SilEducationNotFound();
      const labels=rows.rows.map(item=>item.name);
      const normalized=normalize(question).trim()
        .replace(/^([¿¡]?\s*)q\s+/,'$1que ')
        .replace(/\bxq\b/g,'por que').replace(/\bpa q\b/g,'para que');
      const result=(answer:string,source:'catalogo'|'modelo_local'|'politica')=>({
        answer,source,notice:educationNotice,approved:false,
      });
      const extraction:Extraction={
        examen:labels.join(', '),fecha:null,
        resultados:rows.rows.slice(0,20).map(row=>({
          nombre:row.name,valor:null,unidad:null,rango_referencia:null,
        })),
      };
      if(/[^\s@]+@[^\s@]+|\b\d{1,2}\.?\d{3}\.?\d{3}-[\dk]\b|\b\d{8,}\b/.test(normalized)){
        return result('Reformula tu pregunta sin correos, identificadores ni otros datos personales.','politica');
      }
      const blocked=gate(normalized,extraction,[]);
      if(blocked?.kind==='restricted'){
        return result(blocked.answer,'politica');
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
      if(/\b(?:cuanto|cuantos|cuanta|valor|valores|numero|cifra|resultado numerico|resultado de mi|me salio|salio|porcentaje|nivel|rango|referencia|normal|anormal|alt[oa]s?|baj[oa]s?|elevad[oa]s?|grave|diabetes|diagnostic|tratamiento|dosis|medicamento|debo tomar|que hago|estoy bien|estoy mal)\b/.test(normalized)) {
        return result(
          'Las cifras de tu examen están en el PDF publicado. Aquí puedo explicar qué mide una prestación y qué significan las unidades o los intervalos de referencia.',
          'politica');
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
        const generated=await model({extraction,question:promptQuestion,mode:'chat',history:[],catalogOnly:true});
        const reply=validateReply(generated.reply,extraction,'chat');
        return result(reply.answer,generated.model==='backend-policy'?'politica':
          generated.model==='knowledge-fast-path'?'catalogo':'modelo_local');
      }catch {
        // Una explicación general aún puede servirse desde el catálogo si
        // todas las prestaciones tienen una nota educativa verificada.
        const summary=/^(?:[¿¡]\s*)?(?:explica(?:me)?|resume|que miden|para que sirven)\b/.test(normalized)
          && /\b(?:estas|ambas|las|los)\s+(?:pruebas|prestaciones|examenes)\b/.test(normalized);
        const notes=summary?educationalEvidence(extraction):[];
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
