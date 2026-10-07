import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/asignaciones/asignaciones_api.dart';
import 'package:vitalia_health/features/asignaciones/asignaciones_page.dart';
import 'package:vitalia_health/app/vitalia_mvp_app.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> assignment(bool active) => {'id': id, 'patientEmail': 'p@example.com',
  'professionalEmail': 'r@example.com', 'active': active};
AuthApi makeAuth(String role, Future<http.Response> Function(http.Request) work) {
  final token = List.filled(64, 'a').join();
  return AuthApi(client: MockClient((req) async {
    if (req.url.path.endsWith('/login')) return http.Response(jsonEncode({
      'token': token, 'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
    }), 200);
    if (req.url.path.endsWith('/me')) return http.Response(jsonEncode({'user': {'id': id,
      'email': '$role@example.com', 'role': role}}), 200);
    expect(req.headers['Authorization'], 'Bearer $token');
    return work(req);
  }));
}
Future<AuthApi> session(String role, Future<http.Response> Function(http.Request) work) async {
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
        return http.Response(jsonEncode({'assignments': [assignment(true)]}), 200);
      }
      if (req.url.path.endsWith('/deactivate')) {
        expect(req.url.path, '/api/assignments/$id/deactivate');
        expect(jsonDecode(req.body), isEmpty);
      } else {
        expect(jsonDecode(req.body), {'patientEmail': 'p@example.com', 'professionalEmail': 'r@example.com'});
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
    final auth = await session('administrador', (_) async { calls++; return http.Response('{}', 200); });
    await expectLater(auth.sendAssignmentRequest(http.Request('GET', Uri.parse('https://example.com/api/assignments'))), throwsA(isA<AuthFailure>()));
    expect(() => auth.assignmentUri('$id/file'), throwsA(isA<AuthFailure>()));
    expect(calls, 0);
    auth.close();
  });
  test('lista profesional exige contrato de pacientes', () async {
    final auth = await session('profesional', (_) async => http.Response('{"assignments":[]}', 200));
    await expectLater(AsignacionesApi(auth).pacientes(), throwsA(isA<AuthFailure>()));
    auth.close();
  });
  testWidgets('administrador asigna, desactiva y reactiva', (tester) async {
    var rows = <Map<String, dynamic>>[];
    var posts = 0;
    final auth = await session('administrador', (req) async {
      if (req.method == 'GET') return http.Response(jsonEncode({'assignments': rows}), 200);
      posts++;
      rows = [assignment(!req.url.path.endsWith('/deactivate'))];
      return http.Response(jsonEncode({'assignment': rows.single}), 200);
    });
    await tester.pumpWidget(MaterialApp(home: AsignacionesPage(auth: auth,
      email: 'administrador@example.com', role: 'administrador', onExpired: () {}, onLogout: () {})));
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
  testWidgets('profesional no tiene controles administrativos y actualizar elimina revocados', (tester) async {
    var assigned = true;
    final auth = await session('profesional', (_) async => http.Response(jsonEncode({'patients': assigned
      ? [{'id': id, 'email': 'p@example.com'}] : []}), 200));
    await tester.pumpWidget(MaterialApp(home: AsignacionesPage(auth: auth,
      email: 'r@example.com', role: 'profesional', onExpired: () {}, onLogout: () {})));
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
  });
  testWidgets('sesión vencida vuelve a acceso mediante callback', (tester) async {
    var expired = 0;
    final auth = await session('profesional', (_) async => http.Response('', 401));
    await tester.pumpWidget(MaterialApp(home: AsignacionesPage(auth: auth,
      email: 'r@example.com', role: 'profesional', onExpired: () { expired++; }, onLogout: () {})));
    await tester.pumpAndSettle();
    expect(expired, 1);
    expect(auth.hasSession, isFalse);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('error de conexión permite actualizar sin excepción', (tester) async {
    final auth = await session('profesional', (_) async => throw Exception('sin conexión'));
    await tester.pumpWidget(MaterialApp(home: AsignacionesPage(auth: auth,
      email: 'r@example.com', role: 'profesional', onExpired: () {}, onLogout: () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);
    expect(find.text('Actualizar lista'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  for (final role in ['administrador', 'profesional']) {
    testWidgets('acceso de $role conecta su pantalla real', (tester) async {
      final auth = makeAuth(role, (_) async => http.Response(role == 'administrador'
        ? '{"assignments":[]}' : '{"patients":[]}', 200));
      await tester.pumpWidget(VitaliaMvpApp(api: auth));
      await tester.enterText(find.byType(TextFormField).at(0), '$role@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'contraseña ficticia');
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text(role == 'administrador' ? 'Asignaciones de pacientes' : 'Mis pacientes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.close();
    });
  }
}
