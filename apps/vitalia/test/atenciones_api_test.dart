import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/profesional/atenciones_api.dart';

const id = '11111111-1111-4111-8111-111111111111';
Future<AuthApi> session(
  Future<http.Response> Function(http.Request) action,
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
      return action(r);
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
  test('lista usa sesión y página sin identidad del paciente', () async {
    final auth = await session((r) async {
      expect(r.url.path, '/api/care-inbox');
      expect(r.url.queryParameters, {'offset': '20'});
      return http.Response('{"items":[],"nextOffset":null}', 200);
    });
    expect((await AtencionesApi(auth).list(offset: 20))['items'], isEmpty);
    auth.close();
  });
  test('inicio envía solo revisión esperada a la atención elegida', () async {
    final auth = await session((r) async {
      expect(r.url.path, '/api/care-inbox/$id/begin');
      expect(r.method, 'POST');
      expect(jsonDecode(r.body), {'expectedRevision': 0});
      return http.Response('{"started":true}', 200);
    });
    await AtencionesApi(auth).begin(id, 0);
    auth.close();
  });
  test('401 elimina sesión y no entrega detalle', () async {
    final auth = await session((_) async => http.Response('{}', 401));
    await expectLater(
      AtencionesApi(auth).details(id),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 401)),
    );
    expect(auth.hasSession, false);
    auth.close();
  });
}
