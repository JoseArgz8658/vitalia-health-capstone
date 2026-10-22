const { reviewExtraction, isCalendarDate } = require('../dist/ai/contract');
const { createLocalExtractor } = require('../dist/ai/local-extractor');
const row={nombre:'Indicador ficticio',valor:'1.234,50',unidad:'U/L',rango_referencia:'1.000,00–2.000,00 U/L'};
const complete={examen:'Perfil ficticio',fecha:'01-10-2026',resultados:[row]};
const response=(value,extra={})=>new Response(JSON.stringify({done:true,message:{content:JSON.stringify(value)},...extra}));
test('datos completos conservados y siempre pendientes de revisión',()=>{
 const raw=JSON.stringify(complete), result=reviewExtraction(raw);
 expect(result).toMatchObject({raw,extraction:complete,incidents:[],status:'requires_review',approved:false});
});
test('fecha inválida conserva original y no oculta campo null',()=>{
 const result=reviewExtraction(JSON.stringify({...complete,fecha:'31-02-2026',resultados:[{...row,unidad:null}]}));
 expect(result.extraction.fecha).toBe('31-02-2026');
 expect(result.incidents.map(i=>[i.code,i.path])).toEqual([['invalid_date','fecha'],['not_extracted','resultados[0].unidad']]);
});
test('valor null conserva unidad y rango',()=>{
 const result=reviewExtraction(JSON.stringify({...complete,resultados:[{...row,valor:null}]}));
 expect(result.extraction.resultados[0]).toEqual({...row,valor:null});
 expect(result.incidents).toHaveLength(1);
});
test('JSON, claves extra y tipos incorrectos rechazados sin perder original',()=>{
 for(const raw of ['{',JSON.stringify({...complete,diagnostico:'x'}),JSON.stringify({...complete,resultados:[{...row,valor:123}]})]){
  expect(reviewExtraction(raw)).toMatchObject({status:'rejected',extraction:null,raw,approved:false});
 }
});
test('sin resultados y campos ausentes genera incidencias',()=>{
 expect(reviewExtraction(JSON.stringify({examen:null,fecha:null,resultados:[]})).incidents.map(i=>i.code)).toEqual(['not_extracted','not_extracted','no_results']);
});
test('calendario distingue años bisiestos',()=>{
 for(const v of ['31-11-2026','29-02-2027','29-02-1900','2026-10-01']) expect(isCalendarDate(v)).toBe(false);
 for(const v of ['29-02-2028','29-02-2000','01-10-2026']) expect(isCalendarDate(v)).toBe(true);
});
test('solicitud solo local, sin redirección y con prompt congelado',async()=>{
 const result=await createLocalExtractor({fetchImpl:async(url,init)=>{
  expect(url).toBe('http://127.0.0.1:11434/api/chat');expect(init.redirect).toBe('error');
  const body=JSON.parse(init.body);expect(body.model).toBe('qwen3:4b-instruct');expect(body.stream).toBe(false);
  expect(body.messages[0].content).toContain('INDEPENDIENTEMENTE');return response(complete);
 }})('Texto ficticio');
 expect(result).toMatchObject({extraction:complete,promptVersion:3,approved:false});
});
test('entrada inválida y modelo cloud fallan antes de red',async()=>{
 const fetchImpl=jest.fn(), extract=createLocalExtractor({fetchImpl});
 await expect(extract(' ')).rejects.toThrow('texto');await expect(extract('á'.repeat(6001))).rejects.toThrow('texto');
 expect(fetchImpl).not.toHaveBeenCalled();expect(()=>createLocalExtractor({model:'model-cloud'})).toThrow('local');
});
test('HTTP, transporte e incompleto producen error de servicio',async()=>{
 await expect(createLocalExtractor({fetchImpl:async()=>new Response('',{status:404})})('x')).rejects.toThrow('HTTP 404');
 await expect(createLocalExtractor({fetchImpl:async()=>{throw Error('privado');}})('x')).rejects.toThrow('No se pudo');
 await expect(createLocalExtractor({fetchImpl:async()=>response(complete,{done_reason:'length'})})('x')).rejects.toThrow('incompleta');
});
test('límite de respuesta y JSON del modelo inválido',async()=>{
 await expect(createLocalExtractor({fetchImpl:async()=>new Response('x'.repeat(131073))})('x')).rejects.toThrow('grande');
 const result=await createLocalExtractor({fetchImpl:async()=>new Response(JSON.stringify({done:true,message:{content:'{'}}))})('x');
 expect(result).toMatchObject({status:'rejected',raw:'{'});
});

test('detecta rango de referencia que no aparece en el documento original', () => {
  const documentoOriginal = 'Perfil ficticio\nIndicador ficticio: 1.234,50 U/L\nFecha: 01-10-2026';

  const resultadoOllama = {
    ...complete,
    resultados: [{
      ...row,
      rango_referencia: '1.000,00–2.000,00 U/L'
    }]
  };

  const result = reviewExtraction(
    JSON.stringify(resultadoOllama),
    false,
    documentoOriginal
  );

  expect(result.incidents).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        path: 'resultados[0].rango_referencia'
      })
    ])
  );
});

test('Ollama registra incidencia cuando inventa un rango de referencia', async () => {
  const documentoOriginal =
    'Perfil ficticio\n' +
    'Fecha: 01-10-2026\n' +
    'Indicador ficticio: 1.234,50 U/L';

  const extract = createLocalExtractor({
    fetchImpl: async () => response(complete)
  });

  const result = await extract(documentoOriginal);

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);

  expect(result.incidents).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        code: 'not_in_source',
        path: 'resultados[0].rango_referencia'
      })
    ])
  );

  expect(result.extraction.resultados[0].rango_referencia)
    .toBe(row.rango_referencia);
});

test('no genera incidencia cuando el rango aparece en el documento original', async () => {
  const documentoOriginal =
    'Perfil ficticio\n' +
    'Fecha: 01-10-2026\n' +
    'Indicador ficticio: 1.234,50 U/L\n' +
    'Rango de referencia: 1.000,00–2.000,00 U/L';

  const extract = createLocalExtractor({
    fetchImpl: async () => response(complete)
  });

  const result = await extract(documentoOriginal);

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);
  expect(result.incidents).toEqual([]);
});

test('reconoce un rango separado por saltos de linea en el PDF', async () => {
  const documentoOriginal =
    'Perfil ficticio\n' +
    'Fecha: 01-10-2026\n' +
    'Indicador ficticio: 1.234,50 U/L\n' +
    'Rango de referencia:\n' +
    '1.000,00–2.000,00\n' +
    'U/L';

  const extract = createLocalExtractor({
    fetchImpl: async () => response(complete)
  });

  const result = await extract(documentoOriginal);

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);
  expect(result.incidents).toEqual([]);
});
test('normaliza guiones Unicode sin alterar signos de interrogación', () => {
  const documentoOriginal =
    'Perfil ficticio\n' +
    'Indicador ficticio: 1.234,50 U/L\n' +
    'Rango de referencia: 1.000,00\u20132.000,00 U/L';

  const resultadoOllama = {
    ...complete,
    resultados: [{
      ...row,
      rango_referencia: '1.000,00-2.000,00 U/L'
    }]
  };

  const result = reviewExtraction(
    JSON.stringify(resultadoOllama),
    false,
    documentoOriginal
  );

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);
  expect(result.incidents).toEqual([]);

  const documentoConInterrogacion =
    'Rango de referencia: 1.000,00?2.000,00 U/L';

  const resultConInterrogacion = reviewExtraction(
    JSON.stringify(resultadoOllama),
    false,
    documentoConInterrogacion
  );

  expect(resultConInterrogacion.incidents).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        code: 'not_in_source',
        path: 'resultados[0].rango_referencia'
      })
    ])
  );
});

test('detecta un valor numerico que no aparece en el documento', () => {
  const documento = 'Glucosa: 95 mg/dL. Referencia: 70-100 mg/dL.';
  const respuesta = {
    ...complete,
    resultados: [{
      ...row,
      nombre: 'Glucosa',
      valor: '190',
      unidad: 'mg/dL',
      rango_referencia: '70-100 mg/dL'
    }]
  };

  const result = reviewExtraction(
    JSON.stringify(respuesta),
    false,
    documento
  );

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);
  expect(result.incidents).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        code: 'not_in_source',
        path: 'resultados[0].valor'
      })
    ])
  );
});

test('detecta valor asignado al analito equivocado', () => {
  const documento = [
    'Examen: Hemograma',
    'Hemoglobina: 14.2 g/dL',
    'Leucocitos: 7200 /uL',
    'Plaquetas: 250000 /uL'
  ].join('\n');

  const respuesta = {
    ...complete,
    resultados: [{
      ...row,
      nombre: 'Hemoglobina',
      valor: '7200',
      unidad: 'g/dL',
      rango_referencia: null
    }]
  };

  const result = reviewExtraction(
    JSON.stringify(respuesta),
    false,
    documento
  );

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);
  expect(result.incidents).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        code: 'not_in_source',
        path: 'resultados[0].valor'
      })
    ])
  );
});

test('acepta valores correctamente asociados a sus analitos', () => {
  const documento = [
    'Examen: Hemograma',
    'Hemoglobina: 14.2 g/dL',
    'Leucocitos: 7200 /uL',
    'Plaquetas: 250000 /uL'
  ].join('\n');

  const respuesta = {
    ...complete,
    resultados: [
      {
        nombre: 'Hemoglobina',
        valor: '14.2',
        unidad: 'g/dL',
        rango_referencia: null
      },
      {
        nombre: 'Leucocitos',
        valor: '7200',
        unidad: '/uL',
        rango_referencia: null
      },
      {
        nombre: 'Plaquetas',
        valor: '250000',
        unidad: '/uL',
        rango_referencia: null
      }
    ]
  };

  const result = reviewExtraction(
    JSON.stringify(respuesta),
    false,
    documento
  );

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);
  expect(result.incidents.filter(
    incident => incident.code === 'not_in_source'
  )).toEqual([]);
});

test('no marca como incorrecto un valor valido de un analito repetido', () => {
  const documento = [
    'Glucosa: 95 mg/dL',
    'Glucosa: 100 mg/dL'
  ].join('\n');

  const respuesta = {
    ...complete,
    resultados: [{
      nombre: 'Glucosa',
      valor: '100',
      unidad: 'mg/dL',
      rango_referencia: null
    }]
  };

  const result = reviewExtraction(
    JSON.stringify(respuesta),
    false,
    documento
  );

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);
  expect(result.incidents.filter(
    incident => incident.code === 'not_in_source'
  )).toEqual([]);
});

test('distingue el mensaje de un valor asociado a otro analito', () => {
  const documento = [
    'Hemoglobina: 14.2 g/dL',
    'Leucocitos: 7200 /uL'
  ].join('\n');

  const respuesta = {
    ...complete,
    resultados: [{
      nombre: 'Hemoglobina',
      valor: '7200',
      unidad: 'g/dL',
      rango_referencia: null
    }]
  };

  const result = reviewExtraction(
    JSON.stringify(respuesta),
    false,
    documento
  );

  const incidencia = result.incidents.find(
    incident =>
      incident.code === 'not_in_source' &&
      incident.path === 'resultados[0].valor'
  );

  expect(incidencia).toBeDefined();
  expect(incidencia.message).toContain(
    'no coincide con el asociado a este analito'
  );
});

test('reconoce valores con operadores de comparacion presentes en el documento', () => {
  const casos = [
    { nombre: 'Glucosa', valor: '<70', documento: 'Glucosa: <70 mg/dL' },
    { nombre: 'PCR', valor: '>200', documento: 'PCR: >200 mg/L' }
  ];

  for (const caso of casos) {
    const respuesta = {
      ...complete,
      resultados: [{
        nombre: caso.nombre,
        valor: caso.valor,
        unidad: null,
        rango_referencia: null
      }]
    };

    const result = reviewExtraction(
      JSON.stringify(respuesta),
      false,
      caso.documento
    );

    expect(result.status).toBe('requires_review');
    expect(result.approved).toBe(false);
    expect(result.incidents.filter(
      incident => incident.code === 'not_in_source'
    )).toEqual([]);
  }
});

test('detecta operadores de comparacion omitidos o intercambiados', () => {
  const casos = [
    ['Glucosa: <70 mg/dL', 'Glucosa', '70'],
    ['Glucosa: 70 mg/dL', 'Glucosa', '<70'],
    ['PCR: >200 mg/L', 'PCR', '200'],
    ['PCR: <200 mg/L', 'PCR', '>200']
  ];

  for (const [documento, nombre, valor] of casos) {
    const respuesta = {
      ...complete,
      resultados: [{
        nombre,
        valor,
        unidad: null,
        rango_referencia: null
      }]
    };

    const result = reviewExtraction(
      JSON.stringify(respuesta),
      false,
      documento
    );

    expect(result.status).toBe('requires_review');
    expect(result.approved).toBe(false);

    expect(result.incidents.some(
      incident =>
        incident.code === 'not_in_source' &&
        incident.path === 'resultados[0].valor'
    )).toBe(true);
  }
});
test('detecta operadores inclusivos omitidos o intercambiados', () => {
  const casos = [
    ['Glucosa: <=70 mg/dL', 'Glucosa', '70'],
    ['Glucosa: <=70 mg/dL', 'Glucosa', '<70'],
    ['Glucosa: <70 mg/dL', 'Glucosa', '<=70'],
    ['PCR: >=200 mg/L', 'PCR', '200'],
    ['PCR: >=200 mg/L', 'PCR', '>200'],
    ['PCR: >200 mg/L', 'PCR', '>=200']
  ];

  for (const [documento, nombre, valor] of casos) {
    const respuesta = {
      ...complete,
      resultados: [{
        nombre,
        valor,
        unidad: null,
        rango_referencia: null
      }]
    };

    const result = reviewExtraction(
      JSON.stringify(respuesta),
      false,
      documento
    );

    expect(result.status).toBe('requires_review');
    expect(result.approved).toBe(false);

    expect(result.incidents.some(
      incident =>
        incident.code === 'not_in_source' &&
        incident.path === 'resultados[0].valor'
    )).toBe(true);
  }
});
test('detecta valor asignado al analito equivocado en una tabla', () => {
  const documentoOriginal = [
    'Examen          Resultado      Unidad',
    'Glucosa         95             mg/dL',
    'Colesterol      180            mg/dL'
  ].join('\n');

  const respuestaOllama = {
    ...complete,
    resultados: [{
      nombre: 'Glucosa',
      valor: '180',
      unidad: 'mg/dL',
      rango_referencia: null
    }]
  };

  const result = reviewExtraction(
    JSON.stringify(respuestaOllama),
    false,
    documentoOriginal
  );

  expect(result.status).toBe('requires_review');
  expect(result.approved).toBe(false);

  expect(result.incidents).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        code: 'not_in_source',
        path: 'resultados[0].valor'
      })
    ])
  );
});
test('valida analitos con nombres compuestos en tablas', () => {
  const documento = [
    'Examen                 Resultado    Unidad',
    'Colesterol HDL         45           mg/dL',
    'Colesterol LDL         130          mg/dL'
  ].join('\n');

  for (const [valor, debeDetectar] of [
    ['45', false],
    ['130', true]
  ]) {
    const respuesta = {
      ...complete,
      resultados: [{
        nombre: 'Colesterol HDL',
        valor,
        unidad: 'mg/dL',
        rango_referencia: null
      }]
    };

    const result = reviewExtraction(
      JSON.stringify(respuesta),
      false,
      documento
    );

    const detectado = result.incidents.some(
      incident =>
        incident.code === 'not_in_source' &&
        incident.path === 'resultados[0].valor'
    );

    expect(detectado).toBe(debeDetectar);
    expect(result.status).toBe('requires_review');
    expect(result.approved).toBe(false);
  }
});
test('distingue valores repetidos entre analitos de una tabla', () => {
  const documento = [
    'Examen                Resultado    Unidad',
    'Glucosa               95           mg/dL',
    'Colesterol HDL        45           mg/dL',
    'Trigliceridos         95           mg/dL'
  ].join('\n');

  const casos = [
    ['Glucosa', '95', false],
    ['Trigliceridos', '95', false],
    ['Colesterol HDL', '95', true]
  ];

  for (const [nombre, valor, debeDetectar] of casos) {
    const respuesta = {
      ...complete,
      resultados: [{
        nombre,
        valor,
        unidad: 'mg/dL',
        rango_referencia: null
      }]
    };

    const result = reviewExtraction(
      JSON.stringify(respuesta),
      false,
      documento
    );

    const detectado = result.incidents.some(
      incident =>
        incident.code === 'not_in_source' &&
        incident.path === 'resultados[0].valor'
    );

    expect(detectado).toBe(debeDetectar);
    expect(result.status).toBe('requires_review');
    expect(result.approved).toBe(false);
  }
});
