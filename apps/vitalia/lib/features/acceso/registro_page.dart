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
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: SizedBox(width: 500, child: Form(key: _form, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('La cuenta se registra como paciente.'),
          const SizedBox(height: 16),
          TextFormField(controller: _email, enabled: !_busy, autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo electrónico'),
            validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
              .hasMatch((v ?? '').trim()) ? null : 'Escribe un correo válido.'),
          TextFormField(controller: _password, enabled: !_busy, obscureText: true,
            autocorrect: false, enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Contraseña',
              helperText: 'Al menos 12 caracteres. No necesitas símbolos.'),
            validator: (v) => (v ?? '').runes.length >= 12 ? null : 'Usa al menos 12 caracteres.'),
          TextFormField(controller: _confirmation, enabled: !_busy, obscureText: true,
            autocorrect: false, enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
            validator: (v) => v == _password.text ? null : 'Las contraseñas no coinciden.'),
          const SizedBox(height: 24),
          if (_message != null) Text(_message!),
          FilledButton(onPressed: _busy ? null : _register,
            child: Text(_busy ? 'Procesando…' : 'Crear cuenta')),
        ])))),
    ),
  );
}
