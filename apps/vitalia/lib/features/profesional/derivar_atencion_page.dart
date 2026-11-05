import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/auth_api.dart';
import 'atenciones_api.dart';

String _requestId() {
  final r = Random.secure(),
      bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class DerivarAtencionPage extends StatefulWidget {
  const DerivarAtencionPage({
    super.key,
    required this.api,
    required this.id,
    required this.onExpired,
  });
  final AtencionesApi api;
  final String id;
  final VoidCallback onExpired;
  @override
  State<DerivarAtencionPage> createState() => _DerivarAtencionPageState();
}

class _DerivarAtencionPageState extends State<DerivarAtencionPage> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _items = <Map<String, dynamic>>[];
  String _request = _requestId();
  String? _selected, _error, _clinic;
  int? _next, _revision;
  bool _busy = false, _confirmed = false, _sent = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _changed() {
    _request = _requestId();
    _confirmed = false;
  }

  Future<void> _load({bool more = false}) async {
    if (_busy || (more && _next == null)) return;
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _items.clear();
        _selected = null;
        _next = null;
        _changed();
      }
    });
    try {
      final data = await widget.api.referralOptions(
        widget.id,
        offset: more ? _next! : 0,
      );
      if (mounted)
        setState(() {
          _items.addAll(
            (data['items'] as List).map(
              (x) => Map<String, dynamic>.from(x as Map),
            ),
          );
          _revision = data['expectedRevision'] as int;
          _clinic = data['clinicName'] as String;
          _next = data['nextOffset'] as int?;
        });
    } on AuthFailure catch (e) {
      if (e.status == 401) {
        widget.onExpired();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = 'No se pudieron consultar los destinatarios.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy ||
        !_confirmed ||
        _selected == null ||
        _revision == null ||
        !_form.currentState!.validate())
      return;
    final choice = _items[int.parse(_selected!)];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.refer(widget.id, {
        'requestId': _request,
        'expectedRevision': _revision,
        'membershipId': choice['membershipId'],
        'branchId': choice['branchId'],
        'specialtyId': choice['specialtyId'],
        'reason': _reason.text.trim(),
        'confirmed': true,
      });
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (e) {
      if (e.status == 401) {
        widget.onExpired();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'No se pudo confirmar la derivación. Conserva los datos para reintentar o vuelve a la bandeja para comprobar el estado.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected == null ? null : _items[int.parse(_selected!)];
    return Scaffold(
      appBar: AppBar(title: const Text('Derivar atención')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_sent) ...[
                    const Icon(Icons.check_circle_outline, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Derivación registrada. El examen quedó a cargo del profesional seleccionado.',
                    ),
                    if (selected != null)
                      Text(
                        '${selected['professionalName']} · ${selected['branchName']}',
                      ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Volver a mis atenciones'),
                    ),
                  ] else ...[
                    Text(
                      _clinic ?? 'Misma clínica',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Elige otro profesional habilitado de esta clínica. Al confirmar, dejarás de ser responsable de esta atención.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _load(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar destinatarios'),
                    ),
                    if (!_busy && _items.isEmpty && _error == null)
                      const Text(
                        'No hay otro profesional habilitado con sucursal y especialidad en esta clínica.',
                      ),
                    if (_items.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'destination-$_selected-${_items.length}',
                        ),
                        initialValue: _selected,
                        isExpanded: true,
                        itemHeight: 72,
                        decoration: const InputDecoration(
                          labelText: 'Destinatario de la derivación',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(
                          _items.length,
                          (i) => DropdownMenuItem(
                            value: '$i',
                            child: Text(
                              '${_items[i]['professionalName']} · ${_items[i]['specialtyName']} · ${_items[i]['branchName']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                _selected = v;
                                _changed();
                              }),
                        validator: (v) =>
                            v == null ? 'Selecciona un destinatario.' : null,
                      ),
                    if (_next != null)
                      TextButton(
                        onPressed: _busy ? null : () => _load(more: true),
                        child: const Text('Cargar más destinatarios'),
                      ),
                    if (selected != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(selected['professionalName'] as String),
                              Text(selected['specialtyName'] as String),
                              Text(selected['branchName'] as String),
                              Text(
                                '${selected['street']} ${selected['addressNumber']}, ${selected['communeName']}',
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _reason,
                      enabled: !_busy,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Motivo de la derivación',
                        helperText: 'Este motivo será visible para el paciente y el nuevo responsable.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(_changed),
                      validator: (v) => (v ?? '').trim().length < 5
                          ? 'Escribe un motivo de al menos 5 caracteres.'
                          : null,
                    ),
                    CheckboxListTile(
                      value: _confirmed,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _confirmed = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Confirmo el profesional, la sucursal y el motivo de esta derivación',
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy || !_confirmed || _selected == null
                          ? null
                          : _send,
                      child: const Text('Confirmar derivación'),
                    ),
                  ],
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
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
