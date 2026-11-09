import {createHash,randomUUID} from 'node:crypto';
import {type Pool} from 'pg';
import {readPdfText,type PdfReadResult} from '../pdf/reader';
import {identifyDocument} from '../documents/file-validation';
import {SilConflictError,SilNotFoundError} from './service';

type IntakeReceipt={
  actorId:string;
  patientId:string;
  patientIdentifier:string;
  bytes:Buffer;
  fileName:string;
  sha256:string;
  expiresAt:number;
};
export type IntakeConfirmation={
  previewToken:string;
  patientId:string;
  branchCode:string;
  examCodes:string[];
  documentReference:string;
  prescriberName:string;
  requestDate:string;
  verified:true;
};

/**
 * Recepción de órdenes médicas DEMO. El lector propone prestaciones del
 * catálogo mediante coincidencia textual determinista; NO es OCR ni modelo
 * generativo. Nadie crea una orden sin cotejo y confirmación del operador.
 */
export function createSilMedicalRequestIntake(
  db:Pool, options:{read?:typeof readPdfText}={},
){
  const read=options.read??readPdfText;
  const receipts=new Map<string,IntakeReceipt>();
  const normalize=(value:string)=>value.normalize('NFKD')
    .replace(/[\u0300-\u036f]/g,'')
    .toLowerCase().replace(/[^a-z0-9]+/g,' ').replace(/\s+/g,' ').trim();
  const matchesName=(text:string,name:string)=>{
    const full=normalize(name);
    return Boolean(full)&&(' '+text+' ').includes(' '+full+' ');
  };
  function prune(){
    const now=Date.now();
    for(const [token,item] of receipts){
      if(item.expiresAt<now)receipts.delete(token);
    }
    while(receipts.size>=15){
      const oldest=receipts.keys().next().value;
      if(oldest===undefined)break;
      receipts.delete(oldest);
    }
  }
  async function patient(email:string){
    if(!email.endsWith('@example.invalid'))throw new SilNotFoundError();
    const result=await db.query<{
      id:string;email:string;identifier:string|null;
      givenNames:string|null;familyNames:string|null;birthDate:string|null;
    }>(
      `SELECT a.id,a.email,
          p.synthetic_identifier AS identifier,
          p.given_names AS "givenNames",
          p.family_names AS "familyNames",
          p.birth_date::text AS "birthDate"
       FROM public.vitalia_accounts a
       LEFT JOIN public.vitalia_sil_patient_profiles_demo p
         ON p.patient_id=a.id
       WHERE a.email=$1 AND a.role_code='paciente'`,[email.toLowerCase()]);
    if(!result.rows.length)throw new SilNotFoundError();
    return result.rows[0];
  }
  async function preview(actorId:string,email:string,fileName:string,bytes:Buffer){
    if(bytes.length<8||bytes.length>2*1024*1024 ||
       fileName.length<5||fileName.length>120 ||
       !/\.pdf$/i.test(fileName)||/[\\/\x00-\x1f]/.test(fileName))
      throw new SilConflictError();
    identifyDocument(bytes,'application/pdf',fileName);
    const person=await patient(email);
    if(!person.identifier||!person.givenNames||
       !person.familyNames||!person.birthDate)
      throw new SilConflictError();
    const catalog=await db.query<{code:string;name:string}>(
      'SELECT code,name FROM public.vitalia_sil_exam_catalog WHERE active ORDER BY name');

    let reading:PdfReadResult;
    try{reading=await read(bytes);}catch{
      reading={status:'rejected',text:null,pageCount:null,incidents:[]};
    }
    const warnings:string[]=[];
    if(reading.status!=='text_ready'||!reading.text){
      warnings.push(reading.status==='needs_ocr'
        ? 'Este PDF necesita OCR. No se creará una orden desde un archivo que no se puede leer.'
        : 'No se pudo comprobar el contenido del PDF. Usa una orden ficticia con texto seleccionable.');
    }
    const source=reading.text??'';
    const normalized=normalize(source);
    // Requiere identificación comprobable en el documento original.
    const documentIds=[...new Set((source.match(/(?<![A-Z0-9-])DEMO-[A-Z0-9-]{3,16}(?![A-Z0-9-])/gi)??[])
      .map(id=>id.toUpperCase()))];
    const identifierMatches=documentIds.length===1&&
      documentIds[0]===person.identifier;
    const givenNamesMatch=matchesName(normalized,person.givenNames);
    const familyNamesMatch=matchesName(normalized,person.familyNames);
    const iso=person.birthDate;
    const dateVariants=[
      iso,
      iso?iso.slice(8,10)+'/'+iso.slice(5,7)+'/'+iso.slice(0,4):'',
      iso?iso.slice(8,10)+'-'+iso.slice(5,7)+'-'+iso.slice(0,4):'',
    ];
    const birthDateMatches=Boolean(iso)&&dateVariants.some(v=>v&&source.includes(v));
    if(!identifierMatches)warnings.push(
      'Identificador distinto, ausente o ambiguo. La solicitud no puede vincularse al paciente.');
    if(!givenNamesMatch||!familyNamesMatch)warnings.push(
      'Los nombres o apellidos del paciente no coinciden literalmente con la ficha DEMO.');
    if(!birthDateMatches)warnings.push(
      'La fecha de nacimiento no se encuentra en el documento con el formato registrado.');
    const selected=catalog.rows.filter(item=>{
      const candidate=normalize(item.name);
      const hints=item.code==='glicemia'?['glicemia','glucosa','glucemia']:
        item.code==='hba1c'?['hba1c','hemoglobina glicosilada','hemoglobina glucosilada']:
        [candidate];
      return hints.some(h=>normalized.includes(normalize(h)));
    }).map(item=>({code:item.code,name:item.name}));
    if(!selected.length)warnings.push(
      'No se detectaron prestaciones del catálogo. El operador debe seleccionarlas desde la orden original.');
    // Ningún PDF, ni siquiera uno con datos coincidentes, se considera aprobado.
    const verified=reading.status==='text_ready'&&identifierMatches&&
      givenNamesMatch&&familyNamesMatch&&birthDateMatches;
    let previewToken:string|null=null;
    if(verified){
      prune();
      previewToken=randomUUID();
      receipts.set(previewToken,{
        actorId,patientId:person.id,patientIdentifier:person.identifier,
        bytes:Buffer.from(bytes),fileName,sha256:createHash('sha256').update(bytes).digest('hex'),
        expiresAt:Date.now()+10*60_000,
      });
    }
    return {
      state:verified?'requires_operator_review':'identity_mismatch',
      patient:{id:person.id,email:person.email,identifier:person.identifier,
        givenNames:person.givenNames,familyNames:person.familyNames,
        birthDate:person.birthDate},
      identity:{identifierMatches,givenNamesMatch,familyNamesMatch,birthDateMatches},
      suggestedExams:selected,warnings,previewToken,confirmed:false as const,
      extractionMethod:'text_catalog_match' as const,
      // No devolver el contenido clínico del PDF al cliente.
    };
  }

  async function confirm(actorId:string,input:IntakeConfirmation){
    const receipt=receipts.get(input.previewToken);
    if(!receipt||receipt.actorId!==actorId||receipt.patientId!==input.patientId||
       receipt.expiresAt<Date.now()||!input.verified)throw new SilConflictError();
    if(input.examCodes.length<1||input.examCodes.length>6 ||
       new Set(input.examCodes).size!==input.examCodes.length ||
       input.documentReference.trim().length<3 ||
       input.prescriberName.trim().length<3)throw new SilConflictError();
    const date=new Date(input.requestDate+'T12:00:00Z');
    if(!Number.isFinite(date.getTime())||
       input.requestDate!==date.toISOString().slice(0,10)||
       input.requestDate>new Date().toISOString().slice(0,10))
      throw new SilConflictError();

    const client=await db.connect();
    let failed=false;
    try{
      await client.query('BEGIN');
      const verified=await client.query<{identifier:string}>(
        `SELECT p.synthetic_identifier AS identifier
         FROM public.vitalia_sil_patient_profiles_demo p
         JOIN public.vitalia_accounts a ON a.id=p.patient_id
         WHERE p.patient_id=$1 AND a.role_code='paciente'
         FOR UPDATE OF p`,[receipt.patientId]);
      if(verified.rows[0]?.identifier!==receipt.patientIdentifier)
        throw new SilConflictError();
      const branch=await client.query(
        'SELECT 1 FROM public.vitalia_sil_branches WHERE code=$1 AND active=true',
        [input.branchCode]);
      if(branch.rows.length!==1)throw new SilConflictError();
      const exams=await client.query<{code:string}>(
        'SELECT code FROM public.vitalia_sil_exam_catalog WHERE code=ANY($1::text[]) AND active=true',
        [input.examCodes]);
      if(exams.rows.length!==input.examCodes.length)
        throw new SilConflictError();
      const duplicate=await client.query(
        `SELECT 1 FROM public.vitalia_sil_medical_requests_demo
         WHERE patient_id=$1 AND pdf_sha256=$2 LIMIT 1`,
        [receipt.patientId,receipt.sha256]);
      if(duplicate.rows.length)throw new SilConflictError();
      const orderId=randomUUID();
      const created=await client.query<{orderNumber:string}>(
        `INSERT INTO public.vitalia_sil_orders(
           id,patient_id,created_by,exam_code,origin_branch_code)
         VALUES($1,$2,$3,$4,$5)
         RETURNING 'VH-' || lpad(order_number::text,6,'0') AS "orderNumber"`,
        [orderId,receipt.patientId,actorId,input.examCodes[0],input.branchCode]);
      for(const code of input.examCodes){
        await client.query(
          'INSERT INTO public.vitalia_sil_order_exams(order_id,exam_code) VALUES($1,$2)',
          [orderId,code]);
      }
      const referralId=randomUUID();
      await client.query(
        `INSERT INTO public.vitalia_sil_medical_requests_demo(
          id,order_id,patient_id,origin_branch_code,document_reference,
          prescriber_name,request_date,file_name,pdf_data,pdf_sha256,
          patient_identity_checked,request_review_confirmed,created_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,true,true,$11)`,
        [referralId,orderId,receipt.patientId,input.branchCode,
          input.documentReference.trim(),input.prescriberName.trim(),
          input.requestDate,receipt.fileName,receipt.bytes,receipt.sha256,actorId]);
      const details={
        requestId:referralId,branchCode:input.branchCode,
        examCodes:input.examCodes,documentSha256:receipt.sha256,
        operatorReviewed:true,
      };
      await client.query(
        `INSERT INTO public.vitalia_sil_audit(id,order_id,actor_id,action,details)
         VALUES($1,$2,$3,'order_created',$4::jsonb),
               ($5,$2,$3,'medical_request_received',$4::jsonb)`,
        [randomUUID(),orderId,actorId,JSON.stringify(details),randomUUID()]);
      await client.query('COMMIT');
      receipts.delete(input.previewToken);
      return {order:{id:orderId,orderNumber:created.rows[0].orderNumber,
        status:'registered',examCodes:input.examCodes},requestId:referralId};
    }catch(error){
      try{await client.query('ROLLBACK');}catch{failed=true;}
      if((error as {code?:string}).code==='23505')
        throw new SilConflictError();
      throw error;
    }finally{client.release(failed);}
  }
  return {preview,confirm};
}
