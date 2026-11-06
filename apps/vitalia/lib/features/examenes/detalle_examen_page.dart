import 'package:flutter/material.dart';
import 'examen_demo.dart';

class DetalleExamenPage extends StatelessWidget {
  const DetalleExamenPage({super.key, required this.examen});
  final ExamenDemo examen;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalle del examen')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: Center(child: SizedBox(width: 760, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(examen.nombre, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('Datos sintéticos · no hay un documento real adjunto'),
          const SizedBox(height: 20),
          Card(child: Column(children: [
            ListTile(leading: const Icon(Icons.category_outlined),
              title: const Text('Tipo de examen'), subtitle: Text(examen.tipo)),
            ListTile(leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Fecha del examen'), subtitle: Text(examen.fechaTexto)),
          ])),
          const SizedBox(height: 20),
          const Card(child: Padding(padding: EdgeInsets.all(24), child: Column(
            children: [
              Icon(Icons.description_outlined, size: 56),
              SizedBox(height: 12),
              Text('Visualización del documento pendiente de integración.'),
            ],
          ))),
          const SizedBox(height: 20),
          const Text('La extracción y explicación por IA todavía no están disponibles. '
            'La futura asistencia no sustituirá la evaluación profesional.'),
        ],
      ))),
    ),
  );
}
