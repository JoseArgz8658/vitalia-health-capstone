import 'package:flutter/material.dart';
import '../../core/auth_api.dart';

/// Demostración para administrador. No emite informes clínicos.
class LaboratorioSimuladoPage extends StatefulWidget {
  const LaboratorioSimuladoPage({
    super.key, required this.api, required this.onExpired, this.onLogout,
  });
  final AuthApi api;
  final VoidCallback onExpired;
  final VoidCallback? onLogout;

  @override
  State<LaboratorioSimuladoPage> createState() => _LaboratorioSimuladoPageState();
}

class _LaboratorioSimuladoPageState extends State<LaboratorioSimuladoPage> {
  final _patient = TextEditingController();
  final _barcode = TextEditingController();
  final _orderLookup = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _order;
  String? _orderId;

  @override
  void dispose() {
    _patient.dispose();
    _barcode.dispose();
    _orderLookup.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await operation();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.status == 401) widget.onExpired();
      else setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo completar la operación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(String id) async {
    final response = await widget.api.silRequest('/orders/$id');
    if (mounted) setState(() { _order = response; _orderId = id; _orderLookup.text = id; });
  }

  String get _status {
    final o = _order?['order'] as Map?;
    return (o?['status'] as String?) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final results = (_order?['results'] as List?) ?? [];
    final sample = _order?['sample'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitalia SIL Simple'),
        actions: [
          if (widget.onLogout != null)
            TextButton(
              onPressed: _busy ? null : widget.onLogout,
              child: const Text('Cerrar sesión'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 750),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Card(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('ENTORNO DEMOSTRATIVO. Los datos y resultados del analizador son ficticios y no tienen validez clínica. No se emiten informes ni se notifican pacientes.'),
                  )),
                  const SizedBox(height: 12),
                  Text('1. Crear orden de hemograma', style: Theme.of(context).textTheme.titleLarge),
                  TextField(
                    controller: _patient,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'UUID de paciente de prueba'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(() async {
                      final data = await widget.api.silRequest('/orders',body: {
                        'patientId':_patient.text.trim(),'examCode':'hemograma',
                      });
                      final id = (data['order'] as Map)['id'] as String;
                      await _load(id);
                    }),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Crear orden'),
                  ),
                  const SizedBox(height: 16),
                  Text('2. Buscar orden existente',style: Theme.of(context).textTheme.titleLarge),
                  TextField(
                    controller: _orderLookup,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'UUID de orden'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run(() => _load(_orderLookup.text.trim())),
                    child: const Text('Consultar orden'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_error!,style: TextStyle(color:Theme.of(context).colorScheme.error)),
                  ),
                  if (_orderId != null) ...[
                    const Divider(height: 32),
                    SelectableText('Orden: $_orderId'),
                    Text('Estado: $_status'),
                    const SizedBox(height: 12),
                    if (_status == 'registered') ...[
                      Text('3. Registrar muestra',style: Theme.of(context).textTheme.titleLarge),
                      TextField(
                        controller:_barcode,
                        enabled: !_busy,
                        decoration: const InputDecoration(labelText:'Código de muestra (A-Z, 0-9 o guion)'),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(() async {
                          await widget.api.silRequest('/orders/$_orderId/sample',body: {
                            'barcode':_barcode.text.trim(),
                          });
                          await _load(_orderId!);
                        }),
                        child: const Text('Registrar muestra'),
                      ),
                    ],
                    if (sample != null) Text('Muestra registrada: ${sample['barcode']}'),
                    if (_status == 'sampled') ...[
                      const SizedBox(height: 12),
                      Text('4. Analizador ficticio',style: Theme.of(context).textTheme.titleLarge),
                      const Text('Genera cinco resultados predeterminados de demostración. No es un dispositivo médico.'),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _run(() async {
                          await widget.api.silRequest('/orders/$_orderId/simulate',body: {});
                          await _load(_orderId!);
                        }),
                        icon:const Icon(Icons.science_outlined),
                        label:const Text('Ejecutar simulación'),
                      ),
                    ],
                    if (results.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Resultados ficticios',style:Theme.of(context).textTheme.titleLarge),
                      ...results.map((item) {
                        final r = item as Map;
                        return ListTile(
                          title: Text('${r['analyte']}'),
                          subtitle: Text('Intervalo de demostración: ${r['referenceMin'] ?? '—'} – ${r['referenceMax'] ?? '—'}'),
                          trailing: Text('${r['numericValue']} ${r['unit']}'),
                        );
                      }),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
