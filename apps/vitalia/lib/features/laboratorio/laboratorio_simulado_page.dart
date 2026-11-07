import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth_api.dart';

/// Interfaz local de un laboratorio ficticio. No publica resultados clínicos.
class LaboratorioSimuladoPage extends StatefulWidget {
  const LaboratorioSimuladoPage({
    super.key,
    required this.api,
    required this.onExpired,
    this.onLogout,
  });

  final AuthApi api;
  final VoidCallback onExpired;
  final VoidCallback? onLogout;

  @override
  State<LaboratorioSimuladoPage> createState() =>
      _LaboratorioSimuladoPageState();
}

class _LaboratorioSimuladoPageState extends State<LaboratorioSimuladoPage> {
  final _patient = TextEditingController();
  final _barcode = TextEditingController();
  final _orderLookup = TextEditingController();
  final _recentOrders = <String>[];

  bool _busy = false;
  String? _error;
  String? _message;
  Map<String, dynamic>? _data;
  String? _orderId;

  @override
  void dispose() {
    _patient.dispose();
    _barcode.dispose();
    _orderLookup.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        widget.onExpired();
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo completar la operación.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(String id) async {
    final result = await widget.api.silRequest('/orders/$id');
    if (!mounted) return;
    setState(() {
      _data = result;
      _orderId = id;
      _orderLookup.text = id;
      _recentOrders.remove(id);
      _recentOrders.insert(0, id);
      if (_recentOrders.length > 5) _recentOrders.removeLast();
    });
  }

  Map<String, dynamic>? get _order {
    final value = _data?['order'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  String get _status => (_order?['status'] as String?) ?? '';

  String get _statusLabel => switch (_status) {
    'registered' => 'Orden registrada',
    'sampled' => 'Muestra recibida',
    'results_recorded' => 'Resultados registrados',
    _ => 'Sin orden seleccionada',
  };

  String get _nextAction => switch (_status) {
    'registered' => 'Registrar la muestra',
    'sampled' => 'Ejecutar el analizador simulado',
    'results_recorded' => 'Pendiente de revisión y validación',
    _ => 'Crear o consultar una orden',
  };

  Future<void> _create() => _run(() async {
    final id = _patient.text.trim();
    if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) {
      throw const AuthFailure('Introduce el UUID válido de un paciente ficticio.');
    }
    final response = await widget.api.silRequest('/orders', body: {
      'patientId': id,
      'examCode': 'hemograma',
    });
    final orderId = (response['order'] as Map)['id'] as String;
    await _load(orderId);
    if (mounted) setState(() => _message = 'Orden de hemograma creada correctamente.');
  });

  Future<void> _registerSample() => _run(() async {
    final barcode = _barcode.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9-]{3,40}$').hasMatch(barcode)) {
      throw const AuthFailure('Usa entre 3 y 40 caracteres: letras, números o guiones.');
    }
    await widget.api.silRequest('/orders/$_orderId/sample', body: {
      'barcode': barcode,
    });
    await _load(_orderId!);
    if (mounted) setState(() => _message = 'Muestra registrada correctamente.');
  });

  Future<void> _simulate() => _run(() async {
    await widget.api.silRequest('/orders/$_orderId/simulate', body: {});
    await _load(_orderId!);
    if (mounted) {
      setState(() => _message =
          'Resultados ficticios registrados. No están validados ni publicados.');
    }
  });

  Widget _panel(String title, String subtitle, Widget child, {IconData? icon}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                ],
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      width: 210,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(value, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _resultsTable(List<dynamic> results) {
    final theme = Theme.of(context);
    return _panel(
      'Resultados del hemograma',
      'Datos sintéticos del analizador. No constituyen un informe clínico.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                theme.colorScheme.primary.withValues(alpha: 0.06),
              ),
              columns: const [
                DataColumn(label: Text('Analito')),
                DataColumn(label: Text('Resultado')),
                DataColumn(label: Text('Unidad')),
                DataColumn(label: Text('Intervalo ficticio')),
              ],
              rows: results.map((item) {
                final value = item as Map;
                return DataRow(cells: [
                  DataCell(Text('${value['analyte']}')),
                  DataCell(Text('${value['numericValue']}')),
                  DataCell(Text('${value['unit']}')),
                  DataCell(Text(
                    '${value['referenceMin'] ?? '—'} – ${value['referenceMax'] ?? '—'}',
                  )),
                ]);
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pendiente de validación. La publicación y entrega al paciente '
            'no están habilitadas en este prototipo.',
          ),
        ],
      ),
      icon: Icons.biotech_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sample = _data?['sample'] as Map?;
    final results = (_data?['results'] as List?) ?? [];
    final current = _order;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitalia SIL Simple'),
        actions: [
          if (widget.onLogout != null)
            TextButton.icon(
              onPressed: _busy ? null : widget.onLogout,
              icon: const Icon(Icons.logout_outlined, size: 18),
              label: const Text('Cerrar sesión'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Panel del laboratorio', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Órdenes, recepción de muestras y análisis simulado de hemograma.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.tertiaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'ENTORNO DE DEMOSTRACIÓN · Laboratorio ficticio. '
                              'No utiliza muestras reales, no emite informes '
                              'clínicos y no notifica pacientes.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metric(Icons.assignment_outlined, 'Orden seleccionada',
                          _orderId == null ? 'Sin seleccionar' : 'Hemograma'),
                      _metric(Icons.fact_check_outlined, 'Estado actual',
                          _statusLabel),
                      _metric(Icons.science_outlined, 'Analitos registrados',
                          '${results.length}'),
                      _metric(Icons.lock_outline, 'Publicación',
                          'No habilitada'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_message!,
                          style: TextStyle(color: theme.colorScheme.primary)),
                    ),
                  LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    final createPanel = _panel(
                      'Nueva orden',
                      'Se requiere una cuenta de paciente ficticio existente.',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _patient,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Identificador de paciente (UUID)',
                              hintText: 'Pegar UUID del paciente de prueba',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _busy ? null : _create,
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Crear orden de hemograma'),
                          ),
                        ],
                      ),
                      icon: Icons.note_add_outlined,
                    );
                    final lookupPanel = _panel(
                      'Consultar orden',
                      'Busca por identificador o usa una orden reciente.',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _orderLookup,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Identificador de orden (UUID)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _load(_orderLookup.text.trim())),
                            icon: const Icon(Icons.search),
                            label: const Text('Consultar orden'),
                          ),
                          if (_recentOrders.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text('Consultadas en esta sesión'),
                            ..._recentOrders.map((id) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(id, maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              leading: const Icon(Icons.history),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _busy ? null : () => _run(() => _load(id)),
                            )),
                          ],
                        ],
                      ),
                      icon: Icons.manage_search_outlined,
                    );
                    if (!wide) {
                      return Column(children: [
                        createPanel,
                        lookupPanel,
                      ]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: createPanel),
                        const SizedBox(width: 14),
                        Expanded(child: lookupPanel),
                      ],
                    );
                  }),
                  if (_orderId != null) ...[
                    const SizedBox(height: 14),
                    _panel(
                      'Detalle de la orden',
                      'Seguimiento postanalítico y próximos pasos.',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SelectableText('Orden: $_orderId'),
                          const SizedBox(height: 6),
                          Text('Examen: Hemograma'),
                          if (current?['createdAt'] != null)
                            Text('Creación: ${current!['createdAt']}'),
                          const SizedBox(height: 6),
                          Text('Estado: $_statusLabel',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('Siguiente paso: $_nextAction'),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _orderId!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Identificador copiado')),
                              );
                            },
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Copiar identificador'),
                          ),
                          if (_status == 'registered') ...[
                            const Divider(height: 32),
                            Text('Recepción de muestra',
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _barcode,
                              enabled: !_busy,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Código de muestra',
                                hintText: 'HEM-0001',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _busy ? null : _registerSample,
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: const Text('Registrar muestra'),
                            ),
                          ],
                          if (sample != null) ...[
                            const Divider(height: 28),
                            Text('Muestra: ${sample['barcode']}',
                                style: theme.textTheme.titleMedium),
                          ],
                          if (_status == 'sampled') ...[
                            const SizedBox(height: 14),
                            const Text(
                              'El analizador simulado generará cinco '
                              'resultados predeterminados y ficticios.',
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _busy ? null : _simulate,
                              icon: const Icon(Icons.science_outlined),
                              label: const Text('Ejecutar simulador'),
                            ),
                          ],
                        ],
                      ),
                      icon: Icons.assignment_turned_in_outlined,
                    ),
                    if (results.isNotEmpty) _resultsTable(results),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Vitalia SIL Simple · Prototipo académico de gestión '
                    'postanalítica. No conectado a analizadores reales.',
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
