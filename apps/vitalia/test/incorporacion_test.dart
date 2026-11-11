import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/incorporacion/activar_invitacion_page.dart';
import 'package:vitalia_health/features/incorporacion/incorporacion_page.dart';

class OnboardingFake extends AuthApi {
  bool empty = false;
  final sent = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> onboarding(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (body != null) {
      sent.add(body);
      return {'activated': true};
    }
    return {
      'clinics': empty
          ? []
          : [
              {
                'id': '22222222-2222-4222-8222-222222222222',
                'name': 'Clínica ficticia',
              },
            ],
    };
  }
}

void main() {
  test(
    'activación pública envía código en cuerpo y no adjunta sesión',
    () async {
      final api = AuthApi(
        client: MockClient((r) async {
          expect(r.method, 'POST');
          expect(r.url.path, '/api/onboarding/activate');
          expect(r.url.hasQuery, isFalse);
          expect(r.headers.containsKey('Authorization'), isFalse);
          expect((jsonDecode(r.body) as Map)['token'], 'a' * 64);
          return http.Response('{"activated":true}', 200);
        }),
      );
      expect(
        (await api.onboarding(
          '/activate',
          body: {'token': 'a' * 64},
        ))['activated'],
        isTrue,
      );
      api.close();
    },
  );
  test('gestión exige sesión antes de enviar y rechaza ruta ajena', () async {
    var called = false;
    final api = AuthApi(
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(api.onboarding('/context'), throwsA(isA<AuthFailure>()));
    await expectLater(
      api.onboarding('https://otro.example'),
      throwsA(isA<AuthFailure>()),
    );
    expect(called, isFalse);
    api.close();
  });
  test(
    'incorporación usa sesión y no permite token como parámetro de URL',
    () async {
      final api = AuthApi(
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            return http.Response(
              jsonEncode({
                'token': 'a' * 64,
                'expiresAt': DateTime.now()
                    .add(const Duration(minutes: 30))
                    .toIso8601String(),
              }),
              200,
            );
          }
          if (r.url.path.endsWith('/me')) {
            return http.Response('{"user":{"role":"profesional"}}', 200);
          }
          expect(r.url.path, '/api/onboarding/context');
          expect(r.headers['Authorization'], 'Bearer ${'a' * 64}');
          return http.Response('{"clinics":[]}', 200);
        }),
      );
      await api.login('ficticio@example.invalid', 'prueba');
      expect((await api.onboarding('/context'))['clinics'], isEmpty);
      await expectLater(
        api.onboarding('/activate?token=secreto', body: {}),
        throwsA(isA<AuthFailure>()),
      );
      api.close();
    },
  );
  testWidgets('contraseñas distintas impiden activar la invitación', (t) async {
    final api = OnboardingFake();
    await t.pumpWidget(MaterialApp(home: ActivarInvitacionPage(api: api)));
    final fields = find.byType(TextFormField);
    for (final pair in [
      (0, 'a' * 64),
      (1, 'Persona'),
      (2, 'Ficticia'),
      (3, 'Clave-larga-2026'),
      (4, 'Otra-clave-2026'),
    ]) {
      await t.enterText(fields.at(pair.$1), pair.$2);
    }
    await t.ensureVisible(find.text('Activar mi cuenta'));
    await t.tap(find.text('Activar mi cuenta'));
    await t.pumpAndSettle();
    expect(find.text('Las contraseñas deben coincidir.'), findsOneWidget);
    expect(api.sent, isEmpty);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('activación correcta no crea sesión ni permite elegir rol', (
    t,
  ) async {
    final api = OnboardingFake();
    await t.pumpWidget(MaterialApp(home: ActivarInvitacionPage(api: api)));
    final fields = find.byType(TextFormField);
    for (final pair in [
      (0, 'a' * 64),
      (1, 'Persona'),
      (2, 'Ficticia'),
      (3, 'Clave-larga-2026'),
      (4, 'Clave-larga-2026'),
    ]) {
      await t.enterText(fields.at(pair.$1), pair.$2);
    }
    await t.ensureVisible(find.text('Activar mi cuenta'));
    await t.tap(find.text('Activar mi cuenta'));
    await t.pumpAndSettle();
    expect(api.sent.single.containsKey('role'), isFalse);
    expect(api.hasSession, isFalse);
    expect(find.textContaining('Invitación aceptada.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('profesional sin jefatura no ve formulario para invitar', (
    t,
  ) async {
    final api = OnboardingFake()..empty = true;
    await t.pumpWidget(
      MaterialApp(
        home: IncorporacionPage(api: api, admin: false, onExpired: () {}),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.textContaining('No tienes una pertenencia activa'),
      findsOneWidget,
    );
    expect(find.text('Invitar profesional'), findsNothing);
    expect(api.sent, isEmpty);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
}
