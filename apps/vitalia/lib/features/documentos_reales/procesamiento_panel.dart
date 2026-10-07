import 'revision_paciente_panel.dart';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'procesamiento_api.dart';

class ProcesamientoPanel extends StatefulWidget {
  const ProcesamientoPanel({super.key, required this.auth,
    required this.documentId, required this.onExpired});
  final AuthApi auth;
  final String documentId;
  final VoidCallback onExpired;
  @override
  State<ProcesamientoPanel> createState() => _ProcesamientoPanelState();
}

class _ProcesamientoPanelState extends State<ProcesamientoPanel> {
  String? _status;
  String? _error;
  bool _busy = false;
  @override
  void initState() { super.initState(); _run(false); }
  Future<void> _run(bool request) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _status = null; });
    try {
      final api = ProcesamientoApi(widget.auth);
      final status = request ? await api.solicitar(widget.documentId)
        : await api.consultar(widget.documentId);
      if (mounted) setState(() => _status = status);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) { widget.onExpired(); }
      else { setState(() => _error = error.message); }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo consultar el procesamiento.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  String get _label => switch (_status) {
    'not_requested' => 'Procesamiento no solicitado',
    'queued' => 'Procesamiento pendiente',
    'processing' => 'Documento en procesamiento',
    'professionally_reviewed' => 'Revisión profesional registrada',
    'requires_review' => 'Extracción pendiente de revisión profesional',
    'rejected' => 'No se pudo extraer información de este documento',
    'failed' => 'El procesamiento no se pudo completar',
    _ => 'Estado de procesamiento no disponible',
  };
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_label),
      if (_status == 'queued')
        const Text('La solicitud quedó registrada y espera ejecución.'),
      if (_status == 'professionally_reviewed')
        const Text('La revisión fue aprobada por un profesional. Puedes consultar sus resultados.'),
      if (_status == 'requires_review')
        const Text('Los datos extraídos aún no están aprobados.'),
      if (_error != null) Text(_error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (!_busy && _error == null && _status != null)
        RevisionPacientePanel(key: ValueKey('${widget.documentId}:$_status'), auth: widget.auth,
          documentId: widget.documentId, onExpired: widget.onExpired),
      Wrap(spacing: 8, children: [
        if (_status == 'not_requested' && _error == null)
          OutlinedButton(onPressed: _busy ? null : () => _run(true),
            child: const Text('Solicitar procesamiento')),
        TextButton(onPressed: _busy ? null : () => _run(false),
          child: Text(_busy ? 'Consultando…' : 'Actualizar estado')),
      ]),
    ]),
  );
}
