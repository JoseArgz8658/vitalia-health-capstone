import 'package:flutter/material.dart';

import '../../core/auth_api.dart';
import 'credenciales_paciente.dart';

class RecuperarPortalSilPage extends StatefulWidget {
  const RecuperarPortalSilPage({super.key, required this.api, this.email = ''});

  final AuthApi api;
  final String email;

  @override
  State<RecuperarPortalSilPage> createState() => _RecuperarPortalSilPageState();
}

class _RecuperarPortalSilPageState extends State<RecuperarPortalSilPage> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _completed = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_email, _key, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _recover() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api
          .recoverSilPassword(_email.text, _key.text, _password.text);
      if (!mounted) return;
      _key.clear();
      _password.clear();
      _confirmation.clear();
      setState(() => _completed = true);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar acceso')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                            _completed
                                ? Icons.check_circle_outline
                                : Icons.key_outlined,
                            size: 40,
                            color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text(
                            _completed
                                ? 'Contraseña actualizada'
                                : 'Elige una nueva contraseña',
                            style: theme.textTheme.headlineSmall,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        if (_completed) ...[
                          const Text(
                              'Las sesiones de paciente se cerraron. Ingresa con tu nueva contraseña y genera una nueva clave de respaldo.'),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(context, _email.text.trim()),
                            child: const Text('Volver a iniciar sesión'),
                          ),
                        ] else ...[
                          const Text(
                              'Usa la clave de recuperación que guardaste desde Mis informes. Si no tienes una, solicita ayuda al laboratorio.'),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            autocorrect: false,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'Correo ficticio'),
                            validator: (value) =>
                                validatePatientEmail(value, demo: true),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _key,
                            enabled: !_busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'Clave de recuperación'),
                            validator: (value) => RegExp(r'^[A-Za-z0-9_-]{43}$')
                                    .hasMatch((value ?? '').trim())
                                ? null
                                : 'Revisa la clave de respaldo de 43 caracteres.',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: _hidden,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Nueva contraseña',
                              helperText: 'Al menos 12 caracteres.',
                              suffixIcon: IconButton(
                                tooltip: _hidden
                                    ? 'Mostrar contraseñas'
                                    : 'Ocultar contraseñas',
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _hidden = !_hidden),
                                icon: Icon(_hidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                              ),
                            ),
                            validator: validateNewPatientPassword,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmation,
                            enabled: !_busy,
                            obscureText: _hidden,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                                labelText: 'Confirmar nueva contraseña'),
                            onFieldSubmitted: (_) => _recover(),
                            validator: (value) => value == _password.text
                                ? null
                                : 'Las contraseñas no coinciden.',
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Semantics(
                                liveRegion: true,
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: theme.colorScheme.error))),
                          ],
                          const SizedBox(height: 18),
                          if (_busy) const LinearProgressIndicator(),
                          FilledButton(
                            onPressed: _busy ? null : _recover,
                            child: Text(_busy
                                ? 'Actualizando…'
                                : 'Actualizar contraseña'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
