import 'derivar_atencion_page.dart';
import 'revision_panel.dart';

import 'package:flutter/material.dart';

import '../../core/auth_api.dart';
import '../documentos_reales/documento.dart';
import '../documentos_reales/guardar_documento.dart';
import 'atenciones_api.dart';

String _state(dynamic value) => switch (value) {
  'active' => 'En atención',
  'completed' => 'Completada',
  _ => 'Pendiente de iniciar',
};

class AtencionesPage extends StatefulWidget {
  const AtencionesPage({
    super.key,
    required this.auth,
    required this.onExpired,
  });
  final AuthApi auth;
  final VoidCallback onExpired;
  @override
  State<AtencionesPage> createState() => _AtencionesPageState();
}

class _AtencionesPageState extends State<AtencionesPage> {
  late final AtencionesApi _api;
  List<Map<String, dynamic>> _items = [];
  bool _busy = false;
  int _offset = 0;
  int? _next;
  String? _error;
  @override
  void initState() {
    super.initState();
    _api = AtencionesApi(widget.auth);
    _load(0);
  }

  Future<void> _load(int offset) async {
    setState(() {
      _busy = true;
      _items = [];
      _error = null;
    });
    try {
      final data = await _api.list(offset: offset);
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List)
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        _offset = offset;
        _next = data['nextOffset'] as int?;
      });
    } on AuthFailure catch (e) {
      if (e.status == 401) {
        widget.onExpired();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo consultar la bandeja.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis atenciones por examen')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Exámenes a tu cargo',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Atenciones solicitadas, iniciadas o completadas de tus pertenencias habilitadas. Cada examen tiene su propio responsable.',
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _load(_offset),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar bandeja'),
                ),
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
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No tienes atenciones pendientes habilitadas en esta página.',
                    ),
                  ),
                ),
              for (final x in _items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (x['document'] as Map)['examName'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(x['patientName'] as String),
                        Text('${x['clinicName']} · ${x['branchName']}'),
                        Text(x['specialtyName'] as String),
                        Chip(label: Text(_state(x['status']))),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => AtencionDetallePage(
                                        api: _api,
                                        id: x['id'] as String,
                                        onExpired: widget.onExpired,
                                      ),
                                    ),
                                  );
                                  if (mounted) _load(_offset);
                                },
                          child: const Text('Abrir atención'),
                        ),
                      ],
                    ),
                  ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  if (_offset > 0)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () =>
                                _load((_offset - 20).clamp(0, 100000).toInt()),
                      child: const Text('Página anterior'),
                    ),
                  if (_next != null)
                    TextButton(
                      onPressed: _busy ? null : () => _load(_next!),
                      child: const Text('Página siguiente'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AtencionDetallePage extends StatefulWidget {
  const AtencionDetallePage({
    super.key,
    required this.api,
    required this.id,
    required this.onExpired,
  });
  final AtencionesApi api;
  final String id;
  final VoidCallback onExpired;
  @override
  State<AtencionDetallePage> createState() => _AtencionDetallePageState();
}

class _AtencionDetallePageState extends State<AtencionDetallePage> {
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _failure(AuthFailure e) {
    if (!mounted) return;
    if (e.status == 401) {
      widget.onExpired();
    } else {
      setState(() {
        _error = e.message;
        _data = null;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _data = null;
    });
    try {
      final data = await widget.api.details(widget.id);
      if (mounted) setState(() => _data = data);
    } on AuthFailure catch (e) {
      _failure(e);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir la atención.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _begin() async {
    if (_busy || _data == null) return;
    final revision = (_data!['care'] as Map)['revision'] as int;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.begin(widget.id, revision);
      if (!mounted) return;
      _notice = 'Atención iniciada.';
      await _load();
    } on AuthFailure catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy || _data == null) return;
    final doc = Documento.fromJson(
      Map<String, dynamic>.from((_data!['care'] as Map)['document'] as Map),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.api.download(widget.id, doc);
      if (!mounted) return;
      final saved = await guardarDocumento(doc, bytes);
      if (mounted)
        setState(
          () => _notice = saved ? 'Archivo guardado.' : 'Descarga cancelada.',
        );
    } on AuthFailure catch (e) {
      _failure(e);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar el archivo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final care = _data?['care'] as Map?, contact = _data?['contact'] as Map?;
    final doc = care?['document'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('Atención del examen')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar atención'),
                  ),
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
                if (_notice != null)
                  Semantics(liveRegion: true, child: Text(_notice!)),
                if (care != null && contact != null && doc != null) ...[
                  _card('Atención a tu cargo', [
                    Text(care['patientName'] as String),
                    Text('${care['clinicName']} · ${care['branchName']}'),
                    Text(care['specialtyName'] as String),
                    Chip(label: Text(_state(care['status']))),
                    if (care['status'] == 'requested')
                      FilledButton.icon(
                        onPressed: _busy ? null : _begin,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Comenzar atención'),
                      ),
                  ]),
                  if (_data?['referral'] is Map)
                    _card('Derivación recibida', [
                      Text(
                        'Profesional de origen: ${(_data!['referral'] as Map)['referredBy']}',
                      ),
                      Text('Motivo: ${(_data!['referral'] as Map)['reason']}'),
                    ]),
                  _card('Contacto confirmado por el paciente', [
                    SelectableText('Teléfono: ${contact['phone']}'),
                    SelectableText('Correo: ${contact['email']}'),
                    const SizedBox(height: 8),
                    Text(
                      'Domicilio: ${contact['street']} ${contact['addressNumber']}, ${contact['residenceCommune']}',
                    ),
                    Text('Zona de atención: ${contact['consultationCommune']}'),
                    const SizedBox(height: 8),
                    const Text(
                      'Datos confirmados al enviar este examen; pueden diferir del perfil actual.',
                    ),
                  ]),
                  _card('Documento del examen', [
                    Text(doc['examName'] as String),
                    Text('${doc['examType']} · ${doc['examDate']}'),
                    Text(doc['originalName'] as String),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy || !descargaDisponible
                          ? null
                          : _download,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Descargar examen'),
                    ),
                  ]),
                  if (care['status'] == 'requested' ||
                      care['status'] == 'active')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.forward_to_inbox_outlined),
                      label: const Text('Derivar dentro de la clínica'),
                      onPressed: _busy
                          ? null
                          : () async {
                              final sent = await Navigator.of(context)
                                  .push<bool>(
                                    MaterialPageRoute<bool>(
                                      builder: (_) => DerivarAtencionPage(
                                        api: widget.api,
                                        id: widget.id,
                                        onExpired: widget.onExpired,
                                      ),
                                    ),
                                  );
                              if (mounted && sent == true) {
                                Navigator.of(context).pop();
                              } else if (mounted) {
                                await _load();
                              }
                            },
                    ),
                  if (care['status'] == 'active' ||
                      care['status'] == 'completed')
                    RevisionPanel(
                      auth: widget.api.auth,
                      patientId: '',
                      documentId: doc['id'] as String,
                      careId: widget.id,
                      onFailure: _failure,
                      onSaving: (value) {
                        if (mounted) setState(() => _busy = value);
                      },
                      onSaved: () {
                        if (mounted) _load();
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
