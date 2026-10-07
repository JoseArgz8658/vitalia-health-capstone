import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';
import '../documentos_reales/documento.dart';

class ExtraccionPendiente {
  ExtraccionPendiente(this.status, this.sourceText, this.extraction, this.incidents);
  final String status;
  final String? sourceText;
  final Map<String, dynamic>? extraction;
  final List<String> incidents;
  factory ExtraccionPendiente.fromJson(Map<String, dynamic> data) {
    final status = data['status'] as String;
    if (data['approved'] != false || !['not_requested', 'queued', 'processing',
      'requires_review', 'rejected', 'failed'].contains(status)) {
      throw const FormatException();
    }
    final extraction = data['extraction'] as Map<String, dynamic>?;
    bool textOrNull(dynamic value) => value == null || value is String;
    if (extraction != null) {
      if (!textOrNull(extraction['examen']) || !textOrNull(extraction['fecha']) ||
          extraction['resultados'] is! List) throw const FormatException();
      for (final item in extraction['resultados'] as List) {
        if (item is! Map<String, dynamic> || !['nombre', 'valor', 'unidad', 'rango_referencia']
          .every((key) => textOrNull(item[key]))) throw const FormatException();
      }
    }
    final issues = data['incidents'] as Map<String, dynamic>;
    final incidents = <String>[];
    for (final category in ['reading', 'ocr', 'ai']) {
      for (final item in issues[category] as List) {
        final row = item as Map<String, dynamic>;
        final location = row['path'] ?? (row['page'] == null ? '' : 'Página ${row['page']}');
        incidents.add('${location == '' ? '' : '$location: '}${row['message'] as String}');
      }
    }
    return ExtraccionPendiente(status, data['sourceText'] as String?,
      extraction, incidents);
  }
}
class ProfesionalApi {
  ProfesionalApi(this.auth);
  final AuthApi auth;
  Future<List<Documento>> listar(String patientId, {int offset = 0}) async {
    final response = await auth.sendProfessionalRequest(http.Request('GET',
      auth.professionalUri(patientId, query: {'limit': '20', 'offset': '$offset'})));
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['documents'] as List).map((item) => Documento.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) { throw const AuthFailure('El servidor devolvió un historial inválido.'); }
  }
  Future<ExtraccionPendiente> consultar(String patientId, String documentId) async {
    final response = await auth.sendProfessionalRequest(http.Request('GET',
      auth.professionalUri(patientId, documentId: documentId, action: 'extraction')));
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ExtraccionPendiente.fromJson(data['processing'] as Map<String, dynamic>);
    } catch (_) { throw const AuthFailure('El servidor devolvió una extracción inválida.'); }
  }
  Future<Uint8List> descargar(String patientId, Documento item) async {
    final response = await auth.sendProfessionalRequest(http.Request('GET',
      auth.professionalUri(patientId, documentId: item.id, action: 'file')));
    if (response.bodyBytes.length != item.bytes || response.bodyBytes.length > 10 * 1024 * 1024) {
      throw const AuthFailure('El archivo recibido está incompleto o supera el límite.');
    }
    return response.bodyBytes;
  }
}
