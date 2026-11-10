import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';
import 'clave_recuperacion_sil_dialog.dart';
import 'resumen_informes_sil_page.dart';
import 'sil_workspace.dart';
import 'portal_visual_sil.dart';
import 'portal_ayuda_sil.dart';

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
  static const _mainSil =
      bool.fromEnvironment('VITALIA_SIL_MAIN_MODE',defaultValue:false);
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
  late Future<Map<String, dynamic>> _profileRequest;
  final _reportsAnchor = GlobalKey();
  final _pageScroll = ScrollController();
  bool _reportsTabSelected = false;

  @override
  void dispose() {
    _question.dispose();
    _filter.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _profileRequest = widget.api.silRequest('/patient/profile');
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
      if (mounted) {
        setState(() => _error = 'No se pudo consultar tus informes.');
      }
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

  bool _simpleReading = false;

  Widget _profileField(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ColoresVitalia.fondoAzul,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColoresVitalia.bordeTenue),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ColoresVitalia.azul, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: ColoresVitalia.textoSecundario,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ColoresVitalia.texto,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile() {
    final request = _profileRequest;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => FutureBuilder<Map<String, dynamic>>(
        future: request,
        builder: (context, snapshot) {
          final profile = snapshot.data?['profile'] as Map?;
          final hasProfile = profile?['hasProfile'] == true;
          final name = hasProfile
              ? [profile?['givenNames'], profile?['familyNames']]
                  .whereType<String>()
                  .join(' ')
                  .trim()
              : '';
          final expired = snapshot.error is AuthFailure &&
              (snapshot.error as AuthFailure).status == 401;
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650, maxHeight: 750),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(23),
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF1C465D),
                            Color(0xFF2D7B80),
                          ],
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CircleAvatar(
                            radius: 28,
                            backgroundColor: Color(0x33FFFFFF),
                            child: Icon(Icons.person_outline,
                                color: Colors.white, size: 29),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Mi perfil',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  name.isEmpty ? 'Tu cuenta privada' : name,
                                  style: const TextStyle(
                                    color: Color(0xFFE3F2F2),
                                    height: 1.4,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _mainSil
                                    ? 'Cuenta activa · Vitalia Health'
                                    : 'Cuenta activa · Paciente DEMO',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(21),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            const LinearProgressIndicator()
                          else if (snapshot.hasError)
                            Text(
                              expired
                                  ? 'Tu sesión terminó. Vuelve a ingresar.'
                                  : 'No pudimos cargar tu ficha. '
                                      'Intenta abrir Mi perfil otra vez.',
                            )
                          else ...[
                            _profileField(
                              Icons.alternate_email,
                              'Correo de acceso',
                              widget.email,
                            ),
                            const SizedBox(height: 10),
                            if (hasProfile) ...[
                              _profileField(
                                Icons.person_outline,
                                'Nombre',
                                name,
                              ),
                              const SizedBox(height: 10),
                              _profileField(
                                Icons.cake_outlined,
                                'Fecha de nacimiento',
                                _date(profile?['birthDate']),
                              ),
                              if (profile?['identifier']
                                  case final String identifier
                                  when identifier.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _profileField(
                                  Icons.badge_outlined,
                                  'Identificador DEMO',
                                  identifier,
                                ),
                              ],
                              if (profile?['phone']
                                  case final String phone
                                  when phone.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _profileField(
                                  Icons.phone_outlined,
                                  'Teléfono',
                                  phone,
                                ),
                              ],
                            ] else ...[
                              const SizedBox(height: 14),
                              const Text(
                                'Tu cuenta web aún no tiene una ficha '
                                'asociada por el laboratorio.',
                              ),
                            ],
                          ],
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: ColoresVitalia.verdeSuave,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Los datos de esta ficha los administra el '
                              'laboratorio. Si detectas un error, solicita '
                              'su revisión por un canal oficial.',
                              style: TextStyle(
                                color: ColoresVitalia.texto,
                                height: 1.45,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 7,
                            children: [
                              if (!expired)
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    PortalAyudaSil.contacto(
                                      this.context,
                                      _reports,
                                    );
                                  },
                                  icon: const Icon(Icons.support_agent_outlined),
                                  label: const Text('Ayuda con mis datos'),
                                ),
                              FilledButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  if (expired && mounted) widget.onExpired();
                                },
                                child: Text(
                                  expired ? 'Volver a ingresar' : 'Cerrar',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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
    if (_chatBusyReport != null || question.length < 3 || question.length > 400) {
      return;
    }
    setState(() {
      _chatBusyReport = reportId;
      _chatError = null;
    });
    try {
      final result = await widget.api.silRequest(
        '/patient/reports/$reportId/chat',
        body: {'question': question, if (_simpleReading) 'simple': true},
      );
      if (!mounted || !widget.api.hasSession || _activeChatReport != reportId) {
        return;
      }
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
      ('Mis resultados', '¿Cuáles son mis resultados?'),
      ('Observación médica', '¿Qué dice la observación de la derivación?'),
      ('¿Qué datos veo?', '¿Qué datos tengo?'),
      ('¿Quién pidió el examen?', '¿Quién me pidió estos exámenes?'),
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
          'Escribe tu pregunta o elige un ejemplo. Usa Lectura fácil para explicaciones más directas. Evita escribir datos personales.',
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Lectura fácil'),
          value: _simpleReading,
          onChanged: working
              ? null
              : (value) => setState(() => _simpleReading = value),
        ),
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
                            'informe' => 'Datos de este informe',
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
          'Coteja las cifras detectadas con el PDF. El asistente explica conceptos generales. '
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

  void _openOverview([String? reportId]) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ResumenInformesSilPage(
        api: widget.api,
        reports: List.of(_reports),
        onExpired: widget.onExpired,
        initialReportId: reportId,
      ),
    ));
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final theme = Theme.of(context);
    final exams = _examNames(report);
    final id = report['id'] as String;
    final chatOpen = _activeChatReport == id;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: ColoresVitalia.azulSuave,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: ColoresVitalia.azul,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exams.isEmpty
                            ? report['fileName'] as String
                            : exams.join(' · '),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ColoresVitalia.texto,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${report['issuingLaboratory']}',
                        style: const TextStyle(
                          color: ColoresVitalia.textoSecundario,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  avatar: const Icon(Icons.verified_outlined, size: 16),
                  label: const Text('Publicado'),
                  backgroundColor: ColoresVitalia.verdeSuave,
                  side: BorderSide.none,
                ),
                Chip(
                  avatar: const Icon(Icons.tag_outlined, size: 16),
                  label: Text('Orden ${report['orderNumber']}'),
                ),
                Chip(
                  avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                  label: Text(_date(report['publishedAt'])),
                ),
              ],
            ),
            if (report['prescriberName'] != null ||
                report['requestDate'] != null ||
                report['documentReference'] != null) ...[
              const Divider(height: 24),
              if (report['prescriberName'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('Solicitó: ${report['prescriberName']}'),
                ),
              if (report['requestDate'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Fecha de solicitud: ${_date(report['requestDate'])}',
                  ),
                ),
              if (report['documentReference'] != null)
                Text(
                  'Referencia de solicitud: ${report['documentReference']}',
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _openOverview(id),
                  icon: const Icon(Icons.analytics_outlined, size: 19),
                  label: const Text('Ver resultados'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _downloading == null ? () => _download(report) : null,
                  icon: const Icon(Icons.download_outlined, size: 19),
                  label: Text(
                    _downloading == id
                        ? 'Preparando descarga…'
                        : 'Descargar PDF',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _chatBusyReport == null ? () => _toggleChat(id) : null,
                  icon: const Icon(Icons.chat_bubble_outline, size: 19),
                  label: Text(
                    chatOpen ? 'Cerrar asistente' : 'Preguntar sobre el informe',
                  ),
                ),
              ],
            ),
            if (chatOpen) _chatPanel(report),
          ],
        ),
      ),
    );
  }

  Widget _portalTools(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(21),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: ColoresVitalia.verdeSuave,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _reports.length >= 2
                          ? Icons.compare_arrows_outlined
                          : Icons.menu_book_outlined,
                      color: ColoresVitalia.verde,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _reports.length >= 2
                        ? 'Compara tus informes'
                        : 'Una lectura con más claridad',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _reports.length >= 2
                        ? 'Selecciona hasta cuatro documentos publicados. '
                            'Comparamos cifras solo cuando el examen, '
                            'analito, unidad y laboratorio coinciden.'
                        : 'Tu informe puede incluir cifras y términos '
                            'difíciles. Conoce cómo revisarlo, qué '
                            'significan las unidades y cuándo consultar '
                            'al laboratorio.',
                    style: const TextStyle(
                      color: ColoresVitalia.textoSecundario,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _reports.length >= 2
                          ? () => _openOverview()
                          : () => PortalAyudaSil.preguntasFrecuentes(context),
                      icon: Icon(
                        _reports.length >= 2
                            ? Icons.compare_arrows_outlined
                            : Icons.help_outline,
                      ),
                      label: Text(
                        _reports.length >= 2
                            ? 'Comparar informes'
                            : 'Cómo leer mis resultados',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tu recorrido en Vitalia',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final step in const [
                    (
                      Icons.file_copy_outlined,
                      'Abre un informe',
                      'Encuentra su orden y fecha de publicación.',
                    ),
                    (
                      Icons.query_stats_outlined,
                      'Consulta sus cifras',
                      'Comprueba los valores en el PDF original.',
                    ),
                    (
                      Icons.forum_outlined,
                      'Resuelve tus dudas',
                      'Pregunta por los términos del documento.',
                    ),
                  ]) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(step.$1,
                            color: ColoresVitalia.azul, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(step.$2,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(step.$3,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: ColoresVitalia.textoSecundario)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: ColoresVitalia.azulSuave,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ColoresVitalia.borde),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined,
                    color: ColoresVitalia.azul, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Espacio privado: únicamente se muestran informes '
                    'publicados para tu cuenta. Las explicaciones son '
                    'educativas, no diagnósticos.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: ColoresVitalia.texto,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _reportList(ThemeData theme, String query,
          List<Map<String, dynamic>> visibleReports) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        ],
      );

  void _accountAction(String action) {
    switch (action) {
      case 'profile':
        _openProfile();
        break;
      case 'refresh':
        if (!_loading) _refresh();
        break;
      case 'recovery':
        _openRecovery();
        break;
      case 'logout':
        widget.onLogout();
        break;
      case 'help':
        PortalAyudaSil.preguntasFrecuentes(context);
        break;
      case 'contact':
        PortalAyudaSil.contacto(context, _reports);
        break;
    }
  }

  Widget _accountMenu({bool includeProfileAndRefresh = true}) =>
      PopupMenuButton<String>(
        tooltip: 'Mi cuenta',
        icon: FutureBuilder<Map<String, dynamic>>(
          future: _profileRequest,
          builder: (context, snapshot) {
            final profile = snapshot.data?['profile'] as Map?;
            final names = profile?['hasProfile'] == true
                ? (profile?['givenNames'] as String? ?? '').trim()
                : '';
            final initial = names.isNotEmpty
                ? names.substring(0, 1).toUpperCase()
                : 'P';
            return CircleAvatar(
              radius: 18,
              backgroundColor: ColoresVitalia.azulSuave,
              child: Text(
                initial,
                style: const TextStyle(
                  color: ColoresVitalia.azulActivo,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          },
        ),
        onSelected: _accountAction,
        itemBuilder: (context) => [
          if (includeProfileAndRefresh) ...[
            const PopupMenuItem(
              value: 'profile',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.person_outline),
                title: Text('Mi perfil'),
              ),
            ),
            const PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.refresh),
                title: Text('Actualizar informes'),
              ),
            ),
          ],
          const PopupMenuItem(
              value: 'recovery',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.key_outlined),
                title: Text('Configurar recuperación'),
              ),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'help',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.help_outline),
              title: Text('Centro de ayuda'),
            ),
          ),
          const PopupMenuItem(
            value: 'contact',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.support_agent_outlined),
              title: Text('Contacto del laboratorio'),
            ),
          ),
        ],
      );

  Widget _patientGreeting() => FutureBuilder<Map<String, dynamic>>(
        future: _profileRequest,
        builder: (context, snapshot) {
          final profile = snapshot.data?['profile'] as Map?;
          final rawName = profile?['hasProfile'] == true
              ? (profile?['givenNames'] as String? ?? '').trim()
              : '';
          final firstName = rawName.isEmpty
              ? ''
              : rawName.split(RegExp(r'\s+')).first;
          return PortalHeroSil(
            eyebrow: _mainSil ? 'Tu espacio personal · Vitalia Health' : 'Tu espacio personal · SIL DEMO',
            title: firstName.isEmpty
                ? 'Hola, bienvenido a Vitalia'
                : 'Hola, $firstName',
            subtitle: 'Tus informes publicados, sus documentos originales '
                'y una guía sencilla para comprenderlos. '
                'Toda tu información de laboratorio en un espacio privado.',
            icon: Icons.favorite_outline,
            compact: MediaQuery.sizeOf(context).width < 600,
            action: FilledButton.icon(
              onPressed: _scrollToReports,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: ColoresVitalia.azulActivo,
                disabledBackgroundColor: const Color(0xFFD2E4EA),
                disabledForegroundColor: ColoresVitalia.azulActivo,
              ),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Ir a mis informes'),
            ),
          );
        },
      );

  void _scrollToTop() {
    if (mounted) setState(() => _reportsTabSelected = false);
    if (_pageScroll.hasClients) {
      _pageScroll.animateTo(0,
        duration: const Duration(milliseconds: 330),
        curve: Curves.easeOutCubic);
    }
  }

  void _scrollToReports() {
    if (mounted) setState(() => _reportsTabSelected = true);
    final destination = _reportsAnchor.currentContext;
    if (destination != null) {
      Scrollable.ensureVisible(
        destination,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.07,
      );
    }
  }

  Widget _dashboardIndicators() => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 880
              ? 3
              : constraints.maxWidth >= 540
                  ? 2
                  : 1;
          final cardWidth = (constraints.maxWidth -
                  (columns - 1) * 12) /
              columns;
          final publishedDates = _reports
              .map((report) => DateTime.tryParse(
                    '${report['publishedAt'] ?? ''}',
                  ))
              .whereType<DateTime>()
              .toList()
            ..sort();
          final lastPublished = publishedDates.isEmpty
              ? '—'
              : _date(publishedDates.last.toIso8601String());
          final indicators = [
            PortalIndicadorSil(
              icon: Icons.description_outlined,
              label: 'Informes disponibles',
              value: _loading ? '…' : '${_reports.length}',
              detail: 'Documentos publicados para tu cuenta.',
              onTap: _scrollToReports,
            ),
            PortalIndicadorSil(
              icon: Icons.event_available_outlined,
              label: 'Última publicación',
              value: lastPublished,
              detail: 'Fecha informada por el laboratorio.',
              accent: ColoresVitalia.verde,
            ),
            PortalIndicadorSil(
              icon: Icons.query_stats_outlined,
              label: 'Consulta conjunta',
              value: _reports.length >= 2 ? 'Hasta 4' : 'Desde 2',
              detail: _reports.length >= 2
                  ? 'Compara mediciones cuando sean compatibles.'
                  : 'Disponible cuando tengas al menos dos informes.',
              onTap: _reports.length >= 2 ? () => _openOverview() : null,
            ),
          ];
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final indicator in indicators)
                SizedBox(width: cardWidth, child: indicator),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 600;
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 79,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1C485E),
                  Color(0xFF3BA4A0),
                  Color(0xFFE2F0ED),
                ],
              ),
            ),
          ),
        ),
        title: const SilWorkspaceBrand(),
        actions: [
          IconButton(
            tooltip: 'Actualizar informes',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_outlined),
          ),
          _accountMenu(),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SilWorkspaceTopNavigation(
              label: 'Navegación del paciente',
              tabs: [
                SilWorkspaceTab(
                  label: 'Inicio', icon: Icons.home_outlined,
                  selected: !_reportsTabSelected,
                  onPressed: _scrollToTop,
                ),
                SilWorkspaceTab(
                  label: 'Mis informes', icon: Icons.description_outlined,
                  selected: _reportsTabSelected,
                  onPressed: _scrollToReports,
                ),
                SilWorkspaceTab(
                  label: 'Explorar resultados', icon: Icons.query_stats_outlined,
                  selected: false,
                  onPressed: _reports.isEmpty ? null : () => _openOverview(),
                ),
                SilWorkspaceTab(
                  label: 'Ayuda', icon: Icons.help_outline,
                  selected: false,
                  onPressed: () => PortalAyudaSil.preguntasFrecuentes(context),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _pageScroll,
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 14 : 25,
            vertical: narrow ? 17 : 26,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1230),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _patientGreeting(),
                  const SizedBox(height: 16),
                  _dashboardIndicators(),
                  const SizedBox(height: 28),
                  const PortalEncabezadoSeccionSil(
                    title: 'Tus documentos y herramientas',
                    subtitle:
                        'Consulta los archivos publicados y utiliza las '
                        'herramientas que necesites.',
                  ),
                  const SizedBox(height: 15),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final reports = KeyedSubtree(
                        key: _reportsAnchor,
                        child: _reportList(
                          theme,
                          query,
                          visibleReports,
                        ),
                      );
                      final tools = _portalTools(theme);
                      if (constraints.maxWidth >= 850) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: reports),
                            const SizedBox(width: 18),
                            Expanded(flex: 4, child: tools),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          reports,
                          const SizedBox(height: 16),
                          tools,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 43),
                  PortalAyudaFooterSil(
                    reports: _reports,
                    onProfile: _openProfile,
                    onRecovery: _openRecovery,
                    onReports: _scrollToReports,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _mainSil
                        ? 'Vitalia Health · Integración en revisión · '
                            'No utilizar datos clínicos reales antes de la validación.'
                        : 'Vitalia Health · Proyecto académico · '
                            'Entorno con datos ficticios.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}
