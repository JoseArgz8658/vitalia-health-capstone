const request=require('supertest');
const {createApp}=require('../dist/app');
const {createSilMainService,SilMainAccessDenied,SilMainConflict,SilMainNotFound}
  =require('../dist/sil/main-service');

const token='b'.repeat(64);
const bearer={Authorization:'Bearer '+token};
const lab='11111111-1111-4111-8111-111111111111';
const patient='22222222-2222-4222-8222-222222222222';
const order='33333333-3333-4333-8333-333333333333';
const report='44444444-4444-4444-8444-444444444444';
const operator='55555555-5555-4555-8555-555555555555';

function demo(role='operador_laboratorio',authenticated=true){
  const service={
    laboratoriesFor:jest.fn().mockResolvedValue({laboratories:[]}),
    createLaboratory:jest.fn().mockResolvedValue({laboratory:{id:lab}}),
    listStaff:jest.fn().mockResolvedValue({staff:[]}),
    setReviewPermission:jest.fn().mockResolvedValue({membership:{canReviewReports:true}}),
    setStaffMembershipActive:jest.fn().mockResolvedValue({membership:{active:false,canReviewReports:false}}),
    reportForReview:jest.fn().mockResolvedValue({fileName:'revision.pdf',bytes:Buffer.from('%PDF-1.4')}),
    grantStaff:jest.fn().mockResolvedValue({membership:{labId:lab}}),
    associatePatient:jest.fn().mockResolvedValue({patientId:patient,linked:true}),
    issuePatientLinkCode:jest.fn().mockResolvedValue({
      code:'a'.repeat(43),expiresAt:'2026-11-22T18:00:00.000Z',
    }),
    redeemPatientLinkCode:jest.fn().mockResolvedValue({linked:true}),
    createOrder:jest.fn().mockResolvedValue({order:{id:order}}),
    listPatients:jest.fn().mockResolvedValue({patients:[],hasMore:false}),
    listOrders:jest.fn().mockResolvedValue({orders:[]}),
    cancelPendingMedicalRequest:jest.fn().mockResolvedValue({
      pending:{id:'66666666-6666-4666-8666-666666666666',status:'cancelled'},
    }),
    operatorSummary:jest.fn().mockResolvedValue({summary:{
      ordersTotal:104,registered:20,inReview:14,published:70,pendingRequests:8,
    }}),
    attachReport:jest.fn().mockResolvedValue({report:{id:report}}),
    publishReport:jest.fn().mockResolvedValue({publication:{orderId:order}}),
    patientProfile:jest.fn().mockResolvedValue({profile:{hasProfile:false}}),
    patientReports:jest.fn().mockResolvedValue({reports:[]}),
    downloadPatientReport:jest.fn().mockResolvedValue({
      fileName:'informe.pdf',bytes:Buffer.from('%PDF-1.4\narchivo')}),
    getPatientReportOverview:jest.fn().mockResolvedValue({reports:[],statistics:[]}),
    askPatientReport:jest.fn().mockResolvedValue({answer:'Ayuda general',source:'catalogo'}),
  };
  const auth={find:jest.fn().mockResolvedValue(authenticated
    ?{id:operator,role,email:'operador@example.invalid'}:null)};
  // createApp(auth,...register..sil(18 posiciones),silMain)
  const application=createApp(auth,...Array(18).fill(undefined),service);
  return {application,service};
}
let previous;
beforeEach(()=>{
  previous=process.env.VITALIA_SIL_MAIN_MODE;
  process.env.VITALIA_SIL_MAIN_MODE='YES';
});
afterEach(()=>{
  if(previous===undefined)delete process.env.VITALIA_SIL_MAIN_MODE;
  else process.env.VITALIA_SIL_MAIN_MODE=previous;
  jest.clearAllMocks();
});

test('sin habilitar MAIN_MODE la API no se monta',async()=>{
  delete process.env.VITALIA_SIL_MAIN_MODE;
  const {application}=demo();
  const r=await request(application).get('/api/sil/main/labs').set(bearer);
  expect(r.status).toBe(404);
});
test('ninguna ruta principal acepta acceso anónimo',async()=>{
  const {application}=demo('administrador',false);
  for(const url of ['/api/sil/main/labs','/api/sil/main/patient/reports']){
    expect((await request(application).get(url).set(bearer)).status).toBe(401);
  }
});
test('paciente no puede crear laboratorios ni órdenes ajenas',async()=>{
  const {application,service}=demo('paciente');
  expect((await request(application).post('/api/sil/main/labs')
    .set(bearer).send({displayName:'Laboratorio privado'})).status).toBe(403);
  expect((await request(application).post('/api/sil/main/labs/'+lab+'/orders')
    .set(bearer).send({patientId:patient,examCodes:['glicemia']})).status).toBe(403);
  expect(service.createOrder).not.toHaveBeenCalled();
});
test('solo administrador habilita un laboratorio o personal',async()=>{
  const {application,service}=demo('administrador');
  expect((await request(application).post('/api/sil/main/labs')
    .set(bearer).send({displayName:'Laboratorio privado'})).status).toBe(201);
  expect(service.createLaboratory).toHaveBeenCalledWith('Laboratorio privado',operator);
  expect((await request(application).post('/api/sil/main/labs/'+lab+'/staff')
    .set(bearer).send({accountId:patient})).status).toBe(201);
  expect(service.grantStaff).toHaveBeenCalledWith(lab,patient,operator);
  expect((await request(application).post('/api/sil/main/labs/'+lab+'/staff')
    .set(bearer).send({accountId:patient,kind:'validator'})).status).toBe(400);
});
test('solo el administrador puede consultar operadores de cada laboratorio',async()=>{
  const path='/api/sil/main/labs/'+lab+'/staff';
  const admin=demo('administrador');
  const operatorSession=demo('operador_laboratorio');
  const patientSession=demo('paciente');
  const anonymous=demo('administrador',false);
  const response=await request(admin.application).get(path).set(bearer);
  expect(response.status).toBe(200);
  expect(response.body).toEqual({staff:[]});
  expect(admin.service.listStaff).toHaveBeenCalledWith(lab);
  for(const other of [operatorSession,patientSession]){
    expect((await request(other.application).get(path).set(bearer)).status).toBe(403);
    expect(other.service.listStaff).not.toHaveBeenCalled();
  }
  expect((await request(anonymous.application).get(path).set(bearer)).status).toBe(401);
  expect(anonymous.service.listStaff).not.toHaveBeenCalled();
  expect((await request(admin.application).get('/api/sil/main/labs/no-es-uuid/staff').set(bearer)).status).toBe(404);
});

test('listado de operadores consulta solo el laboratorio y no retorna hashes',async()=>{
  const query=jest.fn().mockResolvedValue({rows:[{
    accountId:operator,email:'test@example.invalid',active:true,canReviewReports:false,
  }]});
  const service=createSilMainService({query});
  const result=await service.listStaff(lab);
  expect(result.staff).toHaveLength(1);
  const [sql,values]=query.mock.calls[0];
  expect(sql).toContain('s.lab_id=$1');
  expect(sql).toContain("s.kind='operator'");
  expect(sql).not.toContain('password_hash');
  expect(values).toEqual([lab]);
});

test('resumen del laboratorio solo permite operador autenticado',async()=>{
  const path='/api/sil/main/labs/'+lab+'/summary';
  const valid=demo();
  const result=await request(valid.application).get(path).set(bearer);
  expect(result.status).toBe(200);
  expect(result.body).toEqual({summary:{
    ordersTotal:104,registered:20,inReview:14,published:70,pendingRequests:8,
  }});
  expect(valid.service.operatorSummary).toHaveBeenCalledWith(lab,operator);
  for(const role of ['paciente','administrador','profesional']){
    const denied=demo(role);
    expect((await request(denied.application).get(path).set(bearer)).status).toBe(403);
    expect(denied.service.operatorSummary).not.toHaveBeenCalled();
  }
  const anonymous=demo('operador_laboratorio',false);
  expect((await request(anonymous.application).get(path).set(bearer)).status).toBe(401);
  expect(anonymous.service.operatorSummary).not.toHaveBeenCalled();
  expect((await request(valid.application)
    .get('/api/sil/main/labs/no-uuid/summary').set(bearer)).status).toBe(404);
  valid.service.operatorSummary.mockRejectedValueOnce(new SilMainAccessDenied());
  expect((await request(valid.application).get(path).set(bearer)).status).toBe(403);
});

test('resumen obtiene conteos totales sin pacientes ni documentos y exige membresía',async()=>{
  const query=jest.fn()
    .mockResolvedValueOnce({rows:[{allowed:1}]})
    .mockResolvedValueOnce({rows:[{
      ordersTotal:'104',registered:'20',inReview:'14',
      published:'70',pendingRequests:'8',
    }]});
  const service=createSilMainService({query});
  const result=await service.operatorSummary(lab,operator);
  expect(result).toEqual({summary:{
    ordersTotal:104,registered:20,inReview:14,published:70,pendingRequests:8,
  }});
  expect(query).toHaveBeenCalledTimes(2);
  const [accessSql,accessParams]=query.mock.calls[0];
  expect(accessSql).toContain('s.lab_id=$1');
  expect(accessSql).toContain('s.account_id=$2');
  expect(accessParams).toEqual([lab,operator,false]);
  const [sql,params]=query.mock.calls[1];
  expect(sql).toContain('l.id=$1 AND l.active');
  expect(sql).toContain('o.lab_id=l.id');
  expect(sql).toContain("p.status='pending'");
  expect(sql).not.toMatch(/email|password_hash|pdf_data/);
  expect(params).toEqual([lab]);

  const deniedQuery=jest.fn().mockResolvedValue({rows:[]});
  const deniedService=createSilMainService({query:deniedQuery});
  await expect(deniedService.operatorSummary(lab,operator))
    .rejects.toBeInstanceOf(SilMainAccessDenied);
  expect(deniedQuery).toHaveBeenCalledTimes(1);
});

test('conteos nulos o fuera de rango nunca se publican como cero',async()=>{
  for(const invalid of [null,'','9007199254740992']){
    const query=jest.fn()
      .mockResolvedValueOnce({rows:[{allowed:1}]})
      .mockResolvedValueOnce({rows:[{
        ordersTotal:invalid,registered:'0',inReview:'0',
        published:'0',pendingRequests:'0',
      }]});
    const service=createSilMainService({query});
    await expect(service.operatorSummary(lab,operator))
      .rejects.toThrow();
  }
});

test('orden principal exige paciente y prestaciones válidas',async()=>{
  const {application,service}=demo();
  expect((await request(application).post('/api/sil/main/labs/'+lab+'/orders')
    .set(bearer).send({patientId:patient,examCodes:['glicemia']})).status).toBe(201);
  expect(service.createOrder).toHaveBeenCalledWith(lab,patient,['glicemia'],operator);
  for(const body of [
    {patientId:patient,examCodes:['glicemia','glicemia']},
    {patientId:patient,examCodes:['glicemia'],labId:lab},
    {patientId:'x',examCodes:['glicemia']},
  ])expect((await request(application).post('/api/sil/main/labs/'+lab+'/orders')
    .set(bearer).send(body)).status).toBe(400);
});
test('solo administración puede conceder o retirar el permiso por laboratorio',async()=>{
  const path='/api/sil/main/labs/'+lab+'/staff/review-permission';
  const admin=demo('administrador');
  const staff=demo();
  for(const enabled of [true,false]){
    const body={accountId:patient,enabled};
    expect((await request(admin.application).post(path).set(bearer).send(body)).status).toBe(200);
    expect(admin.service.setReviewPermission).toHaveBeenLastCalledWith(lab,patient,operator,enabled);
    expect((await request(staff.application).post(path).set(bearer).send(body)).status).toBe(403);
  }
  expect(staff.service.setReviewPermission).not.toHaveBeenCalled();
});

test('revisión y publicación requieren sesión de operador y permiso del servicio',async()=>{
  const prefix='/api/sil/main/labs/'+lab+'/orders/'+order+'/report';
  const body={operatorReviewConfirmed:true};
  for(const role of ['profesional','administrador','paciente']){
    const other=demo(role);
    expect((await request(other.application).get(prefix+'/file').set(bearer)).status).toBe(403);
    expect((await request(other.application).post(prefix+'/publish').set(bearer).send(body)).status).toBe(403);
    expect(other.service.publishReport).not.toHaveBeenCalled();
  }
  const {application,service}=demo();
  expect((await request(application).get(prefix+'/file').set(bearer)).status).toBe(200);
  expect(service.reportForReview).toHaveBeenCalledWith(lab,order,operator);
  expect((await request(application).post(prefix+'/publish').set(bearer)
    .send({operatorReviewConfirmed:false})).status).toBe(400);
  expect((await request(application).post(prefix+'/publish').set(bearer).send(body)).status).toBe(201);
  expect(service.publishReport).toHaveBeenCalledWith(lab,order,operator);
  service.publishReport.mockRejectedValueOnce(new SilMainAccessDenied());
  expect((await request(application).post(prefix+'/publish').set(bearer).send(body)).status).toBe(403);
});
test('informes del paciente pertenecen a su cuenta y no aceptan id externo',async()=>{
  const {application,service}=demo('paciente');
  expect((await request(application).get('/api/sil/main/patient/reports')
    .set(bearer)).status).toBe(200);
  expect(service.patientReports).toHaveBeenCalledWith(operator);
  expect((await request(application).get('/api/sil/main/patient/reports/'+report+'/file')
    .set(bearer)).status).toBe(200);
  expect(service.downloadPatientReport).toHaveBeenCalledWith(operator,report);
  expect((await request(application).get('/api/sil/main/patient/reports/not-a-uuid/file')
    .set(bearer)).status).toBe(404);
});
test('comparación y chat exigen un paciente autenticado',async()=>{
  const patientApp=demo('paciente');
  expect((await request(patientApp.application).post('/api/sil/main/patient/reports/overview')
    .set(bearer).send({reportIds:[report]})).status).toBe(200);
  expect((await request(patientApp.application).post('/api/sil/main/patient/reports/'+report+'/chat')
    .set(bearer).send({question:'¿Qué mide el examen?'})).status).toBe(200);
  expect((await request(demo('operador_laboratorio').application)
    .post('/api/sil/main/patient/reports/overview')
    .set(bearer).send({reportIds:[report]})).status).toBe(403);
});
test('consulta de informes principales está filtrada por paciente y laboratorio activo',async()=>{
  const query=jest.fn().mockResolvedValue({rows:[]});
  const main=createSilMainService({query});
  await main.patientReports(patient);
  const [sql,values]=query.mock.calls[0];
  expect(sql).toMatch(/p\.active/);
  expect(sql).toMatch(/l\.active/);
  expect(sql).toMatch(/r\.patient_id=\$1/);
  expect(sql).toMatch(/report_published/);
  expect(values).toEqual([patient,null,null,null,0]);
});

test('la búsqueda de informes pagina dentro de la sesión paciente',async()=>{
  const path='/api/sil/main/patient/reports';
  const {application,service}=demo('paciente');
  await request(application).get(path+'?offset=50&search=VH-000005')
    .set(bearer).expect(200);
  expect(service.patientReports).toHaveBeenCalledWith(operator,
    {offset:50,search:'VH-000005'});
  await request(application).get(path+'?patientId='+patient).set(bearer).expect(400);
  await request(demo('administrador').application).get(path+'?offset=50')
    .set(bearer).expect(403);
});

test('el directorio solo admite operadores y valida los parámetros de búsqueda',async()=>{
  const path='/api/sil/main/labs/'+lab+'/patients';
  const {application,service}=demo();
  await request(application).get(path+'?limit=10&offset=20&search=ana').set(bearer).expect(200);
  expect(service.listPatients).toHaveBeenCalledWith(lab,operator,{limit:10,offset:20,search:'ana'});
  await request(application).get(path+'?limit=51').set(bearer).expect(400);
  await request(demo('paciente').application).get(path).set(bearer).expect(403);
  await request(demo('administrador').application).get(path).set(bearer).expect(403);
});

const pendingId='66666666-6666-4666-8666-666666666666';
const closurePath='/api/sil/main/labs/'+lab+
  '/medical-requests/pending/'+pendingId+'/cancel';

test('solo operador cierra una derivación con motivo controlado',async()=>{
  const valid=demo();
  const body={reason:'unreadable_document'};
  await request(valid.application).post(closurePath).set(bearer)
    .send(body).expect(200);
  expect(valid.service.cancelPendingMedicalRequest)
    .toHaveBeenCalledWith(lab,pendingId,operator,body.reason);
  for(const role of ['paciente','administrador','profesional']){
    const denied=demo(role);
    await request(denied.application).post(closurePath).set(bearer)
      .send(body).expect(403);
    expect(denied.service.cancelPendingMedicalRequest).not.toHaveBeenCalled();
  }
  await request(demo('operador_laboratorio',false).application)
    .post(closurePath).set(bearer).send(body).expect(401);
  await request(valid.application).post(closurePath.replace(pendingId,'bad-id'))
    .set(bearer).send(body).expect(404);
  for(const bad of [{reason:'secretos'}, {reason:'unreadable_document',note:'dato privado'},
    {reason:''}, {}]){
    await request(valid.application).post(closurePath).set(bearer)
      .send(bad).expect(400);
  }
  expect(valid.service.cancelPendingMedicalRequest).toHaveBeenCalledTimes(1);
});

test('cierre de derivación es transaccional y registra solo motivo codificado',async()=>{
  let status='pending';
  const pendingAudit=[];
  const tx={
    query:jest.fn(async(sql,params=[])=>{
      if(sql==='BEGIN'||sql==='COMMIT'||sql==='ROLLBACK')return {rows:[]};
      if(sql.includes('FROM public.vitalia_sil_main_staff'))return {rows:[{allowed:1}]};
      if(sql.includes('SELECT status FROM public.vitalia_sil_main_pending_requests')){
        if(params[1]!==lab)return {rows:[]};
        return {rows:[{status}]};
      }
      if(sql.includes('UPDATE public.vitalia_sil_main_pending_requests')){
        expect(params).toEqual([pendingId,lab,operator,'request_withdrawn']);
        expect(status).toBe('pending');
        status='cancelled';
        return {rowCount:1,rows:[{id:pendingId}]};
      }
      if(sql.includes('INSERT INTO public.vitalia_sil_main_audit')){
        pendingAudit.push(params);
        return {rowCount:1,rows:[]};
      }
      throw Error('SQL inesperado en cierre: '+sql);
    }),
    release:jest.fn(),
  };
  const db={connect:jest.fn().mockResolvedValue(tx),query:jest.fn()};
  const service=createSilMainService(db);
  const response=await service.cancelPendingMedicalRequest(
    lab,pendingId,operator,'request_withdrawn');
  expect(response.pending).toEqual({
    id:pendingId,status:'cancelled',reason:'request_withdrawn',
  });
  expect(status).toBe('cancelled');
  expect(tx.query.mock.calls.some(([sql])=>sql==='COMMIT')).toBe(true);
  expect(pendingAudit).toHaveLength(1);
  expect(pendingAudit[0][4]).toBe('pending_request_cancelled');
  expect(JSON.parse(pendingAudit[0][5])).toEqual({
    pendingId,reason:'request_withdrawn',
  });
  await expect(service.cancelPendingMedicalRequest(
    lab,pendingId,operator,'request_withdrawn')).rejects.toBeInstanceOf(SilMainConflict);
  expect(pendingAudit).toHaveLength(1);
  await expect(service.cancelPendingMedicalRequest(
    '77777777-7777-4777-8777-777777777777',pendingId,
    operator,'other')).rejects.toBeInstanceOf(SilMainNotFound);
});

test('administrador suspende membresía por laboratorio y los otros roles no',async()=>{
  const path='/api/sil/main/labs/'+lab+'/staff/membership';
  const admin=demo('administrador');
  await request(admin.application).post(path).set(bearer)
    .send({accountId:operator,active:false}).expect(200);
  expect(admin.service.setStaffMembershipActive)
    .toHaveBeenCalledWith(lab,operator,operator,false);
  for(const role of ['operador_laboratorio','paciente','profesional']){
    const denied=demo(role);
    await request(denied.application).post(path).set(bearer)
      .send({accountId:operator,active:false}).expect(403);
    expect(denied.service.setStaffMembershipActive).not.toHaveBeenCalled();
  }
  for(const invalid of [
    {accountId:'bad',active:false},
    {accountId:operator,active:'false'},
    {accountId:operator,active:false,token:'secret'},
  ]){
    await request(admin.application).post(path).set(bearer)
      .send(invalid).expect(400);
  }
  expect(admin.service.setStaffMembershipActive).toHaveBeenCalledTimes(1);
});

test('suspender operador anula permiso de revisión y audita la membresía',async()=>{
  const auditParams=[];
  let active=true;
  let review=true;
  const tx={
    query:jest.fn(async(sql,params=[])=>{
      if(['BEGIN','COMMIT','ROLLBACK'].includes(sql))return {rows:[]};
      if(sql.includes('FROM public.vitalia_sil_main_laboratories'))
        return {rows:[{exists:1}]};
      if(sql.includes('FROM public.vitalia_sil_main_staff s'))
        return {rows:[{active,roleActive:true}]};
      if(sql.includes('UPDATE public.vitalia_sil_main_staff')){
        expect(params).toEqual([lab,operator,false]);
        active=false;review=false;
        return {rows:[{active,canReviewReports:review}]};
      }
      if(sql.includes('INSERT INTO public.vitalia_sil_main_audit')){
        auditParams.push(params);
        return {rows:[]};
      }
      throw Error('SQL no esperado: '+sql);
    }),
    release:jest.fn(),
  };
  const service=createSilMainService({
    connect:jest.fn().mockResolvedValue(tx),query:jest.fn(),
  });
  const result=await service.setStaffMembershipActive(lab,operator,operator,false);
  expect(result.membership).toEqual({
    labId:lab,accountId:operator,active:false,canReviewReports:false,
  });
  expect(auditParams).toHaveLength(1);
  expect(auditParams[0][4]).toBe('operator_membership_disabled');
  expect(JSON.parse(auditParams[0][5])).toEqual({accountId:operator});
  expect(tx.query.mock.calls.some(([sql])=>sql==='COMMIT')).toBe(true);
  await expect(service.setStaffMembershipActive(lab,operator,operator,false))
    .rejects.toBeInstanceOf(SilMainConflict);
  expect(auditParams).toHaveLength(1);
});

test('Camino B exige rol, no almacena códigos en caché y valida el canje',async()=>{
  const patientApp=demo('paciente');
  const issued=await request(patientApp.application)
    .post('/api/sil/main/patient/link-code').set(bearer)
    .send({}).expect(201);
  expect(issued.headers['cache-control']).toBe('private, no-store');
  expect(issued.body.code).toHaveLength(43);
  expect(patientApp.service.issuePatientLinkCode).toHaveBeenCalledWith(operator);
  await request(patientApp.application).post('/api/sil/main/patient/link-code')
    .set(bearer).send({patientId:patient}).expect(400);
  const operatorApp=demo('operador_laboratorio');
  await request(operatorApp.application).post('/api/sil/main/patient/link-code')
    .set(bearer).send({}).expect(403);
  expect(operatorApp.service.issuePatientLinkCode).not.toHaveBeenCalled();

  const path='/api/sil/main/labs/'+lab+'/patient-link-code';
  const claim={code:'a'.repeat(43),
    identityReference:'CHECK-20261122',identityConfirmed:true};
  const redeemed=await request(operatorApp.application).post(path)
    .set(bearer).send(claim).expect(200);
  expect(redeemed.headers['cache-control']).toBe('private, no-store');
  expect(redeemed.body).toEqual({linked:true});
  expect(operatorApp.service.redeemPatientLinkCode).toHaveBeenCalledWith(
    lab,operator,claim.code,claim.identityReference);
  await request(patientApp.application).post(path).set(bearer)
    .send(claim).expect(403);
  await request(operatorApp.application).post(path).set(bearer)
    .send({...claim,identityConfirmed:false}).expect(400);
  await request(operatorApp.application).post(path).set(bearer)
    .send({...claim,patientId:patient}).expect(400);
  expect(operatorApp.service.redeemPatientLinkCode).toHaveBeenCalledTimes(1);
});

test('la verificación de dirección se restringe a administradores y al territorio seleccionado',async()=>{
  const path='/api/sil/main/labs/'+lab+'/sites/verify-address';
  const body={address:'Calle Ficticia 123',commune:'Conchalí',region:'Metropolitana de Santiago'};
  const admin=demo('administrador');
  const operatorSession=demo();
  expect((await request(operatorSession.application).post(path).set(bearer).send(body)).status).toBe(403);
  expect((await request(admin.application).post(path).set(bearer)
    .send({...body,region:'Ñuble'})).status).toBe(400);
});
