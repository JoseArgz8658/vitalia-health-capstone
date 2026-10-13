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
  int? _archivoBytes;
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
      setState(() { _archivo = file; _archivoBytes = size; });
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
  Widget _section(String number, String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 16, child: Text(number)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(description),
      ])),
    ]),
  );
  @override
  Widget build(BuildContext context) => Form(key: _form, child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Subir examen', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('Usa documentos ficticios o correctamente anonimizados durante las pruebas.'),
      const SizedBox(height: 24),
      _section('1', 'Identifica tu examen', 'Estos datos te ayudan a encontrarlo en tu historial.'),
      TextFormField(controller: _nombre, enabled: !_busy, maxLength: 100,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Nombre del examen',
          hintText: 'Por ejemplo: Hemograma de octubre',
          prefixIcon: Icon(Icons.description_outlined),
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
      _section('2', 'Indica la fecha', 'Selecciona la fecha que corresponde a este examen.'),
      OutlinedButton.icon(onPressed: _busy ? null : _date,
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(_fecha == null ? 'Seleccionar fecha'
          : '${_fecha!.day}/${_fecha!.month}/${_fecha!.year}')),
      const SizedBox(height: 24),
      _section('3', 'Adjunta el documento', 'Elige un PDF o una imagen legible del examen completo.'),
      OutlinedButton.icon(onPressed: _busy ? null : _pick,
        icon: const Icon(Icons.attach_file),
        label: const Text('Seleccionar PDF, JPEG o PNG')),
      if (_archivo != null) Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.attach_file),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Archivo seleccionado', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(_archivo!.name),
            if (_archivoBytes != null) Text('${(_archivoBytes! / 1024).toStringAsFixed(1)} KB'),
          ])),
        ])),
      const SizedBox(height: 8),
      const Text('Tamaño máximo: 10 MiB.'),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
        child: Semantics(liveRegion: true,
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
      const SizedBox(height: 20),
      if (_busy) const Padding(padding: EdgeInsets.only(bottom: 16),
        child: Column(children: [LinearProgressIndicator(), SizedBox(height: 8),
          Text('Estamos guardando tu documento. Espera a que finalice la carga.') ])),
      FilledButton.icon(onPressed: _busy ? null : _upload,
        icon: Icon(_busy ? Icons.hourglass_top : Icons.cloud_upload_outlined),
        label: Text(_busy ? 'Subiendo…' : 'Guardar examen')),
      const SizedBox(height: 12),
      TextButton(onPressed: _busy ? null : widget.onCancel, child: const Text('Volver al historial')),
    ],
  ));
}
