import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

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
  State<PacienteInformesSilPage> createState() => _PacienteInformesSilPageState();
}

class _PacienteInformesSilPageState extends State<PacienteInformesSilPage> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _downloading;
  String? _error;
  final _question = TextEditingController();
  final Map<String, List<Map<String, String>>> _conversations = {};
  String? _activeChatReport;
  String? _chatBusyReport;
  String? _chatError;

  @override
  void dispose() {
    _question.dispose();
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
      setState(() => _reports = (data['reports'] as List? ?? [])
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList());
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        widget.onExpired();
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo consultar tus informes.');
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
      final pdf = XFile.fromData(bytes, name: name, mimeType: 'application/pdf');
      if (kIsWeb) {
        await pdf.saveTo(name);
      } else {
        final target = await getSaveLocation(suggestedName: name);
        if (target == null) return;
        await pdf.saveTo(target.path);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Descarga solicitada. Revisa tus archivos.')),
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
      if (!mounted || !widget.api.hasSession) return;
      final response = Map<String, dynamic>.from(result['response'] as Map);
      final answer = response['answer'] as String?;
      if (answer == null || answer.isEmpty) {
        throw const AuthFailure('El asistente no entregó una respuesta válida.');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 30),
        Text('Asistente educativo — IA local',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Pregunta qué significa un examen o para qué se mide. '
          'El asistente conoce las prestaciones de esta orden, pero '
          'todavía NO lee los valores del PDF. No realiza diagnósticos '
          'ni prescribe tratamientos.',
        ),
        const SizedBox(height: 12),
        for (final turn in turns) ...[
          Align(
            alignment: turn['role'] == 'user'
                ? Alignment.centerRight : Alignment.centerLeft,
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
                          turn['source'] == 'modelo_local'
                              ? 'Modelo de IA local'
                              : 'Biblioteca educativa de Vitalia',
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
        TextField(
          controller: _question,
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
            onPressed: _chatBusyReport == null ? () => _askChat(id) : null,
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(working ? 'Consultando…' : 'Preguntar al asistente'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Orientación educativa, no validada clínicamente. '
          'Para conocer tus cifras consulta el PDF original. '
          'El historial de esta conversación no se guarda en la base de datos.',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitalia Health'),
        actions: [
          TextButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Mis informes', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text('Paciente: ${widget.email}'),
                  const SizedBox(height: 10),
                  const Text('Consulta los PDF publicados por el laboratorio '
                      'y autorizados previamente fuera de Vitalia.'),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar informes'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 12),
                  ],
                  if (!_loading && _reports.isEmpty && _error == null)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(26),
                        child: Text('Aún no tienes informes publicados por el laboratorio.'),
                      ),
                    ),
                  for (final report in _reports)
                    Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              const Icon(Icons.picture_as_pdf_outlined),
                              const SizedBox(width: 12),
                              Expanded(child: Text(report['fileName'] as String,
                                  style: theme.textTheme.titleMedium)),
                            ]),
                            const SizedBox(height: 10),
                            Text('Orden: ${report['orderNumber']}'),
                            Text('Laboratorio: ${report['issuingLaboratory']}'),
                            Text('Autorizado externamente: ${_date(report['externallyAuthorizedAt'])}'),
                            Text('Disponible desde: ${_date(report['publishedAt'])}'),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                onPressed: _downloading != null ? null
                                    : () => _download(report),
                                icon: const Icon(Icons.download_outlined),
                                label: Text(_downloading == report['id']
                                    ? 'Preparando descarga…' : 'Descargar PDF'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _chatBusyReport != null
                                    ? null : () => _toggleChat(report['id'] as String),
                                icon: const Icon(Icons.smart_toy_outlined),
                                label: Text(_activeChatReport == report['id']
                                    ? 'Cerrar asistente educativo'
                                    : 'Consultar con IA educativa'),
                              ),
                            ),
                            if (_activeChatReport == report['id'])
                              _chatPanel(report),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Esta sección muestra documentos de prueba. '
                    'No constituye una plataforma clínica habilitada para uso real.',
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
