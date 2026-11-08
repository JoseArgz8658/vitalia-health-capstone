import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

/// Estación de trabajo del operador. No publica ni valida resultados clínicos.
class OperadorLaboratorioPage extends StatefulWidget {
  const OperadorLaboratorioPage({
    super.key,
    required this.api,
    required this.onExpired,
    this.onLogout,
  });

  final AuthApi api;
  final VoidCallback onExpired;
  final VoidCallback? onLogout;

  @override
  State<OperadorLaboratorioPage> createState() => _OperadorLaboratorioPageState();
}

class _OperadorLaboratorioPageState extends State<OperadorLaboratorioPage> {
  static const _pageSize = 20;
  static const _nav = <(IconData, String)>[
    (Icons.dashboard_outlined, 'Resumen'),
    (Icons.assignment_outlined, 'Órdenes'),
    (Icons.note_add_outlined, 'Nueva orden'),
    (Icons.science_outlined, 'Muestras'),
    (Icons.fact_check_outlined, 'Resultados'),
  ];

  final _patientController = TextEditingController();
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _selectedExams = <String>{'hemograma'};

  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _recentOrders = [];
  int _listRequestId = 0;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _selected;
  String? _error;
  String? _message;
  String? _filterStatus;
  bool _busy = false;
  bool _loading = true;
  int _page = 0;
  int _total = 0;
  int _section = 0;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _patientController.dispose();
    _searchController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final catalog = await widget.api.silRequest('/catalog');
      final summary = await widget.api.silRequest('/summary');
      final recent = await widget.api.silRequest('/orders?limit=5&offset=0');
      if (!mounted) return;
      setState(() {
        _catalog = (catalog['exams'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _summary = Map<String, dynamic>.from(summary['summary'] as Map);
        _recentOrders = (recent['orders'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
      await _refreshOrders();
    } on AuthFailure catch (error) {
      _showFailure(error);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los datos del laboratorio.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshOrders() async {
    final requestId = ++_listRequestId;
    try {
      final params = <String, String>{
        'limit': '$_pageSize',
        'offset': '${_page * _pageSize}',
        if (_filterStatus != null) 'status': _filterStatus!,
        if (_searchController.text.trim().isNotEmpty)
          'search': _searchController.text.trim(),
      };
      final query = Uri(queryParameters: params).query;
      final response = await widget.api.silRequest('/orders?$query');
      if (!mounted || requestId != _listRequestId) return;
      setState(() {
        _orders = (response['orders'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _total = (response['total'] as num?)?.toInt() ?? _orders.length;
      });
    } on AuthFailure catch (error) {
      _showFailure(error);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo actualizar la lista de órdenes.');
    }
  }

  void _showFailure(AuthFailure error) {
    if (!mounted) return;
    if (error.status == 401) {
      widget.onExpired();
    } else {
      setState(() => _error = error.message);
    }
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
      _showFailure(error);
    } catch (_) {
      if (mounted) setState(() => _error = 'No fue posible completar la operación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOrder(String id) async {
    final response = await widget.api.silRequest('/orders/$id');
    if (!mounted) return;
    final selected = Map<String, dynamic>.from(response);
    final order = Map<String, dynamic>.from(selected['order'] as Map);
    setState(() {
      _selected = selected;
      _barcodeController.clear();
      _section = order['status'] == 'results_recorded' ? 4 : 3;
    });
  }

  Future<void> _createOrder() => _run(() async {
    final email = _patientController.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const AuthFailure('Ingresa el correo de un paciente registrado.');
    }
    if (_selectedExams.isEmpty) {
      throw const AuthFailure('Selecciona al menos un examen.');
    }
    final patient = await widget.api.silRequest(
      '/patients?email=${Uri.encodeQueryComponent(email)}',
    );
    final id = (patient['patient'] as Map)['id'] as String;
    final created = await widget.api.silRequest('/orders', body: {
      'patientId': id,
      'examCodes': _selectedExams.toList()..sort(),
    });
    await _openOrder((created['order'] as Map)['id'] as String);
    _page = 0;
    _filterStatus = null;
    _searchController.clear();
    await _refreshAll();
    if (mounted) {
      setState(() => _message = 'Orden registrada. Continúa con la recepción de la muestra.');
    }
  });

  Future<void> _receiveSample() => _run(() async {
    final order = _selected?['order'] as Map?;
    if (order == null) throw const AuthFailure('Selecciona una orden.');
    final barcode = _barcodeController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9-]{3,40}$').hasMatch(barcode)) {
      throw const AuthFailure('Código de muestra inválido: usa letras, números o guiones.');
    }
    final id = order['id'] as String;
    await widget.api.silRequest('/orders/$id/sample', body: {'barcode': barcode});
    await _openOrder(id);
    await _refreshAll();
    if (mounted) setState(() => _message = 'Recepción de muestra registrada.');
  });

  Future<void> _processSample() => _run(() async {
    final order = _selected?['order'] as Map?;
    if (order == null) throw const AuthFailure('Selecciona una orden.');
    final id = order['id'] as String;
    await widget.api.silRequest('/orders/$id/simulate', body: {});
    await _openOrder(id);
    await _refreshAll();
    if (mounted) {
      setState(() => _message =
          'Resultados de prueba registrados. Pendientes de revisión profesional.');
    }
  });

  void _search() {
    if (_searchController.text.trim().length > 100) {
      setState(() => _error = 'El término de búsqueda es demasiado largo.');
      return;
    }
    setState(() {
      _page = 0;
      _error = null;
    });
    _refreshOrders();
  }

  String _examName(String code) {
    for (final exam in _catalog) {
      if (exam['code'] == code) return exam['name'] as String;
    }
    return code.replaceAll('_', ' ');
  }

  String _orderCode(Map order) => '${order['orderNumber'] ?? 'Orden'}';

  String _statusLabel(String? status) => switch (status) {
    'registered' => 'Pendiente de muestra',
    'sampled' => 'Pendiente de resultados',
    'results_recorded' => 'Pendiente de revisión',
    _ => 'Sin estado',
  };

  String _date(Object? input) {
    final date = DateTime.tryParse('$input')?.toLocal();
    if (date == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Widget _panel(String title, String subtitle, Widget child,
      {IconData? icon}) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            ]),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String title, int count) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: _panel(
        title,
        'Órdenes del laboratorio',
        Row(children: [
          Icon(icon, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 14),
          Text('$count', style: theme.textTheme.headlineMedium),
        ]),
      ),
    );
  }

  Widget _ordersTable({bool recent = false}) {
    final rows = recent ? _recentOrders : _orders;
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No hay órdenes que coincidan con la búsqueda.'),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('N.º de orden')),
          DataColumn(label: Text('Paciente')),
          DataColumn(label: Text('Exámenes')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Fecha')),
          DataColumn(label: Text('Acción')),
        ],
        rows: rows.map((order) {
          final exams = (order['examCodes'] as List? ?? [])
              .map((code) => _examName('$code'))
              .join(', ');
          return DataRow(cells: [
            DataCell(Text(_orderCode(order))),
            DataCell(Text('${order['patientEmail'] ?? '—'}')),
            DataCell(SizedBox(
              width: 250,
              child: Text(exams, maxLines: 2, overflow: TextOverflow.ellipsis),
            )),
            DataCell(Text(_statusLabel(order['status'] as String?))),
            DataCell(Text(_date(order['createdAt']))),
            DataCell(TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => _openOrder(order['id'] as String)),
              child: const Text('Abrir'),
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _dashboard() {
    final summary = _summary;
    if (summary == null) {
      return const Text('Cargando indicadores del laboratorio…');
    }
    int count(String key) => (summary[key] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _metric(Icons.assignment_outlined, 'Órdenes totales', count('total')),
          _metric(Icons.inventory_2_outlined, 'Pendientes de muestra', count('pendingSample')),
          _metric(Icons.science_outlined, 'Pendientes de resultados', count('pendingResults')),
          _metric(Icons.verified_outlined, 'Pendientes de revisión', count('pendingReview')),
        ]),
        const SizedBox(height: 20),
        _panel(
          'Actividad reciente',
          'Últimas órdenes obtenidas desde PostgreSQL.',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _ordersTable(recent: true),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _section = 1),
                icon: const Icon(Icons.arrow_forward_outlined),
                label: const Text('Ver todas las órdenes'),
              ),
            ),
          ]),
          icon: Icons.history,
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => setState(() => _section = 2),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Registrar orden'),
          ),
        ),
      ],
    );
  }

  Widget _ordersView() => _panel(
    'Gestión de órdenes',
    'Consulta por paciente, número de orden o identificador, y filtra por estado.',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 340,
          child: TextField(
            controller: _searchController,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Buscar orden o correo',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        DropdownButton<String>(
          value: _filterStatus ?? '',
          items: const [
            DropdownMenuItem(value: '', child: Text('Todos los estados')),
            DropdownMenuItem(value: 'registered', child: Text('Pendiente de muestra')),
            DropdownMenuItem(value: 'sampled', child: Text('Pendiente de resultados')),
            DropdownMenuItem(value: 'results_recorded', child: Text('Pendiente de revisión')),
          ],
          onChanged: (value) {
            setState(() {
              _filterStatus = value == '' ? null : value;
              _page = 0;
            });
            _refreshOrders();
          },
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _search,
          icon: const Icon(Icons.search),
          label: const Text('Buscar'),
        ),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () {
                  _searchController.clear();
                  setState(() {
                    _page = 0;
                    _filterStatus = null;
                  });
                  _refreshOrders();
                },
          icon: const Icon(Icons.clear),
          label: const Text('Limpiar filtros'),
        ),
      ]),
      const SizedBox(height: 12),
      Text('$_total órdenes encontradas'),
      const SizedBox(height: 10),
      _ordersTable(),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('Página ${_page + 1}'),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: _busy || _page == 0
              ? null
              : () {
                  setState(() => _page--);
                  _refreshOrders();
                },
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: _busy || (_page + 1) * _pageSize >= _total
              ? null
              : () {
                  setState(() => _page++);
                  _refreshOrders();
                },
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
    ]),
    icon: Icons.assignment_outlined,
  );

  Widget _newOrderView() => _panel(
    'Nueva orden de exámenes',
    'Selecciona un paciente existente y las prestaciones que se realizarán.',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _patientController,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: 'Correo del paciente',
          hintText: 'paciente.sil@example.invalid',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_search_outlined),
        ),
      ),
      const SizedBox(height: 20),
      Text('Catálogo de exámenes', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      if (_catalog.isEmpty)
        const Text('Cargando catálogo de exámenes…')
      else
        Wrap(
          spacing: 9,
          runSpacing: 6,
          children: _catalog.map((exam) {
            final code = exam['code'] as String;
            return FilterChip(
              label: Text(exam['name'] as String),
              selected: _selectedExams.contains(code),
              onSelected: _busy
                  ? null
                  : (selected) => setState(() {
                      if (selected) {
                        _selectedExams.add(code);
                      } else {
                        _selectedExams.remove(code);
                      }
                    }),
            );
          }).toList(),
        ),
      const SizedBox(height: 20),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy || _catalog.isEmpty ? null : _createOrder,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Registrar orden'),
        ),
      ),
    ]),
    icon: Icons.note_add_outlined,
  );

  Widget _withoutOrder(String title) => _panel(
    title,
    'Selecciona una orden para continuar.',
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _section = 1),
        icon: const Icon(Icons.assignment_outlined),
        label: const Text('Consultar órdenes'),
      ),
    ),
  );

  Widget _orderHeader(Map<String, dynamic> order) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Orden: ${_orderCode(order)}',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text('Paciente: ${order['patientEmail'] ?? '—'}'),
      Text('Creación: ${_date(order['createdAt'])}'),
      Text('Estado: ${_statusLabel(order['status'] as String?)}'),
      const SizedBox(height: 8),
      Text('Prestaciones: ${(_selected?['exams'] as List? ?? [])
          .map((item) => (item as Map)['name']).join(', ')}'),
    ],
  );

  Widget _samplesView() {
    final data = _selected;
    if (data == null) return _withoutOrder('Recepción de muestras');
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final sample = data['sample'] as Map?;
    final status = order['status'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panel(
        'Recepción y seguimiento de muestras',
        'Registro de una muestra sanguínea por orden en esta etapa.',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _orderHeader(order),
          if (sample != null) ...[
            const Divider(height: 30),
            Text('Código de muestra: ${sample['barcode']}'),
            Text('Recepción: ${_date(sample['registeredAt'])}'),
            Text('Tipo: Sangre venosa'),
          ],
          if (status == 'registered') ...[
            const SizedBox(height: 20),
            TextField(
              controller: _barcodeController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Código de muestra',
                hintText: 'LAB-2026-001',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _receiveSample,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Registrar recepción'),
              ),
            ),
          ],
          if (status == 'sampled') ...[
            const SizedBox(height: 20),
            const Text('Los datos del catálogo se utilizarán para registrar '
                'resultados de prueba de los exámenes solicitados.'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _processSample,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Procesar resultados de prueba'),
              ),
            ),
          ],
          if (status == 'results_recorded') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _section = 4),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Ver resultados registrados'),
            ),
          ],
        ]),
        icon: Icons.science_outlined,
      ),
    ]);
  }

  Widget _resultsView() {
    final data = _selected;
    if (data == null) return _withoutOrder('Resultados');
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final results = data['results'] as List? ?? [];
    return _panel(
      'Resultados de la orden',
      'Consulta interna. La validación y publicación clínica no están habilitadas.',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _orderHeader(order),
        const SizedBox(height: 18),
        if (results.isEmpty)
          const Text('No hay resultados registrados para esta orden.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Examen')),
                DataColumn(label: Text('Analito')),
                DataColumn(label: Text('Valor')),
                DataColumn(label: Text('Unidad')),
                DataColumn(label: Text('Referencia de prueba')),
              ],
              rows: results.map((item) {
                final row = item as Map;
                return DataRow(cells: [
                  DataCell(Text(_examName('${row['examCode'] ?? ''}'))),
                  DataCell(Text('${row['analyte']}')),
                  DataCell(Text('${row['numericValue']}')),
                  DataCell(Text('${row['unit']}')),
                  DataCell(Text(
                    '${row['referenceMin'] ?? '—'} – ${row['referenceMax'] ?? '—'}',
                  )),
                ]);
              }).toList(),
            ),
          ),
        const SizedBox(height: 14),
        const Text('Los resultados de prueba aún no constituyen informes '
            'clínicos validados ni son visibles para pacientes.'),
      ]),
      icon: Icons.fact_check_outlined,
    );
  }

  Widget _bodyForSection() => switch (_section) {
    0 => _dashboard(),
    1 => _ordersView(),
    2 => _newOrderView(),
    3 => _samplesView(),
    _ => _resultsView(),
  };

  Widget _content() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_nav[_section].$2 == 'Resumen'
                  ? 'Panel del laboratorio'
                  : _nav[_section].$2,
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 5),
              Text(
                'Gestión de órdenes, muestras y resultados.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 10),
              ],
              if (_message != null) ...[
                Text(_message!, style: TextStyle(color: theme.colorScheme.primary)),
                const SizedBox(height: 10),
              ],
              _bodyForSection(),
              const SizedBox(height: 28),
              Text(
                'Vitalia Health · Gestión postanalítica de órdenes, muestras y resultados.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitalia Health'),
        actions: [
          IconButton(
            tooltip: 'Actualizar datos del laboratorio',
            onPressed: _busy || _loading ? null : _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Center(child: Text('Operador de laboratorio')),
          ),
          if (widget.onLogout != null)
            TextButton.icon(
              onPressed: _busy ? null : widget.onLogout,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('Cerrar sesión'),
            ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return _content();
        }
        return Row(children: [
          NavigationRail(
            extended: constraints.maxWidth >= 1250,
            selectedIndex: _section,
            labelType: constraints.maxWidth >= 1250
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            onDestinationSelected: (index) =>
                setState(() => _section = index),
            destinations: _nav
                .map((item) => NavigationRailDestination(
                  icon: Icon(item.$1), label: Text(item.$2),
                ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _content()),
        ]);
      }),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
          ? NavigationBar(
              selectedIndex: _section,
              onDestinationSelected: (index) =>
                  setState(() => _section = index),
              destinations: _nav
                  .map((item) => NavigationDestination(
                    icon: Icon(item.$1), label: item.$2,
                  ))
                  .toList(),
            )
          : null,
    );
  }
}
