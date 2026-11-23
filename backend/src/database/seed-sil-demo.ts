import {createHash,randomBytes} from 'node:crypto';
import type {PoolClient} from 'pg';
import {hashPassword} from '../auth/password';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';

const digest=(input:string|Buffer)=>createHash('sha256').update(input).digest('hex');
function id(key:string){
  const hex=digest('vitalia-showcase-v1:'+key);
  return [hex.slice(0,8),hex.slice(8,12),'4'+hex.slice(13,16),
    '8'+hex.slice(17,20),hex.slice(20,32)].join('-');
}
const labId=(index:number)=>id('lab:'+index);
const siteId=(lab:number,index:number)=>id('site:'+lab+':'+index);
const operatorId=(index:number)=>id('operator:'+index);
const patientId=(index:number)=>id('patient:'+index);
const email=(name:string,index?:number)=>name+
  (index===undefined?'':'-'+String(index).padStart(3,'0'))+'@showcase.example.invalid';

function pdf(lines:string[]){
  const stream='BT /F1 15 Tf 50 740 Td '+lines.map(line=>'('+line+') Tj').join(' 0 -28 Td ')+' ET';
  const objects=[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length '+stream.length+' >>\nstream\n'+stream+'\nendstream',
  ];
  let output='%PDF-1.4\n';
  const offsets=objects.map((object,index)=>{
    const offset=output.length;
    output+=(index+1)+' 0 obj\n'+object+'\nendobj\n';
    return String(offset).padStart(10,'0')+' 00000 n \n';
  });
  return Buffer.from(output+'xref\n0 6\n0000000000 65535 f \n'+offsets.join('')+
    'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n'+output.length+'\n%%EOF\n','ascii');
}

async function seed(tx:PoolClient,admin:string,credentials:{operator:string;patient:string}){
  const operatorHash=await hashPassword(credentials.operator);
  const patientHash=await hashPassword(credentials.patient);
  async function account(accountId:string,address:string,role:string,hash:string){
    await tx.query('INSERT INTO vitalia_accounts(id,email,role_code,password_hash) VALUES ($1,$2,$3,$4)',
      [accountId,address,role,hash]);
  }
  const audit=async(key:string,lab:string,actor:string,action:string,order:string|null,date:Date)=>
    tx.query(`INSERT INTO vitalia_sil_main_audit(id,lab_id,actor_id,action,order_id,details,created_at)
      VALUES ($1,$2,$3,$4,$5,'{"showcase":true,"origin":"synthetic_seed"}',$6)`,
      [id('audit:'+key),lab,actor,action,order,date]);
  const day=86400000;
  const anchor=Math.floor(Date.now()/day)*day;
  const date=(days:number)=>new Date(anchor-days*day);
  for(let lab=0;lab<2;lab++){
    await tx.query('INSERT INTO vitalia_sil_main_laboratories(id,display_name,created_by,created_at) VALUES ($1,$2,$3,$4)',
      [labId(lab),['DEMO - Laboratorio Cordillera','DEMO - Laboratorio Costa'][lab],admin,date(740)]);
    await audit('lab:'+lab,labId(lab),admin,'laboratory_created',null,date(740));
    for(let site=0;site<3;site++){
      await tx.query(`INSERT INTO vitalia_sil_main_sites(id,lab_id,name,address,commune,region)
        VALUES ($1,$2,$3,$4,$5,$6)`,[siteId(lab,site),labId(lab),
        ['Casa matriz','Sede Norte','Sede Sur'][site],'Vía ficticia '+(100+site),
        (lab===0?['Providencia','Conchalí','Ñuñoa']:['Valparaíso','Viña del Mar','Quilpué'])[site],
        lab===0?'Metropolitana de Santiago':'Valparaíso']);
      await audit('site:'+lab+':'+site,labId(lab),admin,'site_created',null,date(739));
    }
  }
  for(let index=1;index<=10;index++){
    const lab=index<=7?0:1;
    await account(operatorId(index),email('operador',index),'operador_laboratorio',operatorHash);
    await tx.query(`INSERT INTO vitalia_sil_main_staff
      (lab_id,account_id,kind,granted_by,can_review_reports)
      VALUES ($1,$2,'operator',$3,$4)`,
      [labId(lab),operatorId(index),admin,index%3===0]);
    await audit('staff:'+index,labId(lab),admin,'staff_granted',null,date(738));
  }
  for(let index=1;index<=132;index++){
    const lab=index<=120?0:1;
    await account(patientId(index),email('paciente',index),'paciente',patientHash);
    const person=id('person:'+index);
    await tx.query(`INSERT INTO vitalia_people(id,account_id,first_name,first_surname,birth_date)
      VALUES ($1,$2,$3,$4,$5)`,[person,patientId(index),
      ['Alex','Cris','Dani','Fran','Martín','Valentina'][index%6],'Simulación '+index,
      date(365*(20+index%55))]);
    await tx.query('INSERT INTO vitalia_patient_profiles(person_id) VALUES ($1)',[person]);
    await tx.query(`INSERT INTO vitalia_sil_main_patients
      (lab_id,patient_id,verified_by,identity_evidence_reference,identity_checked_at)
      VALUES ($1,$2,$3,$4,$5)`,[labId(lab),patientId(index),operatorId(lab===0?3:9),
      'IDENTIDAD-FICTICIA-'+index,date(737)]);
  }
  for(let index=1;index<=660;index++){
    const lab=index<=600?0:1;
    const actor=operatorId(lab===0?3:9);
    const patient=patientId(index<=54?1:lab===0?2+(index-55)%119:121+(index-601)%12);
    const site=siteId(lab,index<=54?0:index%3);
    const order=id('order:'+index);
    const created=date(index<=54?(54-index)*13+2:1+index%170);
    const published=index<=54||index%10<6;
    const status=published?'report_published':index%10<8?'report_attached':'registered';
    const glucose=(84+index%29+(index%10)/10).toFixed(1);
    const includesA1c=index%3===0;
    const a1c=(5.1+(index%13)/10).toFixed(1);
    await tx.query(`INSERT INTO vitalia_sil_main_orders
      (id,lab_id,patient_id,site_id,status,created_by,created_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7)`,[order,labId(lab),patient,site,status,actor,created]);
    await tx.query(`INSERT INTO vitalia_sil_main_order_exams(order_id,exam_code)
      SELECT $1::uuid,unnest($2::text[])`,[order,includesA1c?['glicemia','hba1c']:['glicemia']]);
    const request=pdf(['Vitalia | Solicitud ficticia '+index,'Observacion: Control de seguimiento simulado','Glicemia',...(includesA1c?['HbA1c']:[])]);
    await tx.query(`INSERT INTO vitalia_sil_main_medical_requests
      (id,order_id,lab_id,patient_id,document_reference,prescriber_name,request_date,file_name,
       pdf_data,pdf_sha256,patient_identity_confirmed,human_review_confirmed,received_by,received_at)
      VALUES ($1,$2,$3,$4,$5,'Profesional ficticio',$6::timestamptz::date,$7,$8,$9,true,true,$10,$6)`,
      [id('request:'+index),order,labId(lab),patient,'SOL-SIM-'+index,created,
        'solicitud-simulada-'+index+'.pdf',request,digest(request),actor]);
    await audit('order:'+index,labId(lab),actor,'order_created',order,created);
    if(status==='registered')continue;
    const report=pdf(['Vitalia | Informe ficticio '+index,'Fecha: '+created.toISOString().slice(0,10),
      'Glucosa: '+glucose+' mg/dL',...(includesA1c?['HbA1c: '+a1c+' %']:[]),'Documento de simulacion, sin uso clinico']);
    const publication=new Date(created.getTime()+day);
    await tx.query(`INSERT INTO vitalia_sil_main_reports
      (id,order_id,lab_id,patient_id,file_name,pdf_data,pdf_sha256,issuing_laboratory,
       external_authorization_ref,authorized_professional_name,externally_authorized_at,
       patient_match_confirmed,attached_by,attached_at,published_by,published_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'Profesional ficticio',$10,true,$11,$10,$12,$13)`,
      [id('report:'+index),order,labId(lab),patient,'informe-simulado-'+index+'.pdf',report,digest(report),
        lab===0?'DEMO - Laboratorio Cordillera':'DEMO - Laboratorio Costa','AUT-SIM-'+index,created,
        actor,published?actor:null,published?publication:null]);
    await audit('report:'+index,labId(lab),actor,'report_attached',order,created);
    if(published)await audit('published:'+index,labId(lab),actor,'report_published',order,publication);
  }
  for(let index=1;index<=72;index++){
    const lab=index<=60?0:1;
    const actor=operatorId(lab===0?3:9);
    const pending=pdf(['Vitalia | Derivacion ficticia '+index,'Glicemia']);
    await tx.query(`INSERT INTO vitalia_sil_main_pending_requests
      (id,lab_id,site_id,uploaded_by,patient_email,file_name,pdf_data,pdf_sha256,extraction_status,created_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [id('pending:'+index),labId(lab),siteId(lab,index%3),actor,email('por-activar',index),
        'derivacion-simulada-'+index+'.pdf',pending,digest(pending),index%4?'text_ready':'needs_ocr',date(index%31)]);
    await audit('pending:'+index,labId(lab),actor,'pending_request_saved',null,date(index%31));
  }
}

async function main(){
  const [confirmation,rawEmail]=process.argv.slice(2);
  const adminEmail=rawEmail?.trim().toLowerCase();
  const config=readDatabaseConfig(process.env);
  if(confirmation!=='--cargar-demostracion' || !adminEmail || config.database!=='vitalia' ||
    process.env.VITALIA_SIL_MAIN_MODE!=='YES'){
    throw new Error('Uso en el SIL principal: --cargar-demostracion correo-del-administrador-existente');
  }
  const pool=createDatabasePool(config);
  try{
    const tx=await pool.connect();
    try{
      await tx.query('BEGIN');
      const identity=await tx.query('SELECT current_database() AS database');
      if(identity.rows[0].database!=='vitalia')throw new Error('La base de destino debe ser vitalia.');
      await tx.query("SELECT pg_advisory_xact_lock(hashtext('vitalia-sil-demo-seed'))");
      const schema=await tx.query(`SELECT EXISTS(
        SELECT 1 FROM public.vitalia_schema_migrations WHERE version='046_sil_main_laboratory_sites'
      ) AS ready`);
      if(!schema.rows[0].ready)throw new Error('La carga requiere el esquema SIL 046.');
      const marker=await tx.query(`SELECT EXISTS(
        SELECT 1 FROM public.vitalia_sil_main_audit
        WHERE id=$1 AND lab_id=$2 AND action='laboratory_created'
          AND details @> '{"showcase":true,"origin":"synthetic_seed"}'
      ) AS loaded`,[id('audit:lab:0'),labId(0)]);
      if(marker.rows[0].loaded){
        await tx.query('COMMIT');
        console.info('La demostración ya está cargada. Se conservaron sus datos y credenciales.');
        return;
      }
      const administrator=await tx.query<{id:string}>(`SELECT a.id FROM public.vitalia_accounts a
        JOIN public.vitalia_account_roles r ON r.account_id=a.id
        WHERE a.email=$1 AND r.role_code='administrador' AND r.active`,[adminEmail]);
      const admin=administrator.rows[0]?.id;
      if(!admin)throw new Error('El correo debe pertenecer a un administrador activo de Vitalia.');
      const credentials={
        operator:randomBytes(32).toString('hex'),
        patient:randomBytes(32).toString('hex'),
      };
      await seed(tx,admin,credentials);
      await tx.query('COMMIT');
      console.info('Carga completada: 2 laboratorios DEMO, 132 pacientes, 660 órdenes y 416 informes publicados.');
      console.info('Operadores DEMO (003 puede publicar): '+[1,2,3].map(index=>email('operador',index)).join(', '));
      console.info('Contraseña de operador DEMO: '+credentials.operator);
      console.info('Paciente DEMO: '+email('paciente',1));
      console.info('Contraseña de paciente DEMO: '+credentials.patient);
    } catch(error){
      await tx.query('ROLLBACK');
      throw error;
    } finally {
      tx.release();
    }
  } finally {
    await pool.end();
  }
}

void main().catch(error=>{
  const message=error instanceof Error?error.message:'error de inicialización';
  console.error('Carga DEMO:',message);
  process.exitCode=1;
});
