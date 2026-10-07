import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'chat_examen_api.dart';

class ChatExamenPanel extends StatefulWidget {
  const ChatExamenPanel({super.key, required this.auth, required this.documentId,
    required this.reviewedExtraction, required this.onExpired});
  final AuthApi auth;
  final String documentId;
  final Map<String, dynamic> reviewedExtraction;
  final VoidCallback onExpired;
  @override
  State<ChatExamenPanel> createState() => _ChatExamenPanelState();
}
class _ChatExamenPanelState extends State<ChatExamenPanel> {
  final _question = TextEditingController();
  List<Map<String, dynamic>> _turns = [];
  String? _error, _lastId, _lastQuestion;
  bool _busy = false, _opened = false, _available = false;
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
    setState(() { _busy = true; _turns = []; _error = null; _available = false; });
    try {
      final data = await ChatExamenApi(widget.auth).consultar(widget.documentId);
      final turns = (data['turns'] as List).cast<Map<String, dynamic>>();
      _validateReferences(turns);
      if (mounted) setState(() { _turns = turns; _opened = true; _available = data['status'] == 'available'; });
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() => _error = 'No se pudo consultar esta conversación.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  void _failure(AuthFailure error) {
    if (!mounted) return;
    if (error.status == 401) { widget.onExpired(); }
    else { setState(() { _turns = []; _available = false; _error = error.message; }); }
  }
  Future<void> _send() async {
    final question = _question.text.trim();
    if (_busy || question.isEmpty) return;
    final requestId = _lastQuestion == question && _lastId != null ? _lastId! : nuevaSolicitudChat();
    _lastQuestion = question; _lastId = requestId;
    setState(() { _busy = true; _error = null; });
    try {
      final api = ChatExamenApi(widget.auth);
      final turn = await api.preguntar(widget.documentId, requestId, question);
      _validateReferences([turn]);
      if (!mounted) return;
      setState(() {
        _turns = [..._turns.where((t) => t['id'] != turn['id']), turn];
        if (turn['status'] != 'pending') { _lastId = null; _lastQuestion = null; _question.clear(); }
      });
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() { _turns = []; _available = false; _error = 'No se pudo aceptar la respuesta. Actualiza la conversación.'; }); }
    finally { if (mounted) setState(() => _busy = false); }
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
      if (_busy) const Text('El asistente está trabajando. Puede tardar hasta dos minutos.'),
      if (_error != null) Text(_error!),
      if (_opened && !_available && _error == null) const Text('Se requiere una revisión profesional aprobada.'),
      for (final turn in _turns) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tu pregunta'), SelectableText(turn['question'] as String),
          const SizedBox(height: 8), const Text('Respuesta de IA, sin aprobación profesional'),
          if (turn['status'] == 'pending') const Text('Respuesta pendiente. Actualiza la conversación antes de repetir.'),
          if (turn['status'] == 'failed') const Text('No se obtuvo una respuesta aceptable. Puedes enviar una nueva solicitud.'),
          if (turn['response'] != null) ...[
            SelectableText(turn['response']['answer'] as String),
            for (final index in turn['response']['indices'] as List) SelectableText(
              'Dato revisado: ${rows[index]['nombre'] ?? 'Sin nombre'} — ${rows[index]['valor'] ?? 'No disponible'} ${rows[index]['unidad'] ?? ''}'),
          ],
        ]))),
      if (_available) ...[
        const Text('Hasta treinta preguntas por examen; solo las últimas seis respuestas educativas se usan como contexto.'),
        TextField(controller: _question, enabled: !_busy, maxLength: 500, minLines: 1, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Pregunta sobre este examen')),
        FilledButton(onPressed: _busy ? null : _send, child: const Text('Enviar pregunta')),
      ],
    ]);
  }
}
