'use strict';
const {
  createSilPatientEducation,SilEducationNotFound,SilEducationBusy,
  SilEducationUnavailable,
}=require('../dist/sil/patient-education');
const {AssistantModelError}=require('../dist/exam-assistant/local-model');

const patient='11111111-1111-4111-8111-111111111111';
const report='22222222-2222-4222-8222-222222222222';
const exams=[
  {code:'glicemia',name:'Glicemia'},
  {code:'hba1c',name:'Hemoglobina glicosilada (HbA1c)'},
];
const reportRows = (available=true)=>({
  query:jest.fn(async (_sql,args)=>{
    expect(args).toEqual([report,patient]);
    return {rows:available?exams:[]};
  }),
});
const mockModel=()=>jest.fn(async ({extraction,question,mode})=>{
  expect(extraction.resultados).toEqual([
    {nombre:'Glicemia',valor:null,unidad:null,rango_referencia:null},
    {nombre:'Hemoglobina glicosilada (HbA1c)',valor:null,unidad:null,rango_referencia:null},
  ]);
  expect(mode).toBe('chat');
  expect(question).toBe('¿Qué es la glicemia?');
  return {reply:{kind:'education',answer:'La glicemia mide glucosa en sangre.',
    indices:[0],definitions:[]},model:'knowledge-fast-path',promptVersion:2,elapsedMs:0};
});

describe('IA educativa del SIL: separación de documentos y prestaciones',()=>{
  test('no revela informes no autorizados o sin publicar',async()=>{
    const db=reportRows(false),model=mockModel();
    const service=createSilPatientEducation(db,model);
    await expect(service.ask(patient,report,'¿Qué es la glicemia?'))
      .rejects.toBeInstanceOf(SilEducationNotFound);
    expect(model).not.toHaveBeenCalled();
  });
  test('pregunta conceptual usa solo las prestaciones, sin cifras',async()=>{
    const db=reportRows(),model=mockModel();
    const service=createSilPatientEducation(db,model);
    const answer=await service.ask(patient,report,'¿Qué es la glicemia?');
    expect(answer.answer).toContain('glucosa');
    expect(answer.approved).toBe(false);
    expect(answer.source).toBe('catalogo');
    expect(db.query).toHaveBeenCalledTimes(1);
  });
  test('preguntas sobre cifras no inventan valores ni llaman modelo',async()=>{
    const model=mockModel();
    const service=createSilPatientEducation(reportRows(),model);
    const answer=await service.ask(patient,report,'¿Cuánto me salió la glicemia?');
    expect(answer.answer).toContain('PDF');
    expect(model).not.toHaveBeenCalled();
  });
  test('informa las prestaciones registradas, no presume lectura del PDF',async()=>{
    const model=mockModel();
    const service=createSilPatientEducation(reportRows(),model);
    const answer=await service.ask(patient,report,'¿Qué exámenes tengo?');
    expect(answer.answer).toContain('Glicemia');
    expect(answer.answer).toContain('Hemoglobina glicosilada');
    expect(answer.answer).toContain('orden');
    expect(model).not.toHaveBeenCalled();
  });
  test('fallo local de IA se declara, sin respuestas clínicas inventadas',async()=>{
    const model=jest.fn(async()=>{throw new AssistantModelError('transport');});
    const service=createSilPatientEducation(reportRows(),model);
    await expect(service.ask(patient,report,'¿Qué es la glicemia?'))
      .rejects.toBeInstanceOf(SilEducationUnavailable);
  });
});
