import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { validate, missing, prompt } from './evaluar-extraccion.mjs';
const independent = JSON.parse(await readFile(new URL('./casos-extraccion-independientes.json', import.meta.url)));
const original = JSON.parse(await readFile(new URL('./casos-extraccion.json', import.meta.url)));
test('diez casos nuevos con referencias válidas e identificadores únicos', () => {
  assert.equal(independent.length, 10);
  assert.equal(new Set(independent.map(c => c.id)).size, 10);
  for (const item of independent) {
    assert.deepEqual(validate(item.expected), []);
    assert.ok(!original.some(c => c.document === item.document));
    assert.ok(!prompt.includes(item.expected.examen ?? 'Título del examen: no indicado'));
  }
});
test('valor desconocido conserva unidad y referencia y solo falta valor', () => {
  assert.deepEqual(missing(independent[0].expected), ['resultados[0].valor', 'resultados[1].unidad']);
  assert.equal(independent[0].expected.resultados[0].rango_referencia, '2,1–6,8 mmol/L');
});
