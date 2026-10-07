import 'procesamiento_panel.dart';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'documento.dart';
import 'documentos_api.dart';
import 'guardar_documento.dart';
import 'subir_documento_form.dart';

class PacienteDocumentosPage extends StatefulWidget {
  const PacienteDocumentosPage({super.key, required this.api, required this.email,
    required this.onExpired, required this.onLogout, this.sessionBusy = false});
  final AuthApi api;
  final String email;
  final VoidCallback onExpired;
  final VoidCallback onLogout;
  final bool sessionBusy;
  @override
  State<PacienteDocumentosPage> createState() => _PacienteDocumentosPageState();
}
class _PacienteDocumentosPageState extends State<PacienteDocumentosPage> {
  late final DocumentosApi _documents;
  List<Documento> _items = [];
  int _offset = 0;
  bool _loading = true;
  bool _upload = false;
  String? _downloading;
  String? _error;
  @override
  void initState() {
    super.initState();
    _documents = DocumentosApi(widget.api);
    _load(0);
  }
  Future<void> _load(int offset) async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _documents.list(offset: offset);
      if (mounted) setState(() { _items = items; _offset = offset; });
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.status == 401) { widget.onExpired(); }
      else { setState(() => _error = e.message); }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el historial.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  Future<void> _download(Documento item) async {
    if (_downloading != null) return;
    setState(() { _downloading = item.id; _error = null; });
    try {
      final bytes = await _documents.download(item);
      if (!mounted || !widget.api.hasSession) return;
      final saved = await guardarDocumento(item, bytes);
      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Descarga solicitada. Revisa la ubicación de descargas.')));
      }
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.status == 401) { widget.onExpired(); }
      else { setState(() => _error = e.message); }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar el archivo.');
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }
  void _saved() {
    setState(() => _upload = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Examen guardado.')));
    _load(0);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis exámenes'), actions: [
      TextButton(onPressed: widget.sessionBusy ? null : widget.onLogout,
        child: const Text('Cerrar sesión')),
    ]),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.email, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          if (_upload)
            Card(child: Padding(padding: const EdgeInsets.all(24),
              child: SubirDocumentoForm(api: _documents, onSaved: _saved,
                onCancel: () => setState(() => _upload = false), onExpired: widget.onExpired)))
          else ...[
            Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(onPressed: _loading || _downloading != null ? null
                : () => setState(() => _upload = true),
                icon: const Icon(Icons.upload_file), label: const Text('Subir examen')),
              OutlinedButton.icon(onPressed: _loading || _downloading != null ? null : () => _load(_offset),
                icon: const Icon(Icons.refresh), label: const Text('Actualizar historial')),
            ]),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (!_loading && _items.isEmpty && _error == null)
              const Card(child: Padding(padding: EdgeInsets.all(24),
                child: Text('No hay exámenes en esta página. Puedes subir un documento.'))),
            if (!_loading)
              ..._items.map((item) => Card(child: Padding(padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.nombre, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${item.tipo} · ${item.fechaVisible}'),
                  Text(item.archivo),
                  Text('${(item.bytes / 1024).toStringAsFixed(1)} KB'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _downloading != null || !descargaDisponible ? null : () => _download(item),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(_downloading == item.id ? 'Descargando…' : 'Descargar')),
                  ProcesamientoPanel(key: ValueKey('processing-${item.id}'),
                    auth: widget.api, documentId: item.id, onExpired: widget.onExpired),
                  if (!descargaDisponible)
                    const Text('La descarga en este dispositivo aún está pendiente.'),
                ])))),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Página ${_offset ~/ 20 + 1}'),
              TextButton(onPressed: _loading || _offset == 0 ? null : () => _load(_offset - 20),
                child: const Text('Anterior')),
              TextButton(onPressed: _loading || _items.length < 20 || _offset >= 10000 ? null : () => _load(_offset + 20),
                child: const Text('Siguiente')),
            ]),
          ],
        ]),
      )),
    )),
  );
}

