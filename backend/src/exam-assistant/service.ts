import {randomUUID} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {z} from 'zod';
import {type Pool} from 'pg';
import {type AccountSummary} from '../accounts/repository';
import {type DocumentDatabase} from '../documents/service';
import {type Extraction,extractionSchema} from '../ai/contract';
import {type ExamAssistant} from './local-model';
import {type Mode,type Reply,gate,synthetic,fixed,ASSISTANT_VERSION,validateReply,explanationView,notice} from './contract';
export class AssistantAccessError extends Error {constructor(public status:401|403|404|409|400|503){super();}}
type DB=Pick<Pool,'query'>;
interface Review{id:string;reviewed_extraction:Extraction}
interface Thread{id:string;review_snapshot:Extraction}
interface Turn{id:string;mode:Mode;question:string;status:'pending'|'ready'|'failed';response:Reply|null;created_at:Date;started_at:Date;finished_at:Date|null;attempt_id:string}
async function authorize(tx:DB,account:AccountSummary,doc:string){
 const own=await tx.query(`SELECT id FROM public.vitalia_documents WHERE id=$1 AND patient_id=$2 AND status='stored' FOR SHARE`,[doc,account.id]);
 if(own.rows.length!==1)throw new AssistantAccessError(404);
 const found=await tx.query<Review>(`SELECT id,reviewed_extraction FROM public.vitalia_professional_reviews WHERE document_id=$1 AND patient_id=$2 AND approved=true`,[doc,account.id]);
 const row=found.rows[0];return row?{id:row.id,reviewed_extraction:extractionSchema.parse(row.reviewed_extraction)}:null;
}
function identity(account:AccountSummary,doc:string){if(account.role!=='paciente')throw new AssistantAccessError(403);if(!z.uuid().safeParse(doc).success)throw new AssistantAccessError(404);}
async function audit(tx:DB,account:AccountSummary,doc:string,action:string){await tx.query(`INSERT INTO public.vitalia_exam_assistant_audit (id,patient_id,document_id,action) VALUES ($1,$2,$3,$4)`,[randomUUID(),account.id,doc,action]);}
async function threadFor(tx:DB,account:AccountSummary,doc:string,review:Review,lock=false){
 const found=await tx.query<Thread>(`SELECT id,review_snapshot FROM public.vitalia_exam_assistant_threads WHERE review_id=$1 AND document_id=$2 AND patient_id=$3${lock?' FOR UPDATE':''}`,[review.id,doc,account.id]);
 const row=found.rows[0];if(row&&!isDeepStrictEqual(row.review_snapshot,review.reviewed_extraction))throw new AssistantAccessError(503);return row??null;
}
async function turnFor(tx:DB,thread:string,id:string){
 const found=await tx.query<Turn>(`SELECT id,mode,question,status,response,created_at,started_at,finished_at,attempt_id FROM public.vitalia_exam_assistant_turns WHERE thread_id=$1 AND id=$2`,[thread,id]);return found.rows[0]??null;
}
function publicTurn(turn:Turn,extraction:Extraction){return {id:turn.id,mode:turn.mode,question:turn.question,status:turn.status,
 response:turn.status==='ready'?validateReply(turn.response,extraction,turn.mode):null,createdAt:turn.created_at,approved:false};}
function explanationState(turn:Turn|null,review:Review|null){
 const reply=turn?.status==='ready'&&review?validateReply(turn.response,review.reviewed_extraction,'explanation'):null;
 return {status:!review?'not_available':!turn?'not_requested':turn.status==='pending'?'generating':turn.status,
  reviewId:review?.id??null,approved:false,generatedAt:turn?.status==='ready'?turn.finished_at:null,
  explanation:reply&&review?explanationView(review.reviewed_extraction,reply):null};
}
export function createExamAssistantService(db:DocumentDatabase,model:ExamAssistant){
 let busy=false;
 async function run(account:AccountSummary,doc:string,mode:Mode,input:unknown){
  identity(account,doc);
  const parsed=mode==='chat'?z.object({requestId:z.uuid(),question:z.string().trim().min(1).max(500)}).strict().safeParse(input):z.object({}).strict().safeParse(input??{});
  if(!parsed.success)throw new AssistantAccessError(400);
  const question=mode==='chat'?(parsed.data as {question:string}).question:'Explica en palabras sencillas los indicadores de este examen, sin interpretar sus cifras.';
  const requestedId=mode==='chat'?(parsed.data as {requestId:string}).requestId:null;
  const preview=await db.transaction(async tx=>{
   const review=await authorize(tx,account,doc);if(!review)throw new AssistantAccessError(409);
   if(review.reviewed_extraction.resultados.length<1||review.reviewed_extraction.resultados.length>20||Buffer.byteLength(JSON.stringify(review.reviewed_extraction))>12000)throw new AssistantAccessError(400);
   const thread=await threadFor(tx,account,doc,review);const id=requestedId??thread?.id;
   const turn=thread&&id?await turnFor(tx,thread.id,id):null;
   if(turn&&(turn.mode!==mode||turn.question!==question))throw new AssistantAccessError(409);
   return {review,thread,turn};
  });
  if(preview.turn&&(preview.turn.status==='ready'||(preview.turn.status==='pending'&&Date.now()-preview.turn.started_at.getTime()<180000)||mode==='chat'&&preview.turn.status==='failed')){
   return mode==='chat'?{turn:publicTurn(preview.turn,preview.review.reviewed_extraction)}:explanationState(preview.turn,preview.review);
  }
  if(busy)throw new AssistantAccessError(503);busy=true;const attempt=randomUUID();let claimed:Turn|null=null;let threadId:string|null=null;
  try{
   const reserved=await db.transaction(async tx=>{
    const review=await authorize(tx,account,doc);if(!review||review.id!==preview.review.id)throw new AssistantAccessError(409);
    await tx.query(`INSERT INTO public.vitalia_exam_assistant_threads (id,review_id,document_id,patient_id,review_snapshot)
     VALUES ($1,$2,$3,$4,$5::jsonb) ON CONFLICT (review_id) DO NOTHING`,[randomUUID(),review.id,doc,account.id,JSON.stringify(review.reviewed_extraction)]);
    const thread=await threadFor(tx,account,doc,review,true);if(!thread)throw new AssistantAccessError(503);
    threadId=thread.id;
    const expired=await tx.query(`UPDATE public.vitalia_exam_assistant_turns SET status='failed',response=NULL,finished_at=CURRENT_TIMESTAMP
     WHERE thread_id=$1 AND status='pending' AND started_at<CURRENT_TIMESTAMP-INTERVAL '3 minutes' RETURNING id`,[thread.id]);
    if(expired.rows.length)await audit(tx,account,doc,'failed');
    const id=requestedId??thread.id;const existing=await turnFor(tx,thread.id,id);
    if(existing&&(existing.mode!==mode||existing.question!==question))throw new AssistantAccessError(409);
    if(existing&&(mode==='chat'||existing.status!=='failed'))return {turn:existing,review,execute:false,history:[]};
    const pending=await tx.query(`SELECT id FROM public.vitalia_exam_assistant_turns WHERE thread_id=$1 AND status='pending'`,[thread.id]);if(pending.rows.length)throw new AssistantAccessError(503);
    const count=await tx.query<{n:string}>(`SELECT count(*)::text AS n FROM public.vitalia_exam_assistant_turns WHERE thread_id=$1 AND mode='chat'`,[thread.id]);
    if(mode==='chat'&&Number(count.rows[0]?.n??0)>=30)throw new AssistantAccessError(409);
    if(existing){
     if(existing.finished_at&&Date.now()-existing.finished_at.getTime()<30000)throw new AssistantAccessError(503);
     await tx.query(`UPDATE public.vitalia_exam_assistant_turns SET status='pending',response=NULL,attempt_id=$1,started_at=CURRENT_TIMESTAMP,finished_at=NULL WHERE id=$2 AND thread_id=$3 AND status='failed'`,[attempt,id,thread.id]);
    }else{
     const inserted=await tx.query(`INSERT INTO public.vitalia_exam_assistant_turns (id,thread_id,mode,question,status,attempt_id)
      VALUES ($1,$2,$3,$4,'pending',$5) ON CONFLICT (id) DO NOTHING RETURNING id`,[id,thread.id,mode,question,attempt]);
     if(inserted.rows.length!==1)throw new AssistantAccessError(409);
    }
    await audit(tx,account,doc,'request');
    const prior=await tx.query<Turn>(`SELECT id,mode,question,status,response,created_at,started_at,finished_at,attempt_id
     FROM public.vitalia_exam_assistant_turns WHERE thread_id=$1 AND mode='chat' AND status='ready' AND response->>'kind'='education' ORDER BY ordinal DESC LIMIT 6`,[thread.id]);
    const turn=await turnFor(tx,thread.id,id);if(!turn)throw new AssistantAccessError(503);
    return {turn,review,execute:true,history:prior.rows.reverse().map(row=>({question:row.question,response:validateReply(row.response,review.reviewed_extraction,'chat')}))};
   });
   if(!reserved.execute)return mode==='chat'?{turn:publicTurn(reserved.turn,reserved.review.reviewed_extraction)}:explanationState(reserved.turn,reserved.review);
   claimed=reserved.turn;
   const extraction=reserved.review.reviewed_extraction;
   const blocked=mode==='chat'?gate(question,extraction,reserved.history):extraction.resultados.every(row=>synthetic(row.nombre))?fixed('insufficient',extraction.resultados.map((_,i)=>i)):null;
   const generated=blocked?{reply:blocked,model:'backend-policy',promptVersion:ASSISTANT_VERSION,elapsedMs:0}:
    await model({extraction,question,mode,history:reserved.history});
   const checked=validateReply(generated.reply,reserved.review.reviewed_extraction,mode);if(generated.promptVersion!==2)throw new AssistantAccessError(503);
   return await db.transaction(async tx=>{
    const review=await authorize(tx,account,doc);if(!review||review.id!==reserved.review.id)throw new AssistantAccessError(404);
    const updated=await tx.query(`UPDATE public.vitalia_exam_assistant_turns SET status='ready',response=$1::jsonb,model=$2,prompt_version=$3,elapsed_ms=$4,finished_at=CURRENT_TIMESTAMP
     WHERE id=$5 AND thread_id=$6 AND attempt_id=$7 AND status='pending' RETURNING id`,[JSON.stringify(checked),generated.model,generated.promptVersion,generated.elapsedMs,claimed!.id,threadId,attempt]);
    if(updated.rows.length!==1)throw new AssistantAccessError(503);
    await audit(tx,account,doc,'ready');const saved=await turnFor(tx,threadId!,claimed!.id);if(!saved)throw new AssistantAccessError(503);
    return mode==='chat'?{turn:publicTurn(saved,review.reviewed_extraction)}:explanationState(saved,review);
   });
  }catch(error){
   if(claimed)await db.transaction(async tx=>{
    const changed=await tx.query(`UPDATE public.vitalia_exam_assistant_turns SET status='failed',response=NULL,finished_at=CURRENT_TIMESTAMP
     WHERE id=$1 AND thread_id=$2 AND attempt_id=$3 AND status='pending' RETURNING id`,[claimed!.id,threadId,attempt]);
    if(changed.rows.length)await audit(tx,account,doc,'failed');
   });
   if(error instanceof AssistantAccessError)throw error;throw new AssistantAccessError(503);
  }finally{busy=false;}
 }
 return {
  async get(account:AccountSummary,doc:string){
   identity(account,doc);return db.transaction(async tx=>{
    const review=await authorize(tx,account,doc),thread=review?await threadFor(tx,account,doc,review):null;
    const result=thread?await tx.query<Turn>(`SELECT id,mode,question,status,response,created_at,started_at,finished_at,attempt_id FROM public.vitalia_exam_assistant_turns WHERE thread_id=$1 AND mode='chat' ORDER BY ordinal LIMIT 30`,[thread.id]):{rows:[]};
    await audit(tx,account,doc,'view');return {status:review?'available':'not_available',reviewId:review?.id??null,notice,approved:false,
     turns:review?result.rows.map(row=>publicTurn(row,review.reviewed_extraction)):[]};
   });
  },
  async getExplanation(account:AccountSummary,doc:string){
   identity(account,doc);return db.transaction(async tx=>{
    const review=await authorize(tx,account,doc),thread=review?await threadFor(tx,account,doc,review):null;
    const turn=thread?await turnFor(tx,thread.id,thread.id):null;await audit(tx,account,doc,'view');return explanationState(turn,review);
   });
  },
  request:(account:AccountSummary,doc:string,input:unknown)=>run(account,doc,'chat',input),
  explain:(account:AccountSummary,doc:string,input:unknown)=>run(account,doc,'explanation',input),
 };
}
export type ExamAssistantServices=ReturnType<typeof createExamAssistantService>;
