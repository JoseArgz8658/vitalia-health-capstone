import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'explicacion_api.dart';

class ExplicacionPanel extends StatefulWidget {
  const ExplicacionPanel({super.key, required this.auth, required this.documentId,
    required this.reviewedExtraction, required this.onExpired});
  final AuthApi auth;
  final String documentId;
  final Map<String, dynamic> reviewedExtraction;
  final VoidCallback onExpired;
  @override
  State<ExplicacionPanel> createState() => _ExplicacionPanelState();
}
class _ExplicacionPanelState extends State<ExplicacionPanel> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  Future<void> _load(bool generate) async {
    if (_busy) return;
    setState(() { _busy = true; _data = null; _error = null; });
    try {
      final api = ExplicacionApi(widget.auth);
      final data = generate ? await api.generar(widget.documentId) : await api.consultar(widget.documentId);
      if (data['status'] == 'ready') {
        final explanation = data['explanation'] as Map<String, dynamic>;
        final rows = widget.reviewedExtraction['resultados'] as List;
        final items = explanation['items'] as List;
        if (explanation['exam'] != widget.reviewedExtraction['examen'] ||
            explanation['date'] != widget.reviewedExtraction['fecha'] || items.length != rows.length) throw const FormatException();
        for (var i = 0; i < rows.length; i++) {
          if (items[i]['name'] != rows[i]['nombre'] || items[i]['value'] != rows[i]['valor'] ||
              items[i]['unit'] != rows[i]['unidad'] || items[i]['reference'] != rows[i]['rango_referencia']) throw const FormatException();
        }
      }
      if (mounted) setState(() => _data = data);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) { widget.onExpired(); }
      else { setState(() => _error = error.message); }
    } catch (_) {
      if (mounted) setState(() => _error = 'La explicación no corresponde a los datos revisados disponibles.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final status = _data?['status'];
    final explanation = _data?['explanation'] as Map<String, dynamic>?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text('Explicación educativa con asistencia de IA', style: Theme.of(context).textTheme.titleMedium),
      const Text('Esta explicación no está aprobada por un profesional. No diagnostica ni recomienda tratamientos.'),
      TextButton(onPressed: _busy ? null : () => _load(false),
        child: const Text('Consultar explicación')),
      if (_busy) const Text('Consultando o generando explicación. Puede tardar hasta dos minutos.'),
      if (_error != null) Text(_error!),
      if (status == 'not_available') const Text('Se requiere una revisión profesional aprobada.'),
      if (status == 'not_requested') const Text('Todavía no se ha generado una explicación.'),
      if (status == 'generating') const Text('La explicación está en generación. Actualiza la consulta más adelante.'),
      if (status == 'failed') const Text('No se pudo obtener una explicación válida. Puedes reintentar después de treinta segundos.'),
      if (!_busy && ['not_requested', 'failed'].contains(status))
        OutlinedButton(onPressed: () => _load(true), child: const Text('Generar explicación')),
      if (explanation != null) ...[
        Text(explanation['notice'] as String),
        for (final row in explanation['items'] as List) Padding(
          padding: const EdgeInsets.symmetric(vertical: 8), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(row['name'] as String? ?? 'Indicador sin nombre disponible'),
              SelectableText(row['explanation'] as String),
              if (row['source'] != null) SelectableText('Fuente: ${row['source']}'),
            ])),
      ],
    ]);
  }
}
