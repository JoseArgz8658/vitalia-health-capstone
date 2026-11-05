import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';

class MedidasPanel extends StatefulWidget {
  const MedidasPanel({super.key, required this.api, required this.onExpired, this.enabled = true, this.onEditingChanged});
  final AuthApi api;
  final VoidCallback onExpired;
  final bool enabled;
  final ValueChanged<bool>? onEditingChanged;
  @override
  State<MedidasPanel> createState() => _MedidasPanelState();
}
class _MedidasPanelState extends State<MedidasPanel> {
  final _form = GlobalKey<FormState>();
  final _weight = TextEditingController(), _height = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _busy = false, _ready = false, _editing = false;
  DateTime _date = DateTime.now();
  String? _requestId, _message;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _weight.dispose(); _height.dispose(); super.dispose(); }
  String _uuid() {
    final random = Random.secure();final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }
  String _day(DateTime value) => '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
  double? _number(String value) => value.trim().isEmpty ? null : double.tryParse(value.trim().replaceAll(',', '.'));
  void _error(AuthFailure error) {
    if (error.status == 401) { widget.onExpired(); return; }
    if (mounted) setState(() => _message = error.message);
  }
  Future<void> _load() async {
    if (_busy || _editing) return;
    setState(() { _busy = true; _ready = false; _items = []; _message = null; });
    try {
      final items = await widget.api.measurements();
      if (mounted) setState(() { _items = items; _ready = true; });
    } on AuthFailure catch (error) { _error(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  void _start() {
    _weight.clear();_height.clear();
    setState(() { _date = DateTime.now(); _requestId = null; _message = null; _editing = true; });
    widget.onEditingChanged?.call(true);
  }
  Future<void> _chooseDate() async {
    final date = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1900), lastDate: DateTime.now());
    if (date != null && mounted) setState(() { _date = date; _requestId = null; });
  }
  Future<void> _save() async {
    if (_busy || !widget.enabled || !_form.currentState!.validate()) return;
    if (_weight.text.trim().isEmpty && _height.text.trim().isEmpty) {
      setState(() => _message = 'Registra al menos peso o altura.');return;
    }
    _requestId ??= _uuid();
    final body = {'requestId':_requestId, 'measuredAt':_date.toUtc().toIso8601String(),
      'weightKg':_number(_weight.text), 'heightCm':_number(_height.text)};
    setState(() { _busy = true; _message = null; });
    try {
      final saved = await widget.api.recordMeasurement(body);
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        final items = [saved, ..._items.where((item) => item['id'] != saved['id'])];
        items.sort((a, b) => DateTime.parse(b['measuredAt'] as String).compareTo(DateTime.parse(a['measuredAt'] as String)));
        _items = items.take(20).toList(); _editing = false; _message = 'Medida guardada en tu historial.';
      });
      widget.onEditingChanged?.call(false);
    } on AuthFailure catch (error) { _error(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: TextFormField(controller: controller,
      enabled: !_busy && widget.enabled, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => _requestId = null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final number = _number(value);
        return number == null || !number.isFinite || number <= 0 ? 'Ingresa un número mayor que cero.' : null;
      }),
  );
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(top: 18), child: Padding(
    padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [const Icon(Icons.monitor_weight_outlined), const SizedBox(width: 12),
        Expanded(child: Text('Medidas personales', style: Theme.of(context).textTheme.titleMedium))]),
      const Divider(height: 28),
      const Text('Peso y altura son opcionales. Son datos declarados por ti; no son una medición confirmada por un profesional ni se envían al asistente.'),
      const SizedBox(height: 16),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Semantics(liveRegion: true, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_message!))),
      if (!_editing) Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(onPressed: _busy || !_ready || !widget.enabled ? null : _start,
          icon: const Icon(Icons.add), label: const Text('Registrar medidas')),
        TextButton.icon(onPressed: _busy || !widget.enabled ? null : _load,
          icon: const Icon(Icons.refresh), label: const Text('Actualizar medidas')),
      ]),
      if (_editing) Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field(_weight, 'Peso en kg (opcional)'), _field(_height, 'Altura en cm (opcional)'),
        Text('Fecha de medición: ${_day(_date)}'),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _busy || !widget.enabled ? null : _chooseDate,
          icon: const Icon(Icons.calendar_today_outlined), label: const Text('Cambiar fecha de medición'))),
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton(onPressed: _busy || !widget.enabled ? null : _save, child: const Text('Guardar medidas')),
          OutlinedButton(onPressed: _busy || !widget.enabled ? null : () {
            FocusManager.instance.primaryFocus?.unfocus();setState(() { _editing = false; _message = null; });
            widget.onEditingChanged?.call(false);
          }, child: const Text('Cancelar registro')),
        ]),
      ])),
      const SizedBox(height: 20),
      Text('Últimos registros (hasta 20)', style: Theme.of(context).textTheme.titleSmall),
      if (_ready && _items.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Todavía no registras medidas.')),
      for (final item in _items) Padding(padding: const EdgeInsets.only(top: 12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_day(DateTime.parse(item['measuredAt'] as String).toLocal())),
          Text('Peso: ${item['weightKg'] == null ? 'Sin registrar' : '${item['weightKg']} kg'} · Altura: ${item['heightCm'] == null ? 'Sin registrar' : '${item['heightCm']} cm'}'),
          Text(item['source'] == 'patient_reported' ? 'Declarado por el paciente' : 'Registro profesional'),
          const Divider(),
        ])),
    ]),
  ));
}
