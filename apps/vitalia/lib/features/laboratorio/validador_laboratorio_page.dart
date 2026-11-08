import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

/// Revisión interna de resultados sintéticos, sin publicación a pacientes.
class ValidadorLaboratorioPage extends StatefulWidget {
  const ValidadorLaboratorioPage({
    super.key,
    required this.api,
    required this.onExpired,
    required this.email,
    this.onLogout,
  });

  final AuthApi api;
  final VoidCallback onExpired;
  final String email;
  final VoidCallback? onLogout;

  @override
  State<ValidadorLaboratorioPage> createState() =>
      _ValidadorLaboratorioPageState();
}

class _ValidadorLaboratorioPageState extends State<ValidadorLaboratorioPage> {
  static const _pageSize = 20;
  final _search = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _pending = [];
  Map<String, dynamic>? _detail;
  int _total = 0;
  int _page = 0;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  void _failure(AuthFailure error) {
    if (!mounted) return;
    if (error.status == 401) {
      widget.onExpired();
    } else {
      setState(() => _error = error.message);
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await work();
    } on AuthFailure catch (error) {
      _failure(error);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo completar la operación.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(() async {
    final params = <String, String>{
      'status': 'results_recorded',
      'limit': '$_pageSize',
      'offset': '${_page * _pageSize}',
      if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
    };
    final data = await widget.api.silRequest(
      '/orders?${Uri(queryParameters: params).query}',
    );
    if (!mounted) return;
    setState(() {
      _pending = (data['orders'] as List? ?? [])
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      _total = (data['total'] as num?)?.toInt() ?? _pending.length;
    });
  });

  Future<void> _open(String id) => _run(() async {
    final data = await widget.api.silRequest('/orders/$id');
    if (!mounted) return;
    setState(() {
      _detail = data;
      _note.clear();
    });
  });

  Future<void> _decide(String decision) async {
    final data = _detail;
    if (data == null || _busy) return;
    final order = data['order'] as Map;
    if (order['status'] != 'results_recorded') return;
    final note = _note.text.trim();
    if (decision == 'return' && note.length < 10) {
      setState(() => _error = 'Indica un motivo de devolución de al menos 10 caracteres.');
      return;
    }
    final label = decision == 'approve' ? 'Aprobar revisión' : 'Devolver orden';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text(
          decision == 'approve'
              ? 'Se marcará la revisión interna como aprobada. '
                  'Esto no publica resultados ni genera un informe clínico.'
              : 'La orden volverá al operador para corregir resultados. '
                  'Se conservarán los valores y el motivo en la auditoría.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.api.silRequest('/orders/${order['id']}/review', body: {
        'decision': decision,
        'note': note,
      });
      final updated = await widget.api.silRequest('/orders/${order['id']}');
      final params = <String, String>{
        'status': 'results_recorded',
        'limit': '$_pageSize',
        'offset': '${_page * _pageSize}',
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
      };
      final pending = await widget.api.silRequest(
        '/orders?${Uri(queryParameters: params).query}',
      );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _pending = (pending['orders'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _total = (pending['total'] as num?)?.toInt() ?? _pending.length;
        _message = decision == 'approve'
            ? 'Revisión interna aprobada y registrada en auditoría.'
            : 'Orden devuelta al operador con motivo registrado.';
        _note.clear();
      });
    });
  }

  String _date(Object? value) {
    final d = DateTime.tryParse('$value')?.toLocal();
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  String _auditLabel(String value) => switch (value) {
    'order_created' => 'Orden registrada',
    'sample_received' => 'Muestra recibida',
    'results_manual' => 'Resultados ingresados manualmente',
    'results_simulated' => 'Resultados de prueba generados',
    'results_corrected' => 'Valores corregidos por operador',
    'review_approved' => 'Revisión interna aprobada',
    'review_rejected' => 'Orden devuelta con observaciones',
    _ => value,
  };

  String _status(String? value) => switch (value) {
    'results_recorded' => 'Pendiente de revisión',
    'review_approved' => 'Revisión aprobada',
    'review_rejected' => 'Devuelta al operador',
    _ => value ?? 'Sin estado',
  };

  Widget _box(String title, Widget child, {String? subtitle}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _queue() => _box(
    'Órdenes pendientes de revisión',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _search,
        maxLength: 100,
        decoration: const InputDecoration(
          labelText: 'Buscar por orden o correo',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
          counterText: '',
        ),
        onSubmitted: (_) {
          setState(() => _page = 0);
          _refresh();
        },
      ),
      const SizedBox(height: 9),
      Wrap(spacing: 10, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () {
                  setState(() => _page = 0);
                  _refresh();
                },
          icon: const Icon(Icons.search),
          label: const Text('Buscar'),
        ),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () {
                  _search.clear();
                  setState(() => _page = 0);
                  _refresh();
                },
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
      ]),
      const SizedBox(height: 10),
      Text('$_total órdenes pendientes'),
      const SizedBox(height: 10),
      if (_pending.isEmpty)
        const Text('No hay órdenes pendientes con estos filtros.')
      else
        for (final order in _pending)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${order['orderNumber']} · ${order['patientEmail']}'),
            subtitle: Text(
              '${_status(order['status'] as String?)} · ${_date(order['createdAt'])}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _open(order['id'] as String),
          ),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('Página ${_page + 1}'),
        IconButton(
          tooltip: 'Anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: _busy || _page == 0
              ? null
              : () {
                  setState(() => _page--);
                  _refresh();
                },
        ),
        IconButton(
          tooltip: 'Siguiente',
          icon: const Icon(Icons.chevron_right),
          onPressed: _busy || (_page + 1) * _pageSize >= _total
              ? null
              : () {
                  setState(() => _page++);
                  _refresh();
                },
        ),
      ]),
    ]),
    subtitle: 'Consulta de resultados registrados, sin acceso a crear órdenes ni muestras.',
  );

  DataRow _resultRow(Map row) {
    final value = (row['numericValue'] as num?)?.toDouble();
    final min = (row['referenceMin'] as num?)?.toDouble();
    final max = (row['referenceMax'] as num?)?.toDouble();
    final outside = value != null &&
        ((min != null && value < min) || (max != null && value > max));
    return DataRow(cells: [
      DataCell(Text('${row['examCode']}')),
      DataCell(Text('${row['analyte']}')),
      DataCell(Text('${row['numericValue']}')),
      DataCell(Text('${row['unit']}')),
      DataCell(Text('${min ?? '—'} – ${max ?? '—'}')),
      DataCell(Text(outside ? 'Revisar valor' : '—')),
    ]);
  }

  Widget _detailView() {
    final data = _detail;
    if (data == null) {
      return _box(
        'Detalle de revisión',
        const Text('Selecciona una orden de la lista para revisar sus resultados.'),
      );
    }
    final order = data['order'] as Map;
    final results = data['results'] as List? ?? [];
    final exams = data['exams'] as List? ?? [];
    final audit = data['audit'] as List? ?? [];
    final canReview = order['status'] == 'results_recorded';
    int flagged = 0;
    for (final item in results) {
      final row = item as Map;
      final value = (row['numericValue'] as num?)?.toDouble();
      final min = (row['referenceMin'] as num?)?.toDouble();
      final max = (row['referenceMax'] as num?)?.toDouble();
      if (value != null &&
          ((min != null && value < min) || (max != null && value > max))) {
        flagged++;
      }
    }
    return _box(
      'Revisión de orden ${order['orderNumber']}',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Paciente: ${order['patientEmail']}'),
        Text('Estado: ${_status(order['status'] as String?)}'),
        Text('Creación: ${_date(order['createdAt'])}'),
        Text('Exámenes: ${exams.map((exam) => (exam as Map)['name']).join(', ')}'),
        const SizedBox(height: 15),
        Text(
          flagged == 0
              ? 'Sin alertas respecto a las referencias de prueba disponibles.'
              : '$flagged resultados fuera de las referencias de prueba configuradas.',
          style: TextStyle(
            color: flagged == 0
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Examen')),
              DataColumn(label: Text('Analito')),
              DataColumn(label: Text('Resultado')),
              DataColumn(label: Text('Unidad')),
              DataColumn(label: Text('Referencia de prueba')),
              DataColumn(label: Text('Observación')),
            ],
            rows: [for (final item in results) _resultRow(item as Map)],
          ),
        ),
        const SizedBox(height: 16),
        if (canReview) ...[
          TextField(
            controller: _note,
            enabled: !_busy,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Observación de revisión',
              helperText: 'Obligatoria al devolver (mínimo 10 caracteres).',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 10, children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _decide('approve'),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Aprobar revisión interna'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _decide('return'),
              icon: const Icon(Icons.undo_outlined),
              label: const Text('Devolver al operador'),
            ),
          ]),
        ] else
          const Text('La decisión está registrada. Esta orden ya no admite '
              'una segunda decisión desde esta pantalla.'),
        const Divider(height: 28),
        Text('Historial de actividad', style: Theme.of(context).textTheme.titleMedium),
        for (final event in audit)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(_auditLabel((event as Map)['action'] as String)),
            subtitle: Text('${event['actorEmail']} · ${_date(event['createdAt'])}'
                '${(event['details'] as Map?)?['note'] == null
                    ? '' : ' · ${(event['details'] as Map)['note']}'}'),
          ),
        const SizedBox(height: 10),
        const Text('Revisión interna sobre datos de prueba. '
            'No constituye validación clínica ni habilita su publicación.'),
      ]),
      subtitle: 'Verifica parámetros, unidades y trazabilidad antes de tomar una decisión.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitalia Health'),
        actions: [
          if (widget.onLogout != null)
            TextButton.icon(
              onPressed: _busy ? null : widget.onLogout,
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
              constraints: const BoxConstraints(maxWidth: 1260),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Panel de validación',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 5),
                  Text('Responsable: ${widget.email}'),
                  const SizedBox(height: 7),
                  const Text('Revisión y devolución de órdenes con resultados '
                      'registrados. No se entregan documentos a pacientes.'),
                  const SizedBox(height: 20),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) ...[
                    Text(_error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 12),
                  ],
                  if (_message != null) ...[
                    Text(_message!,
                        style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 12),
                  ],
                  LayoutBuilder(builder: (context, constraints) {
                    if (constraints.maxWidth < 950) {
                      return Column(children: [
                        _queue(),
                        const SizedBox(height: 16),
                        _detailView(),
                      ]);
                    }
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 2, child: _queue()),
                      const SizedBox(width: 18),
                      Expanded(flex: 3, child: _detailView()),
                    ]);
                  }),
                  const SizedBox(height: 25),
                  Text(
                    'Vitalia Health · Gestión postanalítica de órdenes y resultados.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
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
