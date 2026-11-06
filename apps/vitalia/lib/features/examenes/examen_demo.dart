/// Metadatos sintéticos para probar navegación; no representa un archivo almacenado.
class ExamenDemo {
  const ExamenDemo({required this.nombre, required this.tipo, required this.fecha});
  final String nombre;
  final String tipo;
  final DateTime fecha;
  String get fechaTexto =>
    '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
}
final examenesDemo = List<ExamenDemo>.unmodifiable([
  ExamenDemo(nombre: 'Hemograma de demostración', tipo: 'Laboratorio', fecha: DateTime(2026, 9, 23)),
  ExamenDemo(nombre: 'Perfil lipídico de demostración', tipo: 'Laboratorio', fecha: DateTime(2026, 9, 12)),
  ExamenDemo(nombre: 'Informe de imagen de demostración', tipo: 'Imagenología', fecha: DateTime(2026, 8, 28)),
]);
