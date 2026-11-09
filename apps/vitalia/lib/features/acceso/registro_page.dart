import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'credenciales_paciente.dart';

class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key, required this.api});
  final AuthApi api;
  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _processed = false;
  bool _hidden = true;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy || _processed || !(_form.currentState?.validate() ?? false))
      return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.register(_email.text, _password.text);
      if (mounted)
        setState(() {
          _processed = true;
          _message =
              'Solicitud procesada. Vuelve al acceso para iniciar sesión con tu correo.';
        });
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) {
        _password.clear();
        _confirmation.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Crear cuenta de paciente')),
        body: Stack(fit: StackFit.expand, children: [
          Positioned.fill(
              child: ExcludeSemantics(
                  child: Image.asset(
            'assets/branding/vitalia-fondo-acceso.png',
            fit: BoxFit.cover,
          ))),
          const Positioned.fill(child: ColoredBox(color: Color(0x33FFFFFF))),
          SafeArea(
              child: Center(
                  child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
                width: 500,
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 420 ? 20 : 32),
                    child: Form(
                        key: _form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Image.asset('assets/branding/vitalia-simbolo.png',
                                height: 88,
                                semanticLabel: 'Símbolo de Vitalia Health'),
                            const SizedBox(height: 16),
                            Text('Comienza con Vitalia',
                                textAlign: TextAlign.center,
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            const Text(
                                silPatientDemo
                                    ? 'Crea una cuenta ficticia para consultar informes que el laboratorio publique para esa cuenta. Si recibiste una invitación, actívala desde el acceso.'
                                    : 'Crea tu cuenta para reunir tus exámenes y consultar su revisión profesional.',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            if (!_processed) ...[
                              TextFormField(
                                  controller: _email,
                                  enabled: !_busy,
                                  autocorrect: false,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                      labelText: 'Correo electrónico',
                                      prefixIcon: Icon(Icons.mail_outline)),
                                  autofillHints: const [AutofillHints.email],
                                  validator: validatePatientEmail),
                              const SizedBox(height: 20),
                              TextFormField(
                                  controller: _password,
                                  enabled: !_busy,
                                  obscureText: _hidden,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.newPassword
                                  ],
                                  decoration: InputDecoration(
                                      labelText: 'Contraseña',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        tooltip: _hidden
                                            ? 'Mostrar contraseñas'
                                            : 'Ocultar contraseñas',
                                        onPressed: _busy
                                            ? null
                                            : () => setState(
                                                () => _hidden = !_hidden),
                                        icon: Icon(_hidden
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined),
                                      ),
                                      helperText: 'Al menos 12 caracteres.',
                                      helperMaxLines: 2),
                                  validator: validateNewPatientPassword),
                              const SizedBox(height: 20),
                              TextFormField(
                                  controller: _confirmation,
                                  enabled: !_busy,
                                  obscureText: _hidden,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _register(),
                                  decoration: const InputDecoration(
                                      labelText: 'Confirmar contraseña',
                                      prefixIcon: Icon(Icons.lock_outline)),
                                  validator: (v) => v == _password.text
                                      ? null
                                      : 'Las contraseñas no coinciden.'),
                              const SizedBox(height: 24),
                            ],
                            if (_message != null) ...[
                              Semantics(
                                  liveRegion: true,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(_message!),
                                  )),
                              const SizedBox(height: 16),
                            ],
                            if (!_processed)
                              FilledButton(
                                  onPressed: _busy ? null : _register,
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_busy)
                                          const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                        else
                                          const Icon(Icons.person_add_outlined),
                                        const SizedBox(width: 10),
                                        Flexible(
                                            child: Text(_busy
                                                ? 'Procesando…'
                                                : 'Crear cuenta')),
                                      ])),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.pop(context,
                                        _processed ? _email.text.trim() : null),
                                child: Text(_processed
                                    ? 'Volver a iniciar sesión'
                                    : 'Ya tengo cuenta. Volver al acceso')),
                          ],
                        )),
                  ),
                )),
          ))),
        ]),
      );
}
