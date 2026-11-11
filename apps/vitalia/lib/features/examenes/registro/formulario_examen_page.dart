import 'package:flutter/material.dart';
import '../examen_demo.dart';

/// Registra metadatos de prueba; no selecciona ni sube archivos.
class FormularioExamenPage extends StatefulWidget {
  const FormularioExamenPage({super.key});
  @override
  State<FormularioExamenPage> createState() => _FormularioExamenPageState();
}
class _FormularioExamenPageState extends State<FormularioExamenPage> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  String? _tipo;
  DateTime? _fecha;
  @override
  void dispose() { _nombre.dispose(); super.dispose(); }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(context: context,
      initialDate: _fecha ?? DateTime.now(),
      firstDate: DateTime(1900), lastDate: DateTime.now(),
      helpText: 'Fecha del examen', cancelText: 'Cancelar', confirmText: 'Aceptar');
    if (!mounted || fecha == null) return;
    setState(() => _fecha = fecha);
  }

  void _guardar() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(ExamenDemo(
      nombre: _nombre.text.trim(), tipo: _tipo!, fecha: _fecha!));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Registrar examen de demostración')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: Center(child: SizedBox(width: 640,
        child: Card(child: Padding(padding: const EdgeInsets.all(24),
          child: Form(key: _form, child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Datos del examen', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text('Usa únicamente datos ficticios. El registro vive en memoria '
                'y se pierde al reiniciar. No se adjunta ni almacena un archivo.'),
              const SizedBox(height: 24),
              TextFormField(controller: _nombre, maxLength: 100,
                decoration: const InputDecoration(labelText: 'Nombre del examen',
                  border: OutlineInputBorder()),
                validator: (valor) {
                  final nombre = (valor ?? '').trim();
                  if (nombre.isEmpty) return 'Escribe el nombre del examen.';
                  if (nombre.length > 100) return 'Usa hasta 100 caracteres.';
                  return null;
                }),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Tipo',
                  border: OutlineInputBorder()),
                items: ['Laboratorio', 'Imagenología'].map((tipo) =>
                  DropdownMenuItem(value: tipo, child: Text(tipo))).toList(),
                onChanged: (tipo) => setState(() => _tipo = tipo),
                validator: (valor) => valor == null ? 'Selecciona un tipo.' : null,
              ),
              const SizedBox(height: 16),
              FormField<DateTime>(
                validator: (_) => _fecha == null ? 'Selecciona la fecha del examen.' : null,
                builder: (estado) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(onPressed: _elegirFecha,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_fecha == null ? 'Seleccionar fecha'
                        : '${_fecha!.day}/${_fecha!.month}/${_fecha!.year}')),
                    if (estado.hasError) Text(estado.errorText!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: _guardar,
                icon: const Icon(Icons.check), label: const Text('Añadir a la demostración')),
              TextButton(onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar')),
            ],
          )),
        )),
      )),
    ),
  );
}
