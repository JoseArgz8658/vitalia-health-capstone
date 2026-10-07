import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';

class ProcesamientoApi {
  ProcesamientoApi(this.auth);
  final AuthApi auth;
  Future<String> consultar(String id) => _send(id, 'GET');
  Future<String> solicitar(String id) => _send(id, 'POST');
  Future<String> _send(String id, String method) async {
    final request = http.Request(method, auth.documentUri('$id/processing'));
    if (method == 'POST') {
      request.headers['Content-Type'] = 'application/json';
      request.body = '{}';
    }
    final response = await auth.sendDocumentRequest(request);
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final processing = data['processing'] as Map<String, dynamic>;
      final status = processing['status'] as String;
      if (processing['approved'] != false || ![
        'not_requested', 'queued', 'processing', 'requires_review', 'rejected', 'failed',
      ].contains(status)) {
        throw const FormatException();
      }
      final reviewStatus = processing['reviewStatus'] ?? 'not_reviewed';
      if (!['approved', 'not_reviewed'].contains(reviewStatus)) throw const FormatException();
      if (reviewStatus == 'approved') {
        if (status != 'requires_review' || processing['reviewedAt'] is! String ||
            DateTime.tryParse(processing['reviewedAt'] as String) == null) throw const FormatException();
        return 'professionally_reviewed';
      }
      return status;
    } catch (_) {
      throw const AuthFailure('El servidor devolvió un estado inválido.');
    }
  }
}
