import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { validate, missing, compare, request, assess } from './evaluar-extraccion.mjs';
const cases = JSON.parse(await readFile(new URL('./casos-extraccion.json', import.meta.url)));
test('referencias de los ocho casos son válidas', () => {
  assert.equal(cases.length, 8);
  for (const item of cases) assert.deepEqual(validate(item.expected), []);
});
test('detecta los errores observados en la prueba manual', () => {
  const value = structuredClone(cases[1].expected);
  value.fecha = 'no visible';
  value.datos_faltantes = ['Referencia de Plaquetas'];
  assert.ok(validate(value).length);
  delete value.datos_faltantes;
  assert.deepEqual(validate(value), ['fecha: inválida']);
  assert.deepEqual(missing(cases[1].expected), ['fecha', 'resultados[1].valor', 'resultados[2].rango_referencia']);
});
test('rechaza fechas imposibles y permite día bisiesto válido', () => {
  const value = structuredClone(cases[0].expected);
  for (const date of ['31-02-2026', '29-02-2026', '01-13-2026']) {
    value.fecha = date; assert.ok(validate(value).length);
  }
  value.fecha = '29-02-2024'; assert.deepEqual(validate(value), []);
});
test('detecta cambio de cifra, unidad duplicada y resultados extra', () => {
  const expected = cases[0].expected;
  const value = structuredClone(expected);
  value.resultados[0].valor = '14,2 g/dL';
  value.resultados.push(value.resultados[1]);
  assert.equal(compare(value, expected).length, 2);
  value.resultados[0].valor = '99,9';
  assert.ok(compare(value, expected).some(e => e.startsWith('resultados[0].valor')));
});
test('solicita esquema, sin streaming y únicamente al servidor local', async () => {
  const response = await request('Documento ficticio', {model: 'qwen2.5:3b', fetchImpl: async (url, options) => {
    assert.equal(url, 'http://127.0.0.1:11434/api/chat');
    const body = JSON.parse(options.body);
    assert.equal(body.stream, false);
    assert.equal(body.options.temperature, 0);
    assert.equal(body.format.additionalProperties, false);
    return {ok: true, json: async () => ({done:true, message:{content:'{}'}})};
  }});
  assert.equal(response.raw, '{}');
});
test('fallos HTTP y respuestas incompletas no se aceptan', async () => {
  await assert.rejects(request('x', {fetchImpl: async () => ({ok:false,status:404,text:async()=> 'modelo ausente'})}), /HTTP 404/);
  await assert.rejects(request('x', {fetchImpl: async () => ({ok:true,json:async()=>({done:true,done_reason:'length'})})}), /incompleta/);
});

test('fecha inválida no oculta unidad o valor discrepantes', () => {
  const expected = cases[3].expected;
  const actual = structuredClone(expected);
  actual.fecha = '31-02-2026';
  actual.resultados[0].unidad = null;
  actual.resultados[0].valor = '99,9';
  const result = assess(actual, expected);
  assert.equal(result.passed, false);
  assert.equal(result.datos_faltantes, null);
  assert.ok(result.errors.includes('fecha: inválida'));
  assert.ok(result.errors.some(e => e.startsWith('fecha: esperado')));
  assert.ok(result.errors.some(e => e.startsWith('resultados[0].unidad')));
  assert.ok(result.errors.some(e => e.startsWith('resultados[0].valor')));
  assert.equal(actual.fecha, '31-02-2026');
});
test('evaluación informa estructura inválida sin lanzar y conserva aprobación exacta', () => {
  for (const actual of [null, {}, {examen: 'x', fecha: null, resultados: null}]) {
    const result = assess(actual, cases[0].expected);
    assert.equal(result.passed, false);
    assert.ok(result.errors.length);
  }
  const result = assess(cases[0].expected, cases[0].expected);
  assert.deepEqual(result, {errors: [], datos_faltantes: [], passed: true});
});
