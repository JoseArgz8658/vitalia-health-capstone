import '../profesional/profesional_documentos_page.dart';
import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'asignaciones_api.dart';

class AsignacionesPage extends StatefulWidget {
  const AsignacionesPage({super.key, required this.auth, required this.email,
    required this.role, required this.onExpired, required this.onLogout, this.sessionBusy = false, this.notice});
  final AuthApi auth;
  final String email;
  final String role;
  final VoidCallback onExpired;
  final VoidCallback onLogout;
  final bool sessionBusy;
  final String? notice;
  @override
  State<AsignacionesPage> createState() => _AsignacionesPageState();
}
class _AsignacionesPageState extends State<AsignacionesPage> {
  final _patient = TextEditingController();
  final _professional = TextEditingController();
  List<Asignacion> _assignments = [];
  List<PacienteAsignado> _patients = [];
  PacienteAsignado? _selectedPatient;
  bool _busy = false;
  String? _error;
  int _offset = 0;
  bool get _admin => widget.role == 'administrador';
  AsignacionesApi get _api => AsignacionesApi(widget.auth);
  int get _count => _admin ? _assignments.length : _patients.length;
  @override
  void initState() { super.initState(); _load(0); }
  @override
  void dispose() { _patient.dispose(); _professional.dispose(); super.dispose(); }
  void _failure(AuthFailure error) {
    if (!mounted) return;
    if (error.status == 401) { widget.onExpired(); }
    else { setState(() => _error = error.message); }
  }
  Future<void> _load(int offset) async {
    setState(() { _busy = true; _error = null; _assignments = []; _patients = []; });
    try {
      if (_admin) {
        final list = await _api.listar(offset: offset);
        if (mounted) setState(() => _assignments = list);
      } else {
        final list = await _api.pacientes(offset: offset);
        if (mounted) setState(() => _patients = list);
      }
      if (mounted) setState(() => _offset = offset);
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() => _error = 'No se pudo cargar la lista.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _change(Future<void> Function() work) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await work();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asignación actualizada.')));
      await _load(0);
    } on AuthFailure catch (error) { _failure(error); }
    catch (_) { if (mounted) setState(() => _error = 'No se pudo actualizar la asignación.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final selected = _selectedPatient;
    if (!_admin && selected != null) {
      return ProfesionalDocumentosPage(key: ValueKey(selected.id), auth: widget.auth,
        patientId: selected.id, patientEmail: selected.email,
        onExpired: widget.onExpired, onLogout: widget.onLogout, sessionBusy: widget.sessionBusy,
        onBack: () { setState(() => _selectedPatient = null); _load(_offset); });
    }
    return Scaffold(
    appBar: AppBar(title: Text(_admin ? 'Asignaciones de pacientes' : 'Mis pacientes'), actions: [
      TextButton(onPressed: widget.sessionBusy || _busy ? null : widget.onLogout,
        child: const Text('Cerrar sesión')),
    ]),
    body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.email),
          Text('Cuenta: ${widget.role}'),
          if (widget.notice != null) Text(widget.notice!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
          if (_admin) ...[
            const Text('Usa los correos de cuentas existentes. Asignar no cambia sus roles.'),
            TextField(controller: _patient, enabled: !_busy,
              keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo del paciente')),
            TextField(controller: _professional, enabled: !_busy,
              keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo del profesional')),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : () => _change(() => _api.asignar(_patient.text, _professional.text)),
              child: const Text('Asignar paciente')),
          ] else
            const Text('Solo se muestran tus pacientes con asignación activa. Puedes consultar documentos y extracciones pendientes; la aprobación estará disponible en una etapa posterior.'),
          TextButton(onPressed: _busy ? null : () => _load(_offset), child: const Text('Actualizar lista')),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (!_busy && _error == null && _count == 0)
            Text(_admin ? 'No hay asignaciones en esta página.' : 'No tienes pacientes asignados en esta página.'),
          if (_admin)
            ..._assignments.map((item) => Card(child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Paciente: ${item.patientEmail}'),
                Text('Profesional: ${item.professionalEmail}'),
                Text(item.active ? 'Asignación activa' : 'Asignación inactiva'),
                TextButton(onPressed: _busy ? null : () => _change(() => item.active
                  ? _api.desactivar(item.id) : _api.asignar(item.patientEmail, item.professionalEmail)),
                  child: Text(item.active ? 'Desactivar asignación' : 'Reactivar asignación')),
              ]))))
          else
            ..._patients.map((item) => Card(child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.email),
                TextButton(onPressed: _busy ? null : () => setState(() => _selectedPatient = item),
                  child: const Text('Ver exámenes')),
              ])))),
          Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Página ${_offset ~/ 20 + 1}'),
            TextButton(onPressed: _busy || _offset == 0 ? null : () => _load(_offset - 20), child: const Text('Anterior')),
            TextButton(onPressed: _busy || _count < 20 || _offset >= 10000 ? null : () => _load(_offset + 20), child: const Text('Siguiente')),
          ]),
        ]),
      )),
    )),
  );
  }
}
