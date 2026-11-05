import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/profesional/atenciones_api.dart';

const id = '11111111-1111-4111-8111-111111111111';
Future<AuthApi> session(
  Future<http.Response> Function(http.Request) handler, {
  String mode = 'profesional',
}) async {
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
          '{"user":{"id":"$id","email":"synthetic@example.invalid","role":"$mode"}}',
          200,
        );
      expect(r.headers['Authorization'], 'Bearer $token');
      return handler(r);
    }),
  );
  await auth.login(
    'synthetic@example.invalid',
    'contraseña sintética',
    mode: mode,
  );
  return auth;
}

void main() {
  test('destinatarios usan sesión y página sin clínica del cliente', () async {
    final auth = await session((r) async {
      expect(r.url.path, '/api/care-inbox/$id/referral-options');
      expect(r.url.queryParameters, {'offset': '30'});
      return http.Response('{"items":[],"expectedRevision":0}', 200);
    });
    await AtencionesApi(auth).referralOptions(id, offset: 30);
    auth.close();
  });
  test('derivación usa POST con identificador estable y motivo', () async {
    final value = {
      'requestId': id,
      'reason': 'Continuidad sintética',
      'confirmed': true,
    };
    final auth = await session((r) async {
      expect(r.method, 'POST');
      expect(r.url.path, '/api/care-inbox/$id/referrals');
      expect(jsonDecode(r.body), value);
      return http.Response('{"referred":true}', 201);
    });
    expect((await AtencionesApi(auth).refer(id, value))['referred'], true);
    auth.close();
  });
  test('seguimiento permite GET y bloquea escritura del cliente', () async {
    var calls = 0;
    final auth = await session((r) async {
      calls++;
      expect(r.url.path, '/api/documents/$id/care');
      expect(r.method, 'GET');
      return http.Response('{"items":[]}', 200);
    }, mode: 'paciente');
    await auth.sendDocumentRequest(
      http.Request('GET', auth.documentUri('$id/care')),
    );
    await expectLater(
      auth.sendDocumentRequest(
        http.Request('POST', auth.documentUri('$id/care')),
      ),
      throwsA(isA<AuthFailure>()),
    );
    expect(calls, 1);
    auth.close();
  });
}
