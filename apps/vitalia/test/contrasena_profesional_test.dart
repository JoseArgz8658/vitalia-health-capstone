import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/acceso/acceso_page.dart';
import 'package:vitalia_health/features/perfil/contrasena_profesional_page.dart';

class PasswordFake extends AuthApi {
  bool pending = false;
  int saves = 0;
  String? usedToken;
  @override
  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String mode = 'paciente',
  }) async {
    if (pending) throw ProfessionalPasswordSetupRequired('a' * 64);
    return {'role': mode};
  }

  @override
  Future<void> saveProfessionalPassword({
    required String currentPassword,
    required String password,
    required String confirmation,
    String? setupToken,
  }) async {
    saves++;
    usedToken = setupToken;
  }
}

Future<void> fill(
  WidgetTester t, {
  String next = 'Profesional-nueva-2026!',
}) async {
  for (final pair in [
    ('Contraseña actual', 'Paciente-actual-2026!'),
    ('Nueva contraseña profesional', next),
    ('Confirmar contraseña profesional', next),
  ]) {
    final field = find.widgetWithText(TextFormField, pair.$1);
    await t.ensureVisible(field);
    await t.enterText(field, pair.$2);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  t.testTextInput.hide();
  await t.pumpAndSettle();
}

Future<void> submit(WidgetTester t) async {
  final button = find.text('Guardar contraseña profesional');
  await t.ensureVisible(button);
  await t.pumpAndSettle();
  await t.tap(button.hitTestable());
  await t.pumpAndSettle();
}

void main() {
  test('autorización restringida no guarda sesión ni consulta me', () async {
    final requests = <http.Request>[];
    final api = AuthApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'professionalPasswordSetup': {
              'token': 'a' * 64,
              'expiresAt': DateTime.now()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            },
          }),
          200,
        );
      }),
    );
    await expectLater(
      api.login(
        'persona@example.invalid',
        'Paciente-actual-2026!',
        mode: 'profesional',
      ),
      throwsA(isA<ProfessionalPasswordSetupRequired>()),
    );
    expect(api.hasSession, isFalse);
    expect(requests.length, 1);
    expect(requests.single.url.path, '/api/auth/login');
    api.close();
  });
  test(
    'configuración utiliza autorización exclusiva sin token de sesión',
    () async {
      final api = AuthApi(
        client: MockClient((request) async {
          expect(
            request.url.path,
            '/api/onboarding/professional-password/setup',
          );
          expect(
            request.headers['Authorization'],
            'ProfessionalSetup ${'a' * 64}',
          );
          expect(
            jsonDecode(request.body)['currentPassword'],
            'Paciente-actual-2026!',
          );
          return http.Response('{"configured":true}', 200);
        }),
      );
      await api.saveProfessionalPassword(
        currentPassword: 'Paciente-actual-2026!',
        password: 'Profesional-nueva-2026!',
        confirmation: 'Profesional-nueva-2026!',
        setupToken: 'a' * 64,
      );
      expect(api.hasSession, isFalse);
      api.close();
    },
  );
  testWidgets(
    'inicio profesional pendiente abre solo configuración sin autenticar app',
    (t) async {
      final api = PasswordFake()..pending = true;
      bool authenticated = false;
      await t.pumpWidget(
        MaterialApp(
          home: AccesoPage(
            api: api,
            onAuthenticated: (_) => authenticated = true,
          ),
        ),
      );
      await t.ensureVisible(find.text('Cambiar a modo profesional'));
      await t.tap(find.text('Cambiar a modo profesional'));
      await t.pumpAndSettle();
      expect(
        find.text('Configurar contraseña profesional de mi cuenta de paciente'),
        findsNothing,
      );
      await t.enterText(
        find.byType(TextFormField).first,
        'persona@example.invalid',
      );
      await t.enterText(
        find.byType(TextFormField).at(1),
        'Paciente-actual-2026!',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      t.testTextInput.hide();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Iniciar sesión'));
      await t.tap(find.text('Iniciar sesión').hitTestable());
      await t.pumpAndSettle();
      expect(find.byType(ContrasenaProfesionalPage), findsOneWidget);
      expect(authenticated, isFalse);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'guardar exige confirmación y conserva la autorización restringida',
    (t) async {
      final api = PasswordFake();
      await t.pumpWidget(
        MaterialApp(
          home: ContrasenaProfesionalPage(api: api, setupToken: 'a' * 64),
        ),
      );
      await fill(t);
      await submit(t);
      expect(api.saves, 0);
      final consent = find.byType(CheckboxListTile);
      await t.ensureVisible(consent);
      await t.pumpAndSettle();
      await t.tap(
        find
            .descendant(of: consent, matching: find.byType(Checkbox))
            .hitTestable(),
      );
      await t.pumpAndSettle();
      await submit(t);
      expect(api.saves, 1);
      expect(api.usedToken, 'a' * 64);
      expect(
        find.textContaining('Contraseña profesional guardada.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('nueva contraseña igual a actual no se envía', (t) async {
    final api = PasswordFake();
    await t.pumpWidget(MaterialApp(home: ContrasenaProfesionalPage(api: api)));
    await fill(t, next: 'Paciente-actual-2026!');
    await submit(t);
    expect(api.saves, 0);
    expect(
      find.text('Usa una contraseña diferente a la actual.'),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
    api.close();
  });
}
