import '../documentos_reales/informe_fields.dart';
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
    final working = value.status == 'queued' || value.status == 'processing';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(reviewed ? Icons.verified_outlined : Icons.auto_awesome_outlined),
          const SizedBox(height: 12),
          Text(reviewed ? 'Datos revisados y aprobados por un profesional' : status,
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(reviewed ? 'Copia revisada' : 'Datos extraídos por IA: pendientes de cotejo con el original'),
        ])),
      const SizedBox(height: 16),
      Text(reviewed ? 'Copia de la revisión profesional. La extracción original de IA se conserva por separado.'
        : 'Extracción original de IA, conservada sin cambios. Compara cada dato con el documento original. La revisión profesional se guarda por separado.'),
      const SizedBox(height: 12),
      if (working) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(value.status == 'queued'
          ? 'Documento en espera de procesamiento. Los datos aparecerán cuando termine la extracción.'
          : 'La lectura y extracción están en curso. Los datos todavía no están disponibles para revisar.'),
        const Text('El estado se consulta automáticamente cada cinco segundos durante diez minutos. También puedes usar Actualizar extracción. La barra indica espera; no representa un porcentaje.'),
        const SizedBox(height: 12),
      ],
      if (extraction != null) ...[
        SelectableText('Examen: ${visible(extraction['examen'])}'),
        SelectableText('${reviewed ? 'Fecha revisada' : 'Fecha extraída'}: ${visible(extraction['fecha'])}'),
        InformeFields(value: extraction['informe']),
        ...((extraction['resultados'] as List?) ?? []).map((item) {
          final row = item as Map<String, dynamic>;
          return Card(margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(visible(row['nombre']), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText('Valor: ${visible(row['valor'])}'),
              SelectableText('Unidad: ${visible(row['unidad'])}'),
              SelectableText('Referencia: ${visible(row['rango_referencia'])}'),
              if (row.containsKey('estado_documento')) SelectableText('Estado transcrito del documento: ${visible(row['estado_documento'])}'),
            ])));
        }),
      ],
      const SizedBox(height: 12),
      if (!reviewed) ...[
        const Divider(),
        const SizedBox(height: 12),
        Text('Incidencias de lectura y extracción', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
      ],
      if (!reviewed && value.incidents.isEmpty && !working) const Text('Sin incidencias registradas. Esto no garantiza exactitud.'),
      ...value.incidents.map((issue) => SelectableText(issue)),
      if (value.sourceText != null) ...[
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
        Text('Texto usado para la extracción', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Puede contener errores de lectura u OCR; el archivo original es la referencia.'),
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ), child: SelectableText(value.sourceText!)),
      ],
    ]);
  }
}
