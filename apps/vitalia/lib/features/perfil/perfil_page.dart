import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'medidas_panel.dart';
import 'contrasena_profesional_page.dart';
import 'ubicacion_panel.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({
    super.key,
    required this.api,
    required this.onExpired,
    this.isPatient = false,
  });
  final AuthApi api;
  final VoidCallback onExpired;
  final bool isPatient;
  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final key in [
      'firstName',
      'additionalNames',
      'firstSurname',
      'secondSurname',
      'birthDate',
      'phone',
      'rut',
    ])
      key: TextEditingController(),
  };
  bool _busy = false,
      _loaded = false,
      _verified = false,
      _editing = false,
      _measuresEditing = false;
  Map<String, dynamic>? _savedProfile;
  String? _revision, _commune, _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fill(Map<String, dynamic>? profile) {
    _savedProfile = profile == null ? null : Map<String, dynamic>.from(profile);
    for (final entry in _fields.entries) {
      entry.value.text = profile?[entry.key] as String? ?? '';
    }
    _revision = profile?['revision'] as String?;
    _commune = profile?['preferredCommuneCode'] as String?;
    _verified = profile?['rutVerified'] == true;
  }

  void _error(AuthFailure error) {
    if (error.status == 401) {
      widget.onExpired();
      return;
    }
    if (mounted) setState(() => _message = error.message);
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _loaded = false;
      _message = null;
    });
    try {
      final profile = await widget.api.profile();
      if (!mounted) return;
      setState(() {
        _fill(profile);
        _loaded = true;
        _editing = false;
      });
    } on AuthFailure catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_loaded || !_editing || !_form.currentState!.validate())
      return;
    final body = <String, dynamic>{
      'revision': _revision,
      'preferredCommuneCode': _commune,
    };
    for (final entry in _fields.entries) {
      final text = entry.value.text.trim();
      body[entry.key] = text.isEmpty ? null : text;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final profile = await widget.api.profile(update: body);
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _fill(profile);
        _editing = false;
        _message =
            'Perfil guardado. Estos datos no verifican tu identidad ni cambian tus permisos.';
      });
    } on AuthFailure catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _fill(_savedProfile);
      _editing = false;
      _message = null;
    });
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          ...children,
        ],
      ),
    ),
  );
  Widget _datum(String key, String label) {
    final value = _savedProfile?[key] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(value == null || value.isEmpty ? 'Sin registrar' : value),
        ],
      ),
    );
  }

  Widget _item(
    String key,
    String label, {
    bool required = false,
    String? hint,
    TextInputType? keyboard,
  }) => _editing
      ? _field(key, label, required: required, hint: hint, keyboard: keyboard)
      : _datum(key, label);
  Widget _field(
    String key,
    String label, {
    bool required = false,
    String? hint,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_busy && _loaded && !(key == 'rut' && _verified),
      keyboardType: keyboard,
      maxLength: key == 'phone'
          ? 40
          : key == 'rut'
          ? 20
          : key == 'birthDate'
          ? 10
          : 150,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (required && text.isEmpty) return 'Completa este dato.';
        if (key == 'birthDate' &&
            text.isNotEmpty &&
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text))
          return 'Usa AAAA-MM-DD.';
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mi perfil')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_circle_outlined, size: 56),
              const SizedBox(height: 12),
              Text(
                'Tus datos personales',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Consulta tus datos por sección. Para cambiarlos, pulsa Editar datos personales. El teléfono y el RUT son opcionales por ahora.',
              ),
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(
                  liveRegion: true,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_message!),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy || _editing || _measuresEditing
                      ? null
                      : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar perfil'),
                ),
              ),
              if (_loaded) ...[
                if (!_editing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: FilledButton.icon(
                      onPressed: _busy || _measuresEditing
                          ? null
                          : () => setState(() {
                              _editing = true;
                              _message = null;
                            }),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar datos personales'),
                    ),
                  ),
                if (_editing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Estás editando. Los cambios se guardan únicamente al pulsar Guardar perfil.',
                    ),
                  ),
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section('Datos personales', Icons.person_outline, [
                        _item('firstName', 'Primer nombre', required: true),
                        _item('additionalNames', 'Otros nombres (opcional)'),
                        _item(
                          'firstSurname',
                          'Primer apellido',
                          required: true,
                        ),
                        _item('secondSurname', 'Segundo apellido (opcional)'),
                        _item(
                          'birthDate',
                          'Fecha de nacimiento (opcional)',
                          hint: 'AAAA-MM-DD',
                          keyboard: TextInputType.datetime,
                        ),
                      ]),
                      _section('Contacto', Icons.phone_outlined, [
                        _item(
                          'phone',
                          'Teléfono (opcional)',
                          keyboard: TextInputType.phone,
                        ),
                        UbicacionPanel(
                          api: widget.api,
                          value: _commune,
                          editing: _editing,
                          enabled: !_busy,
                          onChanged: (value) =>
                              setState(() => _commune = value),
                          onExpired: widget.onExpired,
                        ),
                      ]),
                      _section('Identificación', Icons.badge_outlined, [
                        _item(
                          'rut',
                          'RUT (opcional)',
                          hint:
                              'Sin puntos o con puntos; incluye dígito verificador',
                        ),
                        Text(
                          _verified
                              ? 'Identificación verificada: la modificación requiere revisión del equipo.'
                              : 'El dígito verificador comprueba el formato; no acredita tu identidad. Una vez registrado, no se puede vaciar el RUT desde esta pantalla.',
                        ),
                      ]),
                      if (_editing)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _save,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Guardar perfil'),
                            ),
                            OutlinedButton(
                              onPressed: _busy ? null : _cancel,
                              child: const Text('Cancelar edición'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
              if (_loaded && _savedProfile != null && widget.isPatient)
                MedidasPanel(
                  api: widget.api,
                  onExpired: widget.onExpired,
                  enabled: !_busy && !_editing,
                  onEditingChanged: (value) {
                    if (mounted) setState(() => _measuresEditing = value);
                  },
                ),
              if (!widget.isPatient)
                _section('Seguridad de acceso', Icons.lock_outline, [
                  const Text(
                    'Administra la contraseña de tu acceso profesional.',
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || _editing
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ContrasenaProfesionalPage(
                                api: widget.api,
                                onFinished: widget.onExpired,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.password),
                    label: const Text('Cambiar contraseña profesional'),
                  ),
                ]),
              const SizedBox(height: 24),
              const Text(
                'No se envían datos del perfil ni de ubicación al asistente.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
