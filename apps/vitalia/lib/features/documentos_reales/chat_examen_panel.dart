import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'chat_examen_api.dart';

class ChatExamenPanel extends StatefulWidget {
  const ChatExamenPanel({super.key, required this.auth, required this.documentId,
    required this.reviewedExtraction, required this.onExpired, this.autoOpen = false});
  final bool autoOpen;
  final AuthApi auth;
  final String documentId;
  final Map<String, dynamic> reviewedExtraction;
  final VoidCallback onExpired;
  @override
  State<ChatExamenPanel> createState() => _ChatExamenPanelState();
}
class _ChatExamenPanelState extends State<ChatExamenPanel> {
  final _question = TextEditingController();
  final _composer = GlobalKey();
  bool _sending = false;
  void _showLatest() {
    if (!widget.autoOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _composer.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, alignment: 1,
          duration: const Duration(milliseconds: 250));
      }
    });
  }
  List<Map<String, dynamic>> _turns = [];
  String? _error, _lastId, _lastQuestion;
  bool _busy = false, _opened = false, _available = false;
  @override
  void initState() {
    super.initState();
    if (widget.autoOpen) WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }
  @override
  void dispose() { _question.dispose(); super.dispose(); }
  void _validateReferences(List<Map<String, dynamic>> turns) {
    final rows = widget.reviewedExtraction['resultados'] as List;
    for (final turn in turns) {
      final reply = turn['response'] as Map<String, dynamic>?;
      if (reply != null && (reply['indices'] as List).any((i) => i >= rows.length)) throw const FormatException();
    }
  }
  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final data = await ChatExamenApi(widget.auth).consultar(widget.documentId);
      final turns = (data['turns'] as List).cast<Map<String, dynamic>>();
      _validateReferences(turns);
      if (mounted) setState(() { _available = data['status'] == 'available'; _turns = _available ? turns : []; _opened = true; });
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() { _available = false; _error = 'No se pudo consultar esta conversación.'; }); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  void _failure(AuthFailure error) {
    if (!mounted) return;
    if (error.status == 401) {
      setState(() { _turns = []; _available = false; });
      widget.onExpired();
    } else {
      setState(() {
        if (error.status == 403 || error.status == 404) { _turns = []; _available = false; }
        else if (error.status != 503) { _available = false; }
        _error = error.message;
      });
    }
  }
  Future<void> _recoverAfterFailure() async {
    // Solo consultar: nunca repetir la generación automáticamente.
    try {
      final data = await ChatExamenApi(widget.auth).consultar(widget.documentId);
      final turns = (data['turns'] as List).cast<Map<String, dynamic>>();
      _validateReferences(turns);
      if (!mounted) return;
      setState(() {
        _available = data['status'] == 'available';
        _turns = _available ? turns : [];
        final completed = turns.where((turn) => turn['id'] == _lastId && turn['status'] != 'pending');
        if (completed.isNotEmpty) {
          _error = completed.first['status'] == 'failed'
            ? 'No se obtuvo una respuesta aceptable. La conversación sigue abierta; puedes reformular tu pregunta.' : null;
          _lastId = null; _lastQuestion = null;
        }
        if (!_available) _error = null;
      });
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() { _available = false; _error = 'No se pudo validar la conversación. Actualiza antes de continuar.'; }); }
  }
  Future<void> _send() async {
    final question = _question.text.trim();
    if (_busy || question.isEmpty) return;
    final requestId = _lastQuestion == question && _lastId != null ? _lastId! : nuevaSolicitudChat();
    _lastQuestion = question; _lastId = requestId;
    setState(() { _busy = true; _sending = true; _error = null; });
    FocusManager.instance.primaryFocus?.unfocus();
    _showLatest();
    try {
      final api = ChatExamenApi(widget.auth);
      final turn = await api.preguntar(widget.documentId, requestId, question);
      _validateReferences([turn]);
      if (!mounted) return;
      setState(() {
        _turns = [..._turns.where((t) => t['id'] != turn['id']), turn];
        if (turn['status'] != 'pending') { _lastId = null; _lastQuestion = null; _question.clear(); }
      });
    } on AuthFailure catch (error) {
      _failure(error);
      if (error.status == 503) await _recoverAfterFailure();
    }
    catch (_) { if (mounted) setState(() { _available = false; _error = 'No se pudo aceptar la respuesta. Actualiza la conversación.'; }); }
    finally {
      if (mounted) {
        setState(() { _busy = false; _sending = false; });
        _showLatest();
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final rows = widget.reviewedExtraction['resultados'] as List;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      Text('Preguntas sobre este examen', style: Theme.of(context).textTheme.titleMedium),
      const Text('La IA puede equivocarse. Usa solo los datos revisados de este documento; no diagnostica ni recomienda tratamientos. Las respuestas no están aprobadas por un profesional.'),
      TextButton(onPressed: _busy ? null : _load,
        child: Text(_opened ? 'Actualizar conversación' : 'Abrir conversación')),
      if (_busy && !_sending) ...[
        const LinearProgressIndicator(),
        const Text('Cargando la conversación de este examen…'),
      ],
      if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
      if (_opened && !_available && _error == null) const Text('Se requiere una revisión profesional aprobada.'),
      for (final turn in _turns) ...[
        Align(alignment: Alignment.centerRight, child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.only(top: 16, bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tu pregunta', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8), SelectableText(turn['question'] as String),
          ]),
        )),
        Align(alignment: Alignment.centerLeft, child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(18),
          ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.auto_awesome_outlined),
            const SizedBox(height: 8),
            const Text('Respuesta de IA, sin aprobación profesional'),
            const SizedBox(height: 8),
            if (turn['status'] == 'pending') const Text('Respuesta pendiente. Actualiza la conversación antes de repetir.'),
            if (turn['status'] == 'failed') const Text('No se obtuvo una respuesta aceptable. Puedes enviar una nueva solicitud.'),
            if (turn['response'] != null) ...[
              SelectableText(turn['response']['answer'] as String),
              const SizedBox(height: 12),
              for (final index in turn['response']['indices'] as List) SelectableText(
                'Dato revisado: ${rows[index]['nombre'] ?? 'Sin nombre'} — ${rows[index]['valor'] ?? 'No disponible'} ${rows[index]['unidad'] ?? ''}'),
            ],
          ]),
        )),
      ],
      if (_available) ...[
        if (_sending) Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tu pregunta enviada'),
            const SizedBox(height: 8),
            Text(_lastQuestion ?? ''),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Vitalia está preparando una respuesta sobre este examen. Puede tardar hasta dos minutos.'),
          ]),
        ),
        const SizedBox(height: 16),
        if (_turns.isEmpty) Wrap(spacing: 8, runSpacing: 8, children: [
          for (final suggestion in ['¿Qué significa rango de referencia?', '¿Cuál es la fecha del examen?'])
            ActionChip(label: Text(suggestion), onPressed: _busy ? null : () {
              setState(() => _question.text = suggestion);
            }),
        ]),
        const SizedBox(height: 16),
        const Text('Hasta treinta preguntas por examen; solo las últimas seis respuestas educativas se usan como contexto.'),
        const SizedBox(height: 12),
        TextField(key: _composer, controller: _question, enabled: !_busy, maxLength: 500, minLines: 1, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Pregunta sobre este examen',
            hintText: 'Escribe aquí tu duda', prefixIcon: Icon(Icons.chat_bubble_outline))),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _send,
          icon: const Icon(Icons.send_outlined), label: const Text('Enviar pregunta')),
      ],
    ]);
  }
}

class ChatExamenPage extends StatelessWidget {
  const ChatExamenPage({super.key, required this.auth, required this.documentId,
    required this.reviewedExtraction, required this.onExpired});
  final AuthApi auth;
  final String documentId;
  final Map<String, dynamic> reviewedExtraction;
  final VoidCallback onExpired;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Asistente de Vitalia')),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(reviewedExtraction['examen'] as String? ?? 'Examen abierto',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Esta conversación corresponde únicamente a este examen.'),
          ChatExamenPanel(auth: auth, documentId: documentId,
            reviewedExtraction: reviewedExtraction, onExpired: onExpired, autoOpen: true),
        ]),
      ))),
    ),
  );
}
