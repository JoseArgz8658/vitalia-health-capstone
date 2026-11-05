const request=require('supertest'),express=require('express');
const {createCareInboxService,CareInboxError}=require('../dist/care/inbox');
const {createCareInboxRouter}=require('../dist/care/inbox-router');
const {verifyCareInbox}=require('../dist/database/care-inbox-verification');
const id='11111111-1111-4111-8111-111111111111',a={id,role:'profesional'},token='a'.repeat(64);
test.each(['paciente','administrador'])('%s no consulta ni inicia',async role=>{
 const transaction=jest.fn(),s=createCareInboxService({transaction},{}),other={...a,role};
 await expect(s.list(other,{})).rejects.toMatchObject({status:403});await expect(s.details(other,id)).rejects.toMatchObject({status:403});
 await expect(s.begin(other,id,{expectedRevision:0})).rejects.toMatchObject({status:403});expect(transaction).not.toHaveBeenCalled();
});
test.each([{patientId:id},{offset:'-1'},{offset:''},{offset:['0']},{offset:'1.2'},{offset:'100001'}])('filtros inválidos %j',async input=>{
 const transaction=jest.fn();await expect(createCareInboxService({transaction},{}).list(a,input)).rejects.toMatchObject({status:400});expect(transaction).not.toHaveBeenCalled();
});
test.each([{expectedRevision:-1},{expectedRevision:0,actorId:id},{expectedRevision:'0'},{},null])('inicio inválido %j',async body=>{
 const transaction=jest.fn();await expect(createCareInboxService({transaction},{}).begin(a,id,body)).rejects.toMatchObject({status:400});expect(transaction).not.toHaveBeenCalled();
});
test('UUID inválido no consulta ni lee S3',async()=>{
 const transaction=jest.fn(),read=jest.fn(),s=createCareInboxService({transaction},{read});
 await expect(s.details(a,'x')).rejects.toMatchObject({status:404});await expect(s.download(a,'x')).rejects.toMatchObject({status:404});expect(transaction).not.toHaveBeenCalled();expect(read).not.toHaveBeenCalled();
});
test('atención ajena no lee S3 ni registra acceso al examen',async()=>{
 const query=jest.fn(async()=>({rows:[]})),read=jest.fn();
 await expect(createCareInboxService({transaction:fn=>fn({query})},{read}).download(a,id)).rejects.toMatchObject({status:404});
 expect(read).not.toHaveBeenCalled();expect(query).toHaveBeenCalledTimes(1);expect(query.mock.calls[0][1]).toEqual([id,id]);
});
test.each(['42P01','42703','42501'])('falta de esquema/permiso %s',async code=>{
 await expect(createCareInboxService({transaction:async()=>{throw {code};}},{}).list(a,{})).rejects.toMatchObject({status:503});
});
test('lista paginada registra auditoría y no filtra contacto',async()=>{
 const row={id,status:'requested',revision:0,document_id:id,clinic_name:'Clínica',branch_name:'Sede',specialty_name:'General',patient_name:'Paciente',exam_name:'Examen',phone:'secreto'},query=jest.fn(async sql=>sql.startsWith('SELECT')?{rows:Array(21).fill(row)}:{rows:[]});
 const result=await createCareInboxService({transaction:fn=>fn({query})},{}).list(a,{offset:'20'});
 expect(result.items).toHaveLength(20);expect(result.nextOffset).toBe(40);expect(JSON.stringify(result)).not.toContain('secreto');expect(query.mock.calls.at(-1)[1]).toEqual([null,id,'list']);
});
function fixture(user=a){const service={list:jest.fn(async()=>({items:[]})),details:jest.fn(async()=>({})),begin:jest.fn(async()=>({started:true})),download:jest.fn(async()=>({item:{contentType:'application/pdf',originalName:'synthetic.pdf'},body:Buffer.from('%PDF-1.4')}))};
 const app=express();app.use(express.json());app.use('/api/care-inbox',createCareInboxRouter({find:async()=>user},service));return {app,service};}
test.each([null,{...a,role:'paciente'},{...a,role:'administrador'}])('API exige sesión y rol %j',async user=>{
 const f=fixture(user);expect((await request(f.app).get('/api/care-inbox').set('Authorization','Bearer '+token)).status).toBe(user?403:401);expect(f.service.list).not.toHaveBeenCalled();
});
test('API no acepta paciente ni identidad por query en detalle/inicio',async()=>{
 const f=fixture();for(const endpoint of [`/${id}`,`/${id}/file`])expect((await request(f.app).get('/api/care-inbox'+endpoint+'?patientId='+id).set('Authorization','Bearer '+token)).status).toBe(400);
 expect((await request(f.app).post(`/api/care-inbox/${id}/begin?role=profesional`).set('Authorization','Bearer '+token).send({expectedRevision:0})).status).toBe(400);expect(f.service.begin).not.toHaveBeenCalled();expect(f.service.download).not.toHaveBeenCalled();
});
test('API inicio recibe cuenta autenticada y cuerpo, no usa otra identidad',async()=>{
 const f=fixture(),r=await request(f.app).post(`/api/care-inbox/${id}/begin`).set('Authorization','Bearer '+token).send({expectedRevision:0});expect(r.status).toBe(200);expect(r.headers['cache-control']).toBe('no-store');expect(f.service.begin).toHaveBeenCalledWith(a,id,{expectedRevision:0});
});
test('descarga adjunta no incrusta archivo y no cachea',async()=>{
 const f=fixture(),r=await request(f.app).get(`/api/care-inbox/${id}/file`).set('Authorization','Bearer '+token);expect(r.status).toBe(200);expect(r.headers['content-disposition']).toMatch(/^attachment;/);expect(r.headers['x-content-type-options']).toBe('nosniff');expect(r.headers['cache-control']).toBe('no-store');
});
test('verificador exige 022 y revierte sin insertar',async()=>{
 const query=jest.fn(async()=>({rows:[]}));await expect(verifyCareInbox({query})).rejects.toThrow('Falta migración 022.');expect(query.mock.calls.at(-1)[0]).toBe('ROLLBACK');expect(query.mock.calls.some(([s])=>s.startsWith('INSERT'))).toBe(false);
});
test('verificador sin conexión no revierte transacción inexistente',async()=>{
 const query=jest.fn().mockRejectedValue(new Error('Sin conexión'));await expect(verifyCareInbox({query})).rejects.toThrow('Sin conexión');expect(query).toHaveBeenCalledTimes(1);
});
test.each(['migrate-care-inbox','verify-care-inbox'])('CLI %s no expone secretos',file=>{
 const {spawnSync}=require('node:child_process'),r=spawnSync(process.execPath,[`dist/database/${file}.js`],{cwd:process.cwd(),encoding:'utf8',env:{...process.env,PGPORT:'inválido',PGPASSWORD:'no-exponer-esta-clave'}});expect(r.status).toBe(1);expect(r.stderr).not.toContain('no-exponer-esta-clave');
});
