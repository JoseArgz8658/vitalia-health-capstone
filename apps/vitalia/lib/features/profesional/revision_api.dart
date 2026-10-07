import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';

class RevisionApi {
  RevisionApi(this.auth);
  final AuthApi auth;
  Future<Map<String, dynamic>> _send(http.Request request) async {
    final response = await auth.sendReviewRequest(request);
    try { return jsonDecode(response.body) as Map<String, dynamic>; }
    catch (_) { throw const AuthFailure('El servidor devolvió una revisión inválida.'); }
  }
  Future<Map<String, dynamic>> consultar(String patientId, String documentId) async {
    final data = await _send(http.Request('GET', auth.reviewUri(patientId, documentId)));
    if (data['canReview'] is! bool || (data['processingId'] != null && data['processingId'] is! String) ||
        (data['originalExtraction'] != null && data['originalExtraction'] is! Map<String, dynamic>) ||
        (data['review'] != null && data['review'] is! Map<String, dynamic>)) {
      throw const AuthFailure('El servidor devolvió una revisión inválida.');
    }
    if (data['review'] != null) _validate(data['review'] as Map<String, dynamic>);
    return data;
  }
  void _validate(Map<String, dynamic> review) {
    if (review['approved'] != true || review['extraction'] is! Map<String, dynamic> ||
        review['reviewerEmail'] is! String || review['reviewedAt'] is! String ||
        review['observations'] is! String || DateTime.tryParse(review['reviewedAt'] as String) == null) throw const AuthFailure('El servidor devolvió una revisión inválida.');
  }
  Future<Map<String, dynamic>> aprobar(String patientId, String documentId,
      {required String processingId, required Map<String, dynamic> extraction,
      required String observations, required bool confirmedOriginal}) async {
    final request = http.Request('POST', auth.reviewUri(patientId, documentId));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({'processingId': processingId, 'extraction': extraction,
      'observations': observations, 'confirmedOriginal': confirmedOriginal});
    final data = await _send(request);
    try {
      final review = data['review'] as Map<String, dynamic>;
      _validate(review);
      return review;
    } on AuthFailure { rethrow; }
    catch (_) { throw const AuthFailure('El servidor devolvió una revisión inválida. Actualiza antes de repetir.'); }
  }
}
