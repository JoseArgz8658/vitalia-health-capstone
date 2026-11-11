import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

class ClaveRecuperacionSilDialog extends StatefulWidget {
  const ClaveRecuperacionSilDialog(
      {super.key, required this.api, required this.onExpired});

  final AuthApi api;
  final VoidCallback onExpired;

  @override
  State<ClaveRecuperacionSilDialog> createState() =>
      _ClaveRecuperacionSilDialogState();
}

class _ClaveRecuperacionSilDialogState
    extends State<ClaveRecuperacionSilDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _key;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_busy || _password.text.isEmpty || _key != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.generateSilRecoveryKey(_password.text);
      if (mounted) setState(() => _key = result['recoveryKey'] as String);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        Navigator.pop(context);
        widget.onExpired();
      } else {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        scrollable: true,
        title: Text(key == null
            ? 'Preparar recuperación'
            : 'Guarda tu clave de respaldo'),
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (key == null) ...[
                const Text(
                    'Esta clave permite recuperar tu acceso si olvidas la contraseña. Generar una nueva reemplaza la anterior.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !_busy,
                  onSubmitted: (_) => _generate(),
                  decoration:
                      const InputDecoration(labelText: 'Contraseña actual'),
                ),
              ] else ...[
                const Text(
                    'Cópiala en un lugar privado. Solo se muestra aquí, dura 90 días y sirve una vez.'),
                const SizedBox(height: 14),
                SelectableText(key,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                    liveRegion: true,
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(key == null ? 'Cancelar' : 'Ya guardé la clave'),
          ),
          if (key == null)
            FilledButton(
              onPressed: _busy ? null : _generate,
              child: Text(_busy ? 'Generando…' : 'Generar clave'),
            ),
        ],
      ),
    );
  }
}
