'use strict';
const {createHash}=require('node:crypto');
const {createSilPatientReportOverview}=require('../dist/sil/patient-report-overview');
const {SilEducationNotFound}=require('../dist/sil/patient-education');

const sha=pdf=>createHash('sha256').update(pdf).digest('hex');
const patient='00000000-0000-4000-8000-000000000001';
const ids=[1,2,3,4].map(i=>'10000000-0000-4000-8000-00000000000'+i);
function report(index,text,unit='mg/dL'){
  const pdf=Buffer.from(text);
  const requestPdf=Buffer.from('Paciente ficticio\nObservación de la solicitud: Control de seguimiento.');
  return {
    id:ids[index],orderNumber:'VH-00000'+(index+1),laboratory:'Laboratorio DEMO',
    authorizedAt:new Date(Date.UTC(2026,0,index+1)),pdf,sha:sha(pdf),
    requestPdf,requestSha:sha(requestPdf),reference:'SOL-DEMO',
    analytes:[{examCode:'glicemia',analyte:'Glucosa',unit}],
  };
}
const read=jest.fn(async pdf=>({status:'text_ready',text:pdf.toString()}));

test('lee el PDF autorizado y calcula estadística solo para cifras comparables',async()=>{
  const rows=[
    report(0,'Glucosa: 95,5 mg/dL | 80 - 110'),
    report(1,'Glucemia | 110.5 | mg/dL'),
    report(2,'Glucosa 7 mmol/L','mmol/L'),
    report(3,'Glucosa 99 mg/dL\nGlucosa 113 mg/dL'),
  ];
  const db={query:jest.fn(async()=>({rows}))};
  const overview=await createSilPatientReportOverview(db,read)(patient,ids);
  expect(db.query).toHaveBeenCalledWith(
    expect.stringMatching(/r.patient_id=\$1.*published_at IS NOT NULL/s),[patient,ids]);
  expect(overview.reports[0]).toMatchObject({
    measurements:[{value:95.5,unit:'mg/dL'}],observation:'Control de seguimiento.',reference:'SOL-DEMO',
  });
  expect(overview.reports[2].measurements[0].value).toBe(7);
  expect(overview.reports[3].measurements).toEqual([]);
  expect(overview.statistics).toMatchObject([
    {analyte:'Glucosa',count:2,minimum:95.5,maximum:110.5,mean:103},
  ]);
  expect(JSON.stringify(overview)).not.toContain('Paciente ficticio');
});

test('rechaza un lote incompleto o ajeno antes de entregar o leer datos',async()=>{
  const parser=jest.fn();
  const db={query:jest.fn(async()=>({rows:[report(0,'Glucosa 80 mg/dL')]}))};
  await expect(createSilPatientReportOverview(db,parser)(patient,ids))
    .rejects.toBeInstanceOf(SilEducationNotFound);
  expect(parser).not.toHaveBeenCalled();
});

test('omite un archivo alterado o sin texto y no cuenta dos veces el mismo PDF',async()=>{
  const rows=[
    report(0,'Glucosa 95 mg/dL'),
    report(1,'Glucosa 95 mg/dL'),
    {...report(2,'Glucosa 112 mg/dL'),sha:'wrong'},
    report(3,'imagen sin capa de texto'),
  ];
  const parser=jest.fn(async pdf=>pdf.toString().startsWith('imagen')
    ? {status:'needs_ocr',text:null}
    : {status:'text_ready',text:pdf.toString()});
  const overview=await createSilPatientReportOverview({query:async()=>({rows})},parser)(patient,ids);
  expect(overview.reports.map(row=>row.measurements.length)).toEqual([1,1,0,0]);
  expect(overview.statistics).toEqual([]);
  expect(parser).not.toHaveBeenCalledWith(rows[2].pdf);
});

test('procesa un PDF con texto usando el lector real',async()=>{
  const line='BT /F1 12 Tf 72 700 Td (Glucosa 101.5 mg/dL) Tj ET';
  const objects=[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length '+Buffer.byteLength(line)+' >>\nstream\n'+line+'\nendstream',
  ];
  let content='%PDF-1.4\n';
  const offsets=objects.map((object,index)=>{
    const offset=Buffer.byteLength(content);
    content+=(index+1)+' 0 obj\n'+object+'\nendobj\n';
    return offset;
  });
  const xref=Buffer.byteLength(content);
  content+='xref\n0 6\n0000000000 65535 f \n'+offsets.map(offset=>
    String(offset).padStart(10,'0')+' 00000 n \n').join('')+
    'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF\n';
  const pdf=Buffer.from(content);
  const row={...report(0,''),pdf,sha:sha(pdf),requestPdf:null,requestSha:null};
  const overview=await createSilPatientReportOverview({query:async()=>({rows:[row]})})(patient,[ids[0]]);
  expect(overview.reports[0].measurements).toMatchObject([{value:101.5,unit:'mg/dL'}]);
});
