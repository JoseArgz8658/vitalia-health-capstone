import 'package:flutter/material.dart';
import '../examenes/registro/formulario_examen_page.dart';
import '../examenes/examen_demo.dart';
import '../examenes/detalle_examen_page.dart';
import '../acceso/acceso_page.dart';
import 'documento_local.dart';
import 'package:file_selector/file_selector.dart';

/// Integra metadatos existentes y selección local sin alterar los incrementos previos.
class DocumentosPage extends StatefulWidget {
  const DocumentosPage({super.key});
  @override
  State<DocumentosPage> createState() => _DocumentosPageState();
}
class _DocumentosPageState extends State<DocumentosPage> {
  final _documentos = <DocumentoLocal>[];
  bool _ocupado = false;
  String _busqueda = '';
  String _tipo = 'Todos';

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _registrar() async {
    setState(() => _ocupado = true);
    try {
      final archivo = await openFile();
      if (!mounted) return;
      if (archivo == null) { _avisar('Selección cancelada. No se añadió un registro.'); return; }
      final bytes = await archivo.length();
      if (!mounted) return;
      if (bytes == 0) { _avisar('El archivo está vacío. Elige otro archivo.'); return; }
      final examen = await Navigator.of(context).push<ExamenDemo>(
        MaterialPageRoute<ExamenDemo>(builder: (_) => const FormularioExamenPage()));
      if (!mounted) return;
      if (examen == null) { _avisar('Registro cancelado. No se añadió el archivo.'); return; }
      final confirmar = await showDialog<bool>(context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar registro local'),
          content: Text('${examen.nombre}\n${examen.tipo} · ${examen.fechaTexto}\n'
            '${archivo.name}\n$bytes bytes\n\n'
            'Solo se conservará durante esta sesión. No se subirá el archivo.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar')),
          ],
        ));
      if (!mounted || confirmar != true) return;
      setState(() => _documentos.add(DocumentoLocal(
        examen: examen, archivo: archivo, bytes: bytes)));
      _avisar('Registro local añadido. Pendiente de almacenamiento seguro.');
    } catch (_) {
      if (mounted) _avisar('No se pudo completar la selección. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _detalle(DocumentoLocal documento) {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(documento.examen.nombre),
      content: Text('Archivo: ${documento.archivo.name}\n'
        'Tamaño: ${documento.bytes} bytes\n'
        'Fecha: ${documento.examen.fechaTexto}\n\n'
        'Seleccionado localmente. Formato y contenido aún sin validar. '
        'No hay documento almacenado, extracción IA ni revisión profesional.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar')),
        TextButton(onPressed: () {
          Navigator.of(context).pop();
          Navigator.of(this.context).push(MaterialPageRoute<void>(
            builder: (_) => DetalleExamenPage(examen: documento.examen)));
        }, child: const Text('Ver metadatos')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lista = _documentos.where((d) =>
      d.examen.nombre.toLowerCase().contains(_busqueda.toLowerCase()) &&
      (_tipo == 'Todos' || d.examen.tipo == _tipo)).toList()
      ..sort((a, b) => b.examen.fecha.compareTo(a.examen.fecha));
    return Scaffold(
      appBar: AppBar(title: const Text('Vitalia Health · Documentos')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: Center(child: SizedBox(width: 1000, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Exámenes con archivo asociado',
              style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text('Demostración local. Usa documentos ficticios. '
              'Al cerrar o reiniciar se pierden los registros.'),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(onPressed: _ocupado ? null : _registrar,
                icon: const Icon(Icons.upload_file),
                label: Text(_ocupado ? 'Registro en curso…' : 'Seleccionar archivo y registrar')),
              OutlinedButton(onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccesoPage())),
                child: const Text('Explorar vistas anteriores')),
            ]),
            if (_ocupado) const Padding(padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator()),
            const SizedBox(height: 24),
            TextField(decoration: const InputDecoration(
              labelText: 'Buscar examen', border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search)),
              onChanged: (texto) => setState(() => _busqueda = texto.trim())),
            const SizedBox(height: 12),
            Wrap(spacing: 12, children: [
              for (final tipo in ['Todos', 'Laboratorio', 'Imagenología'])
                ChoiceChip(label: Text(tipo), selected: _tipo == tipo,
                  onSelected: (_) => setState(() => _tipo = tipo)),
            ]),
            const SizedBox(height: 20),
            Text('${lista.length} registros locales · más recientes primero'),
            if (lista.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24),
              child: Text('No hay registros que mostrar. Añade un examen o revisa los filtros.'))),
            for (final documento in lista) Card(child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(documento.examen.nombre),
              subtitle: Text('${documento.examen.fechaTexto} · ${documento.archivo.name}\n'
                'Local · pendiente de almacenamiento'),
              isThreeLine: true, trailing: const Icon(Icons.chevron_right),
              onTap: () => _detalle(documento),
            )),
          ],
        ))),
      ),
    );
  }
}
