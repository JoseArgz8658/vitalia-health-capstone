import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'registro_page.dart';

class AccesoPage extends StatefulWidget {
  const AccesoPage({super.key, this.api, this.onAuthenticated, this.notice});
  final AuthApi? api;
  final String? notice;
  final ValueChanged<Map<String, dynamic>>? onAuthenticated;
  @override
  State<AccesoPage> createState() => _AccesoPageState();
}
class _AccesoPageState extends State<AccesoPage> {
  final _form = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _busy = false;
  bool _ocultar = true;
  String? _error;
  @override
  void dispose() { _correo.dispose(); _clave.dispose(); super.dispose(); }
  Future<void> _login() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.api == null) {
      setState(() => _error = 'El servicio de acceso no está configurado.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final user = await widget.api!.login(_correo.text, _clave.text);
      if (mounted) widget.onAuthenticated?.call(user);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _clave.clear();
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(width: 500, child: Card(child: Padding(
        padding: const EdgeInsets.all(32), child: Form(key: _form,
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.health_and_safety_outlined, size: 64,
                color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Vitalia Health', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('Accede a tu cuenta', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (widget.notice != null) Text(widget.notice!),
              TextFormField(controller: _correo, enabled: !_busy,
                keyboardType: TextInputType.emailAddress, autocorrect: false,
                decoration: const InputDecoration(labelText: 'Correo electrónico',
                  border: OutlineInputBorder()),
                validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                  .hasMatch((v ?? '').trim()) ? null : 'Escribe un correo válido.'),
              const SizedBox(height: 16),
              TextFormField(controller: _clave, enabled: !_busy, obscureText: _ocultar,
                autocorrect: false, enableSuggestions: false,
                decoration: InputDecoration(labelText: 'Contraseña',
                  border: const OutlineInputBorder(), suffixIcon: IconButton(
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                    tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
                validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña.' : null,
                onFieldSubmitted: (_) => _login()),
              const SizedBox(height: 16),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: roleStyle(context))),
              FilledButton(onPressed: _busy ? null : _login,
                child: Text(_busy ? 'Ingresando…' : 'Iniciar sesión')),
              TextButton(onPressed: _busy || widget.api == null ? null : () =>
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RegistroPage(api: widget.api!))),
                child: const Text('Crear cuenta de paciente')),
              TextButton(onPressed: () => showDialog<void>(context: context,
                builder: (c) => AlertDialog(title: const Text('Recuperar acceso'),
                  content: const Text('La recuperación de contraseña aún no está disponible.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(c),
                    child: const Text('Entendido'))])),
                child: const Text('Olvidé mi contraseña')),
          ])),
      ))),
    ))),
  );
  TextStyle roleStyle(BuildContext context) =>
    TextStyle(color: Theme.of(context).colorScheme.error);
}
