import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

class SilMainClinicalPanel extends StatefulWidget {
  const SilMainClinicalPanel({
    super.key,
    required this.api,
    required this.labId,
    required this.orders,
    required this.canReview,
    required this.onExpired,
  });

  final AuthApi api;
  final String labId;
  final List<Map<String, dynamic>> orders;
  final bool canReview;
  final VoidCallback onExpired;

  @override
  State<SilMainClinicalPanel> createState() => _SilMainClinicalPanelState();
}

class _SilMainClinicalPanelState extends State<SilMainClinicalPanel> {
  String? _orderId;
  Map<String, dynamic>? _details;
  final _values = <String, String>{};
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;
  int _revision = 0;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _key(Map row) => '${row['examCode']}|${row['analyte']}';
  String get _path => '/labs/${widget.labId}/orders/$_orderId/clinical';

  Future<void> _load() async {
    final details = await widget.api.silMainRequest(_path);
    if (!mounted) return;
    final result = details['results'] as Map?;
    setState(() {
      _details = details;
      _values.clear();
      for (final row in (result?['values'] as List? ?? []).cast<Map>()) {
        _values[_key(row)] = row['numericValue'].toString();
      }
      _reason.clear();
      _revision++;
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      if (failure.status == 401) {
        widget.onExpired();
      } else {
        setState(() => _error = failure.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo completar la operación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(String action, Map<String, dynamic> body) async {
    await widget.api.silMainRequest('$_path/$action', body: body);
    await _load();
  }

  Future<void> _save(List<Map> analytes) async {
    final results = <Map<String, dynamic>>[];
    for (final row in analytes) {
      final number = double.tryParse((_values[_key(row)] ?? '').trim().replaceAll(',', '.'));
      if (number == null || !number.isFinite) {
        throw const AuthFailure('Ingresa un valor numérico para cada analito.');
      }
      results.add({'examCode': row['examCode'], 'analyte': row['analyte'], 'numericValue': number});
    }
    await _write('results', {'values': results});
  }

  @override
  Widget build(BuildContext context) {
    final containers = (_details?['containers'] as List? ?? []).cast<Map>();
    final analytes = (_details?['analytes'] as List? ?? []).cast<Map>();
    final result = _details?['results'] as Map?;
    final status = result?['status'];
    final open = _details?['status'] == 'registered';
    final sampled = containers.isNotEmpty && containers.every((row) => row['barcode'] != null);
    final editable = open && sampled && (status == null || status == 'returned');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(widget.labId),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Orden para muestras y resultados'),
          items: [
            for (final order in widget.orders)
              DropdownMenuItem(
                value: order['id'] as String,
                child: Text('VH-${order['orderNumber'].toString().padLeft(6, '0')}'),
              ),
          ],
          onChanged: _busy ? null : (orderId) {
            if (orderId == null) return;
            setState(() {
              _orderId = orderId;
              _details = null;
            });
            _run(_load);
          },
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_details != null) ...[
          const SizedBox(height: 12),
          const Text('Contenedores requeridos'),
          for (final row in containers)
            ListTile(
              title: Text(row['label'] as String),
              subtitle: Text(row['barcode'] as String? ?? 'Pendiente de recepción'),
              trailing: row['barcode'] == null && open
                  ? TextButton(
                      onPressed: _busy ? null : () => _run(
                        () => _write('samples', {'containerCode': row['code']}),
                      ),
                      child: const Text('Recibir'),
                    ) : null,
            ),
          if (sampled || result != null) ...[
            Text(switch (status) {
              'pending' => 'Resultados pendientes de revisión',
              'approved' => 'Resultados aprobados',
              'returned' => 'Resultados devueltos para corrección',
              _ => 'Ingresar resultados por analito',
            }),
            for (final row in analytes)
              TextFormField(
                key: ValueKey('$_revision-${_key(row)}'),
                initialValue: _values[_key(row)],
                enabled: editable && !_busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: '${row['analyte']} (${row['unit']})'),
                onChanged: (value) => _values[_key(row)] = value,
              ),
            if (editable)
              FilledButton(
                onPressed: _busy || analytes.isEmpty ? null : () => _run(() => _save(analytes)),
                child: const Text('Guardar resultados para revisión'),
              ),
            if (open && status == 'pending' && widget.canReview) ...[
              TextField(
                controller: _reason,
                enabled: !_busy,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Motivo de devolución'),
              ),
              Wrap(spacing: 8, children: [
                FilledButton(
                  onPressed: _busy ? null : () => _run(
                    () => _write('review', {'decision': 'approved'}),
                  ),
                  child: const Text('Aprobar resultados'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(
                    () => _write('review', {'decision': 'returned', 'reason': _reason.text.trim()}),
                  ),
                  child: const Text('Devolver para corregir'),
                ),
              ]),
            ],
          ],
        ],
      ],
    );
  }
}
