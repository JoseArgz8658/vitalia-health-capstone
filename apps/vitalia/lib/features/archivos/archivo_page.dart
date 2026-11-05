import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../acceso/acceso_page.dart';

/// Selección local: consulta metadatos y no transmite ni persiste el archivo.
class ArchivoPage extends StatefulWidget {
  const ArchivoPage({super.key});
  @override
  State<ArchivoPage> createState() => _ArchivoPageState();
}
class _ArchivoPageState extends State<ArchivoPage> {
  String? _nombre;
  int? _tamano;
  bool _ocupado = false;
  String? _mensaje;

  Future<void> _seleccionar() async {
    setState(() { _ocupado = true; _mensaje = null; });
    try {
      // Sin restricciones inventadas: formatos y límite se definirán con requisitos.
      final archivo = await openFile();
      if (!mounted) return;
      if (archivo == null) {
        setState(() => _mensaje = 'Selección cancelada. No se cambió el archivo anterior.');
        return;
      }
      final tamano = await archivo.length();
      if (!mounted) return;
      if (tamano == 0) {
        setState(() => _mensaje = 'El archivo está vacío. Selecciona otro archivo.');
        return;
      }
      setState(() { _nombre = archivo.name; _tamano = tamano; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _mensaje = 'No se pudo acceder al archivo. Intenta seleccionarlo nuevamente.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seleccionar documento')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: Center(child: SizedBox(width: 720, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Archivo del examen', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text('Prueba con archivos sintéticos. La selección es local: '
            'no se sube a S3, no se registra un examen ni se procesa con IA.'),
          const SizedBox(height: 24),
          Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.upload_file_outlined, size: 64),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _ocupado ? null : _seleccionar,
                icon: const Icon(Icons.folder_open),
                label: Text(_ocupado ? 'Seleccionando…' : 'Elegir archivo'),
              ),
              if (_ocupado) const Padding(padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator()),
              if (_nombre != null) ...[
                const SizedBox(height: 20),
                Text(_nombre!, style: Theme.of(context).textTheme.titleMedium),
                Text('Tamaño: $_tamano bytes'),
                const SizedBox(height: 8),
                const Text('Seleccionado localmente · contenido y formato aún sin validar'),
                TextButton(onPressed: _ocupado ? null : () => setState(() {
                  _nombre = null; _tamano = null; _mensaje = null;
                }), child: const Text('Quitar selección')),
              ],
              if (_mensaje != null) Padding(padding: const EdgeInsets.only(top: 16),
                child: Text(_mensaje!, semanticsLabel: _mensaje)),
            ],
          ))),
          const SizedBox(height: 16),
          const Text('Los formatos permitidos, tamaño máximo y comprobaciones de '
            'contenido se definirán antes de habilitar la carga real.'),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AccesoPage())),
            child: const Text('Explorar acceso y vistas anteriores')),
        ],
      ))),
    ),
  );
}
