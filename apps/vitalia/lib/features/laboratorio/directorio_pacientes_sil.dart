import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

/// Directorio exclusivamente sintético. El servidor devuelve páginas pequeñas
/// y aplica todos los filtros: la interfaz nunca trae los 100+ pacientes juntos.
class DirectorioPacientesSil extends StatefulWidget {
  const DirectorioPacientesSil({
    super.key,
    required this.api,
    required this.onExpired,
    required this.onOpenProfile,
    required this.onPrepareRequest,
    required this.onViewOrders,
    this.selectedEmail,
  });

  final AuthApi api;
  final VoidCallback onExpired;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<String> onPrepareRequest;
  final ValueChanged<String> onViewOrders;
  final String? selectedEmail;

  @override
  State<DirectorioPacientesSil> createState() => DirectorioPacientesSilState();
}

class DirectorioPacientesSilState extends State<DirectorioPacientesSil> {
  static const _pageSize = 20;
  static const _ink = Color(0xFF22394B);
  static const _line = Color(0xFFE0E7ED);
  static const _subtle = Color(0xFFF4F7FA);
  static const _accent = Color(0xFF245D72);

  final _search = TextEditingController();
  String _submittedSearch = '';
  String _profile = 'all';
  String _orders = 'all';
  String _sex = 'all';
  String _sort = 'name';
  int _offset = 0;
  int _total = 0;
  int _requestId = 0;
  int _filterVersion = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _patients = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _requestId++;
    _search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final id = ++_requestId;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final params = <String, String>{
        'limit': '$_pageSize',
        'offset': '$_offset',
        if (_submittedSearch.isNotEmpty) 'search': _submittedSearch,
        'profile': _profile,
        'orders': _orders,
        'sex': _sex,
        'sort': _sort,
      };
      final data = await widget.api.silRequest(
        '/patients/list?${Uri(queryParameters: params).query}',
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _patients = (data['patients'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } on AuthFailure catch (error) {
      if (!mounted || id != _requestId) return;
      if (error.status == 401) {
        widget.onExpired();
        return;
      }
      setState(() { _error = error.message; _loading = false; });
    } catch (_) {
      if (mounted && id == _requestId) {
        setState(() {
          _error = 'No se pudo consultar el directorio. Comprueba que la API DEMO esté actualizada.';
          _loading = false;
        });
      }
    }
  }

  void _applySearch() {
    final value = _search.text.trim();
    if (value.length > 100) {
      setState(() => _error = 'Utiliza una búsqueda de hasta 100 caracteres.');
      return;
    }
    setState(() { _submittedSearch = value; _offset = 0; });
    refresh();
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _submittedSearch = '';
      _profile = 'all';
      _orders = 'all';
      _sex = 'all';
      _sort = 'name';
      _offset = 0;
      _filterVersion++;
    });
    refresh();
  }

  void _changePage(int offset) {
    if (_loading || offset < 0 || offset >= _total) return;
    setState(() => _offset = offset);
    refresh();
  }

  String _name(Map<String, dynamic> patient) {
    final given = (patient['givenNames'] as String? ?? '').trim();
    final family = (patient['familyNames'] as String? ?? '').trim();
    final name = '$given $family'.trim();
    return name.isEmpty ? 'Ficha pendiente' : name;
  }

  bool _complete(Map<String, dynamic> patient) =>
      patient['syntheticIdentifier'] is String &&
      (patient['givenNames'] as String? ?? '').trim().isNotEmpty &&
      (patient['familyNames'] as String? ?? '').trim().isNotEmpty &&
      patient['birthDate'] is String;

  int _orderCount(Map<String, dynamic> patient) =>
      (patient['orderCount'] as num?)?.toInt() ?? 0;

  Widget _status(Map<String, dynamic> patient) {
    final complete = _complete(patient);
    return Tooltip(
      message: complete
          ? 'Identidad sintética disponible para cotejo documental'
          : 'Faltan datos DEMO para cotejar una solicitud',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: complete ? const Color(0xFFEAF3F0) : const Color(0xFFFFF5E7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(complete ? 'Completa' : 'Por completar',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: complete ? const Color(0xFF24634E) : const Color(0xFF87602B),
          ),
        ),
      ),
    );
  }

  Widget _actions(Map<String, dynamic> patient) {
    final email = patient['email'] as String;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: () => widget.onOpenProfile(email),
          icon: const Icon(Icons.badge_outlined, size: 17),
          label: const Text('Ficha'),
        ),
        Tooltip(
          message: _complete(patient)
              ? 'Recibir solicitud médica del paciente'
              : 'Primero completa la ficha de identidad DEMO',
          child: TextButton.icon(
            onPressed: _complete(patient)
                ? () => widget.onPrepareRequest(email) : null,
            icon: const Icon(Icons.note_add_outlined, size: 17),
            label: const Text('Solicitud'),
          ),
        ),
        Tooltip(
          message: _orderCount(patient) > 0
              ? 'Ver las órdenes de esta cuenta'
              : 'Esta cuenta todavía no tiene órdenes',
          child: TextButton.icon(
            onPressed: _orderCount(patient) > 0
                ? () => widget.onViewOrders(email) : null,
            icon: const Icon(Icons.assignment_outlined, size: 17),
            label: const Text('Órdenes'),
          ),
        ),
      ],
    );
  }

  Widget _patientCard(Map<String, dynamic> patient) {
    final selected = widget.selectedEmail == patient['email'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEAF3F5) : Colors.white,
        border: Border.all(color: selected ? _accent : _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: const Color(0xFFE9F0F5),
            child: const Icon(Icons.person_outline, color: _accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name(patient),
                style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
            Text('${patient['email']}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
          ])),
          _status(patient),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 13, runSpacing: 4, children: [
          Text('${patient['syntheticIdentifier'] ?? 'Sin identificador DEMO'}',
              style: Theme.of(context).textTheme.bodySmall),
          if (patient['birthDate'] != null)
            Text('Nac.: ${patient['birthDate']}',
                style: Theme.of(context).textTheme.bodySmall),
          Text('${_orderCount(patient)} órdenes',
              style: Theme.of(context).textTheme.bodySmall),
          if (patient['lastOrderNumber'] != null)
            Text('Última: ${patient['lastOrderNumber']}',
                style: Theme.of(context).textTheme.bodySmall),
        ]),
        if (!_complete(patient)) ...[
          const SizedBox(height: 5),
          const Text('Completa la ficha antes de asociar una solicitud.',
            style: TextStyle(fontSize: 12, color: Color(0xFF87602B))),
        ],
        const SizedBox(height: 5),
        _actions(patient),
      ]),
    );
  }

  Widget _patientTable() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      headingRowColor: const WidgetStatePropertyAll(_subtle),
      columnSpacing: 18,
      dataRowMinHeight: 56,
      dataRowMaxHeight: 86,
      columns: const [
        DataColumn(label: Text('Paciente y cuenta')),
        DataColumn(label: Text('Identificador')),
        DataColumn(label: Text('Fecha nac.')),
        DataColumn(label: Text('Ficha')),
        DataColumn(label: Text('Órdenes')),
        DataColumn(label: Text('Última')),
        DataColumn(label: Text('Acciones')),
      ],
      rows: [
        for (final patient in _patients)
          DataRow(
            selected: widget.selectedEmail == patient['email'],
            cells: [
              DataCell(SizedBox(
                width: 205,
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name(patient), maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${patient['email']}', maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                  ]),
              )),
              DataCell(Text('${patient['syntheticIdentifier'] ?? '—'}')),
              DataCell(Text('${patient['birthDate'] ?? '—'}')),
              DataCell(_status(patient)),
              DataCell(Text('${_orderCount(patient)}')),
              DataCell(Text('${patient['lastOrderNumber'] ?? '—'}')),
              DataCell(_actions(patient)),
            ],
          ),
      ],
    ),
  );

  Widget _dropdown(String label, String value, List<DropdownMenuItem<String>> options,
      ValueChanged<String?> onChanged, double width) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$_filterVersion'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: options,
        onChanged: (v) {
          if (v == null) return;
          onChanged(v);
          setState(() => _offset = 0);
          refresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12, runSpacing: 8, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Directorio de pacientes',
                  style: text.titleLarge?.copyWith(color: _ink)),
                Text('Cuentas ficticias · $_total resultados',
                  style: text.bodySmall),
              ]),
              OutlinedButton.icon(
                onPressed: _loading ? null : refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualizar'),
              ),
            ]),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            maxLength: 100,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _applySearch(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Buscar paciente',
              hintText: 'Nombre, apellido, correo o identificador DEMO',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'Buscar pacientes',
                onPressed: _applySearch,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 11),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 870 ? 4 : width >= 480 ? 2 : 1;
            final fieldWidth = (width - (columns - 1) * 8) / columns;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              _dropdown('Estado ficha', _profile, const [
                DropdownMenuItem(value: 'all', child: Text('Todas')),
                DropdownMenuItem(value: 'complete', child: Text('Completas')),
                DropdownMenuItem(value: 'incomplete', child: Text('Por completar')),
              ], (value) => _profile = value!, fieldWidth),
              _dropdown('Órdenes', _orders, const [
                DropdownMenuItem(value: 'all', child: Text('Con y sin órdenes')),
                DropdownMenuItem(value: 'with', child: Text('Con órdenes')),
                DropdownMenuItem(value: 'without', child: Text('Sin órdenes')),
              ], (value) => _orders = value!, fieldWidth),
              _dropdown('Sexo de referencia', _sex, const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'female', child: Text('Femenino')),
                DropdownMenuItem(value: 'male', child: Text('Masculino')),
                DropdownMenuItem(value: 'not_specified', child: Text('No especificado')),
              ], (value) => _sex = value!, fieldWidth),
              _dropdown('Ordenar por', _sort, const [
                DropdownMenuItem(value: 'name', child: Text('Apellido y nombre')),
                DropdownMenuItem(value: 'recent', child: Text('Actividad reciente')),
              ], (value) => _sort = value!, fieldWidth),
            ]);
          }),
          Align(alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _loading ? null : _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
              label: const Text('Limpiar filtros'),
            )),
          const Divider(height: 17),
          if (_loading)
            const LinearProgressIndicator(semanticsLabel: 'Buscando pacientes')
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            )
          else if (_patients.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Column(children: [
                const Icon(Icons.person_search_outlined, size: 32, color: _accent),
                const SizedBox(height: 8),
                const Text('No hay pacientes para estos filtros.'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Mostrar todas las cuentas DEMO'),
                ),
              ]),
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth < 940) {
                return Column(children: [
                  for (final patient in _patients) _patientCard(patient),
                ]);
              }
              return _patientTable();
            }),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10, runSpacing: 8, children: [
              Text(_total == 0 ? '0 resultados' :
                'Mostrando ${_offset + 1}–${(_offset + _patients.length).clamp(0, _total)} de $_total',
                style: text.bodySmall),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Página anterior de pacientes',
                  onPressed: !_loading && _offset > 0
                      ? () => _changePage(_offset - _pageSize) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Página ${(_offset ~/ _pageSize) + 1}',
                    style: text.bodySmall),
                IconButton(
                  tooltip: 'Página siguiente de pacientes',
                  onPressed: !_loading && _offset + _pageSize < _total
                      ? () => _changePage(_offset + _pageSize) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
            ]),
        ]),
      ),
    );
  }
}
