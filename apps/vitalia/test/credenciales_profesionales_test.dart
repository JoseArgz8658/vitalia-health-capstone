import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/equipo/credenciales_profesionales_page.dart';

const clinic = '11111111-1111-4111-8111-111111111111',
    member = '22222222-2222-4222-8222-222222222222',
    requestId = '33333333-3333-4333-8333-333333333333';

class CredentialsFake extends AuthApi {
  bool admin = false, pending = false;
  final sent = <Map<String, dynamic>>[];
  String status = 'pending';
  int revision = 0;
  @override
  Future<Map<String, dynamic>> professionalCredentials(
    String c,
    String m, {
    String? requestId,
    Map<String, dynamic>? body,
  }) async {
    if (body != null) {
      sent.add({
        'clinic': c,
        'member': m,
        'decisionRequest': requestId,
        ...body,
      });
      if (requestId != null) {
        status = body['decision'] as String;
        revision++;
        pending = false;
      } else {
        pending = true;
      }
      return {'recorded': true, 'decided': true};
    }
    return {
      'profile': {
        'status': status,
        'revision': revision,
        'registrationReference': status == 'verified' ? 'REG-SYNTHETIC' : null,
        'verificationRequestId': status == 'verified'
            ? '33333333-3333-4333-8333-333333333333'
            : null,
      },
      'canDecide': admin,
      'requests': pending
          ? [
              {
                'id': '33333333-3333-4333-8333-333333333333',
                'state': 'pending',
                'registrationReference': 'REG-SYNTHETIC',
                'supportingReference': 'Folio sintético',
                'requestedBy': 'jefe@example.invalid',
                'createdAt': '2026-01-01T00:00:00Z',
              },
            ]
          : [],
    };
  }
}

Future<void> open(WidgetTester t, CredentialsFake api) async {
  await t.pumpWidget(
    MaterialApp(
      home: CredencialesProfesionalesPage(
        api: api,
        clinicId: clinic,
        memberId: member,
        professionalName: 'Profesional ficticio',
        onExpired: () {},
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String label) async {
  final finder = find.text(label).last;
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder.hitTestable());
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await t.ensureVisible(field);
  await t.enterText(field, value);
}

Future<void> keyboard(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  t.testTextInput.hide();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('jefe ve solicitudes pero no puede resolverlas', (t) async {
    final api = CredentialsFake()..pending = true;
    await open(t, api);
    expect(find.text('Revisar solicitud'), findsNothing);
    expect(find.text('REG-SYNTHETIC', findRichText: true), findsNothing);
    expect(find.textContaining('Folio sintético'), findsOneWidget);
    expect(api.sent, isEmpty);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('registro de antecedentes no marca verificado ni envía actor', (
    t,
  ) async {
    final api = CredentialsFake();
    await open(t, api);
    await tapText(t, 'Registrar antecedentes');
    await enter(t, 'Referencia de registro profesional', 'REG-SYNTHETIC');
    await enter(t, 'Referencia de antecedentes', 'Folio sintético de pruebas');
    await keyboard(t);
    await tapText(t, 'Guardar antecedentes');
    expect(api.sent.single['clinic'], clinic);
    expect(api.sent.single['member'], member);
    expect(api.sent.single.containsKey('decision'), isFalse);
    expect(api.sent.single.containsKey('actorId'), isFalse);
    expect(api.status, 'pending');
    expect(find.textContaining('Antecedentes registrados.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'administrador debe elegir resultado y confirmar antes de decidir',
    (t) async {
      final api = CredentialsFake()
        ..admin = true
        ..pending = true;
      await open(t, api);
      await tapText(t, 'Revisar solicitud');
      await tapText(t, 'Guardar decisión');
      expect(api.sent, isEmpty);
      expect(find.text('Selecciona un resultado.'), findsOneWidget);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await t.ensureVisible(dropdown);
      await t.pumpAndSettle();
      await t.tap(dropdown);
      await t.pumpAndSettle();
      await t.tap(find.text('Verificado').last);
      await t.pumpAndSettle();
      await enter(t, 'Fuente contrastada', 'Fuente sintética contrastada');
      await enter(
        t,
        'Fundamento de la decisión',
        'Comprobación sintética sin pacientes',
      );
      await keyboard(t);
      await tapText(t, 'Guardar decisión');
      expect(api.sent, isEmpty);
      final consent = find.byType(CheckboxListTile);
      await t.ensureVisible(consent);
      await t.pumpAndSettle();
      await t.tap(
        find
            .descendant(of: consent, matching: find.byType(Checkbox))
            .hitTestable(),
      );
      await t.pumpAndSettle();
      await tapText(t, 'Guardar decisión');
      expect(api.sent.single['confirmed'], true);
      expect(api.sent.single['decision'], 'verified');
      expect(api.sent.single['decisionRequest'], requestId);
      expect(api.sent.single['expectedRevision'], 0);
      expect(api.status, 'verified');
      expect(
        find.textContaining('Decisión guardada con evidencia'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  test('transporte envía sesión y cuerpo a la pertenencia indicada', () async {
    final calls = <http.Request>[];
    final api = AuthApi(
      client: MockClient((r) async {
        if (r.url.path == '/api/auth/login')
          return http.Response(
            jsonEncode({
              'token': 'a' * 64,
              'expiresAt': DateTime.now()
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
            }),
            200,
          );
        if (r.url.path == '/api/auth/me')
          return http.Response(
            '{"user":{"id":"test","role":"administrador"}}',
            200,
          );
        calls.add(r);
        return http.Response('{"recorded":true}', 200);
      }),
    );
    await api.login(
      'admin@example.invalid',
      'Clave-sintetica',
      mode: 'administrador',
    );
    await api.professionalCredentials(
      clinic,
      member,
      body: {'requestId': requestId},
    );
    expect(
      calls.single.url.path,
      '/api/professional-credentials/$clinic/$member/requests',
    );
    expect(calls.single.headers['Authorization'], 'Bearer ${'a' * 64}');
    expect(jsonDecode(calls.single.body)['requestId'], requestId);
    api.close();
  });
  test('sin sesión no consulta verificación profesional', () async {
    int calls = 0;
    final api = AuthApi(
      client: MockClient((r) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.professionalCredentials(clinic, member),
      throwsA(isA<AuthFailure>()),
    );
    expect(calls, 0);
    api.close();
  });
}
