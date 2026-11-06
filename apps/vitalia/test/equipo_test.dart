import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/equipo/equipo_page.dart';

const clinic = '22222222-2222-4222-8222-222222222222';
const member = '33333333-3333-4333-8333-333333333333';

class TeamFake extends AuthApi {
  bool failOnce = false;
  final sent = <Map<String, dynamic>>[];
  final row = <String, dynamic>{
    'id': member,
    'clinicId': clinic,
    'firstName': 'Persona',
    'firstSurname': 'Ficticia',
    'email': 'persona@example.invalid',
    'clinicalRole': 'profesional',
    'active': true,
    'revision': 0,
    'branches': <dynamic>[],
    'specialties': <dynamic>[],
  };
  @override
  Future<Map<String, dynamic>> team(
    String clinicId, {
    String? memberId,
    bool history = false,
    int offset = 0,
    Map<String, dynamic>? update,
  }) async {
    if (history)
      return {
        'items': [
          {
            'createdAt': '2026-10-29T12:00:00Z',
            'actorEmail': 'jefe@example.invalid',
            'reason': 'Cambio sintético registrado',
            'beforeState': {
              'active': true,
              'branchIds': [],
              'specialtyIds': [],
            },
            'afterState': {
              'active': false,
              'branchIds': [],
              'specialtyIds': [],
            },
          },
        ],
      };
    if (update != null) {
      sent.add(Map.from(update));
      if (failOnce) {
        failOnce = false;
        throw const AuthFailure('Tiempo agotado.');
      }
      row['active'] = update['active'];
      row['revision'] = (row['revision'] as int) + 1;
      return {'updated': true, 'replayed': false};
    }
    return {
      'members': [Map.from(row)],
      'branches': <dynamic>[],
      'specialties': <dynamic>[],
    };
  }
}

Future<void> showTeam(
  WidgetTester t,
  TeamFake api, {
  bool admin = false,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: EquipoPage(
        api: api,
        clinicId: clinic,
        clinicName: 'Clínica ficticia',
        admin: admin,
        onExpired: () {},
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> openEdit(WidgetTester t) async {
  await t.ensureVisible(find.text('Editar pertenencia'));
  await t.tap(find.text('Editar pertenencia'));
  await t.pumpAndSettle();
}

Future<void> suspend(WidgetTester t) async {
  await t.ensureVisible(find.byType(SwitchListTile));
  await t.tap(find.byType(SwitchListTile));
  await t.pumpAndSettle();
}

Future<void> save(WidgetTester t) async {
  await t.ensureVisible(find.text('Guardar cambios'));
  await t.tap(find.text('Guardar cambios'));
  await t.pumpAndSettle();
}

AuthApi connectedApi(Future<http.Response> Function(http.Request) respond) =>
    AuthApi(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login'))
          return http.Response(
            jsonEncode({
              'token': 'a' * 64,
              'expiresAt': DateTime.now()
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
            }),
            200,
          );
        if (r.url.path.endsWith('/me'))
          return http.Response('{"user":{"role":"profesional"}}', 200);
        return respond(r);
      }),
    );
void main() {
  testWidgets(
    'administrador consulta sin editar y las jefaturas tampoco se editan',
    (t) async {
      final api = TeamFake();
      await showTeam(t, api, admin: true);
      expect(find.text('Editar pertenencia'), findsNothing);
      expect(find.textContaining('Consulta administrativa.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      api.row['clinicalRole'] = 'jefe_clinico';
      await showTeam(t, api);
      expect(find.text('Editar pertenencia'), findsNothing);
      expect(api.sent, isEmpty);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('cancelar conserva estado y no envía cambios', (t) async {
    final api = TeamFake();
    await showTeam(t, api);
    await openEdit(t);
    await suspend(t);
    await t.ensureVisible(find.text('Cancelar'));
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(api.sent, isEmpty);
    expect(api.row['active'], isTrue);
    expect(find.byType(TextFormField), findsNothing);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'suspender exige motivo y luego guarda versión sin rol ni identidad',
    (t) async {
      final api = TeamFake();
      await showTeam(t, api);
      await openEdit(t);
      await suspend(t);
      await save(t);
      expect(api.sent, isEmpty);
      expect(
        find.text('Explica el motivo con al menos 5 caracteres.'),
        findsOneWidget,
      );
      await t.enterText(
        find.byType(TextFormField),
        'Suspensión temporal de prueba',
      );
      await save(t);
      expect(api.row['active'], isFalse);
      expect(api.sent.single['expectedRevision'], 0);
      expect(api.sent.single.containsKey('actorId'), isFalse);
      expect(api.sent.single.containsKey('clinicalRole'), isFalse);
      expect(find.text('Pertenencia: Suspendida'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('reintento tras fallo conserva identificador y formulario', (
    t,
  ) async {
    final api = TeamFake()..failOnce = true;
    await showTeam(t, api);
    await openEdit(t);
    await suspend(t);
    await t.enterText(
      find.byType(TextFormField),
      'Suspensión temporal de prueba',
    );
    await save(t);
    expect(find.text('Tiempo agotado.'), findsOneWidget);
    await save(t);
    expect(api.sent.length, 2);
    expect(api.sent[0]['requestId'], api.sent[1]['requestId']);
    expect(api.sent[0]['expectedRevision'], api.sent[1]['expectedRevision']);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('historial muestra autor, motivo y estados sin abrir diálogo', (
    t,
  ) async {
    final api = TeamFake();
    await showTeam(t, api);
    await t.ensureVisible(find.text('Ver historial'));
    await t.tap(find.text('Ver historial'));
    await t.pumpAndSettle();
    expect(find.text('Motivo: Cambio sintético registrado'), findsOneWidget);
    expect(find.textContaining('jefe@example.invalid'), findsOneWidget);
    expect(find.text('Antes: Activa'), findsOneWidget);
    expect(find.text('Después: Suspendida'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  test('API exige sesión y valida identificadores antes de enviar', () async {
    var sent = false;
    final api = AuthApi(
      client: MockClient((r) async {
        sent = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(api.team(clinic), throwsA(isA<AuthFailure>()));
    await expectLater(
      api.team('https://otro.example'),
      throwsA(isA<AuthFailure>()),
    );
    expect(sent, isFalse);
    api.close();
  });
  test(
    'API separa listado e historial paginados de escritura sin query',
    () async {
      var count = 0;
      final api = connectedApi((r) async {
        expect(r.headers['Authorization'], 'Bearer ${'a' * 64}');
        count++;
        if (r.method == 'GET') {
          expect(r.url.queryParameters, {'limit': '20', 'offset': '20'});
          expect(
            r.url.path,
            count == 1
                ? '/api/team/$clinic'
                : '/api/team/$clinic/$member/history',
          );
          return http.Response(
            count == 1
                ? '{"members":[],"branches":[],"specialties":[]}'
                : '{"items":[]}',
            200,
          );
        }
        expect(r.url.path, '/api/team/$clinic/$member');
        expect(r.url.hasQuery, isFalse);
        expect((jsonDecode(r.body) as Map)['expectedRevision'], 0);
        return http.Response('{"updated":true}', 200);
      });
      await api.login('jefe@example.invalid', 'prueba');
      await api.team(clinic, offset: 20);
      await api.team(clinic, memberId: member, history: true, offset: 20);
      await api.team(clinic, memberId: member, update: {'expectedRevision': 0});
      expect(count, 3);
      api.close();
    },
  );
  test('sesión vencida se borra ante rechazo del servidor', () async {
    final api = connectedApi(
      (_) async => http.Response('{"error":{"code":"UNAUTHORIZED"}}', 401),
    );
    await api.login('jefe@example.invalid', 'prueba');
    await expectLater(
      api.team(clinic),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 401)),
    );
    expect(api.hasSession, isFalse);
    api.close();
  });
}
