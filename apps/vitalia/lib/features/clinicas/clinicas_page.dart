import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import '../perfil/ubicacion_panel.dart';

class ClinicasPage extends StatefulWidget {
  const ClinicasPage({
    super.key,
    required this.api,
    required this.onExpired,
    this.clinic,
  });
  final AuthApi api;
  final VoidCallback onExpired;
  final Map<String, dynamic>? clinic;
  @override
  State<ClinicasPage> createState() => _ClinicasPageState();
}

class _ClinicasPageState extends State<ClinicasPage> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final k in [
      'name',
      'contactPhone',
      'street',
      'addressNumber',
      'floor',
      'unit',
    ])
      k: TextEditingController(),
  };
  List<Map<String, dynamic>> _items = [];
  bool _busy = false, _editing = false;
  int _offset = 0;
  String? _message, _commune, _requestId;
  bool get _branch => widget.clinic != null;
  String _uuid() {
    final r = Random.secure();
    final b = List.generate(16, (_) => 0);
    for (var i = 0; i < 16; i++) {
      b[i] = r.nextInt(256);
    }
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _failure(AuthFailure e) {
    if (e.status == 401) {
      widget.onExpired();
    } else if (mounted) {
      setState(() => _message = e.message);
    }
  }

  Future<void> _load(int offset) async {
    if (_busy || _editing) return;
    setState(() {
      _busy = true;
      _message = null;
      _items = [];
    });
    try {
      final rows = await widget.api.institutions(
        clinicId: widget.clinic?['id'] as String?,
        offset: offset,
      );
      if (mounted)
        setState(() {
          _items = rows;
          _offset = offset;
        });
    } on AuthFailure catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _start() {
    for (final c in _fields.values) {
      c.clear();
    }
    setState(() {
      _editing = true;
      _message = null;
      _commune = null;
      _requestId = null;
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_branch && _commune == null) {
      setState(() => _message = 'Selecciona la comuna de la sucursal.');
      return;
    }
    _requestId ??= _uuid();
    String? value(String k) {
      final s = _fields[k]!.text.trim();
      return s.isEmpty ? null : s;
    }

    final body = <String, dynamic>{
      'requestId': _requestId,
      'name': value('name'),
      'contactPhone': value('contactPhone'),
      if (_branch) ...{
        'communeCode': _commune,
        'street': value('street'),
        'addressNumber': value('addressNumber'),
        'floor': value('floor'),
        'unit': value('unit'),
      },
    };
    setState(() {
      _busy = true;
      _message = null;
    });
    var saved = false;
    try {
      await widget.api.createInstitution(
        body,
        clinicId: widget.clinic?['id'] as String?,
      );
      saved = true;
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _editing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_branch ? 'Sucursal guardada.' : 'Clínica guardada.'),
          ),
        );
      }
    } on AuthFailure catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (saved && mounted) await _load(0);
  }

  Widget _field(
    String k,
    String label, {
    bool required = false,
    int max = 150,
    String? hint,
    String? help,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: _fields[k],
      enabled: !_busy,
      maxLength: max,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: help == null
            ? null
            : Tooltip(
                message: help,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.help_outline),
                ),
              ),
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _requestId = null,
      validator: (v) => required && (v?.trim().isEmpty ?? true)
          ? 'Completa este dato.'
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _branch
            ? 'Sucursales de ${widget.clinic!['name']}'
            : 'Clínicas y sucursales',
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _branch
                      ? Icons.location_city_outlined
                      : Icons.local_hospital_outlined,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _branch
                      ? 'Sucursales de la clínica'
                      : 'Gestión institucional',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Gestiona los datos de instituciones. Esta sección no permite consultar exámenes ni designar jefes clínicos.',
                ),
                const SizedBox(height: 20),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(liveRegion: true, child: Text(_message!)),
                  ),
                if (!_editing)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                (_branch && widget.clinic!['active'] != true)
                            ? null
                            : _start,
                        icon: const Icon(Icons.add),
                        label: Text(
                          _branch ? 'Agregar sucursal' : 'Agregar clínica',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _load(_offset),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar'),
                      ),
                    ],
                  ),
                if (_editing)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _branch ? 'Nueva sucursal' : 'Nueva clínica',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 20),
                            _field(
                              'name',
                              _branch
                                  ? 'Nombre de la sucursal'
                                  : 'Nombre de la clínica',
                              required: true,
                            ),
                            _field(
                              'contactPhone',
                              'Teléfono de contacto (opcional)',
                              max: 40,
                            ),
                            if (_branch) ...[
                              _field(
                                'street',
                                'Calle',
                                required: true,
                                max: 200,
                              ),
                              _field(
                                'addressNumber',
                                'Número de la dirección',
                                hint: 'Ej.: 1234 o S/N (sin número)',
                                help:
                                    'Ingresa el número, por ejemplo 1234. Si no tiene, escribe S/N (sin número).',
                                required: true,
                                max: 40,
                              ),
                              _field('floor', 'Piso (opcional)', max: 40),
                              _field(
                                'unit',
                                'Unidad u oficina (opcional)',
                                max: 40,
                              ),
                              UbicacionPanel(
                                api: widget.api,
                                value: _commune,
                                editing: true,
                                enabled: !_busy,
                                onChanged: (v) => setState(() {
                                  _commune = v;
                                  _requestId = null;
                                }),
                                onExpired: widget.onExpired,
                                loadCatalog: widget.api.institutionTerritories,
                                requiredLocation: true,
                              ),
                            ],
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton(
                                  onPressed: _busy ? null : _save,
                                  child: const Text('Guardar'),
                                ),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _editing = false;
                                          _message = null;
                                          _requestId = null;
                                        }),
                                  child: const Text('Cancelar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (!_busy && !_editing && _message == null && _items.isEmpty)
                  const Text('No hay registros en esta página.'),
                if (!_editing)
                  ..._items.map(
                    (x) => Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              x['name'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(x['active'] == true ? 'Activa' : 'Inactiva'),
                            if (x['contactPhone'] != null)
                              Text('Contacto: ${x['contactPhone']}'),
                            if (_branch)
                              Text(
                                '${x['street']} ${x['addressNumber']} · Comuna ${x['communeName'] ?? x['communeCode']}',
                              ),
                            if (_branch && x['floor'] != null)
                              Text('Piso: ${x['floor']}'),
                            if (_branch && x['unit'] != null)
                              Text('Unidad: ${x['unit']}'),
                            if (!_branch)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => ClinicasPage(
                                            api: widget.api,
                                            onExpired: widget.onExpired,
                                            clinic: x,
                                          ),
                                        ),
                                      ),
                                child: const Text('Ver sucursales'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!_editing)
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Página ${_offset ~/ 20 + 1}'),
                      TextButton(
                        onPressed: _busy || _offset == 0
                            ? null
                            : () => _load(_offset - 20),
                        child: const Text('Anterior'),
                      ),
                      TextButton(
                        onPressed:
                            _busy || _items.length < 20 || _offset >= 10000
                            ? null
                            : () => _load(_offset + 20),
                        child: const Text('Siguiente'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
