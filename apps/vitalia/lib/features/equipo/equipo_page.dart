import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'credenciales_profesionales_page.dart';

class EquipoPage extends StatefulWidget {
  const EquipoPage({
    super.key,
    required this.api,
    required this.clinicId,
    required this.clinicName,
    required this.admin,
    required this.onExpired,
  });
  final AuthApi api;
  final String clinicId;
  final String clinicName;
  final bool admin;
  final VoidCallback onExpired;
  @override
  State<EquipoPage> createState() => _EquipoPageState();
}

class _EquipoPageState extends State<EquipoPage> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  List<dynamic> _members = [], _branches = [], _specialties = [];
  final _histories = <String, List<dynamic>>{};
  Map<String, dynamic>? _editing;
  final Set<String> _branchIds = {}, _specialtyIds = {};
  int _offset = 0;
  bool _busy = false, _active = true;
  String? _message, _requestId;
  @override
  void initState() {
    super.initState();
    _run(() => _load(0));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _id() {
    final b = List.generate(16, (_) => Random.secure().nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
    } on AuthFailure catch (e) {
      if (mounted) {
        if (e.status == 401) {
          widget.onExpired();
        } else {
          setState(() => _message = e.message);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(int offset) async {
    final r = await widget.api.team(widget.clinicId, offset: offset);
    if (mounted)
      setState(() {
        _members = r['members'] as List;
        _branches = r['branches'] as List;
        _specialties = r['specialties'] as List;
        _offset = offset;
        _histories.clear();
      });
  }

  Set<String> _ids(dynamic values) =>
      (values as List).map((v) => v['id'] as String).toSet();
  bool _same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
  bool get _changed =>
      _editing != null &&
      (_active != _editing!['active'] ||
          !_same(_branchIds, _ids(_editing!['branches'])) ||
          !_same(_specialtyIds, _ids(_editing!['specialties'])));
  void _edit(Map<String, dynamic> m) {
    setState(() {
      _editing = Map.from(m);
      _active = m['active'] as bool;
      _branchIds
        ..clear()
        ..addAll(_ids(m['branches']));
      _specialtyIds
        ..clear()
        ..addAll(_ids(m['specialties']));
      _reason.clear();
      _requestId = null;
      _message = null;
    });
  }

  void _cancel() {
    setState(() {
      _editing = null;
      _reason.clear();
      _requestId = null;
      _branchIds.clear();
      _specialtyIds.clear();
    });
  }

  Future<void> _save() async {
    if (_busy || !_changed || !_form.currentState!.validate()) return;
    final m = _editing!;
    _requestId ??= _id();
    final body = {
      'requestId': _requestId,
      'expectedRevision': m['revision'],
      'active': _active,
      'branchIds': _branchIds.toList(),
      'specialtyIds': _specialtyIds.toList(),
      'reason': _reason.text.trim(),
    };
    await _run(() async {
      await widget.api.team(
        widget.clinicId,
        memberId: m['id'] as String,
        update: body,
      );
      if (!mounted) return;
      _cancel();
      await _load(_offset);
      if (mounted)
        setState(
          () => _message =
              'Pertenencia actualizada. El cambio quedó registrado en el historial.',
        );
    });
  }

  List<dynamic> _options(List<dynamic> catalog, dynamic existing) {
    final map = <String, dynamic>{
      for (final v in catalog) v['id'] as String: v,
      for (final v in existing as List) v['id'] as String: v,
    };
    return map.values.toList();
  }

  Widget _choices(
    String title,
    List<dynamic> catalog,
    dynamic existing,
    Set<String> selection,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      ..._options(catalog, existing).map(
        (v) => CheckboxListTile(
          title: Text(
            '${v['name']}${v['active'] == true ? '' : ' (inactiva; relación conservada)'}',
          ),
          value: selection.contains(v['id']),
          onChanged: _busy
              ? null
              : (checked) => setState(() {
                  if (checked == true) {
                    selection.add(v['id'] as String);
                  } else {
                    selection.remove(v['id']);
                  }
                  _requestId = null;
                }),
        ),
      ),
    ],
  );
  String _state(dynamic value) =>
      value['active'] == true ? 'Activa' : 'Suspendida';
  String _names(dynamic values) => (values as List).isEmpty
      ? 'Sin selección'
      : values.map((v) => v['name']).join(', ');
  String _historicalNames(dynamic ids, List<dynamic> options) {
    final names = {for (final o in options) o['id']: o['name']};
    final list = ids as List;
    return list.isEmpty
        ? 'Sin selección'
        : list
              .map((id) => names[id] ?? 'Elemento del catálogo anterior')
              .join(', ');
  }

  Widget _history(Map<String, dynamic> member) {
    final items = _histories[member['id']];
    if (items == null)
      return TextButton(
        onPressed: _busy
            ? null
            : () => _run(() async {
                final r = await widget.api.team(
                  widget.clinicId,
                  memberId: member['id'] as String,
                  history: true,
                );
                if (mounted)
                  setState(
                    () =>
                        _histories[member['id'] as String] = r['items'] as List,
                  );
              }),
        child: const Text('Ver historial'),
      );
    final branches = _options(_branches, member['branches']),
        specialties = _options(_specialties, member['specialties']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Últimos 20 cambios de pertenencia'),
        if (items.isEmpty)
          const Text('Todavía no hay cambios registrados en este módulo.'),
        ...items.map(
          (h) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${h['createdAt']} · ${h['actorEmail']}'),
                Text('Motivo: ${h['reason']}'),
                Text('Antes: ${_state(h['beforeState'])}'),
                Text(
                  'Sucursales anteriores: ${_historicalNames(h['beforeState']['branchIds'], branches)}',
                ),
                Text(
                  'Especialidades anteriores: ${_historicalNames(h['beforeState']['specialtyIds'], specialties)}',
                ),
                Text('Después: ${_state(h['afterState'])}'),
                Text(
                  'Sucursales posteriores: ${_historicalNames(h['afterState']['branchIds'], branches)}',
                ),
                Text(
                  'Especialidades posteriores: ${_historicalNames(h['afterState']['specialtyIds'], specialties)}',
                ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _histories.remove(member['id'])),
          child: const Text('Ocultar historial'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Equipo de ${widget.clinicName}')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.admin
                      ? 'Consulta administrativa. Los cambios de pertenencia corresponden al jefe clínico autorizado.'
                      : 'Gestiona las pertenencias de los profesionales de esta clínica.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Suspender afecta solo esta pertenencia y conserva la cuenta y el historial. Las asignaciones de pacientes del flujo actual se gestionan por separado.',
                ),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                if (_editing == null)
                  TextButton(
                    onPressed: _busy ? null : () => _run(() => _load(_offset)),
                    child: const Text('Actualizar equipo'),
                  ),
                if (_editing != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Editar pertenencia de ${_editing!['firstName']} ${_editing!['firstSurname']}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(_editing!['email'] as String),
                            SwitchListTile(
                              title: const Text('Pertenencia activa'),
                              subtitle: Text(
                                _active
                                    ? 'Puede participar según sus permisos y asignaciones.'
                                    : 'Se guardará como suspendida en esta clínica.',
                              ),
                              value: _active,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                      _active = v;
                                      _requestId = null;
                                    }),
                            ),
                            _choices(
                              'Sucursales de esta clínica',
                              _branches,
                              _editing!['branches'],
                              _branchIds,
                            ),
                            _choices(
                              'Especialidades en esta clínica',
                              _specialties,
                              _editing!['specialties'],
                              _specialtyIds,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _reason,
                              enabled: !_busy,
                              maxLength: 500,
                              decoration: const InputDecoration(
                                labelText: 'Motivo del cambio',
                                hintText:
                                    'Ej.: cambio de sucursal o suspensión temporal',
                                helperText:
                                    'No incluyas datos de pacientes ni contraseñas.',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _requestId = null,
                              validator: (v) => (v ?? '').trim().length < 5
                                  ? 'Explica el motivo con al menos 5 caracteres.'
                                  : null,
                            ),
                            Wrap(
                              spacing: 12,
                              children: [
                                FilledButton(
                                  onPressed: _busy || !_changed ? null : _save,
                                  child: const Text('Guardar cambios'),
                                ),
                                TextButton(
                                  onPressed: _busy ? null : _cancel,
                                  child: const Text('Cancelar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_editing == null) ...[
                  if (!_busy && _message == null && _members.isEmpty)
                    const Text('No hay profesionales en esta página.'),
                  ..._members.map((v) {
                    final m = Map<String, dynamic>.from(v as Map);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${m['firstName']} ${m['firstSurname']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(m['email'] as String),
                            Text(
                              m['clinicalRole'] == 'jefe_clinico'
                                  ? 'Jefe clínico'
                                  : 'Profesional',
                            ),
                            Text('Pertenencia: ${_state(m)}'),
                            Text('Sucursales: ${_names(m['branches'])}'),
                            Text(
                              'Especialidades de esta clínica: ${_names(m['specialties'])}',
                            ),
                            if (!widget.admin &&
                                m['clinicalRole'] == 'profesional')
                              TextButton(
                                onPressed: _busy ? null : () => _edit(m),
                                child: const Text('Editar pertenencia'),
                              ),
                            if (m['clinicalRole'] == 'jefe_clinico')
                              const Text(
                                'La gestión de jefaturas requiere su procedimiento institucional.',
                              ),
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            CredencialesProfesionalesPage(
                                              api: widget.api,
                                              clinicId: widget.clinicId,
                                              memberId: m['id'] as String,
                                              professionalName:
                                                  '${m['firstName']} ${m['firstSurname']}',
                                              onExpired: widget.onExpired,
                                            ),
                                      ),
                                    ),
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('Credenciales profesionales'),
                            ),
                            _history(m),
                          ],
                        ),
                      ),
                    );
                  }),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Página ${_offset ~/ 20 + 1}'),
                      TextButton(
                        onPressed: _busy || _offset == 0
                            ? null
                            : () => _run(() => _load(_offset - 20)),
                        child: const Text('Anterior'),
                      ),
                      TextButton(
                        onPressed:
                            _busy || _members.length < 20 || _offset >= 10000
                            ? null
                            : () => _run(() => _load(_offset + 20)),
                        child: const Text('Siguiente'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
