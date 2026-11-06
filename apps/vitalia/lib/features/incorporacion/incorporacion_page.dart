import '../equipo/equipo_page.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';

class IncorporacionPage extends StatefulWidget {
  const IncorporacionPage({
    super.key,
    required this.api,
    required this.admin,
    required this.onExpired,
  });
  final AuthApi api;
  final bool admin;
  final VoidCallback onExpired;
  @override
  State<IncorporacionPage> createState() => _IncorporacionPageState();
}

class _IncorporacionPageState extends State<IncorporacionPage> {
  List<dynamic> _clinics = [];
  Map<String, dynamic>? _detail;
  String? _clinic, _mode, _authorization, _message, _token;
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final Set<String> _branches = {}, _specialties = {}, _confirmed = {};
  bool _busy = false;
  String _id() {
    final b = List.generate(16, (_) => Random.secure().nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  TextEditingController _c(String key) =>
      _fields.putIfAbsent(key, TextEditingController.new);
  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _token = null;
    super.dispose();
  }

  void _failure(AuthFailure e) {
    if (!mounted) return;
    if (e.status == 401) {
      widget.onExpired();
    } else {
      setState(() => _message = e.message);
    }
  }

  Future<void> _loadContext() async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.onboarding('/context');
      if (mounted) setState(() => _clinics = r['clinics'] as List);
    } on AuthFailure catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    if (_clinic == null) return;
    final r = await widget.api.onboarding('/$_clinic');
    if (mounted) setState(() => _detail = r);
  }

  Future<void> _work(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await fn();
    } on AuthFailure catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    setState(() {
      _mode = null;
      _authorization = null;
      _branches.clear();
      _specialties.clear();
      for (final c in _fields.values) {
        c.clear();
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await _work(() async {
      final Map<String, dynamic> body;
      final String path;
      if (_mode == 'authorization') {
        final raw = _c('requestedAt').text.trim();
        final date = DateTime.tryParse('${raw}T00:00:00Z');
        if (date == null ||
            date.toIso8601String().substring(0, 10) != raw ||
            date.isAfter(DateTime.now())) {
          throw const AuthFailure(
            'Usa una fecha válida: AAAA-MM-DD, por ejemplo 2026-10-29, que no sea futura.',
          );
        }
        path = 'authorizations';
        body = {
          'requestId': _id(),
          'nomineeEmail': _c('nomineeEmail').text.trim(),
          'requesterName': _c('requesterName').text.trim(),
          'requesterPosition': _c('requesterPosition').text.trim(),
          'requesterContact': _c('requesterContact').text.trim(),
          'evidenceReference': _c('evidenceReference').text.trim(),
          'requestedAt': date.toIso8601String(),
        };
      } else if (_mode == 'specialty') {
        path = 'specialties';
        body = {'name': _c('specialty').text.trim()};
      } else {
        if (widget.admin && _authorization == null)
          throw const AuthFailure(
            'Selecciona una autorización verificada para ese correo.',
          );
        path = 'invitations';
        body = {
          'requestId': _id(),
          'email': _c('email').text.trim(),
          'authorizationId': widget.admin ? _authorization : null,
          'branchIds': _branches.toList(),
          'specialtyIds': _specialties.toList(),
        };
      }
      final r = await widget.api.onboarding('/$_clinic/$path', body: body);
      if (!mounted) return;
      setState(() {
        _token = r['token'] as String? ?? _token;
        _message = path == 'invitations'
            ? 'Invitación creada. Entrega el código solo al destinatario.'
            : 'Registro guardado.';
      });
      _cancel();
      await _load();
    });
  }

  Widget _field(String key, String label, {int max = 150, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _c(key),
          enabled: !_busy,
          maxLength: max,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Completa este dato.' : null,
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.admin ? 'Incorporación institucional' : 'Equipo de mi clínica',
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
                const Text(
                  'La incorporación a una clínica no concede acceso automático a exámenes. La habilitación profesional se verifica por separado.',
                ),
                const SizedBox(height: 20),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                if (!_busy && _clinics.isEmpty)
                  Text(
                    widget.admin
                        ? 'Crea primero una clínica activa en Clínicas y sucursales.'
                        : 'No tienes una pertenencia activa como jefe clínico. No puedes invitar profesionales.',
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _clinic,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Clínica'),
                  items: _clinics
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c['id'] as String,
                          child: Text(c['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() {
                            _clinic = v;
                            _detail = null;
                            _token = null;
                            _confirmed.clear();
                          });
                          _cancel();
                          _work(_load);
                        },
                ),
                if (_detail != null) ...[
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => EquipoPage(
                                api: widget.api,
                                clinicId: _clinic!,
                                clinicName:
                                    _clinics.firstWhere(
                                          (c) => c['id'] == _clinic,
                                        )['name']
                                        as String,
                                admin: widget.admin,
                                onExpired: widget.onExpired,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Ver equipo de esta clínica'),
                  ),
                  const SizedBox(height: 20),
                  if (_token != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Código privado: se muestra una sola vez. Entrégalo al correo invitado junto con la dirección de activación indicada aquí. No lo publiques en capturas ni documentación. Vence a las 48 horas de emisión.',
                            ),
                            const Text(
                              'Entrega manual: comparte la dirección y el código por privado.',
                            ),
                            SelectableText(widget.api.invitationActivationUrl),
                            const Text(
                              'Entrega por correo: pendiente de configurar el servicio de envío.',
                            ),
                            SelectableText(_token!),
                            TextButton(
                              onPressed: () => setState(() => _token = null),
                              child: const Text('Ocultar código'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_mode == null)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (widget.admin)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _mode = 'authorization'),
                            child: const Text('Registrar autorización'),
                          ),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _mode = 'invitation'),
                          child: Text(
                            widget.admin
                                ? 'Invitar primer jefe clínico'
                                : 'Invitar profesional',
                          ),
                        ),
                        if (widget.admin)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _mode = 'specialty'),
                            child: const Text('Agregar especialidad'),
                          ),
                        TextButton(
                          onPressed: _busy ? null : () => _work(_load),
                          child: const Text('Actualizar'),
                        ),
                      ],
                    ),
                  if (_mode != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_mode == 'authorization') ...[
                                const Text(
                                  'Registra la solicitud recibida fuera de la aplicación. Conserva la autorización en el canal institucional; aquí ingresa su referencia, sin contraseñas ni códigos privados.',
                                ),
                                const SizedBox(height: 16),
                                _field(
                                  'nomineeEmail',
                                  'Correo del jefe clínico designado',
                                  max: 254,
                                ),
                                _field(
                                  'requesterName',
                                  'Nombre de quien solicita',
                                ),
                                _field(
                                  'requesterPosition',
                                  'Cargo o representación institucional',
                                ),
                                _field(
                                  'requesterContact',
                                  'Contacto institucional del solicitante',
                                  max: 254,
                                ),
                                _field(
                                  'evidenceReference',
                                  'Referencia de la autorización',
                                  max: 500,
                                  hint: 'Ej.: acta interna AUT-2026-001',
                                ),
                                _field(
                                  'requestedAt',
                                  'Fecha de la solicitud (AAAA-MM-DD)',
                                  max: 10,
                                  hint: 'Ej.: 2026-10-29',
                                ),
                              ] else if (_mode == 'specialty') ...[
                                const Text(
                                  'Incorpora solo denominaciones revisadas por el equipo. Crear una especialidad no acredita a un profesional.',
                                ),
                                _field(
                                  'specialty',
                                  'Nombre de la especialidad',
                                ),
                              ] else ...[
                                _field(
                                  'email',
                                  'Correo del destinatario',
                                  max: 254,
                                ),
                                if (widget.admin)
                                  DropdownButtonFormField<String>(
                                    initialValue: _authorization,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Autorización verificada',
                                    ),
                                    items: (_detail!['authorizations'] as List)
                                        .where(
                                          (a) =>
                                              a['verifiedAt'] != null &&
                                              a['revokedAt'] == null,
                                        )
                                        .map(
                                          (a) => DropdownMenuItem<String>(
                                            value: a['id'] as String,
                                            child: Text(
                                              '${a['nomineeEmail']} · ${a['evidenceReference']}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(
                                            () => _authorization = v,
                                          ),
                                  ),
                                const SizedBox(height: 12),
                                const Text('Sucursales (opcionales)'),
                                ...(_detail!['branches'] as List).map(
                                  (b) => CheckboxListTile(
                                    title: Text(b['name'] as String),
                                    value: _branches.contains(b['id']),
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(() {
                                            if (v == true) {
                                              _branches.add(b['id'] as String);
                                            } else {
                                              _branches.remove(b['id']);
                                            }
                                          }),
                                  ),
                                ),
                                const Text(
                                  'Especialidades (opcionales; no acreditan habilitación)',
                                ),
                                ...(_detail!['specialties'] as List).map(
                                  (s) => CheckboxListTile(
                                    title: Text(s['name'] as String),
                                    value: _specialties.contains(s['id']),
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(() {
                                            if (v == true) {
                                              _specialties.add(
                                                s['id'] as String,
                                              );
                                            } else {
                                              _specialties.remove(s['id']);
                                            }
                                          }),
                                  ),
                                ),
                              ],
                              Wrap(
                                spacing: 12,
                                children: [
                                  FilledButton(
                                    onPressed: _busy ? null : _save,
                                    child: const Text('Guardar'),
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
                  if (widget.admin)
                    ExpansionTile(
                      title: const Text('Autorizaciones institucionales'),
                      children: (_detail!['authorizations'] as List)
                          .map(
                            (a) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${a['nomineeEmail']} · ${a['evidenceReference']}',
                                    ),
                                    Text(
                                      'Solicitante: ${a['requesterName']} · ${a['requesterPosition']}',
                                    ),
                                    Text('Contacto: ${a['requesterContact']}'),
                                    Text('Solicitud: ${a['requestedAt']}'),
                                    Text(
                                      a['revokedAt'] != null
                                          ? 'Autorización revocada'
                                          : a['verifiedAt'] != null
                                          ? 'Verificada: ${a['verifiedAt']} · cuenta ${a['verifiedBy']}'
                                          : 'Pendiente de verificación',
                                    ),
                                    if (a['verifiedAt'] == null &&
                                        a['revokedAt'] == null) ...[
                                      CheckboxListTile(
                                        title: const Text(
                                          'Verifiqué fuera de la aplicación la procedencia de la solicitud y la autoridad del solicitante.',
                                        ),
                                        value: _confirmed.contains(a['id']),
                                        onChanged: _busy
                                            ? null
                                            : (v) => setState(() {
                                                if (v == true) {
                                                  _confirmed.add(
                                                    a['id'] as String,
                                                  );
                                                } else {
                                                  _confirmed.remove(a['id']);
                                                }
                                              }),
                                      ),
                                      TextButton(
                                        onPressed:
                                            _busy ||
                                                !_confirmed.contains(a['id'])
                                            ? null
                                            : () => _work(() async {
                                                await widget.api.onboarding(
                                                  '/$_clinic/authorizations/${a['id']}/verify',
                                                  body: {'confirmed': true},
                                                );
                                                await _load();
                                              }),
                                        child: const Text(
                                          'Registrar mi verificación',
                                        ),
                                      ),
                                    ],
                                    if (a['revokedAt'] == null)
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _work(() async {
                                                await widget.api.onboarding(
                                                  '/$_clinic/authorizations/${a['id']}/revoke',
                                                  body: {},
                                                );
                                                await _load();
                                              }),
                                        child: const Text(
                                          'Revocar autorización pendiente de uso',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ExpansionTile(
                    title: const Text('Invitaciones recientes (hasta 50)'),
                    children: (_detail!['invitations'] as List)
                        .map(
                          (i) => ListTile(
                            title: Text('${i['email']} · ${i['clinicalRole']}'),
                            subtitle: Text(
                              i['activatedAt'] != null
                                  ? 'Activada: ${i['activatedAt']}'
                                  : i['revokedAt'] != null
                                  ? 'Revocada'
                                  : 'Vence: ${i['expiresAt']}',
                            ),
                            trailing:
                                i['activatedAt'] == null &&
                                    i['revokedAt'] == null
                                ? TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _work(() async {
                                            await widget.api.onboarding(
                                              '/$_clinic/invitations/${i['id']}/revoke',
                                              body: {},
                                            );
                                            await _load();
                                          }),
                                    child: const Text('Revocar'),
                                  )
                                : null,
                          ),
                        )
                        .toList(),
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
