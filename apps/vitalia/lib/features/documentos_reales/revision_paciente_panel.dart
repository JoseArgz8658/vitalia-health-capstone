import 'chat_examen_panel.dart';
import 'explicacion_panel.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';

class RevisionPacientePanel extends StatefulWidget {
  const RevisionPacientePanel({super.key, required this.auth,
    required this.documentId, required this.onExpired});
  final AuthApi auth;
  final String documentId;
  final VoidCallback onExpired;
  @override
  State<RevisionPacientePanel> createState() => _RevisionPacientePanelState();
}

class _RevisionPacientePanelState extends State<RevisionPacientePanel> {
  Map<String, dynamic>? _review;
  String? _message;
  bool _busy = false;
  String visible(dynamic value) => value == null ? 'No disponible' : value.toString();
  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _review = null; _message = null; });
    try {
      final response = await widget.auth.sendDocumentRequest(
        http.Request('GET', widget.auth.documentUri('${widget.documentId}/review')));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final review = data['review'];
      if (!data.containsKey('review')) throw const FormatException();
      if (review == null) {
        if (mounted) setState(() => _message = 'Todavía no hay una revisión aprobada para este documento.');
      } else {
        if (review is! Map<String, dynamic> || review['approved'] != true ||
            review['observations'] is! String || review['reviewedAt'] is! String ||
            DateTime.tryParse(review['reviewedAt'] as String) == null ||
            review['extraction'] is! Map<String, dynamic>) throw const FormatException();
        final extraction = review['extraction'] as Map<String, dynamic>;
        final rows = extraction['resultados'];
        if (rows is! List || rows.isEmpty || rows.length > 100 ||
            ![extraction['examen'], extraction['fecha']].every((v) => v == null || v is String) ||
            rows.any((row) => row is! Map<String, dynamic> ||
              !['nombre', 'valor', 'unidad', 'rango_referencia'].every((key) =>
                row.containsKey(key) && (row[key] == null || row[key] is String)))) throw const FormatException();
        if (mounted) setState(() => _review = review);
      }
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) { widget.onExpired(); }
      else { setState(() => _message = error.message); }
    } catch (_) {
      if (mounted) setState(() => _message = 'No se pudo consultar la revisión aprobada.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final review = _review;
    final extraction = review?['extraction'] as Map<String, dynamic>?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton(onPressed: _busy ? null : _load,
        child: Text(_busy ? 'Consultando resultados…' : 'Ver resultados revisados')),
      if (_message != null) Text(_message!),
      if (review != null && extraction != null) Card(child: Padding(
        padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Resultados revisados por un profesional', style: Theme.of(context).textTheme.titleMedium),
            const Text('Estos datos fueron cotejados con el documento original. No constituyen un diagnóstico ni una recomendación de tratamiento.'),
            SelectableText('Examen: ${visible(extraction['examen'])}'),
            SelectableText('Fecha del examen: ${visible(extraction['fecha'])}'),
            for (final row in extraction['resultados'] as List) Padding(
              padding: const EdgeInsets.symmetric(vertical: 8), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText(visible(row['nombre'])),
                  SelectableText('Valor: ${visible(row['valor'])}'),
                  SelectableText('Unidad: ${visible(row['unidad'])}'),
                  SelectableText('Rango de referencia: ${visible(row['rango_referencia'])}'),
                ])),
            const Text('Observaciones del profesional'),
            SelectableText((review['observations'] as String).isEmpty
              ? 'Sin observaciones registradas.' : review['observations'] as String),
            Text('Revisión registrada: ${_date(review['reviewedAt'] as String)}'),
            ExplicacionPanel(key: ValueKey('${widget.documentId}:${review['reviewedAt']}'),
              auth: widget.auth, documentId: widget.documentId, reviewedExtraction: extraction,
              onExpired: widget.onExpired),
            ChatExamenPanel(key: ValueKey('chat:${widget.documentId}:${review['reviewedAt']}'),
              auth: widget.auth, documentId: widget.documentId, reviewedExtraction: extraction,
              onExpired: widget.onExpired),
          ]))),
    ]);
  }
  String _date(String value) {
    final date = DateTime.parse(value).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }
}
