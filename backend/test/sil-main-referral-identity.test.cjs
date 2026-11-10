const {suggestReferralIdentity}=require('../dist/sil/main-referral-identity');

test('solo propone datos personales rotulados y validados de una derivación chilena',()=>{
  const content=[
    'Paciente: Ana María Pérez Soto',
    'RUT: 12.345.678-5',
    'Fecha de nacimiento: 12/04/1990',
    'Correo electrónico: Ana.Perez@example.invalid',
    'Teléfono: +56 9 1234 5678',
    'Sexo: Femenino',
  ].join('\n');
  expect(suggestReferralIdentity(content)).toEqual({
    fullName:'Ana María Pérez Soto',
    identifier:'12.345.678-5',
    birthDate:'1990-04-12',
    email:'ana.perez@example.invalid',
    phone:'+56 9 1234 5678',
    sex:'femenino',
  });
});

test('no inventa datos personales ausentes ni confunde profesional solicitante',()=>{
  const data=suggestReferralIdentity([
    'Profesional solicitante: Pablo Alvarez',
    'Referencia: ABC-123',
    'Fecha de solicitud: 2026-11-01',
    'Glicemia',
  ].join('|'));
  expect(Object.values(data)).toEqual([null,null,null,null,null,null]);
});

test('rechaza sugerencias ambiguas, fechas imposibles y nombres aislados',()=>{
  const data=suggestReferralIdentity([
    'Paciente: Ana López',
    'Paciente: Cecilia Pérez',
    'Fecha de nacimiento: 31/02/1999',
    'Correo: ana@example.invalid',
    'Correo: otra@example.invalid',
    'Nombre: Ana',
  ].join('|'));
  expect(data.fullName).toBeNull();
  expect(data.birthDate).toBeNull();
  expect(data.email).toBeNull();
  expect(data.identifier).toBeNull();
});

test('RUT sin rótulo y correo del proveedor sin etiqueta no identifican paciente',()=>{
  expect(suggestReferralIdentity('12.345.678-5|doctor@med.example')).toEqual({
    fullName:null,identifier:null,birthDate:null,email:null,phone:null,sex:null,
  });
});
