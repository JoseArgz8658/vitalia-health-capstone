import {createExamAssistantService,AssistantAccessError} from '../exam-assistant/service';
import {createExplanationService,ExplanationPendingReviewError} from '../explanations/service';
import {renderExplanation,expectedConcept} from '../explanations/catalog';
import {randomUUID} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {type Pool,type PoolClient} from 'pg';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {createPrivilegedAccount} from '../accounts/privileged';
import {insertPatientAccount} from '../accounts/repository';
import {hashPassword} from '../auth/password';
import {createAssignmentService} from '../assignments/service';
import {reserveDocument,completeDocument} from '../documents/repository';
import {queueDocumentProcessing,claimDocumentProcessing,completeDocumentProcessing,findProcessingForWorker} from '../processing/repository';
import {createReviewService,ReviewConflictError,ReviewNotFoundError} from '../reviews/service';
import {createProcessingService} from '../processing/service';
async function main(){
 let pool:Pool|undefined,client:PoolClient|undefined,started=false,failed=false;
 try{
  pool=createDatabasePool(readDatabaseConfig(process.env));client=await pool.connect();
  await client.query('BEGIN');started=true;
  const password=randomUUID();
  const create=(role:'administrador'|'profesional')=>createPrivilegedAccount(client!,{email:randomUUID()+'@example.invalid',role,password,confirmation:password});
  const admin=await create('administrador'),professional=await create('profesional'),other=await create('profesional');
  const patient=await insertPatientAccount(client,randomUUID()+'@example.invalid',await hashPassword(password));
  const db={query:client.query.bind(client) as Pool['query'],transaction:async<T>(work:(db:Pick<Pool,'query'>)=>Promise<T>)=>work(client!)};
  const assignments=createAssignmentService(db);
  const relation=await assignments.assign(admin,{patientEmail:patient.email,professionalEmail:professional.email});
  // Metadatos y extracción sintéticos dentro de la transacción; sin S3 ni IA reales.
  const doc=await reserveDocument(client,patient,{examName:'Prueba de revisión',examType:'Laboratorio',examDate:'2026-01-01',originalName:'ficticio.pdf',contentType:'application/pdf',sizeBytes:100});
  await completeDocument(client,patient,doc.id);
  const processingId=await queueDocumentProcessing(client,patient,doc.id);if(!processingId)throw new Error();
  await claimDocumentProcessing(client,processingId);
  const text='Examen ficticio de revisión';
  const extraction={examen:'Prueba ficticia',fecha:'29-09-2026',resultados:[{nombre:'Alfa',valor:'15,2',unidad:' g/dL',rango_referencia:'14,0–16,0 g/dL'}]};
  await completeDocumentProcessing(client,processingId,{status:'requires_review',source:'pdf',method:'direct',reading:{status:'text_ready',text,pageCount:1,incidents:[]},ocr:null,inputText:text,
   ai:{status:'requires_review',raw:JSON.stringify(extraction),extraction,incidents:[],approved:false,model:'qwen3:4b-instruct',promptVersion:3,elapsedMs:1},approved:false});
  const before=await findProcessingForWorker(client,processingId);
  let calls=0;
  const explanations=createExplanationService(db,async extraction=>{
   calls++;return {explanation:renderExplanation(extraction,{items:extraction.resultados.map((row,index)=>({index,concept:expectedConcept(row.nombre)}))}),
    model:'synthetic-local-test',promptVersion:1,catalogVersion:1,elapsedMs:1};
  });
  if((await explanations.get(patient,doc.id)).status!=='not_available')throw new Error('Explicación previa a revisión.');
  let blocked=false;try{await explanations.request(patient,doc.id);}catch(error){if(error instanceof ExplanationPendingReviewError)blocked=true;else throw error;}
  if(!blocked||calls)throw new Error('Generación sin revisión.');
  const service=createReviewService(db);
  if((await service.getPatient(patient,doc.id)).review!==null)throw new Error('Revisión pendiente expuesta.');
  const reviewed=structuredClone(extraction);reviewed.resultados[0].unidad='g/dL';
  const input={processingId,extraction:reviewed,observations:'Espacio inicial de unidad corregido tras cotejar el original ficticio.',confirmedOriginal:true};
  const saved=await service.approve(professional,patient.id,doc.id,input);
  if(!saved.approved||saved.reviewerId!==professional.id||saved.extraction.resultados[0].unidad!=='g/dL')throw new Error();
  async function denied(work:()=>Promise<unknown>,expected:typeof ReviewConflictError|typeof ReviewNotFoundError){
   try{await work();}catch(error){if(error instanceof expected)return;throw error;}throw new Error('Acceso indebido.');
  }
  await denied(()=>service.approve(professional,patient.id,doc.id,input),ReviewConflictError);
  await denied(()=>service.get(other,patient.id,doc.id),ReviewNotFoundError);
  for(const operation of ['UPDATE public.vitalia_professional_reviews SET observations=observations WHERE id=$1','DELETE FROM public.vitalia_professional_reviews WHERE id=$1']){
   await client.query('SAVEPOINT review_guard');let blocked=false;
   try{await client.query(operation,[saved.id]);}catch{blocked=true;await client.query('ROLLBACK TO SAVEPOINT review_guard');}
   await client.query('RELEASE SAVEPOINT review_guard');if(!blocked)throw new Error('Revisión mutable.');
  }
  const after=await findProcessingForWorker(client,processingId);
  if(!isDeepStrictEqual(before?.result,after?.result)||after?.status!=='requires_review')throw new Error('Original modificado.');
  const stored=await client.query<{original_extraction:unknown}>(`SELECT original_extraction FROM public.vitalia_professional_reviews WHERE id=$1`,[saved.id]);
  if(!isDeepStrictEqual(stored.rows[0]?.original_extraction,extraction))throw new Error('Proveniencia inválida.');
  if((await createProcessingService(db).get(patient,doc.id)).reviewStatus!=='approved')throw new Error('Estado de paciente inválido.');
  const patientCopy=await service.getPatient(patient,doc.id);
  if(!patientCopy.review?.approved||!isDeepStrictEqual(patientCopy.review.extraction,reviewed)||
   Object.keys(patientCopy.review).sort().join(',')!=='approved,extraction,observations,reviewedAt')throw new Error('Copia de paciente inválida.');
  const otherPatient=await insertPatientAccount(client,randomUUID()+'@example.invalid',await hashPassword(password));
  await denied(()=>service.getPatient(otherPatient,doc.id),ReviewNotFoundError);
  const explanation=await explanations.request(patient,doc.id);
  if(explanation.status!=='ready'||explanation.approved!==false||explanation.explanation?.items[0].unit!=='g/dL')throw new Error('Explicación inválida.');
  await explanations.request(patient,doc.id);if(calls!==1)throw new Error('Generación duplicada.');
  const {ExplanationNotFoundError}=await import('../explanations/service');
  let isolated=false;try{await explanations.get(otherPatient,doc.id);}catch(error){if(error instanceof ExplanationNotFoundError)isolated=true;else throw error;}
  if(!isolated)throw new Error('Explicación expuesta a otro paciente.');
  const count=await client.query<{n:string}>(`SELECT count(*)::text AS n FROM public.vitalia_exam_explanations WHERE review_id=$1`,[saved.id]);
  if(count.rows[0]?.n!=='1')throw new Error('Persistencia duplicada.');
  const approvedReview=await service.getPatient(patient,doc.id);
  if(!isDeepStrictEqual(approvedReview.review?.extraction,reviewed))throw new Error('Revisión modificada por explicación.');
  let assistantCalls=0;
  const assistant=createExamAssistantService(db,async({mode,extraction})=>{
   assistantCalls++;
   const definitions=mode==='explanation'?extraction.resultados.map((_,index)=>({index,text:'No se identifica con certeza el significado de este indicador.',known:false})):[];
   const indices=mode==='explanation'?extraction.resultados.map((_,index)=>index):[0];
   return {reply:{kind:'education',answer:'La unidad describe cómo se expresa el dato del examen.',indices,definitions},model:'synthetic-local-test',promptVersion:2,elapsedMs:1};
  });
  const inputChat={requestId:randomUUID(),question:'¿Qué significa g/dL?'};
  const response=await assistant.request(patient,doc.id,inputChat);
  if(!('turn' in response)||response.turn.status!=='ready'||response.turn.approved!==false)throw new Error('Chat inválido.');
  await assistant.request(patient,doc.id,inputChat);if(assistantCalls!==1)throw new Error('Chat duplicado.');
  const explanationV2=await assistant.explain(patient,doc.id,{});
  if(!('explanation' in explanationV2)||explanationV2.explanation?.items[0].concept!=='desconocido')throw new Error('Indicador ficticio inventado.');
  const callsBeforeDenied=assistantCalls;
  await assistant.explain(patient,doc.id,{});if(assistantCalls!==callsBeforeDenied)throw new Error('Explicación duplicada.');
  const deniedChat=await assistant.request(patient,doc.id,{requestId:randomUUID(),question:'Consulta otro examen'});
  if(!('turn' in deniedChat)||deniedChat.turn.response?.kind!=='out_of_scope'||assistantCalls!==callsBeforeDenied)throw new Error('Cambio de contexto permitido.');
  let blockedChat=false;try{await assistant.get(otherPatient,doc.id);}catch(error){if(error instanceof AssistantAccessError&&error.status===404)blockedChat=true;else throw error;}
  if(!blockedChat)throw new Error('Chat expuesto.');
  const history=await assistant.get(patient,doc.id);if(history.turns.length!==2)throw new Error('Conversación no persistida.');
  if(!isDeepStrictEqual((await service.getPatient(patient,doc.id)).review?.extraction,reviewed))throw new Error('Revisión alterada.');
  await assignments.deactivate(admin,relation.assignment.id);
  await denied(()=>service.get(professional,patient.id,doc.id),ReviewNotFoundError);
  if(!(await service.getPatient(patient,doc.id)).review?.approved)throw new Error('Historial del paciente perdido.');
  await client.query('ROLLBACK');started=false;
  console.info('Chat por examen, idempotencia, persistencia, aislamiento y conservación del original correctos. Datos sintéticos revertidos.');
 }catch{failed=true;process.exitCode=1;console.error('No se pudo verificar el asistente. Revisa PostgreSQL y migración 011.');}
 finally{
  if(started&&client)try{await client.query('ROLLBACK');}catch{failed=true;}
  client?.release(failed);if(pool)await pool.end().catch(()=>{process.exitCode=1;});
 }
}
void main();
