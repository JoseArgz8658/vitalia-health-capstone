import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/documentos_reales/documentos_api.dart';

Future<AuthApi> session(
  Future<http.Response> Function(http.Request) handler,
) async {
  final token = 'a' * 64;
  final auth = AuthApi(
    client: MockClient((request) async {
      if (request.url.path.endsWith('/login'))
        return http.Response(
          jsonEncode({
            'token': token,
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 30))
                .toIso8601String(),
          }),
          200,
        );
      if (request.url.path.endsWith('/me'))
        return http.Response(
          '{"user":{"id":"11111111-1111-4111-8111-111111111111","email":"paciente@example.invalid","role":"paciente"}}',
          200,
        );
      expect(request.headers['Authorization'], 'Bearer $token');
      return handler(request);
    }),
  );
  await auth.login('paciente@example.invalid', 'contraseña sintética');
  return auth;
}

void main() {
  test('catálogo usa comuna confirmada, paginación y sesión', () async {
    final auth = await session((request) async {
      expect(request.url.path, '/api/care/catalog');
      expect(request.url.queryParameters, {
        'communeCode': '13125',
        'offset': '30',
      });
      expect(request.method, 'GET');
      return http.Response('{"items":[],"nextOffset":null}', 200);
    });
    expect((await auth.careCatalog('13125', offset: 30))['items'], isEmpty);
    auth.close();
  });
  test('contexto expirado limpia sesión y conserva estado 401', () async {
    final auth = await session((request) async {
      expect(request.url.path, '/api/care/context');
      return http.Response('{}', 401);
    });
    await expectLater(
      auth.careContext(),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 401)),
    );
    expect(auth.hasSession, false);
    auth.close();
  });
  test(
    'carga serializa elección y contacto en un campo JSON sin identidad',
    () async {
      final choice = {
        'clinicId': 'synthetic',
        'phone': '+56912345678',
        'confirmed': true,
      };
      final auth = await session((request) async {
        expect(request.url.path, '/api/documents');
        final body = utf8.decode(request.bodyBytes);
        expect(body, contains('name="care"'));
        expect(body, contains(jsonEncode(choice)));
        expect(body, isNot(contains('name="patientId"')));
        expect(body, isNot(contains('name="email"')));
        return http.Response('{}', 201);
      });
      await DocumentosApi(auth).upload(
        nombre: 'Examen sintético',
        tipo: 'Laboratorio',
        fecha: '2026-01-01',
        archivo: 'synthetic.pdf',
        mime: 'application/pdf',
        bytes: Uint8List.fromList(utf8.encode('%PDF-1.4\n%%EOF')),
        care: choice,
      );
      auth.close();
    },
  );
}
