import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/app/vitalia_mvp_app.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/acceso/acceso_page.dart';
import 'package:vitalia_health/features/incorporacion/activar_invitacion_page.dart';

class ModesFake extends AuthApi {
  final modes = <String>[];
  final sent = <Map<String, dynamic>>[];
  bool mismatch = false, loggedOut = false;
  @override
  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String mode = 'paciente',
  }) async {
    modes.add(mode);
    return {'id': 'test', 'email': email, 'role': mode};
  }

  @override
  Future<Map<String, dynamic>> onboarding(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    sent.add({'path': path, ...?body});
    if (mismatch)
      throw const AuthFailure(
        'La invitación no corresponde a la cuenta con la que ingresaste.',
        403,
      );
    return {'accepted': true};
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
    clear();
  }
}

Future<void> fillExisting(WidgetTester t) async {
  await t.tap(find.byType(SwitchListTile).first);
  await t.pumpAndSettle();
  for (final pair in [
    ('Código de invitación', 'a' * 64),
    ('Primer nombre', 'Persona'),
    ('Primer apellido', 'Ficticia'),
    ('Correo de tu cuenta', 'persona@example.invalid'),
    ('Contraseña actual', 'Clave-actual-2026'),
    ('Nueva contraseña profesional', 'Otra-profesional-2026!'),
    ('Confirmar contraseña profesional', 'Otra-profesional-2026!'),
  ]) {
    final field = find.widgetWithText(TextFormField, pair.$1);
    await t.ensureVisible(field);
    await t.enterText(field, pair.$2);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  t.testTextInput.hide();
  await t.pumpAndSettle();
  final consent = find.byType(CheckboxListTile);
  await t.ensureVisible(consent);
  await t.pumpAndSettle();
  final checkbox = find
      .descendant(of: consent, matching: find.byType(Checkbox))
      .hitTestable();
  expect(checkbox, findsOneWidget);
  await t.tap(checkbox);
  await t.pumpAndSettle();
  expect(t.widget<CheckboxListTile>(consent).value, isTrue);
  final submit = find.text('Iniciar sesión y aceptar invitación');
  await t.ensureVisible(submit);
  await t.pumpAndSettle();
  expect(submit.hitTestable(), findsOneWidget);
  await t.tap(submit);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('cuenta dual anterior configura contraseña sin invitación', (
    t,
  ) async {
    final api = ModesFake();
    await t.pumpWidget(
      MaterialApp(home: ActivarInvitacionPage(api: api, passwordSetup: true)),
    );
    expect(find.text('Código de invitación'), findsNothing);
    for (final pair in [
      ('Correo de tu cuenta', 'persona@example.invalid'),
      ('Contraseña actual', 'Clave-actual-2026'),
      ('Nueva contraseña profesional', 'Otra-profesional-2026!'),
      ('Confirmar contraseña profesional', 'Otra-profesional-2026!'),
    ]) {
      final field = find.widgetWithText(TextFormField, pair.$1);
      await t.ensureVisible(field);
      await t.enterText(field, pair.$2);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    t.testTextInput.hide();
    await t.pumpAndSettle();
    final consent = find.byType(CheckboxListTile);
    await t.ensureVisible(consent);
    await t.pumpAndSettle();
    await t.tap(
      find
          .descendant(of: consent, matching: find.byType(Checkbox))
          .hitTestable(),
    );
    await t.pumpAndSettle();
    final submit = find.text('Guardar contraseña profesional');
    await t.ensureVisible(submit);
    await t.pumpAndSettle();
    await t.tap(submit.hitTestable());
    await t.pumpAndSettle();
    expect(api.sent.single['path'], '/professional-password');
    expect(api.sent.single.containsKey('token'), isFalse);
    expect(api.modes, ['paciente']);
    expect(api.loggedOut, isTrue);
    expect(
      find.textContaining('Contraseña profesional configurada.'),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
    'paciente es inicial y cambiar modo no registra ni concede un perfil',
    (t) async {
      final api = ModesFake();
      await t.pumpWidget(MaterialApp(home: AccesoPage(api: api)));
      expect(find.text('Acceso de pacientes'), findsOneWidget);
      expect(find.text('Activar invitación profesional'), findsNothing);
      await t.ensureVisible(find.text('Cambiar a modo profesional'));
      await t.tap(find.text('Cambiar a modo profesional'));
      await t.pumpAndSettle();
      expect(find.text('Acceso de profesionales'), findsOneWidget);
      expect(find.text('Crear cuenta de paciente'), findsNothing);
      expect(api.modes, isEmpty);
      await t.enterText(
        find.byType(TextFormField).at(0),
        'persona@example.invalid',
      );
      await t.enterText(find.byType(TextFormField).at(1), 'Clave-actual-2026');
      await t.ensureVisible(find.text('Iniciar sesión'));
      await t.tap(find.text('Iniciar sesión'));
      await t.pumpAndSettle();
      expect(api.modes, ['profesional']);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('activación se abre por ruta independiente sin botón en inicio', (
    t,
  ) async {
    await t.pumpWidget(
      const VitaliaMvpApp(initialRoute: '/activar-invitacion'),
    );
    await t.pumpAndSettle();
    expect(find.byType(ActivarInvitacionPage), findsOneWidget);
    expect(find.text('Código de invitación'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'administración tiene acceso separado sin selector paciente profesional',
    (t) async {
      final api = ModesFake();
      await t.pumpWidget(
        MaterialApp(home: AccesoPage(api: api, adminMode: true)),
      );
      expect(find.text('Acceso de administración'), findsOneWidget);
      expect(find.text('Cambiar a modo profesional'), findsNothing);
      expect(find.text('Crear cuenta de paciente'), findsNothing);
      await t.enterText(
        find.byType(TextFormField).at(0),
        'admin@example.invalid',
      );
      await t.enterText(find.byType(TextFormField).at(1), 'Clave-actual-2026');
      await t.ensureVisible(find.text('Iniciar sesión'));
      await t.tap(find.text('Iniciar sesión'));
      await t.pumpAndSettle();
      expect(api.modes, ['administrador']);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'cuenta existente revalida contraseña actual y crea credencial profesional',
    (t) async {
      final api = ModesFake();
      await t.pumpWidget(MaterialApp(home: ActivarInvitacionPage(api: api)));
      await fillExisting(t);
      expect(api.modes, ['paciente']);
      expect(api.sent.single['path'], '/accept');
      expect(api.sent.single.containsKey('password'), isFalse);
      expect(api.sent.single['currentPassword'], 'Clave-actual-2026');
      expect(api.sent.single['professionalPassword'], 'Otra-profesional-2026!');
      expect(api.sent.single.containsKey('role'), isFalse);
      expect(api.sent.single['confirmed'], true);
      expect(api.loggedOut, isTrue);
      expect(find.textContaining('Invitación aceptada.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'rechazo de otra cuenta no muestra éxito y cierra la sesión temporal',
    (t) async {
      final api = ModesFake()..mismatch = true;
      await t.pumpWidget(MaterialApp(home: ActivarInvitacionPage(api: api)));
      await fillExisting(t);
      expect(
        find.text(
          'La invitación no corresponde a la cuenta con la que ingresaste.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Invitación aceptada.'), findsNothing);
      expect(api.loggedOut, isTrue);
      final field = t.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Contraseña actual'),
      );
      expect(field.controller!.text, isEmpty);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  test('dirección manual usa ruta web sin incluir el código en la URL', () {
    final api = AuthApi();
    final uri = Uri.parse(api.invitationActivationUrl);
    expect(['http', 'https'], contains(uri.scheme));
    expect(uri.fragment, '/activar-invitacion');
    expect(uri.query, isEmpty);
    api.close();
  });
  test(
    'API envía modo de login y aceptación autenticada sin código en query',
    () async {
      final api = AuthApi(
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            expect((jsonDecode(r.body) as Map)['mode'], 'paciente');
            return http.Response(
              jsonEncode({
                'token': 'b' * 64,
                'expiresAt': DateTime.now()
                    .add(const Duration(minutes: 30))
                    .toIso8601String(),
              }),
              200,
            );
          }
          if (r.url.path.endsWith('/me'))
            return http.Response('{"user":{"role":"paciente"}}', 200);
          expect(r.url.path, '/api/onboarding/accept');
          expect(r.url.hasQuery, isFalse);
          expect(r.headers['Authorization'], 'Bearer ${'b' * 64}');
          expect((jsonDecode(r.body) as Map)['token'], 'a' * 64);
          return http.Response('{"accepted":true}', 200);
        }),
      );
      await expectLater(
        api.onboarding('/accept', body: {}),
        throwsA(isA<AuthFailure>()),
      );
      await api.login('persona@example.invalid', 'Clave-actual-2026');
      expect(
        (await api.onboarding(
          '/accept',
          body: {'token': 'a' * 64},
        ))['accepted'],
        true,
      );
      api.close();
    },
  );
}
