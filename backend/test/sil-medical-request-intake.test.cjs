'use strict';
const {createSilMedicalRequestIntake}=require('../dist/sil/medical-request-intake');
const {SilConflictError}=require('../dist/sil/service');
const patientId='11111111-1111-4111-8111-111111111111';
const actorId='22222222-2222-4222-8222-222222222222';
const source='Solicitud de exámenes ficticia\nIdentificador: DEMO-0001\n'
  +'Paciente Prueba Vitalia Demo\nNacimiento: 1990-01-01\n'
  +'Prestaciones: Glicemia, Hemoglobina glicosilada (HbA1c).\n'
  +'Referencia: SOL-DEMO-001.\n';
const pdf=Buffer.from('%PDF-1.4\nsolicitud ficticia\n%%EOF');
function createDb({duplicate=false}={}){
 const txQueries=[];
 const client={
  query:jest.fn(async(sql,values)=>{
   txQueries.push({sql,values});
   if(sql.includes('SELECT p.synthetic_identifier'))
     return {rows:[{identifier:'DEMO-0001'}]};
   if(sql.includes('SELECT 1 FROM public.vitalia_sil_branches'))
     return {rows:[{ok:true}]};
   if(sql.includes('SELECT code FROM public.vitalia_sil_exam_catalog'))
     return {rows:[{code:'glicemia'},{code:'hba1c'}]};
   if(sql.includes('SELECT 1 FROM public.vitalia_sil_medical_requests_demo'))
     return {rows:duplicate?[{found:true}]:[]};
   if(sql.includes('RETURNING')){
     return {rows:[{orderNumber:'VH-000125'}]};
   }
   return {rows:[]};
  }),
  release:jest.fn(),
 };
 const db={
  query:jest.fn(async(sql,values)=>{
   if(sql.includes('FROM public.vitalia_accounts a'))
     return {rows:[{id:patientId,email:'paciente.sil@example.invalid',
       identifier:'DEMO-0001',givenNames:'Paciente Prueba',
       familyNames:'Vitalia Demo',birthDate:'1990-01-01'}]};
   if(sql.includes('FROM public.vitalia_sil_exam_catalog WHERE active'))
     return {rows:[{code:'glicemia',name:'Glicemia'},
       {code:'hba1c',name:'Hemoglobina glicosilada (HbA1c)'}]};
   throw Error('unexpected query: '+sql);
  }),
  connect:jest.fn(async()=>client),
 };
 return {db,client,txQueries};
}
function read(text=source,status='text_ready'){
 return jest.fn(async()=>({
   text,status,pageCount:1,incidents:[],
 }));
}
const input=token=>({
  previewToken:token,patientId,branchCode:'perez-las-condes',
  examCodes:['glicemia','hba1c'],documentReference:'SOL-DEMO-125',
  prescriberName:'Profesional Ficticio',
  requestDate:'2026-11-01',verified:true,
});
test('prelectura identifica paciente y sugiere prestaciones sin escribir',async()=>{
 const {db}=createDb();
 const intake=createSilMedicalRequestIntake(db,{read:read()});
 const preview=await intake.preview(actorId,'paciente.sil@example.invalid',
   'solicitud-demo.pdf',pdf);
 expect(preview.state).toBe('requires_operator_review');
 expect(preview.confirmed).toBe(false);
 expect(preview.extractionMethod).toBe('text_catalog_match');
 expect(preview.suggestedExams.map(x=>x.code)).toEqual(['glicemia','hba1c']);
 expect(preview.identity).toEqual({
   identifierMatches:true,givenNamesMatch:true,familyNamesMatch:true,
   birthDateMatches:true,
 });
 expect(preview.previewToken).toMatch(/^[a-f0-9-]{36}$/);
 expect(db.connect).not.toHaveBeenCalled();
});
test('no asocia documento con otro identificador ni emite comprobante',async()=>{
 const {db}=createDb();
 const intake=createSilMedicalRequestIntake(db,{
   read:read(source.replace('DEMO-0001','DEMO-0002')),
 });
 const preview=await intake.preview(actorId,'paciente.sil@example.invalid',
   'solicitud-demo.pdf',pdf);
 expect(preview.state).toBe('identity_mismatch');
 expect(preview.previewToken).toBeNull();
 expect(db.connect).not.toHaveBeenCalled();
});
test('detecta dos identificadores completos incompatibles, sin confundir referencias',async()=>{
 const {db}=createDb();
 const intake=createSilMedicalRequestIntake(db,{
   read:read(source+'\nSegundo paciente: DEMO-0002\n'),
 });
 const preview=await intake.preview(actorId,'paciente.sil@example.invalid',
   'solicitud-demo.pdf',pdf);
 expect(preview.state).toBe('identity_mismatch');
 expect(preview.identity.identifierMatches).toBe(false);
 expect(preview.previewToken).toBeNull();
 expect(db.connect).not.toHaveBeenCalled();
});
test('requiere coincidir nombres y fecha, no basta el correo o RUN ficticio',async()=>{
 const {db}=createDb();
 const intake=createSilMedicalRequestIntake(db,{
   read:read(source.replace('Paciente Prueba','Paciente Diferente')
      .replace('1990-01-01','1990-02-01')),
 });
 const preview=await intake.preview(actorId,'paciente.sil@example.invalid',
   'solicitud-demo.pdf',pdf);
 expect(preview.identity.givenNamesMatch).toBe(false);
 expect(preview.identity.birthDateMatches).toBe(false);
 expect(preview.previewToken).toBeNull();
});
test('rechaza PDF escaneado sin OCR sin crear orden',async()=>{
 const {db}=createDb();
 const intake=createSilMedicalRequestIntake(db,{read:read(null,'needs_ocr')});
 const preview=await intake.preview(actorId,'paciente.sil@example.invalid',
   'solicitud-demo.pdf',pdf);
 expect(preview.previewToken).toBeNull();
 expect(preview.warnings.join(' ')).toMatch(/OCR/);
});
test('confirmar crea orden, prestaciones, solicitud y auditoría atómicamente',async()=>{
 const {db,client,txQueries}=createDb();
 const intake=createSilMedicalRequestIntake(db,{read:read()});
 const preview=await intake.preview(actorId,'paciente.sil@example.invalid',
   'solicitud-demo.pdf',pdf);
 const result=await intake.confirm(actorId,input(preview.previewToken));
 expect(result.order.orderNumber).toBe('VH-000125');
 expect(result.order.examCodes).toEqual(['glicemia','hba1c']);
 expect(txQueries[0].sql).toBe('BEGIN');
 expect(txQueries.some(item=>item.sql.includes('INSERT INTO public.vitalia_sil_orders'))).toBe(true);
 expect(txQueries.some(item=>item.sql.includes('INSERT INTO public.vitalia_sil_medical_requests_demo'))).toBe(true);
 expect(txQueries.some(item=>item.sql.includes('medical_request_received'))).toBe(true);
 expect(txQueries.at(-1).sql).toBe('COMMIT');
 expect(client.release).toHaveBeenCalled();
 await expect(intake.confirm(actorId,input(preview.previewToken)))
   .rejects.toBeInstanceOf(SilConflictError);
});
test('comprobante no puede confirmarse desde otro operador',async()=>{
 const {db}=createDb();
 const intake=createSilMedicalRequestIntake(db,{read:read()});
 const preview=await intake.preview(actorId,'paciente.sil@example.invalid',
   'solicitud-demo.pdf',pdf);
 await expect(intake.confirm('33333333-3333-4333-8333-333333333333',
   input(preview.previewToken))).rejects.toBeInstanceOf(SilConflictError);
 expect(db.connect).not.toHaveBeenCalled();
});
test('documento duplicado produce rollback sin generar orden nueva',async()=>{
 const {db,client,txQueries}=createDb({duplicate:true});
 const intake=createSilMedicalRequestIntake(db,{read:read()});
 const preview=await intake.preview(actorId,'paciente.sil@example.invalid',
   'solicitud-demo.pdf',pdf);
 await expect(intake.confirm(actorId,input(preview.previewToken)))
   .rejects.toBeInstanceOf(SilConflictError);
 expect(txQueries.some(item=>item.sql.includes('INSERT INTO public.vitalia_sil_orders'))).toBe(false);
 expect(txQueries.at(-1).sql).toBe('ROLLBACK');
 expect(client.release).toHaveBeenCalled();
});
