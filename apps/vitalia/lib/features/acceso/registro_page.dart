import 'package:flutter/material.dart';
import '../../core/auth_api.dart';

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
  @override
  void dispose() {
    _email.dispose(); _password.dispose(); _confirmation.dispose(); super.dispose();
  }
  Future<void> _register() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; });
    try {
      await widget.api.register(_email.text, _password.text);
      if (mounted) setState(() => _message =
        'Solicitud de registro procesada. Puedes volver al acceso e intentar iniciar sesión.');
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      _password.clear(); _confirmation.clear();
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear cuenta de paciente')),
    body: Stack(fit: StackFit.expand, children: [
      Positioned.fill(child: ExcludeSemantics(child: Image.asset(
        'assets/branding/vitalia-fondo-acceso.png', fit: BoxFit.cover,
      ))),
      const Positioned.fill(child: ColoredBox(color: Color(0x33FFFFFF))),
      SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(width: 500, child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 420 ? 20 : 32),
            child: Form(key: _form, child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Image.asset('assets/branding/vitalia-simbolo.png',
                  height: 88, semanticLabel: 'Símbolo de Vitalia Health'),
                const SizedBox(height: 16),
                Text('Comienza con Vitalia', textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('Crea tu cuenta para reunir tus exámenes y consultar su revisión profesional.',
                  textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextFormField(controller: _email, enabled: !_busy, autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                    .hasMatch((v ?? '').trim()) ? null : 'Escribe un correo válido.'),
                const SizedBox(height: 20),
                TextFormField(controller: _password, enabled: !_busy, obscureText: true,
                  autocorrect: false, enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock_outline),
                    helperText: 'Al menos 12 caracteres. No necesitas símbolos.',
                    helperMaxLines: 2),
                  validator: (v) => (v ?? '').runes.length >= 12 ? null : 'Usa al menos 12 caracteres.'),
                const SizedBox(height: 20),
                TextFormField(controller: _confirmation, enabled: !_busy, obscureText: true,
                  autocorrect: false, enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  decoration: const InputDecoration(labelText: 'Confirmar contraseña',
                    prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) => v == _password.text ? null : 'Las contraseñas no coinciden.'),
                const SizedBox(height: 24),
                if (_message != null) ...[
                  Semantics(liveRegion: true, child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_message!),
                  )),
                  const SizedBox(height: 16),
                ],
                FilledButton(onPressed: _busy ? null : _register,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_busy) const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                    else const Icon(Icons.person_add_outlined),
                    const SizedBox(width: 10),
                    Text(_busy ? 'Procesando…' : 'Crear cuenta'),
                  ])),
                const SizedBox(height: 8),
                TextButton(onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Ya tengo cuenta. Volver al acceso')),
              ],
            )),
          ),
        )),
      ))),
    ]),
  );
}
