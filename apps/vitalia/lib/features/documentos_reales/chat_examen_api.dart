import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';

String nuevaSolicitudChat() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
class ChatExamenApi {
  ChatExamenApi(this.auth);
  final AuthApi auth;
  Future<Map<String, dynamic>> _send(String id, [Map<String, String>? body]) async {
    final request = http.Request(body == null ? 'GET' : 'POST', auth.documentUri('$id/assistant'));
    if (body != null) { request.headers['Content-Type'] = 'application/json'; request.body = jsonEncode(body); }
    final response = await auth.sendDocumentRequest(request);
    try { return jsonDecode(response.body) as Map<String, dynamic>; }
    catch (_) { throw const AuthFailure('El servidor devolvió una conversación inválida.'); }
  }
  Map<String, dynamic> validarTurno(dynamic value) {
    try {
      final turn = value as Map<String, dynamic>;
      if (turn['approved'] != false || turn['id'] is! String || turn['question'] is! String ||
          turn['mode'] != 'chat' || !['pending', 'ready', 'failed'].contains(turn['status'])) throw const FormatException();
      if (turn['status'] == 'ready') {
        final reply = turn['response'] as Map<String, dynamic>;
        if (reply['answer'] is! String || !['education', 'insufficient', 'out_of_scope', 'restricted'].contains(reply['kind']) ||
            reply['indices'] is! List || (reply['indices'] as List).any((i) => i is! int || i < 0 || i > 19)) throw const FormatException();
      } else if (turn['response'] != null) { throw const FormatException(); }
      return turn;
    } catch (_) { throw const AuthFailure('El servidor devolvió una conversación inválida.'); }
  }
  Future<Map<String, dynamic>> consultar(String id) async {
    final data = await _send(id);
    if (data['approved'] != false || !['available', 'not_available'].contains(data['status']) || data['notice'] is! String || data['turns'] is! List || (data['turns'] as List).length > 30) {
      throw const AuthFailure('El servidor devolvió una conversación inválida.');
    }
    for (final turn in data['turns'] as List) { validarTurno(turn); }
    return data;
  }
  Future<Map<String, dynamic>> preguntar(String id, String requestId, String question) async {
    if (question.trim().isEmpty || question.trim().length > 500 || !RegExp(r'^[a-f0-9-]{36}$').hasMatch(requestId)) {
      throw const AuthFailure('Escribe una pregunta de hasta quinientos caracteres.');
    }
    final data = await _send(id, {'requestId': requestId, 'question': question.trim()});
    return validarTurno(data['turn']);
  }
}
