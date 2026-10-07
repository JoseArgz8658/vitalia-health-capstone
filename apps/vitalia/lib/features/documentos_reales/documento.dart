class Documento {
  const Documento({required this.id, required this.nombre, required this.tipo,
    required this.fecha, required this.archivo, required this.mime, required this.bytes});
  final String id;
  final String nombre;
  final String tipo;
  final String fecha;
  final String archivo;
  final String mime;
  final int bytes;
  factory Documento.fromJson(Map<String, dynamic> json) => Documento(
    id: json['id'] as String, nombre: json['examName'] as String,
    tipo: json['examType'] as String, fecha: json['examDate'] as String,
    archivo: json['originalName'] as String, mime: json['contentType'] as String,
    bytes: json['sizeBytes'] as int,
  );
  String get fechaVisible {
    final parts = fecha.split('-');
    return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : fecha;
  }
}
