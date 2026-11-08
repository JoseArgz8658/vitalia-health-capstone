import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../core/auth_api.dart';

/// Estación de trabajo del operador. Publica SOLO PDFs ya autorizados fuera de Vitalia.
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
    (Icons.picture_as_pdf_outlined, 'Informes PDF'),
  ];

  final _patientController = TextEditingController();
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _receiptNoteController = TextEditingController();
  final _reportIssuer = TextEditingController();
  final _reportReference = TextEditingController();
  XFile? _reportFile;
  DateTime? _reportAuthorizedAt;
  bool _confirmExternal = false;
  bool _confirmPatient = false;
  final Map<String, TextEditingController> _manualControllers = {};
  String? _containerCode;
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
    _receiptNoteController.dispose();
    _reportIssuer.dispose();
    _reportReference.dispose();
    for (final controller in _manualControllers.values) {
      controller.dispose();
    }
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
    final required = (selected['requiredContainers'] as List? ?? []);
    final samples = (selected['samples'] as List? ?? []);
    final received = samples.map((item) => (item as Map)['containerCode']).toSet();
    final pending = required
        .where((item) => !received.contains((item as Map)['code']))
        .toList();
    for (final controller in _manualControllers.values) {
      controller.dispose();
    }
    _manualControllers.clear();
    final codes = (selected['exams'] as List? ?? [])
        .map((item) => (item as Map)['code'])
        .toSet();
    final prior = <String, String>{};
    if (order['status'] == 'review_rejected') {
      for (final item in (selected['results'] as List? ?? [])) {
        final value = item as Map;
        prior['${value['examCode']}::${value['analyte']}'] =
            '${value['numericValue']}';
      }
    }
    for (final exam in _catalog) {
      if (!codes.contains(exam['code'])) continue;
      for (final analyte in (exam['analytes'] as List? ?? [])) {
        final name = (analyte as Map)['analyte'] as String;
        final code = exam['code'] as String;
        _manualControllers['$code::$name'] =
            TextEditingController(text: prior['$code::$name'] ?? '');
      }
    }
    setState(() {
      _selected = selected;
      _barcodeController.clear();
      _receiptNoteController.clear();
      _containerCode = pending.isEmpty ? null : (pending.first as Map)['code'] as String;
      _section = ['report_attached', 'report_published'].contains(order['status'])
          ? 5 : ['results_recorded', 'review_rejected', 'review_approved']
          .contains(order['status']) ? 4 : 3;
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
    final container = _containerCode;
    if (container == null) {
      throw const AuthFailure('No hay tubos pendientes de recepción.');
    }
    final id = order['id'] as String;
    await widget.api.silRequest('/orders/$id/sample', body: {
      'barcode': barcode,
      'containerCode': container,
      if (_receiptNoteController.text.trim().isNotEmpty)
        'receiptNote': _receiptNoteController.text.trim(),
    });
    await _openOrder(id);
    await _refreshAll();
    if (mounted) setState(() => _message = 'Recepción de muestra registrada.');
  });

  Future<void> _selectReportPdf() async {
    try {
      final file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Informe PDF',
          extensions: ['pdf'],
          mimeTypes: ['application/pdf'],
        ),
      ]);
      if (file == null || !mounted) return;
      final size = await file.length();
      if (!mounted) return;
      if (size < 8 || size > 2 * 1024 * 1024) {
        setState(() => _error = 'Selecciona un PDF de prueba de hasta 2 MiB.');
        return;
      }
      setState(() {
        _reportFile = file;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo seleccionar el PDF.');
    }
  }

  Future<void> _selectAuthorizationDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reportAuthorizedAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Fecha de autorización externa',
    );
    if (mounted && date != null) setState(() => _reportAuthorizedAt = date);
  }

  Future<void> _attachExternalReport() => _run(() async {
    final order = _selected?['order'] as Map?;
    if (order == null || order['status'] != 'registered') {
      throw const AuthFailure('Selecciona una orden nueva para adjuntar el PDF.');
    }
    final file = _reportFile;
    if (file == null || _reportAuthorizedAt == null ||
        !_confirmExternal || !_confirmPatient) {
      throw const AuthFailure('Selecciona el PDF, la fecha y confirma sus verificaciones.');
    }
    if (_reportIssuer.text.trim().length < 3 ||
        _reportReference.text.trim().length < 3) {
      throw const AuthFailure('Indica el laboratorio emisor y la referencia de autorización.');
    }
    final bytes = await file.readAsBytes();
    await widget.api.silUploadReport(
      orderId: order['id'] as String,
      fileName: file.name,
      issuer: _reportIssuer.text.trim(),
      authorizationReference: _reportReference.text.trim(),
      authorizedAt: _reportAuthorizedAt!,
      bytes: bytes,
    );
    _reportFile = null;
    await _openOrder(order['id'] as String);
    await _refreshAll();
    if (mounted) {
      setState(() => _message =
          'Informe incorporado. Comprueba la asociación antes de publicarlo.');
    }
  });

  Future<void> _publishExternalReport() async {
    final order = _selected?['order'] as Map?;
    if (order == null || order['status'] != 'report_attached' || _busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar publicación al paciente'),
        content: const Text(
          'Confirma que comprobaste la autorización externa del PDF y '
          'su correspondencia con el paciente. La publicación no equivale '
          'a validar resultados clínicos dentro de Vitalia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Publicar informe')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      await widget.api.silRequest(
        '/orders/${order['id']}/report/publish', body: {});
      await _openOrder(order['id'] as String);
      await _refreshAll();
      if (mounted) setState(() => _message =
          'Informe publicado en el portal de ese paciente. '
          'Aún no se envían notificaciones externas.');
    });
  }

  Future<void> _recordManual() => _run(() async {
    final order = _selected?['order'] as Map?;
    if (order == null || !['sampled', 'review_rejected'].contains(order['status'])) {
      throw const AuthFailure('La orden no está habilitada para ingresar o corregir resultados.');
    }
    final values = <Map<String, dynamic>>[];
    for (final entry in _manualControllers.entries) {
      final input = entry.value.text.trim().replaceAll(',', '.');
      final numeric = double.tryParse(input);
      if (numeric == null || !numeric.isFinite ||
          numeric < -1000000000 || numeric > 1000000000) {
        throw AuthFailure('Ingresa un valor numérico válido para ${entry.key.split('::').last}.');
      }
      final parts = entry.key.split('::');
      values.add({
        'examCode': parts.first,
        'analyte': parts.last,
        'numericValue': numeric,
      });
    }
    if (values.isEmpty) {
      throw const AuthFailure('Esta orden no tiene parámetros definidos.');
    }
    final id = order['id'] as String;
    await widget.api.silRequest('/orders/$id/results', body: {'results': values});
    await _openOrder(id);
    await _refreshAll();
    if (mounted) {
      setState(() => _message = 'Resultados registrados. Pendientes de revisión profesional.');
    }
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
    'review_rejected' => 'Devuelta para corrección',
    'review_approved' => 'Revisión interna aprobada',
    'report_attached' => 'Informe externo recibido',
    'report_published' => 'Informe disponible al paciente',
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
          _metric(Icons.undo_outlined, 'Devueltas para corregir', count('returned')),
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
            DropdownMenuItem(value: 'review_rejected', child: Text('Devueltas para corrección')),
            DropdownMenuItem(value: 'review_approved', child: Text('Revisión aprobada')),
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

  String _auditAction(String code) => switch (code) {
    'order_created' => 'Orden registrada',
    'sample_received' => 'Muestra recibida',
    'results_simulated' => 'Resultados de prueba generados',
    'results_manual' => 'Resultados ingresados manualmente',
    'results_corrected' => 'Resultados corregidos y reenviados',
    'review_approved' => 'Revisión interna aprobada',
    'review_rejected' => 'Orden devuelta con observaciones',
    'external_report_attached' => 'PDF externo incorporado',
    'external_report_published' => 'PDF disponible al paciente',
    'external_report_downloaded' => 'Paciente descargó el PDF',
    _ => code,
  };

  Widget _auditTrail(Map<String, dynamic> data) {
    final audit = data['audit'] as List? ?? [];
    return _panel(
      'Historial de actividad',
      'Registro de acciones, fecha y cuenta responsable.',
      audit.isEmpty
          ? const Text('Sin eventos de auditoría para esta orden.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in audit)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(_auditAction((item as Map)['action'] as String)),
                    subtitle: Text(
                      '${item['actorEmail']} · ${_date(item['createdAt'])}'
                      '${(item['details'] as Map?)?['note'] == null
                          ? '' : ' · ${(item['details'] as Map)['note']}'}',
                    ),
                  ),
              ],
            ),
      icon: Icons.history_outlined,
    );
  }

  Widget _samplesView() {
    final data = _selected;
    if (data == null) return _withoutOrder('Recepción de muestras');
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final status = order['status'] as String?;
    final samples = data['samples'] as List? ?? [];
    final required = data['requiredContainers'] as List? ?? [];
    final received = samples
        .map((entry) => (entry as Map)['containerCode'])
        .toSet();
    final pending = required
        .where((entry) => !received.contains((entry as Map)['code']))
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panel(
        'Recepción y seguimiento de muestras',
        'Cada orden debe contar con los tubos requeridos antes de registrar resultados.',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _orderHeader(order),
          const Divider(height: 30),
          Text('Tubos requeridos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final container in required)
              Chip(
                avatar: Icon(
                  received.contains((container as Map)['code'])
                      ? Icons.check_circle_outline
                      : Icons.hourglass_empty,
                  size: 17,
                ),
                label: Text('${container['label']} · '
                    '${received.contains(container['code']) ? 'Recibido' : 'Pendiente'}'),
              ),
          ]),
          if (samples.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Recepciones registradas',
                style: Theme.of(context).textTheme.titleMedium),
            for (final entry in samples)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('${(entry as Map)['barcode']} · ${entry['containerLabel']}'),
                subtitle: Text('${_date(entry['registeredAt'])} · '
                    '${entry['receivedBy'] ?? 'Registro anterior'}'
                    '${entry['receiptNote'] == null ? '' : ' · ${entry['receiptNote']}'}'),
              ),
          ],
          if (status == 'registered' && pending.isNotEmpty) ...[
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _containerCode,
              decoration: const InputDecoration(
                labelText: 'Tipo de tubo pendiente',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final container in pending)
                  DropdownMenuItem(
                    value: (container as Map)['code'] as String,
                    child: Text(container['label'] as String),
                  ),
              ],
              onChanged: _busy ? null : (value) => setState(() => _containerCode = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _barcodeController,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código de muestra',
                hintText: 'LAB-2026-001',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _receiptNoteController,
              maxLength: 300,
              maxLines: 2,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Observación de recepción (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _receiveSample,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Registrar recepción del tubo'),
              ),
            ),
          ],
          if (status == 'sampled') ...[
            const SizedBox(height: 18),
            const Text('Los tubos requeridos están registrados. Puedes ingresar '
                'los resultados manualmente o generar resultados de prueba.'),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 10, children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => setState(() => _section = 4),
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Ingresar resultados manualmente'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _processSample,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Generar resultados de prueba'),
              ),
            ]),
          ],
          if (['results_recorded','review_rejected','review_approved'].contains(status)) ...[
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
      const SizedBox(height: 14),
      _auditTrail(data),
    ]);
  }

  Widget _manualFields(Map<String, dynamic> data) {
    final selectedCodes = (data['exams'] as List? ?? [])
        .map((item) => (item as Map)['code']).toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Registro manual de resultados',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Ingresa todos los valores del catálogo. '
          'La unidad y la referencia se toman del sistema y no se editan.'),
      const SizedBox(height: 16),
      for (final exam in _catalog)
        if (selectedCodes.contains(exam['code'])) ...[
          Text(exam['name'] as String,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final analyte in (exam['analytes'] as List? ?? []))
              SizedBox(
                width: 245,
                child: TextField(
                  controller: _manualControllers[
                      '${exam['code']}::${(analyte as Map)['analyte']}'],
                  enabled: !_busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: '${analyte['analyte']}',
                    helperText: 'Unidad: ${analyte['unit']}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 18),
        ],
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy || _manualControllers.isEmpty ? null : _recordManual,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Registrar resultados'),
        ),
      ),
    ]);
  }

  Widget _resultsView() {
    final data = _selected;
    if (data == null) return _withoutOrder('Resultados');
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final status = order['status'] as String?;
    final results = data['results'] as List? ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panel(
        'Resultados de la orden',
        'Consulta interna. La revisión y publicación clínica no están habilitadas.',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _orderHeader(order),
          const SizedBox(height: 18),
          if (status == 'registered')
            const Text('Primero se deben registrar todos los tubos requeridos '
                'en la sección Muestras.'),
          if (status == 'sampled' || status == 'review_rejected') ...[
            if (status == 'review_rejected') ...[
              Text(
                'Devuelta por el responsable de revisión. Corrige los valores '
                'y registra nuevamente la orden.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (data['latestReview'] is Map)
                Text('Motivo: ${(data['latestReview'] as Map)['details']?['note'] ?? 'Sin motivo disponible'}'),
              const SizedBox(height: 15),
            ],
            _manualFields(data),
          ],
          if (results.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Examen')),
                  DataColumn(label: Text('Analito')),
                  DataColumn(label: Text('Valor')),
                  DataColumn(label: Text('Unidad')),
                  DataColumn(label: Text('Origen')),
                  DataColumn(label: Text('Referencia de prueba')),
                ],
                rows: results.map((item) {
                  final row = item as Map;
                  final source = switch (row['entryMethod']) {
                    'manual' => 'Manual',
                    'simulated' => 'Prueba automática',
                    _ => 'Registro anterior',
                  };
                  return DataRow(cells: [
                    DataCell(Text(_examName('${row['examCode'] ?? ''}'))),
                    DataCell(Text('${row['analyte']}')),
                    DataCell(Text('${row['numericValue']}')),
                    DataCell(Text('${row['unit']}')),
                    DataCell(Text(source)),
                    DataCell(Text(
                      '${row['referenceMin'] ?? '—'} – ${row['referenceMax'] ?? '—'}',
                    )),
                  ]);
                }).toList(),
              ),
            ),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Los resultados registrados permanecen en el sistema '
                'interno y no se publican en el acceso del paciente.'),
          ],
        ]),
        icon: Icons.fact_check_outlined,
      ),
      const SizedBox(height: 14),
      _auditTrail(data),
    ]);
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
