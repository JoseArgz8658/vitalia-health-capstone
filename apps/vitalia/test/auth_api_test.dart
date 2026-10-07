import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';

void main() {
  test('login confirma identidad con me y logout elimina sesión', () async {
    final paths = <String>[];
    final api = AuthApi(client: MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('login')) {
        expect(jsonDecode(request.body), {'email': 'test@example.com', 'password': '  clave larga  '});
        return http.Response(jsonEncode({'token': 'token',
          'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String()}), 200);
      }
      expect(request.headers['Authorization'], 'Bearer token');
      if (request.url.path.endsWith('logout')) return http.Response('', 204);
      return http.Response(jsonEncode({'user': {'email': 'test@example.com', 'role': 'paciente'}}), 200);
    }));
    final user = await api.login(' test@example.com ', '  clave larga  ');
    expect(user['role'], 'paciente');
    expect(api.hasSession, true);
    await api.logout();
    expect(api.hasSession, false);
    expect(paths, ['/api/auth/login', '/api/auth/me', '/api/auth/logout']);
    api.close();
  });
  test('credenciales inválidas no crean sesión', () async {
    final api = AuthApi(client: MockClient((_) async => http.Response('{}', 401)));
    await expectLater(api.login('a@b.cl', 'incorrecta'), throwsA(isA<AuthFailure>()));
    expect(api.hasSession, false);
    api.close();
  });
  test('registro envía solo email y password, sin rol', () async {
    final api = AuthApi(client: MockClient((request) async {
      expect(jsonDecode(request.body), {'email': 'a@b.cl', 'password': 'doce caracteres'});
      return http.Response('{"message":"Solicitud de registro procesada."}', 202);
    }));
    await api.register('a@b.cl', 'doce caracteres');
    expect(api.hasSession, false);
    api.close();
  });
  test('me rechaza rol desconocido y descarta token', () async {
    final api = AuthApi(client: MockClient((request) async {
      if (request.url.path.endsWith('login')) return http.Response(jsonEncode({
        'token': 'token', 'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String()}), 200);
      return http.Response('{"user":{"role":"otro"}}', 200);
    }));
    await expectLater(api.login('a@b.cl', 'clave'), throwsA(isA<AuthFailure>()));
    expect(api.hasSession, false);
    api.close();
  });
}
