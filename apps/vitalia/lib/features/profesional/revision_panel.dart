import '../documentos_reales/informe_fields.dart';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'revision_api.dart';
import 'profesional_api.dart';
import 'extraccion_panel.dart';

class RevisionPanel extends StatefulWidget {
  const RevisionPanel({super.key, required this.auth, required this.patientId,
    required this.documentId, this.processingStatus, required this.onFailure, required this.onSaving});
  final AuthApi auth;
  final String patientId;
  final String documentId;
  final String? processingStatus;
  final void Function(AuthFailure) onFailure;
  final void Function(bool) onSaving;
  @override
  State<RevisionPanel> createState() => _RevisionPanelState();
}
class _ReviewRow {
  _ReviewRow(Map<String, dynamic> row) : fields = {
    for (final key in ['nombre', 'valor', 'unidad', 'rango_referencia', if (row.containsKey('estado_documento')) 'estado_documento'])
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
  final _report = <String, TextEditingController>{
    for (final key in informeLabels.keys) key: TextEditingController(),
  };
  bool _hasReport = false;

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
  void dispose() { _clearRows(); _exam.dispose(); _date.dispose(); _observations.dispose(); for (final field in _report.values) { field.dispose(); } super.dispose(); }
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
      if (!informeValido(original?['informe'])) throw const FormatException();
      _hasReport = original?['informe'] != null;
      final report = original?['informe'] as Map<String, dynamic>?;
      for (final field in _report.entries) { field.value.text = report?[field.key] as String? ?? ''; }

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
          if (_hasReport) 'informe': {for (final field in _report.entries)
            field.key: field.value.text.trim().isEmpty ? null : field.value.text},
          'resultados': _rows.map((row) => row.data()).toList(),
        }, observations: _observations.text, confirmedOriginal: _confirmed);
      if (mounted) setState(() { _saved = saved; _canReview = false; });
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() { _error = 'No se pudo guardar. Actualiza la revisión antes de repetir.'; _canReview = false; }); }
    finally { if (mounted) { setState(() => _busy = false); widget.onSaving(false); } }
  }
  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: TextField(controller: controller, enabled: !_busy, maxLength: 500,
      decoration: InputDecoration(labelText: label)));
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
      const Icon(Icons.fact_check_outlined, size: 32),
      const SizedBox(height: 12),
      Text('Revisión profesional', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
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
        if (_hasReport) ...[
          const Text('Datos del paciente y del estudio: coteja cada campo con el original.'),
          for (final field in _report.entries) Padding(
            padding: const EdgeInsets.symmetric(vertical: 10), child: TextField(
            controller: field.value, enabled: !_busy,
            maxLength: field.key == 'observaciones_originales' ? 2000 : 500,
            decoration: InputDecoration(labelText: informeLabels[field.key]))),
        ],
        ..._rows.asMap().entries.map((entry) => Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Resultado ${entry.key + 1}'),
            _field(entry.value.fields['nombre']!, 'Nombre del indicador'),
            _field(entry.value.fields['valor']!, 'Valor'),
            _field(entry.value.fields['unidad']!, 'Unidad'),
            _field(entry.value.fields['rango_referencia']!, 'Rango de referencia'),
            if (entry.value.fields.containsKey('estado_documento'))
              _field(entry.value.fields['estado_documento']!, 'Estado escrito en el documento (no calculado)'),
            TextButton(onPressed: _busy ? null : () => setState(() { final row = _rows.removeAt(entry.key); WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose()); }),
              child: const Text('Quitar resultado')),
          ])))),
        TextButton(onPressed: _busy || _rows.length >= 100 ? null
          : () => setState(() => _rows.add(_ReviewRow(_hasReport ? {'estado_documento': null} : {}))), child: const Text('Añadir resultado')),
        const SizedBox(height: 24),
        Text('Observaciones de tu revisión', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(controller: _observations, enabled: !_busy, maxLength: 2000, minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Motivo de correcciones o datos ausentes',
            helperText: 'Obligatorio si corriges datos o conservas campos ausentes.',
            helperMaxLines: 3)),
        const SizedBox(height: 16),
        CheckboxListTile(value: _confirmed, onChanged: _busy ? null
          : (value) => setState(() => _confirmed = value ?? false), contentPadding: EdgeInsets.zero,
          title: const Text('Confirmo que cotejé estos datos con el documento original.')),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy || !_confirmed ? null : _save,
          child: const Text('Aprobar y guardar revisión')),
      ] else if (!_busy && _error == null)
        Text(widget.processingStatus == 'failed'
          ? 'La extracción falló y no hay datos para aprobar. Actualizar revisión solo consulta; no vuelve a procesar el documento.'
          : 'Este documento todavía no tiene una extracción disponible para revisar.'),
    ]);
  }
}
