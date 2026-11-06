const {measurementInput,createMeasurementService}=require('../dist/profiles/measurements');
const patient={id:'11111111-1111-4111-8111-111111111111',role:'paciente'};
const input={requestId:'22222222-2222-4222-8222-222222222222',measuredAt:'2020-01-01T12:00:00.000Z',weightKg:70.5,heightCm:null};
test.each([
 {weightKg:null,heightCm:null},{weightKg:0},{weightKg:-1},{weightKg:Infinity},{weightKg:NaN},
 {weightKg:'70'},{heightCm:0},{heightCm:-1},{heightCm:NaN},{heightCm:Infinity},
 {measuredAt:'2999-01-01T00:00:00Z'},{measuredAt:'2025-02-29T00:00:00Z'},
 {requestId:'bad'},{recordedBy:'other'},{source:'professional_recorded'},{patientId:'other'},
])('rechaza medida inválida o identidad del cliente %j',value=>expect(measurementInput.safeParse({...input,...value}).success).toBe(false));
test.each([{...input},{...input,weightKg:null,heightCm:170.2}])('permite registrar solo una medida',value=>expect(measurementInput.safeParse(value).success).toBe(true));
test.each(['administrador','profesional'])('rol %s no registra medidas de paciente',async role=>{
 const db={transaction:jest.fn()};const s=createMeasurementService(db);
 await expect(s.measurements({...patient,role})).rejects.toMatchObject({status:403});
 await expect(s.recordMeasurement({...patient,role},input)).rejects.toMatchObject({status:403});expect(db.transaction).not.toHaveBeenCalled();
});
test('cuenta sin perfil recibe historial vacío y no consulta medidas',async()=>{
 const query=jest.fn(async sql=>{expect(sql).toContain('p.account_id=$1');return {rows:[]};});
 const s=createMeasurementService({transaction:fn=>fn({query})});
 expect(await s.measurements(patient)).toEqual({measurements:[],profileRequired:true});expect(query).toHaveBeenCalledTimes(1);
});
test('registro sin perfil no crea filas ni perfiles implícitos',async()=>{
 const query=jest.fn(async()=>({rows:[]}));const s=createMeasurementService({transaction:fn=>fn({query})});
 await expect(s.recordMeasurement(patient,input)).rejects.toMatchObject({status:409,code:'PROFILE_REQUIRED'});
 expect(query.mock.calls.some(([sql])=>sql.startsWith('INSERT'))).toBe(false);
});
test('consulta filtra por persona de sesión y limita historial',async()=>{
 const query=jest.fn(async(sql,args)=>{
  if(sql.includes('p.account_id')){expect(args).toEqual([patient.id]);return {rows:[{id:'person'}]};}
  expect(sql).toContain('WHERE patient_person_id=$1');expect(sql).toContain('LIMIT 20');expect(args).toEqual(['person']);return {rows:[]};
 });
 expect((await createMeasurementService({transaction:fn=>fn({query})}).measurements(patient)).measurements).toEqual([]);
});
test('inserta con autor de sesión y fuente fija; repetición devuelve misma fila',async()=>{
 const row={id:input.requestId,measured_at:new Date(input.measuredAt),weight_kg:'70.5',height_cm:null,source:'patient_reported',recorded_by:patient.id};
 const query=jest.fn(async(sql,args)=>{
  if(sql.includes('p.account_id'))return {rows:[{id:'person'}]};
  if(sql.startsWith('INSERT')){expect(sql).toContain("'patient_reported'");expect(sql).toContain('ON CONFLICT(id) DO NOTHING');expect(args.at(-1)).toBe(patient.id);return {rows:[]};}
  if(sql.includes('WHERE id=$1 AND'))return {rows:[row]};return {rows:[]};
 });
 const s=createMeasurementService({transaction:fn=>fn({query})});
 expect((await s.recordMeasurement(patient,input)).measurement.weightKg).toBe(70.5);
 expect((await s.recordMeasurement(patient,input)).measurement.id).toBe(input.requestId);
});
test('reutilizar identificador con otro contenido produce conflicto',async()=>{
 const query=jest.fn(async sql=>sql.includes('p.account_id')?{rows:[{id:'person'}]}:sql.includes('WHERE id=$1 AND')?
  {rows:[{id:input.requestId,measured_at:input.measuredAt,weight_kg:'99',height_cm:null,source:'patient_reported',recorded_by:patient.id}]}:{rows:[]});
 await expect(createMeasurementService({transaction:fn=>fn({query})}).recordMeasurement(patient,input)).rejects.toMatchObject({status:409});
});
test('fallo de permisos se traduce sin reflejar datos internos',async()=>{
 const s=createMeasurementService({transaction:async()=>{throw {code:'42501',detail:'sensitive'};}});
 await expect(s.measurements(patient)).rejects.toMatchObject({status:503,code:'PROFILE_UNAVAILABLE'});
});
