import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../../core/auth_api.dart';
import 'documentos_api.dart';

class SubirDocumentoForm extends StatefulWidget {
  const SubirDocumentoForm({super.key, required this.api, required this.onSaved,
    required this.onCancel, required this.onExpired});
  final DocumentosApi api;
  final VoidCallback onSaved;
  final VoidCallback onCancel;
  final VoidCallback onExpired;
  @override
  State<SubirDocumentoForm> createState() => _SubirDocumentoFormState();
}
class _SubirDocumentoFormState extends State<SubirDocumentoForm> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  String? _tipo;
  DateTime? _fecha;
  XFile? _archivo;
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _nombre.dispose(); super.dispose(); }
  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final file = await openFile(acceptedTypeGroups: const [XTypeGroup(
        label: 'Exámenes', extensions: ['pdf', 'jpg', 'jpeg', 'png'],
        mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
        uniformTypeIdentifiers: ['com.adobe.pdf', 'public.jpeg', 'public.png'],
      )]);
      if (file == null || !mounted) return;
      final size = await file.length();
      if (!mounted) return;
      if (size < 1 || size > 10 * 1024 * 1024) {
        setState(() => _error = 'Elige un archivo no vacío de hasta 10 MiB.');
        return;
      }
      setState(() => _archivo = file);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo seleccionar el archivo.');
    }
  }
  Future<void> _date() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: _fecha ?? now,
      firstDate: DateTime(1900), lastDate: now, helpText: 'Fecha del examen',
      cancelText: 'Cancelar', confirmText: 'Aceptar');
    if (mounted && date != null) setState(() => _fecha = date);
  }
  Future<void> _upload() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_fecha == null || _archivo == null) {
      setState(() => _error = 'Selecciona la fecha y el archivo del examen.');
      return;
    }
    final file = _archivo!;
    final date = _fecha!;
    final lower = file.name.toLowerCase();
    final mime = lower.endsWith('.pdf') ? 'application/pdf'
      : lower.endsWith('.png') ? 'image/png'
      : lower.endsWith('.jpg') || lower.endsWith('.jpeg') ? 'image/jpeg' : null;
    if (mime == null) {
      setState(() => _error = 'Solo se permiten PDF, JPEG y PNG.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final fecha = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await widget.api.upload(nombre: _nombre.text, tipo: _tipo!, fecha: fecha,
        archivo: file.name, mime: mime, bytes: bytes);
      if (mounted) widget.onSaved();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.status == 401) { widget.onExpired(); }
      else { setState(() => _error = e.message); }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo leer o subir el archivo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Form(key: _form, child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Subir examen', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('Usa documentos ficticios o correctamente anonimizados durante las pruebas.'),
      const SizedBox(height: 20),
      TextFormField(controller: _nombre, enabled: !_busy, maxLength: 100,
        decoration: const InputDecoration(labelText: 'Nombre del examen',
          border: OutlineInputBorder()),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe el nombre del examen.' : null),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(initialValue: _tipo,
        decoration: const InputDecoration(labelText: 'Tipo de examen', border: OutlineInputBorder()),
        items: ['Laboratorio', 'Imagenología'].map((value) =>
          DropdownMenuItem(value: value, child: Text(value))).toList(),
        onChanged: _busy ? null : (value) => setState(() => _tipo = value),
        validator: (v) => v == null ? 'Selecciona un tipo.' : null),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: _busy ? null : _date,
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(_fecha == null ? 'Seleccionar fecha'
          : '${_fecha!.day}/${_fecha!.month}/${_fecha!.year}')),
      OutlinedButton.icon(onPressed: _busy ? null : _pick,
        icon: const Icon(Icons.attach_file),
        label: Text(_archivo?.name ?? 'Seleccionar PDF, JPEG o PNG')),
      const Text('Tamaño máximo: 10 MiB.'),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 20),
      FilledButton(onPressed: _busy ? null : _upload,
        child: Text(_busy ? 'Subiendo…' : 'Guardar examen')),
      TextButton(onPressed: _busy ? null : widget.onCancel, child: const Text('Volver al historial')),
    ],
  ));
}
