import {type SilResultInput} from './service';

// Valores de demostración ficticios, no originados en un analizador ni en una muestra clínica.
// No utilizar como resultados reales, interpretación médica ni informe emitido.
const DEMO_HEMOGRAM: ReadonlyArray<Readonly<SilResultInput>> = Object.freeze([
  Object.freeze({analyte:'Hemoglobina', numericValue:13.2,unit:'g/dL',referenceMin:12,referenceMax:16}),
  Object.freeze({analyte:'Hematocrito',numericValue:40,unit:'%',referenceMin:35,referenceMax:48}),
  Object.freeze({analyte:'Eritrocitos',numericValue:4.7,unit:'10^6/uL',referenceMin:4.1,referenceMax:5.4}),
  Object.freeze({analyte:'Leucocitos',numericValue:7.2,unit:'10^3/uL',referenceMin:4,referenceMax:11}),
  Object.freeze({analyte:'Plaquetas',numericValue:250,unit:'10^3/uL',referenceMin:150,referenceMax:450}),
]);

export const SIL_ANALYZER_ID='simulador-hemograma-v1' as const;

export function simulateHemogram():SilResultInput[] {
  return DEMO_HEMOGRAM.map(item=>({...item}));
}
