import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';

class CredencialesProfesionalesPage extends StatefulWidget {
  const CredencialesProfesionalesPage({
    super.key,
    required this.api,
    required this.clinicId,
    required this.memberId,
    required this.professionalName,
    required this.onExpired,
  });
  final AuthApi api;
  final String clinicId, memberId, professionalName;
  final VoidCallback onExpired;
  @override
  State<CredencialesProfesionalesPage> createState() =>
      _CredencialesProfesionalesPageState();
}

class _CredencialesProfesionalesPageState
    extends State<CredencialesProfesionalesPage> {
  final _requestForm = GlobalKey<FormState>(),
      _decisionForm = GlobalKey<FormState>();
  final _registration = TextEditingController(),
      _support = TextEditingController(),
      _source = TextEditingController(),
      _reason = TextEditingController();
  Map<String, dynamic>? _data, _reviewing;
  bool _busy = false, _requesting = false, _confirmed = false;
  String? _message, _decision, _requestId, _decisionId;
  DateTime _checked = DateTime.now();
  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  @override
  void dispose() {
    for (final c in [_registration, _support, _source, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  String _id() {
    final b = List.generate(16, (_) => Random.secure().nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  String _state(dynamic state) => switch (state) {
    'verified' => 'Verificado',
    'rejected' => 'Rechazado',
    _ => 'Pendiente',
  };
  String _date(dynamic value) {
    final d = DateTime.tryParse('$value')?.toLocal();
    return d == null
        ? 'Sin registrar'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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

  Future<void> _load() async {
    final result = await widget.api.professionalCredentials(
      widget.clinicId,
      widget.memberId,
    );
    if (mounted)
      setState(() {
        _data = result;
        _requesting = false;
        _reviewing = null;
        _confirmed = false;
        _requestId = null;
        _decisionId = null;
      });
  }

  Future<void> _request() async {
    if (_busy || !_requestForm.currentState!.validate()) return;
    _requestId ??= _id();
    final body = {
      'requestId': _requestId,
      'expectedRevision': _data!['profile']['revision'],
      'registrationReference': _registration.text.trim(),
      'supportingReference': _support.text.trim(),
    };
    await _run(() async {
      await widget.api.professionalCredentials(
        widget.clinicId,
        widget.memberId,
        body: body,
      );
      await _load();
      if (mounted)
        setState(
          () => _message =
              'Antecedentes registrados. La verificación requiere una decisión administrativa.',
        );
    });
  }

  Future<void> _decide() async {
    if (_busy || !_decisionForm.currentState!.validate()) return;
    if (!_confirmed) {
      setState(
        () => _message =
            'Confirma que contrastaste la información antes de guardar.',
      );
      return;
    }
    _decisionId ??= _id();
    final checked = DateTime(
      _checked.year,
      _checked.month,
      _checked.day,
    ).toUtc().toIso8601String();
    final body = {
      'requestId': _decisionId,
      'expectedRevision': _data!['profile']['revision'],
      'decision': _decision,
      'sourceReference': _source.text.trim(),
      'checkedAt': checked,
      'reason': _reason.text.trim(),
      'confirmed': true,
    };
    await _run(() async {
      await widget.api.professionalCredentials(
        widget.clinicId,
        widget.memberId,
        requestId: _reviewing!['id'] as String,
        body: body,
      );
      await _load();
      if (mounted)
        setState(
          () => _message =
              'Decisión guardada con evidencia, responsable y fecha. No cambió los roles ni las asignaciones clínicas.',
        );
    });
  }

  Widget _card(String title, IconData icon, List<Widget> content) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...content,
        ],
      ),
    ),
  );
  Widget _field(
    TextEditingController c,
    String label,
    String hint,
    int max, {
    int min = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: c,
      enabled: !_busy,
      maxLength: max,
      minLines: c == _reason ? 2 : 1,
      maxLines: c == _reason ? 4 : 2,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      onChanged: (_) {
        _requestId = null;
        _decisionId = null;
      },
      validator: (v) => (v ?? '').trim().length < min
          ? 'Completa este dato con al menos $min caracteres.'
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final requests = (_data?['requests'] as List?) ?? [];
    final profile = _data?['profile'] as Map?;
    final pending = requests.any((v) => v['state'] == 'pending');
    return Scaffold(
      appBar: AppBar(title: const Text('Credenciales profesionales')),
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
                    widget.professionalName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'El jefe registra antecedentes de su clínica. El administrador contrasta la fuente y documenta la decisión. Esta verificación pertenece al perfil global del profesional.',
                  ),
                  const SizedBox(height: 20),
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(_message!),
                      ),
                    ),
                  if (profile != null)
                    _card('Estado del perfil', Icons.verified_user_outlined, [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(label: Text(_state(profile['status']))),
                      ),
                      Text(
                        'Referencia de registro: ${profile['registrationReference'] ?? 'Sin registrar'}',
                      ),
                      Text('Última decisión: ${_date(profile['decidedAt'])}'),
                      if (profile['status'] == 'verified' &&
                          profile['verificationRequestId'] == null)
                        const Text(
                          'Este estado anterior no tiene evidencia registrada en este módulo.',
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Verificar credenciales no concede acceso a exámenes. La pertenencia y la especialidad también deben estar activas.',
                      ),
                    ]),
                  if (_data != null && !_requesting && _reviewing == null)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy || pending
                              ? null
                              : () => setState(() {
                                  _requesting = true;
                                  _registration.clear();
                                  _support.clear();
                                  _message = null;
                                }),
                          icon: const Icon(Icons.note_add_outlined),
                          label: const Text('Registrar antecedentes'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _run(_load),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Actualizar'),
                        ),
                      ],
                    ),
                  if (pending && !_requesting && _reviewing == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Hay una solicitud pendiente de revisión en esta clínica.',
                      ),
                    ),
                  if (_requesting)
                    _card('Registrar antecedentes', Icons.note_add_outlined, [
                      Form(
                        key: _requestForm,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _field(
                              _registration,
                              'Referencia de registro profesional',
                              'Número o identificador del registro consultable',
                              200,
                            ),
                            _field(
                              _support,
                              'Referencia de antecedentes',
                              'Folio o referencia institucional de los antecedentes recibidos',
                              500,
                              min: 5,
                            ),
                            const Text(
                              'No incluyas contraseñas, exámenes ni información de pacientes. Registrar antecedentes no marca al profesional como verificado.',
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              children: [
                                FilledButton(
                                  onPressed: _busy ? null : _request,
                                  child: const Text('Guardar antecedentes'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () =>
                                            setState(() => _requesting = false),
                                  child: const Text('Cancelar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ]),
                  if (_reviewing != null)
                    _card('Revisar solicitud', Icons.fact_check_outlined, [
                      Form(
                        key: _decisionForm,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Registro presentado: ${_reviewing!['registrationReference']}',
                            ),
                            Text(
                              'Antecedentes: ${_reviewing!['supportingReference']}',
                            ),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                              initialValue: _decision,
                              decoration: const InputDecoration(
                                labelText: 'Resultado de la revisión',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'verified',
                                  child: Text('Verificado'),
                                ),
                                DropdownMenuItem(
                                  value: 'rejected',
                                  child: Text('Rechazado'),
                                ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                      _decision = v;
                                      _decisionId = null;
                                    }),
                              validator: (v) =>
                                  v == null ? 'Selecciona un resultado.' : null,
                            ),
                            const SizedBox(height: 18),
                            _field(
                              _source,
                              'Fuente contrastada',
                              'Referencia precisa que permita comprobar la revisión',
                              500,
                              min: 5,
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final d = await showDatePicker(
                                        context: context,
                                        initialDate: _checked,
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime.now(),
                                      );
                                      if (d != null && mounted)
                                        setState(() {
                                          _checked = d;
                                          _decisionId = null;
                                        });
                                    },
                              icon: const Icon(Icons.calendar_today_outlined),
                              label: Text(
                                'Fecha de consulta: ${_date(_checked.toIso8601String())}',
                              ),
                            ),
                            const SizedBox(height: 18),
                            _field(
                              _reason,
                              'Fundamento de la decisión',
                              'Explica el resultado de la comprobación',
                              1000,
                              min: 5,
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _confirmed,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                      _confirmed = v == true;
                                      _decisionId = null;
                                    }),
                              title: const Text(
                                'Confirmo que contrasté la fuente y su correspondencia con este profesional.',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              children: [
                                FilledButton(
                                  onPressed: _busy ? null : _decide,
                                  child: const Text('Guardar decisión'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() => _reviewing = null),
                                  child: const Text('Cancelar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ]),
                  const SizedBox(height: 24),
                  Text(
                    'Solicitudes de esta clínica',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_data != null && requests.isEmpty)
                    const Text('Todavía no hay solicitudes registradas.'),
                  ...requests.map(
                    (v) => _card(
                      'Registro ${v['registrationReference']}',
                      Icons.history,
                      [
                        Text(
                          '${_state(v['state'])} · ${_date(v['createdAt'])}',
                        ),
                        Text('Antecedentes: ${v['supportingReference']}'),
                        Text(
                          'Registrado por: ${v['requestedByEmail'] ?? v['requestedBy']}',
                        ),
                        if (v['decision'] != null) ...[
                          const Divider(height: 24),
                          Text('Fuente: ${v['sourceReference']}'),
                          Text('Consulta: ${_date(v['checkedAt'])}'),
                          Text('Fundamento: ${v['reason']}'),
                          Text(
                            'Responsable: ${v['decidedByEmail'] ?? v['decidedBy']}',
                          ),
                          Text('Decisión registrada: ${v['decidedAt']}'),
                        ],
                        if (v['state'] == 'pending' &&
                            _data?['canDecide'] == true &&
                            _reviewing == null &&
                            !_requesting)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _reviewing = Map<String, dynamic>.from(
                                      v as Map,
                                    );
                                    _decision = null;
                                    _source.clear();
                                    _reason.clear();
                                    _checked = DateTime.now();
                                    _confirmed = false;
                                    _decisionId = null;
                                    _message = null;
                                  }),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Revisar solicitud'),
                          ),
                      ],
                    ),
                  ),
                  const Text(
                    'Se muestran las últimas 20 solicitudes de esta pertenencia.',
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
