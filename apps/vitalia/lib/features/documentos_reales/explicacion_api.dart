import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';

class ExplicacionApi {
  ExplicacionApi(this.auth);
  final AuthApi auth;
  Future<Map<String, dynamic>> consultar(String id) => _send(id, false);
  Future<Map<String, dynamic>> generar(String id) => _send(id, true);
  Future<Map<String, dynamic>> _send(String id, bool generate) async {
    final request = http.Request(generate ? 'POST' : 'GET', auth.documentUri('$id/assistant/explanation'));
    if (generate) { request.headers['Content-Type'] = 'application/json'; request.body = '{}'; }
    final response = await auth.sendDocumentRequest(request);
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['approved'] != false || !['not_available', 'not_requested', 'generating', 'ready', 'failed'].contains(data['status'])) throw const FormatException();
      if (data['status'] == 'ready') {
        final explanation = data['explanation'] as Map<String, dynamic>;
        if (explanation['approved'] != false || explanation['notice'] is! String ||
            data['generatedAt'] is! String || DateTime.tryParse(data['generatedAt'] as String) == null) throw const FormatException();
        final items = explanation['items'] as List;
        if (items.isEmpty || items.length > 20) throw const FormatException();
        for (var index = 0; index < items.length; index++) {
          final row = items[index] as Map<String, dynamic>;
          if (row['index'] != index || row['explanation'] is! String ||
              !['medical_general', 'desconocido'].contains(row['concept']) ||
              !['name', 'value', 'unit', 'reference'].every((key) => row.containsKey(key) && (row[key] == null || row[key] is String)) ||
              (row['source'] != null && row['source'] is! String)) throw const FormatException();
        }
      } else if (data['explanation'] != null) { throw const FormatException(); }
      return data;
    } catch (_) { throw const AuthFailure('El servidor devolvió una explicación inválida.'); }
  }
}
