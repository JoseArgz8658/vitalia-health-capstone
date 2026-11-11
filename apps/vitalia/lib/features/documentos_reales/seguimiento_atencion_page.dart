import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/auth_api.dart';

class SeguimientoAtencionPage extends StatefulWidget {
  const SeguimientoAtencionPage({
    super.key,
    required this.auth,
    required this.documentId,
    required this.onExpired,
  });
  final AuthApi auth;
  final String documentId;
  final VoidCallback onExpired;
  @override
  State<SeguimientoAtencionPage> createState() =>
      _SeguimientoAtencionPageState();
}

class _SeguimientoAtencionPageState extends State<SeguimientoAtencionPage> {
  final _items = <Map<String, dynamic>>[];
  bool _busy = false;
  String? _error;
  int? _next;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy || (more && _next == null)) return;
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _items.clear();
        _next = null;
      }
    });
    try {
      final r = await widget.auth.sendDocumentRequest(
        http.Request(
          'GET',
          widget.auth.documentUri('${widget.documentId}/care', {
            'offset': more ? '$_next' : '0',
          }),
        ),
      );
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (mounted)
        setState(() {
          _items.addAll(
            (data['items'] as List).map(
              (x) => Map<String, dynamic>.from(x as Map),
            ),
          );
          _next = data['nextOffset'] as int?;
        });
    } on AuthFailure catch (e) {
      if (e.status == 401) {
        widget.onExpired();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = 'No se pudo consultar el seguimiento.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _state(dynamic s) => switch (s) {
    'active' => 'En atención',
    'completed' => 'Completada',
    'referred' => 'Derivada',
    'cancelled' => 'Cancelada',
    _ => 'Pendiente de iniciar',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seguimiento de atención')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar seguimiento'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (!_busy && _error == null && _items.isEmpty)
                const Text('Este examen no tiene atenciones registradas.'),
              for (final x in _items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          x['professionalName'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${x['clinicName']} · ${x['branchName'] ?? 'Sin sucursal'}',
                        ),
                        Text(x['specialtyName'] as String),
                        Chip(label: Text(_state(x['status']))),
                        if (x['street'] != null)
                          Text(
                            '${x['street']} ${x['addressNumber']}, ${x['communeName']}',
                          ),
                        if (x['referralReason'] != null)
                          Text('Motivo de derivación: ${x['referralReason']}'),
                      ],
                    ),
                  ),
                ),
              if (_next != null)
                TextButton(
                  onPressed: _busy ? null : () => _load(more: true),
                  child: const Text('Cargar más atenciones'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
