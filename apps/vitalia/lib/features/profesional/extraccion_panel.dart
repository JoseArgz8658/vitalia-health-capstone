import 'package:flutter/material.dart';
import 'profesional_api.dart';

class ExtraccionPanel extends StatelessWidget {
  const ExtraccionPanel({super.key, required this.value, this.reviewed = false});
  final ExtraccionPendiente value;
  final bool reviewed;
  String visible(dynamic value) => value == null ? 'No extraído' : value.toString();
  String get status => switch (value.status) {
    'not_requested' => 'Procesamiento no solicitado',
    'queued' => 'Procesamiento pendiente',
    'processing' => 'Documento en procesamiento',
    'requires_review' => 'Extracción pendiente de revisión profesional',
    'rejected' => 'Documento rechazado para extracción',
    _ => 'El procesamiento no se pudo completar',
  };
  @override
  Widget build(BuildContext context) {
    final extraction = value.extraction;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(reviewed ? 'Datos revisados y aprobados por un profesional' : status, style: Theme.of(context).textTheme.titleMedium),
      Text(reviewed ? 'Copia de la revisión profesional. La extracción original de IA se conserva por separado.'
        : 'Extracción original de IA, conservada sin cambios. Compara cada dato con el documento original. La revisión profesional se guarda por separado.'),
      const SizedBox(height: 12),
      if (extraction != null) ...[
        SelectableText('Examen: ${visible(extraction['examen'])}'),
        SelectableText('${reviewed ? 'Fecha revisada' : 'Fecha extraída'}: ${visible(extraction['fecha'])}'),
        ...((extraction['resultados'] as List?) ?? []).map((item) {
          final row = item as Map<String, dynamic>;
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(visible(row['nombre'])),
              SelectableText('Valor: ${visible(row['valor'])}'),
              SelectableText('Unidad: ${visible(row['unidad'])}'),
              SelectableText('Referencia: ${visible(row['rango_referencia'])}'),
            ])));
        }),
      ],
      const SizedBox(height: 12),
      if (!reviewed) const Text('Incidencias de lectura y extracción'),
      if (!reviewed && value.incidents.isEmpty) const Text('Sin incidencias registradas. Esto no garantiza exactitud.'),
      ...value.incidents.map((issue) => SelectableText(issue)),
      if (value.sourceText != null) ...[
        const SizedBox(height: 12),
        const Text('Texto usado para la extracción'),
        const Text('Puede contener errores de lectura u OCR; el archivo original es la referencia.'),
        SelectableText(value.sourceText!),
      ],
    ]);
  }
}
