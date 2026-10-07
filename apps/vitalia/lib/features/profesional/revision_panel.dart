import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'revision_api.dart';
import 'profesional_api.dart';
import 'extraccion_panel.dart';

class RevisionPanel extends StatefulWidget {
  const RevisionPanel({super.key, required this.auth, required this.patientId,
    required this.documentId, required this.onFailure, required this.onSaving});
  final AuthApi auth;
  final String patientId;
  final String documentId;
  final void Function(AuthFailure) onFailure;
  final void Function(bool) onSaving;
  @override
  State<RevisionPanel> createState() => _RevisionPanelState();
}
class _ReviewRow {
  _ReviewRow(Map<String, dynamic> row) : fields = {
    for (final key in ['nombre', 'valor', 'unidad', 'rango_referencia'])
      key: TextEditingController(text: row[key] as String? ?? ''),
  };
  final Map<String, TextEditingController> fields;
  Map<String, dynamic> data() => {for (final field in fields.entries)
    field.key: field.value.text.trim().isEmpty ? null : field.value.text};
  void dispose() { for (final field in fields.values) { field.dispose(); } }
}
class _RevisionPanelState extends State<RevisionPanel> {
  final _exam = TextEditingController();
  final _date = TextEditingController();
  final _observations = TextEditingController();
  final List<_ReviewRow> _rows = [];
  String? _processingId;
  String? _error;
  Map<String, dynamic>? _saved;
  bool _canReview = false;
  bool _confirmed = false;
  bool _busy = false;
  RevisionApi get _api => RevisionApi(widget.auth);
  @override
  void initState() { super.initState(); _load(); }
  void _clearRows({bool deferred = false}) {
    for (final row in _rows) {
      if (deferred) { WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose()); }
      else { row.dispose(); }
    }
    _rows.clear();
  }
  @override
  void dispose() { _clearRows(); _exam.dispose(); _date.dispose(); _observations.dispose(); super.dispose(); }
  void _failure(AuthFailure error) {
    if (!mounted) return;
    if ([401, 403, 404].contains(error.status)) { widget.onFailure(error); return; }
    setState(() { _error = error.message; if (error.status != 400) _canReview = false; });
  }
  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _canReview = false; _saved = null; _confirmed = false; });
    try {
      final data = await _api.consultar(widget.patientId, widget.documentId);
      if (!mounted) return;
      _clearRows(deferred: true);
      _processingId = data['processingId'] as String?;
      final original = data['originalExtraction'] as Map<String, dynamic>?;
      _exam.text = original?['examen'] as String? ?? '';
      _date.text = original?['fecha'] as String? ?? '';
      _observations.clear();
      if (original != null) {
        for (final row in original['resultados'] as List) { _rows.add(_ReviewRow(row as Map<String, dynamic>)); }
      }
      setState(() { _canReview = data['canReview'] == true; _saved = data['review'] as Map<String, dynamic>?; });
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() => _error = 'No se pudo preparar la revisión.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _save() async {
    if (_busy || !_canReview || !_confirmed || _processingId == null) return;
    setState(() { _busy = true; _error = null; });
    widget.onSaving(true);
    try {
      final saved = await _api.aprobar(widget.patientId, widget.documentId,
        processingId: _processingId!, extraction: {
          'examen': _exam.text.trim().isEmpty ? null : _exam.text,
          'fecha': _date.text.trim().isEmpty ? null : _date.text,
          'resultados': _rows.map((row) => row.data()).toList(),
        }, observations: _observations.text, confirmedOriginal: _confirmed);
      if (mounted) setState(() { _saved = saved; _canReview = false; });
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() { _error = 'No se pudo guardar. Actualiza la revisión antes de repetir.'; _canReview = false; }); }
    finally { if (mounted) { setState(() => _busy = false); widget.onSaving(false); } }
  }
  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller, enabled: !_busy, maxLength: 500,
    decoration: InputDecoration(labelText: label));
  String _dateLabel(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return 'Fecha no disponible';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }
  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 20),
      Text('Revisión profesional', style: Theme.of(context).textTheme.titleLarge),
      const Text('La extracción original se conserva. Aprobar guarda una copia revisada que no se sobrescribe. No se guardan borradores.'),
      TextButton(onPressed: _busy ? null : _load, child: const Text('Actualizar revisión')),
      if (_busy) const Center(child: CircularProgressIndicator()),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (saved != null) ...[
        const Text('Revisión aprobada y registrada'),
        Text('Profesional: ${saved['reviewerEmail']}'),
        Text('Fecha de revisión: ${_dateLabel(saved['reviewedAt'] as String)}'),
        Text('Observaciones: ${saved['observations']}'),
        ExtraccionPanel(value: ExtraccionPendiente('requires_review', null,
          saved['extraction'] as Map<String, dynamic>, []), reviewed: true),
      ] else if (!_busy && _canReview) ...[
        const Text('Corrige solo lo comprobado en el original. Un campo vacío se guarda como dato ausente; no se interpreta como cero.'),
        _field(_exam, 'Examen revisado'),
        _field(_date, 'Fecha revisada (DD-MM-AAAA)'),
        ..._rows.asMap().entries.map((entry) => Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Resultado ${entry.key + 1}'),
            _field(entry.value.fields['nombre']!, 'Nombre del indicador'),
            _field(entry.value.fields['valor']!, 'Valor'),
            _field(entry.value.fields['unidad']!, 'Unidad'),
            _field(entry.value.fields['rango_referencia']!, 'Rango de referencia'),
            TextButton(onPressed: _busy ? null : () => setState(() { final row = _rows.removeAt(entry.key); WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose()); }),
              child: const Text('Quitar resultado')),
          ])))),
        TextButton(onPressed: _busy || _rows.length >= 100 ? null
          : () => setState(() => _rows.add(_ReviewRow({}))), child: const Text('Añadir resultado')),
        TextField(controller: _observations, enabled: !_busy, maxLength: 2000, minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Motivo de correcciones o datos ausentes',
            helperText: 'Obligatorio si corriges datos o conservas campos ausentes.')),
        CheckboxListTile(value: _confirmed, onChanged: _busy ? null
          : (value) => setState(() => _confirmed = value ?? false), contentPadding: EdgeInsets.zero,
          title: const Text('Confirmo que cotejé estos datos con el documento original.')),
        FilledButton(onPressed: _busy || !_confirmed ? null : _save,
          child: const Text('Aprobar y guardar revisión')),
      ] else if (!_busy && _error == null)
        const Text('Este documento todavía no tiene una extracción disponible para revisar.'),
    ]);
  }
}
