import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/profesional/revision_api.dart';

const id = '11111111-1111-4111-8111-111111111111',
    doc = '22222222-2222-4222-8222-222222222222';
final extraction = {
  'examen': 'Examen sintético',
  'fecha': '01-01-2026',
  'resultados': <dynamic>[],
};
Future<AuthApi> session(
  Future<http.Response> Function(http.Request) handler,
) async {
  final token = 'a' * 64;
  final auth = AuthApi(
    client: MockClient((r) async {
      if (r.url.path.endsWith('/login'))
        return http.Response(
          jsonEncode({
            'token': token,
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 30))
                .toIso8601String(),
          }),
          200,
        );
      if (r.url.path.endsWith('/me'))
        return http.Response(
          '{"user":{"id":"$id","email":"profesional@example.invalid","role":"profesional"}}',
          200,
        );
      expect(r.headers['Authorization'], 'Bearer $token');
      return handler(r);
    }),
  );
  await auth.login(
    'profesional@example.invalid',
    'contraseña sintética',
    mode: 'profesional',
  );
  return auth;
}

void main() {
  test(
    'consulta usa atención y sesión sin identificador de paciente',
    () async {
      final auth = await session((r) async {
        expect(r.url.path, '/api/care-inbox/$id/review');
        expect(r.method, 'GET');
        return http.Response(
          jsonEncode({
            'processingId': doc,
            'originalExtraction': extraction,
            'canReview': true,
            'review': null,
            'expectedRevision': 1,
          }),
          200,
        );
      });
      expect(
        (await RevisionApi(auth, careId: id).consultar('', doc))['canReview'],
        true,
      );
      auth.close();
    },
  );
  test(
    'aprobación envía versión y datos cotejados sin identidad del cliente',
    () async {
      final auth = await session((r) async {
        expect(r.url.path, '/api/care-inbox/$id/review');
        expect(r.method, 'POST');
        final body = jsonDecode(r.body) as Map;
        expect(body['expectedRevision'], 1);
        expect(body['confirmedOriginal'], true);
        expect(body.containsKey('patientId'), false);
        expect(body.containsKey('reviewerId'), false);
        return http.Response(
          jsonEncode({
            'review': {
              'approved': true,
              'extraction': extraction,
              'reviewerEmail': 'profesional@example.invalid',
              'observations': 'Cotejado',
              'reviewedAt': '2026-01-01T12:00:00Z',
            },
          }),
          201,
        );
      });
      final saved = await RevisionApi(auth, careId: id).aprobar(
        '',
        doc,
        processingId: doc,
        extraction: extraction,
        observations: 'Cotejado',
        confirmedOriginal: true,
        expectedRevision: 1,
      );
      expect(saved['approved'], true);
      auth.close();
    },
  );
  test('rechazo de sesión limpia token y no devuelve revisión', () async {
    final auth = await session((_) async => http.Response('{}', 401));
    await expectLater(
      RevisionApi(auth, careId: id).consultar('', doc),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 401)),
    );
    expect(auth.hasSession, false);
    auth.close();
  });
}
