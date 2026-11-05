import 'package:file_selector/file_selector.dart';
import '../examenes/examen_demo.dart';

/// Referencia temporal al archivo elegido; no representa persistencia en S3.
class DocumentoLocal {
  const DocumentoLocal({required this.examen, required this.archivo, required this.bytes});
  final ExamenDemo examen;
  final XFile archivo;
  final int bytes;
}
