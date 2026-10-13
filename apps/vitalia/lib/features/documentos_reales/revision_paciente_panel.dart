import '../../core/mensaje_vista.dart';
import 'informe_fields.dart';
import 'chat_examen_panel.dart';
import 'explicacion_panel.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';

class RevisionPacientePanel extends StatefulWidget {
  const RevisionPacientePanel({super.key, required this.auth,
    required this.documentId, required this.onExpired,
    this.openInPage = false, this.autoLoad = false, this.onReviewChanged});
  final ValueChanged<Map<String, dynamic>?>? onReviewChanged;
  final bool openInPage;
  final bool autoLoad;
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
  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }
  void _openChat(Map<String, dynamic> extraction) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatExamenPage(auth: widget.auth,
        documentId: widget.documentId, reviewedExtraction: extraction,
        onExpired: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          widget.onExpired();
        })));
  }
  Future<void> _openResults() async {
    final reviewed = ValueNotifier<Map<String, dynamic>?>(null);
    var active = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: reviewed,
          builder: (context, review, _) => Scaffold(
            appBar: AppBar(title: const Text('Resultados de tu examen')),
            floatingActionButton: review == null ? null : FloatingActionButton.extended(
              onPressed: () => _openChat(review['extraction'] as Map<String, dynamic>),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Preguntar a la IA'),
              tooltip: 'Abrir el chat sobre este examen',
            ),
            body: SafeArea(child: SingleChildScrollView(
              // Reserva espacio para que el botón no tape el último contenido.
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24, 24,
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24, 112),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: RevisionPacientePanel(auth: widget.auth,
                  documentId: widget.documentId, autoLoad: true,
                  onReviewChanged: (value) {
                    if (active) reviewed.value = value;
                  },
                  onExpired: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    widget.onExpired();
                  }),
              )),
            )),
          ),
        ),
      ));
    } finally {
      active = false;
      reviewed.dispose();
    }
  }
  String visible(dynamic value) => value == null ? 'No disponible' : value.toString();
  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _review = null; _message = null; });
    widget.onReviewChanged?.call(null);
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
        if (!informeValido(extraction['informe'])) throw const FormatException();
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
      if (mounted) {
        setState(() => _busy = false);
        widget.onReviewChanged?.call(_review);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    if (widget.openInPage) {
      return OutlinedButton.icon(
        onPressed: _openResults,
        icon: const Icon(Icons.assignment_turned_in_outlined),
        label: const Text('Ver resultados revisados'),
      );
    }
    final review = _review;
    final extraction = review?['extraction'] as Map<String, dynamic>?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton(onPressed: _busy ? null : _load,
        child: Text(_busy ? 'Consultando resultados…'
          : widget.autoLoad ? 'Actualizar resultados revisados' : 'Ver resultados revisados')),
      if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator()),
      if (_message != null) MensajeVista(text: _message!),
      if (review != null && extraction != null) Card(child: Padding(
        padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.verified_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text('Resultados revisados por un profesional',
                style: Theme.of(context).textTheme.titleLarge)),
            ]),
            const SizedBox(height: 12),
            const Text('Estos datos fueron cotejados con el documento original. No constituyen un diagnóstico ni una recomendación de tratamiento.'),
            const SizedBox(height: 16),
            SelectableText('Examen: ${visible(extraction['examen'])}'),
            SelectableText('Fecha del examen: ${visible(extraction['fecha'])}'),
            InformeFields(value: extraction['informe']),
            for (final row in extraction['resultados'] as List) Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText(visible(row['nombre']), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText('Valor: ${visible(row['valor'])}'),
                  SelectableText('Unidad: ${visible(row['unidad'])}'),
                  SelectableText('Rango de referencia: ${visible(row['rango_referencia'])}'),
                  if (row.containsKey('estado_documento')) SelectableText('Estado transcrito del documento: ${visible(row['estado_documento'])}'),
                ])),
            const SizedBox(height: 16),
            Container(width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.medical_information_outlined),
                const SizedBox(height: 8),
                Text('Observaciones del profesional', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText((review['observations'] as String).isEmpty
                  ? 'Sin observaciones registradas.' : review['observations'] as String),
                const SizedBox(height: 12),
                Text('Revisión registrada: ${_date(review['reviewedAt'] as String)}'),
              ])),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.auto_awesome_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text('Espacio de IA', style: Theme.of(context).textTheme.titleLarge)),
            ]),
            const SizedBox(height: 8),
            const Text('Las explicaciones y respuestas siguientes son educativas. No forman parte de la aprobación profesional.'),
            const SizedBox(height: 16),
            ExplicacionPanel(key: ValueKey('${widget.documentId}:${review['reviewedAt']}'),
              auth: widget.auth, documentId: widget.documentId, reviewedExtraction: extraction,
              onExpired: widget.onExpired),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openChat(extraction),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Preguntar a la IA'),
            ),
          ]))),
    ]);
  }
  String _date(String value) {
    final date = DateTime.parse(value).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }
}
