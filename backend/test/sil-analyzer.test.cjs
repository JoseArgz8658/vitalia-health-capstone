const {simulateHemogram,SIL_ANALYZER_ID}=require('../dist/sil/analyzer');
test('simulación genera cinco resultados ficticios independientes',()=>{
 const a=simulateHemogram(),b=simulateHemogram();
 expect(SIL_ANALYZER_ID).toBe('simulador-hemograma-v1');
 expect(a).toHaveLength(5);
 expect(a).toEqual(b);
 expect(a).not.toBe(b);
 a[0].numericValue=999;
 expect(simulateHemogram()[0].numericValue).not.toBe(999);
 expect(new Set(b.map(v=>v.analyte)).size).toBe(5);
 for(const item of b) {
  expect(Number.isFinite(item.numericValue)).toBe(true);
  expect(item.referenceMin).toBeLessThanOrEqual(item.referenceMax);
 }
});
