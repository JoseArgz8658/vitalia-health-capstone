import 'package:flutter/material.dart';

const informeLabels = <String, String>{
  'nombre_paciente': 'Nombre completo del paciente',
  'edad': 'Edad indicada',
  'sexo': 'Sexo indicado',
  'fecha_nacimiento': 'Fecha de nacimiento (DD-MM-AAAA)',
  'expediente': 'Número de expediente',
  'medico_solicitante': 'Médico solicitante',
  'fecha_muestra': 'Fecha de toma de muestra (DD-MM-AAAA)',
  'hora_muestra': 'Hora de toma de muestra',
  'fecha_emision': 'Fecha de emisión (DD-MM-AAAA)',
  'hora_emision': 'Hora de emisión',
  'laboratorio': 'Laboratorio',
  'observaciones_originales': 'Observaciones originales del informe',
  'profesional_validante': 'Profesional que validó el informe',
  'registro_profesional': 'Registro profesional del informe',
};

bool informeValido(dynamic value) {
  if (value == null) return true;
  return value is Map<String, dynamic> && value.length == informeLabels.length &&
    informeLabels.keys.every((key) => value.containsKey(key) &&
      (value[key] == null || value[key] is String));
}

class InformeFields extends StatelessWidget {
  const InformeFields({super.key, required this.value});
  final dynamic value;
  @override
  Widget build(BuildContext context) {
    if (value == null) return const Text('Esta extracción anterior no incluye los datos ampliados del informe.');
    if (!informeValido(value)) return const Text('Datos del informe no disponibles.');
    final data = value as Map<String, dynamic>;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Datos transcritos del informe', style: Theme.of(context).textTheme.titleMedium),
      const Text('Son datos del documento; no se deducen de la cuenta del paciente.'),
      for (final field in informeLabels.entries)
        SelectableText('${field.value}: ${data[field.key] ?? 'No disponible'}'),
    ]);
  }
}
