import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';
import 'clave_recuperacion_sil_dialog.dart';

/// Solo demostración local: consulta privada de PDFs autorizados externamente.
class PacienteInformesSilPage extends StatefulWidget {
  const PacienteInformesSilPage({
    super.key,
    required this.api,
    required this.email,
    required this.onExpired,
    required this.onLogout,
  });
  final AuthApi api;
  final String email;
  final VoidCallback onExpired;
  final VoidCallback onLogout;

  @override
  State<PacienteInformesSilPage> createState() =>
      _PacienteInformesSilPageState();
}

class _PacienteInformesSilPageState extends State<PacienteInformesSilPage> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _downloading;
  String? _error;
  final _question = TextEditingController();
  final _filter = TextEditingController();
  final Map<String, List<Map<String, String>>> _conversations = {};
  String? _activeChatReport;
  String? _chatBusyReport;
  String? _chatError;

  @override
  void dispose() {
    _question.dispose();
    _filter.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.silRequest('/patient/reports');
      if (!mounted) return;
      final reports = (data['reports'] as List? ?? [])
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      final ids = reports.map((report) => report['id']).toSet();
      setState(() {
        _reports = reports;
        _conversations.removeWhere((id, _) => !ids.contains(id));
        if (!ids.contains(_activeChatReport)) {
          _activeChatReport = null;
          _question.clear();
          _chatError = null;
        }
      });
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        widget.onExpired();
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = 'No se pudo consultar tus informes.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(Map<String, dynamic> report) async {
    if (_downloading != null) return;
    setState(() {
      _downloading = report['id'] as String;
      _error = null;
    });
    try {
      final bytes = await widget.api.silDownloadReport(report['id'] as String);
      if (!mounted || !widget.api.hasSession) return;
      final name = report['fileName'] as String;
      final pdf =
          XFile.fromData(bytes, name: name, mimeType: 'application/pdf');
      if (kIsWeb) {
        await pdf.saveTo(name);
      } else {
        final target = await getSaveLocation(suggestedName: name);
        if (target == null) return;
        await pdf.saveTo(target.path);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Descarga solicitada. Revisa tus archivos.')),
        );
      }
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        widget.onExpired();
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar el PDF.');
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  void _toggleChat(String reportId) {
    if (_chatBusyReport != null) return;
    setState(() {
      _activeChatReport = _activeChatReport == reportId ? null : reportId;
      _question.clear();
      _chatError = null;
    });
  }

  Future<void> _askChat(String reportId) async {
    final question = _question.text.trim();
    if (_chatBusyReport != null || question.length < 3 || question.length > 400)
      return;
    setState(() {
      _chatBusyReport = reportId;
      _chatError = null;
    });
    try {
      final result = await widget.api.silRequest(
        '/patient/reports/$reportId/chat',
        body: {'question': question},
      );
      if (!mounted || !widget.api.hasSession || _activeChatReport != reportId)
        return;
      final response = Map<String, dynamic>.from(result['response'] as Map);
      final answer = response['answer'] as String?;
      if (answer == null || answer.isEmpty) {
        throw const AuthFailure(
            'El asistente no entregó una respuesta válida.');
      }
      setState(() {
        final turns = _conversations.putIfAbsent(reportId, () => []);
        turns.add({'role': 'user', 'text': question});
        turns.add({
          'role': 'assistant',
          'text': answer,
          'source': response['source'] as String? ?? 'catalogo',
        });
        if (turns.length > 20) turns.removeRange(0, turns.length - 20);
        _question.clear();
      });
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        widget.onExpired();
      } else {
        setState(() => _chatError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _chatError =
            'No se pudo completar la consulta educativa. Prueba nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _chatBusyReport = null);
    }
  }

  Widget _chatPanel(Map<String, dynamic> report) {
    final id = report['id'] as String;
    final turns = _conversations[id] ?? const <Map<String, String>>[];
    final working = _chatBusyReport == id;
    final canAsk = !working && _question.text.trim().length >= 3;
    final exams = _examNames(report);
    final prompts = [
      if (exams.isNotEmpty) ('Qué mide', '¿Qué mide la prueba ${exams.first}?'),
      ('Pruebas de la orden', '¿Qué exámenes incluye esta orden?'),
      ('Rango de referencia', '¿Qué significa rango de referencia?'),
      (
        'Explicación sencilla',
        'Explícame en palabras sencillas qué miden estas pruebas.'
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 30),
        Text('Preguntas sobre este informe',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Escribe una pregunta abierta sobre las prestaciones de la orden. '
          'Puedes partir de un ejemplo y editarlo. Deja fuera datos personales.',
        ),
        const SizedBox(height: 12),
        if (turns.isEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final (label, prompt) in prompts)
                ActionChip(
                  label: Text(label),
                  onPressed: working
                      ? null
                      : () => setState(() {
                            _question.text = prompt;
                            _question.selection =
                                TextSelection.collapsed(offset: prompt.length);
                          }),
                ),
            ],
          ),
        for (final turn in turns) ...[
          Align(
            alignment: turn['role'] == 'user'
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Card(
                color: turn['role'] == 'user'
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (turn['role'] == 'assistant') ...[
                        Text(
                          switch (turn['source']) {
                            'modelo_local' => 'Modelo de IA local',
                            'politica' => 'Alcance de la consulta',
                            _ => 'Biblioteca educativa de Vitalia',
                          },
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 5),
                      ],
                      Text(turn['text'] ?? ''),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
        ],
        if (_chatError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Text(_chatError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (working) const LinearProgressIndicator(),
        TextField(
          controller: _question,
          onChanged: (_) => setState(() {}),
          maxLength: 400,
          maxLines: 2,
          enabled: _chatBusyReport == null,
          decoration: const InputDecoration(
            labelText: 'Consulta educativa sobre este examen',
            hintText: '¿Qué es la glicemia?',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: canAsk ? () => _askChat(id) : null,
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(working ? 'Consultando…' : 'Preguntar al asistente'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Para conocer tus cifras abre el PDF. El asistente explica conceptos generales. '
          'Cada pregunta se responde por separado y el historial solo se muestra durante tu sesión.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _date(Object? source) {
    final date = DateTime.tryParse('$source')?.toLocal();
    if (date == null) return '—';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  List<String> _examNames(Map<String, dynamic> report) =>
      (report['examNames'] as List?)?.whereType<String>().toList() ?? [];

  void _openRecovery() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClaveRecuperacionSilDialog(
          api: widget.api, onExpired: widget.onExpired),
    );
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final theme = Theme.of(context);
    final exams = _examNames(report);
    final id = report['id'] as String;
    final chatOpen = _activeChatReport == id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.picture_as_pdf_outlined,
                  color: ColoresVitalia.azul),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                exams.isEmpty
                    ? report['fileName'] as String
                    : exams.join(' · '),
                style: theme.textTheme.titleMedium,
              )),
            ]),
            const SizedBox(height: 8),
            Text(
                '${report['issuingLaboratory']} · Orden ${report['orderNumber']}'),
            const SizedBox(height: 4),
            Text(
                'Publicado el ${_date(report['publishedAt'])} · Autorizado el ${_date(report['externallyAuthorizedAt'])}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed:
                    _downloading == null ? () => _download(report) : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(_downloading == id
                    ? 'Preparando descarga…'
                    : 'Descargar PDF'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _chatBusyReport == null ? () => _toggleChat(id) : null,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(chatOpen
                    ? 'Cerrar asistente'
                    : 'Preguntar sobre el informe'),
              ),
            ]),
            if (chatOpen) _chatPanel(report),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final query = _filter.text.trim().toLowerCase();
    final visibleReports = _reports
        .where((report) =>
            query.isEmpty ||
            [
              report['orderNumber'],
              report['fileName'],
              report['issuingLaboratory'],
              ..._examNames(report),
            ].join(' ').toLowerCase().contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portal del paciente',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (narrow)
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_outlined),
            )
          else
            TextButton.icon(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('Cerrar sesión'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(narrow ? 14 : 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        ColoresVitalia.azulActivo,
                        ColoresVitalia.verde
                      ]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(narrow ? 16 : 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PORTAL PRIVADO · DEMO',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: Colors.white)),
                          const SizedBox(height: 5),
                          Text('Mis informes',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(widget.email,
                              style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 9),
                          const Text(
                              'Consulta y descarga los informes que el laboratorio publicó para ti.',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar informes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openRecovery,
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Configurar recuperación'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  if (_reports.isNotEmpty) ...[
                    TextField(
                      controller: _filter,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Buscar por orden, examen o laboratorio',
                        helperText: 'Busca en los informes recientes.',
                        helperMaxLines: 2,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar búsqueda',
                                onPressed: () => setState(_filter.clear),
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        query.isEmpty
                            ? 'Informes recientes · ${_reports.length}'
                            : 'Coincidencias · ${visibleReports.length}',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                  ],
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null) ...[
                    Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error))),
                    const SizedBox(height: 12),
                  ],
                  if (!_loading && visibleReports.isEmpty && _error == null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(query.isEmpty
                            ? 'Aún no tienes informes publicados. Aparecerán aquí cuando el laboratorio los publique.'
                            : 'No encontramos informes que coincidan con tu búsqueda.'),
                      ),
                    ),
                  for (final report in visibleReports) _reportCard(report),
                  const SizedBox(height: 18),
                  Text(
                    'Entorno de demostración con informes y cuentas ficticias.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
