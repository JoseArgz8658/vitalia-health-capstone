import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/asignaciones/asignaciones_api.dart';
import 'package:vitalia_health/features/asignaciones/asignaciones_page.dart';
import 'package:vitalia_health/app/vitalia_mvp_app.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> assignment(bool active) => {
  'id': id,
  'patientEmail': 'p@example.com',
  'professionalEmail': 'r@example.com',
  'active': active,
};
AuthApi makeAuth(
  String role,
  Future<http.Response> Function(http.Request) work,
) {
  final token = List.filled(64, 'a').join();
  return AuthApi(
    client: MockClient((req) async {
      if (req.url.path.endsWith('/login'))
        return http.Response(
          jsonEncode({
            'token': token,
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 30))
                .toIso8601String(),
          }),
          200,
        );
      if (req.url.path.endsWith('/me'))
        return http.Response(
          jsonEncode({
            'user': {'id': id, 'email': '$role@example.com', 'role': role},
          }),
          200,
        );
      expect(req.headers['Authorization'], 'Bearer $token');
      return work(req);
    }),
  );
}

Future<AuthApi> session(
  String role,
  Future<http.Response> Function(http.Request) work,
) async {
  final auth = makeAuth(role, work);
  await auth.login('$role@example.com', 'contraseña ficticia');
  return auth;
}

void main() {
  test('API envía solo correos, sesión y paginación', () async {
    var calls = 0;
    final auth = await session('administrador', (req) async {
      calls++;
      if (req.method == 'GET') {
        expect(req.url.path, '/api/assignments');
        expect(req.url.queryParameters, {'limit': '20', 'offset': '20'});
        return http.Response(
          jsonEncode({
            'assignments': [assignment(true)],
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/deactivate')) {
        expect(req.url.path, '/api/assignments/$id/deactivate');
        expect(jsonDecode(req.body), isEmpty);
      } else {
        expect(jsonDecode(req.body), {
          'patientEmail': 'p@example.com',
          'professionalEmail': 'r@example.com',
        });
      }
      return http.Response(jsonEncode({'assignment': assignment(true)}), 200);
    });
    final api = AsignacionesApi(auth);
    expect((await api.listar(offset: 20)).single.active, isTrue);
    await api.asignar(' p@example.com ', 'r@example.com');
    await api.desactivar(id);
    expect(calls, 3);
    auth.close();
  });
  test('no envía token a otro origen ni rutas fuera del contrato', () async {
    var calls = 0;
    final auth = await session('administrador', (_) async {
      calls++;
      return http.Response('{}', 200);
    });
    await expectLater(
      auth.sendAssignmentRequest(
        http.Request('GET', Uri.parse('https://example.com/api/assignments')),
      ),
      throwsA(isA<AuthFailure>()),
    );
    expect(() => auth.assignmentUri('$id/file'), throwsA(isA<AuthFailure>()));
    expect(calls, 0);
    auth.close();
  });
  test('lista profesional exige contrato de pacientes', () async {
    final auth = await session(
      'profesional',
      (_) async => http.Response('{"assignments":[]}', 200),
    );
    await expectLater(
      AsignacionesApi(auth).pacientes(),
      throwsA(isA<AuthFailure>()),
    );
    auth.close();
  });
  testWidgets('administrador asigna, desactiva y reactiva', (tester) async {
    var rows = <Map<String, dynamic>>[];
    var posts = 0;
    final auth = await session('administrador', (req) async {
      if (req.method == 'GET')
        return http.Response(jsonEncode({'assignments': rows}), 200);
      posts++;
      rows = [assignment(!req.url.path.endsWith('/deactivate'))];
      return http.Response(jsonEncode({'assignment': rows.single}), 200);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AsignacionesPage(
          auth: auth,
          email: 'administrador@example.com',
          role: 'administrador',
          onExpired: () {},
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'p@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'r@example.com');
    await tester.tap(find.text('Asignar paciente'));
    await tester.pumpAndSettle();
    expect(find.text('Asignación activa'), findsOneWidget);
    final deactivate = find.text('Desactivar asignación');
    await tester.ensureVisible(deactivate);
    await tester.tap(deactivate);
    await tester.pumpAndSettle();
    expect(find.text('Asignación inactiva'), findsOneWidget);
    final reactivate = find.text('Reactivar asignación');
    await tester.ensureVisible(reactivate);
    await tester.tap(reactivate);
    await tester.pumpAndSettle();
    expect(posts, 3);
    expect(find.text('Asignación activa'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets(
    'profesional no tiene controles administrativos y actualizar elimina revocados',
    (tester) async {
      var assigned = true;
      final auth = await session(
        'profesional',
        (_) async => http.Response(
          jsonEncode({
            'patients': assigned
                ? [
                    {'id': id, 'email': 'p@example.com'},
                  ]
                : [],
          }),
          200,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AsignacionesPage(
            auth: auth,
            email: 'r@example.com',
            role: 'profesional',
            onExpired: () {},
            onLogout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('p@example.com'), findsOneWidget);
      expect(find.text('Asignar paciente'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      assigned = false;
      await tester.tap(find.text('Actualizar lista'));
      await tester.pumpAndSettle();
      expect(find.text('p@example.com'), findsNothing);
      expect(find.textContaining('No tienes pacientes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.close();
    },
  );
  testWidgets('sesión vencida vuelve a acceso mediante callback', (
    tester,
  ) async {
    var expired = 0;
    final auth = await session(
      'profesional',
      (_) async => http.Response('', 401),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AsignacionesPage(
          auth: auth,
          email: 'r@example.com',
          role: 'profesional',
          onExpired: () {
            expired++;
          },
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(expired, 1);
    expect(auth.hasSession, isFalse);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('error de conexión permite actualizar sin excepción', (
    tester,
  ) async {
    final auth = await session(
      'profesional',
      (_) async => throw Exception('sin conexión'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AsignacionesPage(
          auth: auth,
          email: 'r@example.com',
          role: 'profesional',
          onExpired: () {},
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);
    expect(find.text('Actualizar lista'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  for (final role in ['administrador', 'profesional']) {
    testWidgets('acceso de $role conecta su pantalla real', (tester) async {
      final auth = makeAuth(
        role,
        (_) async => http.Response(
          role == 'administrador' ? '{"assignments":[]}' : '{"patients":[]}',
          200,
        ),
      );
      await tester.pumpWidget(
        VitaliaMvpApp(
          api: auth,
          initialRoute: role == 'administrador' ? '/administracion' : '/',
        ),
      );
      await tester.pumpAndSettle();
      if (role == 'profesional') {
        await tester.ensureVisible(find.text('Cambiar a modo profesional'));
        await tester.tap(find.text('Cambiar a modo profesional'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byType(TextFormField).at(0),
        '$role@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'contraseña ficticia',
      );
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          role == 'administrador'
              ? 'Administración de Vitalia Health'
              : 'Mis pacientes',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      auth.close();
    });
  }
  testWidgets('operador entra al laboratorio sin controles administrativos',
      (tester) async {
    final auth = makeAuth('operador_laboratorio', (req) async {
      if (req.url.path.endsWith('/catalog')) {
        return http.Response(
          jsonEncode({
            'exams': [
              {
                'code': 'hemograma',
                'name': 'Hemograma',
                'sampleType': 'sangre_venosa',
                'analytes': []
              }
            ]
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/branches')) {
        return http.Response(
          jsonEncode({
            'branches': [
              {
                'code': 'perez-vitacura',
                'branchName': 'Sucursal Vitacura',
                'commune': 'Vitacura',
                'laboratoryCode': 'perez-demo',
                'laboratoryName': 'Laboratorio Pérez (ficticio)',
              },
            ],
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/summary')) {
        return http.Response(
          '{"summary":{"total":0,"pendingSample":0,"pendingResults":0,"pendingReview":0,"patients":0}}',
          200,
        );
      }
      if (req.url.path.endsWith('/orders')) {
        return http.Response('{"orders":[],"total":0,"limit":20,"offset":0}', 200);
      }
      return http.Response('{}', 404);
    });
    await tester.pumpWidget(
      VitaliaMvpApp(api: auth, initialRoute: '/laboratorio'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Acceso del laboratorio'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0), 'operador_laboratorio@example.com');
    await tester.enterText(
      find.byType(TextFormField).at(1), 'clave de prueba');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Panel del laboratorio'), findsOneWidget);
    expect(find.text('Administración de Vitalia Health'), findsNothing);
    expect(find.text('Registrar orden'), findsOneWidget);
    await tester.ensureVisible(find.text('Ver todas las órdenes'));
    await tester.tap(find.text('Ver todas las órdenes'));
    await tester.pumpAndSettle();
    expect(find.text('Gestión de órdenes'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });

  testWidgets('validador consulta resultados sin controles de operador',
      (tester) async {
    var approved = false;
    final auth = makeAuth('validador_laboratorio', (req) async {
      if (req.url.path == '/api/sil/orders') {
        return http.Response(jsonEncode({
          'orders': approved ? [] : [{
            'id': id,
            'orderNumber': 'VH-000007',
            'patientEmail': 'paciente@example.invalid',
            'status': 'results_recorded',
            'createdAt': '2026-11-08T04:00:00Z',
          }],
          'total': approved ? 0 : 1,
        }), 200);
      }
      if (req.url.path == '/api/sil/orders/$id' && req.method == 'GET') {
        return http.Response(jsonEncode({
          'order': {
            'id': id,
            'orderNumber': 'VH-000007',
            'patientEmail': 'paciente@example.invalid',
            'status': approved ? 'review_approved' : 'results_recorded',
            'createdAt': '2026-11-08T04:00:00Z',
          },
          'exams': [{'name': 'Hemograma'}],
          'results': [{
            'examCode': 'hemograma', 'analyte': 'Hemoglobina',
            'numericValue': 13.2, 'unit': 'g/dL',
            'referenceMin': 12, 'referenceMax': 16,
          }],
          'audit': [],
        }), 200);
      }
      if (req.url.path == '/api/sil/orders/$id/review') {
        expect(req.method, 'POST');
        expect(jsonDecode(req.body)['decision'], 'approve');
        approved = true;
        return http.Response('{"review":{"status":"review_approved"}}', 201);
      }
      return http.Response('{}', 404);
    });
    await tester.pumpWidget(
      VitaliaMvpApp(api: auth, initialRoute: '/validacion'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Acceso de validación'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0), 'validador_laboratorio@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'clave de prueba');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Panel de validación'), findsOneWidget);
    expect(find.text('Registrar orden'), findsNothing);
    await tester.tap(find.textContaining('VH-000007').first);
    await tester.pumpAndSettle();
    expect(find.text('Hemoglobina'), findsOneWidget);
    await tester.ensureVisible(find.text('Aprobar revisión interna'));
    await tester.tap(find.text('Aprobar revisión interna'));
    await tester.pumpAndSettle();
    expect(find.text('Aprobar revisión'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });

  test('API impide rutas arbitrarias del portal SIL', () async {
    var calls = 0;
    final api = await session('paciente', (request) async {
      calls++;
      if (request.url.path == '/api/sil/patient/reports') {
        return http.Response('{"reports":[]}', 200);
      }
      return http.Response('{}', 404);
    });
    final listed = await api.silRequest('/patient/reports');
    expect(listed['reports'], isEmpty);
    await expectLater(
      api.silRequest('/patient/reports?patientId=$id'),
      throwsA(isA<AuthFailure>()),
    );
    expect(calls, 1);
    api.close();
  });

  test('chat educativo paciente usa solo ruta de su informe', () async {
    var calls = 0;
    final api = await session('paciente', (request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/sil/patient/reports/$id/chat');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(jsonDecode(request.body)['question'], '¿Qué es la glicemia?');
      return http.Response(
        '{"response":{"answer":"Explicación educativa del concepto.","approved":false}}',
        200,
      );
    });
    final reply = await api.silRequest('/patient/reports/$id/chat',
        body: {'question': '¿Qué es la glicemia?'});
    expect((reply['response'] as Map)['approved'], isFalse);
    expect(calls, 1);
    await expectLater(
      api.silRequest('/patient/reports/$id/chat?other=1',
          body: {'question': '¿Qué es la glicemia?'}),
      throwsA(isA<AuthFailure>()),
    );
    expect(calls, 1);
    api.close();
  });

  test('API recibe PDF externo mediante POST binario autenticado', () async {
    var called = false;
    final api = await session('operador_laboratorio', (request) async {
      called = true;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/sil/orders/$id/report');
      expect(request.headers['content-type'], 'application/pdf');
      expect(request.headers['x-report-patient-confirmed'], 'true');
      expect(request.headers['x-report-branch-code'], 'perez-vitacura');
      expect(request.headers['x-report-patient-identifier'], 'DEMO-0001');
      expect(request.bodyBytes, isNotEmpty);
      return http.Response('{"report":{"status":"report_attached"}}', 201);
    });
    final result = await api.silUploadReport(
      orderId: id,
      fileName: 'informe.pdf',
      branchCode: 'perez-vitacura',
      authorizedProfessionalName: 'Profesional Ficticio',
      patientIdentifierFromPdf: 'DEMO-0001',
      authorizationReference: 'AUT-TEST-001',
      authorizedAt: DateTime.utc(2026, 11, 1),
      bytes: Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52, 10, 37, 37, 69, 79, 70]),
    );
    expect(called, isTrue);
    expect((result['report'] as Map)['status'], 'report_attached');
    api.close();
  });

}
