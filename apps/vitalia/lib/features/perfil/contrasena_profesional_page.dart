import 'package:flutter/material.dart';
import '../../core/auth_api.dart';

class ContrasenaProfesionalPage extends StatefulWidget {
  const ContrasenaProfesionalPage({
    super.key,
    required this.api,
    this.setupToken,
    this.onFinished,
  });
  final AuthApi api;
  final String? setupToken;
  final VoidCallback? onFinished;
  @override
  State<ContrasenaProfesionalPage> createState() =>
      _ContrasenaProfesionalPageState();
}

class _ContrasenaProfesionalPageState extends State<ContrasenaProfesionalPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _busy = false, _confirmed = false, _done = false;
  String? _message;
  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_confirmed) {
      setState(() => _message = 'Marca la confirmación para continuar.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.saveProfessionalPassword(
        currentPassword: _current.text,
        password: _password.text,
        confirmation: _confirmation.text,
        setupToken: widget.setupToken,
      );
      if (mounted) setState(() => _done = true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) {
        _current.clear();
        _password.clear();
        _confirmation.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop && _done) {
        final finished = widget.onFinished;
        WidgetsBinding.instance.addPostFrameCallback((_) => finished?.call());
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.setupToken == null
              ? 'Cambiar contraseña profesional'
              : 'Configurar contraseña profesional',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _done
                ? Column(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 48),
                      const Text(
                        'Contraseña profesional guardada. Vuelve a iniciar sesión con la nueva contraseña. Tu acceso de paciente se conserva.',
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Volver a iniciar sesión'),
                      ),
                    ],
                  )
                : Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.setupToken == null
                              ? 'Al guardar se cerrarán tus sesiones profesionales. La contraseña del paciente se conserva.'
                              : 'Antes de acceder a las funciones profesionales, crea una contraseña distinta a la de paciente. Valida con tu contraseña actual de paciente. Esta autorización dura cinco minutos.',
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _current,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Contraseña actual',
                          ),
                          validator: (v) => (v ?? '').isEmpty
                              ? 'Escribe tu contraseña actual.'
                              : null,
                        ),
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Nueva contraseña profesional',
                          ),
                          validator: (v) => (v ?? '').runes.length < 12
                              ? 'Usa al menos 12 caracteres.'
                              : v == _current.text
                              ? 'Usa una contraseña diferente a la actual.'
                              : null,
                        ),
                        TextFormField(
                          controller: _confirmation,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Confirmar contraseña profesional',
                          ),
                          validator: (v) => v != _password.text
                              ? 'Las contraseñas deben coincidir.'
                              : null,
                        ),
                        CheckboxListTile(
                          value: _confirmed,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _confirmed = v == true),
                          title: const Text(
                            'Confirmo que quiero guardar mi contraseña profesional.',
                          ),
                        ),
                        if (_message != null)
                          Semantics(liveRegion: true, child: Text(_message!)),
                        if (_busy) const LinearProgressIndicator(),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          child: const Text('Guardar contraseña profesional'),
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
