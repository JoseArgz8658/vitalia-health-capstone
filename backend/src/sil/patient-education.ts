import {type Pool} from 'pg';
import {type Extraction} from '../ai/contract';
import {createExamAssistant,type ExamAssistant,AssistantModelError} from '../exam-assistant/local-model';
import {notice} from '../exam-assistant/contract';

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
      const normalized=question.normalize('NFD').replace(/[\u0300-\u036f]/g,'')
        .toLowerCase().trim();
      const result=(answer:string,source:'catalogo'|'modelo_local'|'politica')=>({
        answer,source,notice:educationNotice,approved:false,
      });

      // Solo datos de catálogo: no inferir ni recuperar cifras desde el PDF.
      if(/(?:cuales|que|mis)\s+(?:son\s+)?(?:examenes|pruebas|prestaciones)|que me pidieron/.test(normalized)) {
        return result('Esta orden registra las prestaciones: '+labels.join(', ')+
          '. Para consultar los valores y observaciones, abre el PDF publicado.','catalogo');
      }
      if(/\b(?:cuanto|cuantos|cuanta|valor|valores|numero|cifra|resultado numerico|resultado de mi|me salio|salio|sali[oó]|porcentaje|nivel|rango|referencia|normal|anormal|alto|bajo|grave|diabetes|diagnostic|tratamiento|dosis|medicamento|debo tomar|que hago|estoy bien|estoy mal)\b/.test(normalized)) {
        return result(
          'No puedo confirmar cifras ni interpretar tus resultados desde esta conversación. '+
          'Los valores están en el PDF del informe. Esta herramienta solo explica conceptos generales.',
          'politica');
      }
      const key=patientId+':'+reportId;
      const now=Date.now();
      const timestamps=(recent.get(key)??[]).filter(t=>now-t<15*60_000);
      if(timestamps.length>=12||busy.has(key))throw new SilEducationBusy();
      timestamps.push(now);
      recent.set(key,timestamps);
      busy.add(key);
      try {
        const extraction:Extraction={
          examen:labels.join(', '),fecha:null,
          resultados:rows.rows.slice(0,20).map(row=>({
            nombre:row.name,valor:null,unidad:null,rango_referencia:null,
          })),
        };
        const generated=await model({extraction,question,mode:'chat',history:[]});
        const kind=generated.reply.kind;
        // La validación del modelo compartido bloquea afirmaciones clínicas y
        // respuestas con cifras no sustentadas; las categorías se conservan.
        return result(generated.reply.answer,
          generated.model==='knowledge-fast-path'||generated.model==='backend-policy'
            ? 'catalogo':'modelo_local');
      }catch(error) {
        if(error instanceof AssistantModelError)throw new SilEducationUnavailable();
        throw error;
      }finally{
        busy.delete(key);
      }
    },
  };
}
