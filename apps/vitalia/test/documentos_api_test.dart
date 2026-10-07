import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/documentos_reales/documentos_api.dart';
import 'package:vitalia_health/features/documentos_reales/documento.dart';

final token = List.filled(64, 'a').join();
const id = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> document() => {'id': id, 'examName': 'Examen sintético',
  'examType': 'Laboratorio', 'examDate': '2026-01-02',
  'originalName': 'examen.pdf', 'contentType': 'application/pdf', 'sizeBytes': 3};
Future<AuthApi> session(Future<http.Response> Function(http.Request) documents) async {
  final api = AuthApi(client: MockClient((request) async {
    if (request.url.path.endsWith('/login')) return http.Response(jsonEncode({
      'token': token, 'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String()}), 200);
    if (request.url.path.endsWith('/me')) return http.Response(
      '{"user":{"id":"11111111-1111-4111-8111-111111111111","email":"test@example.com","role":"paciente"}}', 200);
    expect(request.headers['Authorization'], 'Bearer ${token}');
    return documents(request);
  }));
  await api.login('test@example.com', 'contraseña ficticia');
  return api;
}
void main() {
  test('historial usa sesión y paginación del backend', () async {
    final auth = await session((req) async {
      expect(req.url.path, '/api/documents');
      expect(req.url.queryParameters, {'limit': '20', 'offset': '20'});
      return http.Response(jsonEncode({'documents': [document()]}), 200);
    });
    final items = await DocumentosApi(auth).list(offset: 20);
    expect(items.single.nombre, 'Examen sintético');
    expect(items.single.fechaVisible, '02/01/2026');
    auth.close();
  });
  test('carga serializa MIME y nombre UTF-8, sin propietario ni rol', () async {
    final auth = await session((req) async {
      expect(req.method, 'POST');
      expect(req.headers['Content-Type'], startsWith('multipart/form-data; boundary='));
      final body = utf8.decode(req.bodyBytes);
      expect(body, contains('name="examName"'));
      expect(body, contains('Content-Type: application/pdf'));
      expect(body, contains("filename*=UTF-8''examen.pdf"));
      expect(body, isNot(contains('name="patientId"')));
      expect(body, isNot(contains('name="role"')));
      return http.Response('{"document":{"id":"$id"}}', 201);
    });
    await DocumentosApi(auth).upload(nombre: 'Examen sintético', tipo: 'Laboratorio',
      fecha: '2026-01-02', archivo: 'examen.pdf', mime: 'application/pdf',
      bytes: Uint8List.fromList(utf8.encode('%PDF-1.4\n%%EOF')));
    auth.close();
  });
  test('401 descarta sesión y no devuelve historial', () async {
    final auth = await session((_) async => http.Response('{}', 401));
    await expectLater(DocumentosApi(auth).list(), throwsA(isA<AuthFailure>()));
    expect(auth.hasSession, false);
    auth.close();
  });
  test('archivo mayor al límite no se transmite', () async {
    var requests = 0;
    final auth = await session((_) async { requests++; return http.Response('{}', 201); });
    await expectLater(DocumentosApi(auth).upload(nombre: 'Sintético', tipo: 'Laboratorio',
      fecha: '2026-01-02', archivo: 'examen.pdf', mime: 'application/pdf',
      bytes: Uint8List(10 * 1024 * 1024 + 1)), throwsA(isA<AuthFailure>()));
    expect(requests, 0);
    auth.close();
  });
  test('descarga verifica tamaño y no utiliza URL pública', () async {
    final auth = await session((req) async {
      expect(req.url.path, '/api/documents/$id/file');
      return http.Response.bytes([1, 2, 3], 200);
    });
    expect(await DocumentosApi(auth).download(Documento.fromJson(document())), [1, 2, 3]);
    auth.close();
  });
  test('bloquea envío del token a otro origen', () async {
    final auth = await session((_) async => http.Response('{}', 200));
    await expectLater(auth.sendDocumentRequest(http.Request('GET',
      Uri.parse('https://example.com/api/documents'))), throwsA(isA<AuthFailure>()));
    auth.close();
  });
}
