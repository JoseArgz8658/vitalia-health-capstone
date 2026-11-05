import 'package:flutter/material.dart';
import '../../core/auth_api.dart';

class ActivarInvitacionPage extends StatefulWidget {
  const ActivarInvitacionPage({
    super.key,
    required this.api,
    this.ownsApi = false,
    this.passwordSetup = false,
  });
  final AuthApi api;
  final bool ownsApi;
  final bool passwordSetup;
  @override
  State<ActivarInvitacionPage> createState() => _ActivarInvitacionPageState();
}

class _ActivarInvitacionPageState extends State<ActivarInvitacionPage> {
  final _form = GlobalKey<FormState>();
  final _fields = List.generate(8, (_) => TextEditingController());
  bool _busy = false,
      _done = false,
      _existing = false,
      _professional = false,
      _confirmed = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _existing = widget.passwordSetup;
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    if (widget.ownsApi) widget.api.close();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_existing && !_confirmed) {
      setState(() => _message = 'Marca la confirmación para continuar.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    bool signed = false;
    try {
      if (_existing) {
        await widget.api.login(
          _fields[5].text.trim(),
          _fields[3].text,
          mode: _professional ? 'profesional' : 'paciente',
        );
        signed = true;
        await widget.api.onboarding(
          widget.passwordSetup ? '/professional-password' : '/accept',
          body: {
            if (!widget.passwordSetup) ...{
              'token': _fields[0].text.trim(),
              'firstName': _fields[1].text.trim(),
              'firstSurname': _fields[2].text.trim(),
              'confirmed': true,
            },
            'currentPassword': _fields[3].text,
            if (!_professional) ...{
              'professionalPassword': _fields[6].text,
              'professionalConfirmation': _fields[7].text,
            },
          },
        );
      } else {
        await widget.api.onboarding(
          '/activate',
          body: {
            'token': _fields[0].text.trim(),
            'firstName': _fields[1].text.trim(),
            'firstSurname': _fields[2].text.trim(),
            'password': _fields[3].text,
            'confirmation': _fields[4].text,
          },
        );
      }
      if (mounted) setState(() => _done = true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (signed) {
        try {
          await widget.api.logout();
        } on AuthFailure {
          widget.api.clear();
        }
      }
      if (mounted) {
        _fields[3].clear();
        _fields[4].clear();
        _fields[6].clear();
        _fields[7].clear();
        setState(() => _busy = false);
      }
    }
  }

  Widget _field(int i, String label, {int max = 100}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _fields[i],
      enabled: !_busy,
      obscureText: i == 0 || i == 3 || i == 4 || i == 6 || i == 7,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: max,
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        if (i == 0)
          return RegExp(r'^[a-f0-9]{64}$').hasMatch((v ?? '').trim())
              ? null
              : 'Pega el código completo.';
        if (i == 3)
          return _existing
              ? (v ?? '').isEmpty
                    ? 'Escribe tu contraseña actual.'
                    : null
              : (v ?? '').runes.length < 12
              ? 'Usa al menos 12 caracteres.'
              : null;
        if (i == 4)
          return v != _fields[3].text
              ? 'Las contraseñas deben coincidir.'
              : null;
        if (i == 6) {
          if ((v ?? '').runes.length < 12) return 'Usa al menos 12 caracteres.';
          if (v == _fields[3].text)
            return 'Usa una contraseña diferente a la de paciente.';
          return null;
        }
        if (i == 7)
          return v != _fields[6].text
              ? 'Las contraseñas deben coincidir.'
              : null;
        if (i == 5)
          return RegExp(
                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
              ).hasMatch((v ?? '').trim())
              ? null
              : 'Escribe tu correo registrado.';
        return (v ?? '').trim().isEmpty ? 'Completa este dato.' : null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.passwordSetup
            ? 'Configurar contraseña profesional'
            : 'Activar invitación profesional',
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _done
                ? Column(
                    children: [
                      Text(
                        widget.passwordSetup
                            ? 'Contraseña profesional configurada. Inicia sesión en modo profesional con tu nueva contraseña. Tu acceso de paciente se conserva.'
                            : 'Invitación aceptada. Inicia sesión en modo profesional con tu contraseña profesional. Tu cuenta y sus datos anteriores se conservan.',
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).popUntil((r) => r.isFirst),
                        child: const Text('Volver al inicio de sesión'),
                      ),
                    ],
                  )
                : Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.passwordSetup)
                          const Text(
                            'Pega el código de la invitación que recibiste. Vence a las 48 horas y se utiliza una sola vez. Conocer esta dirección no habilita una cuenta.',
                          ),
                        if (!widget.passwordSetup)
                          SwitchListTile(
                            title: const Text('Ya tengo una cuenta en Vitalia'),
                            value: _existing,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                    _existing = v;
                                    _fields[3].clear();
                                    _fields[4].clear();
                                    _message = null;
                                    _confirmed = false;
                                  }),
                          ),
                        if (!widget.passwordSetup) ...[
                          _field(0, 'Código de invitación', max: 64),
                          _field(1, 'Primer nombre'),
                          _field(2, 'Primer apellido'),
                        ],
                        if (_existing) ...[
                          const Text(
                            'Usa el correo invitado y tu contraseña actual. Los nombres solo se utilizarán si todavía no tienes datos personales registrados.',
                          ),
                          _field(5, 'Correo de tu cuenta', max: 254),
                          if (!widget.passwordSetup)
                            SwitchListTile(
                              title: const Text(
                                'Ingresar con mi perfil profesional existente',
                              ),
                              subtitle: const Text(
                                'Desactivado: ingresar como paciente.',
                              ),
                              value: _professional,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _professional = v),
                            ),
                          _field(3, 'Contraseña actual', max: 1024),
                          if (!_professional) ...[
                            const Text(
                              'Valida tu cuenta con la contraseña de paciente y crea una diferente para el acceso profesional. Si ya tienes contraseña profesional, ingresa con ese perfil para aceptar otra clínica.',
                            ),
                            _field(
                              6,
                              'Nueva contraseña profesional',
                              max: 1024,
                            ),
                            _field(
                              7,
                              'Confirmar contraseña profesional',
                              max: 1024,
                            ),
                          ],
                          CheckboxListTile(
                            title: Text(
                              widget.passwordSetup
                                  ? 'Confirmo que quiero configurar mi contraseña profesional independiente.'
                                  : 'Acepto incorporarme a la clínica indicada en la invitación recibida.',
                            ),
                            value: _confirmed,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _confirmed = v == true),
                          ),
                        ] else ...[
                          _field(
                            3,
                            'Contraseña (mínimo 12 caracteres)',
                            max: 1024,
                          ),
                          _field(4, 'Repetir contraseña', max: 1024),
                        ],
                        if (_message != null)
                          Semantics(liveRegion: true, child: Text(_message!)),
                        if (_busy) const LinearProgressIndicator(),
                        FilledButton(
                          onPressed: _busy ? null : _activate,
                          child: Text(
                            widget.passwordSetup
                                ? 'Guardar contraseña profesional'
                                : _existing
                                ? 'Iniciar sesión y aceptar invitación'
                                : 'Activar mi cuenta',
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}
