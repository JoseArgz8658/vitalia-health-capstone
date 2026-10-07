import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/documentos_reales/procesamiento_api.dart';
import 'package:vitalia_health/features/documentos_reales/procesamiento_panel.dart';

const id = '22222222-2222-4222-8222-222222222222';
Future<AuthApi> session(Future<http.Response> Function(http.Request) work) async {
  final token = List.filled(64, 'a').join();
  final auth = AuthApi(client: MockClient((req) async {
    if (req.url.path.endsWith('/login')) return http.Response(jsonEncode({
      'token': token,
      'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
    }), 200);
    if (req.url.path.endsWith('/me')) return http.Response(
      '{"user":{"id":"11111111-1111-4111-8111-111111111111","role":"paciente"}}', 200);
    expect(req.headers['Authorization'], 'Bearer $token');
    expect(req.url.path, '/api/documents/$id/processing');
    return work(req);
  }));
  await auth.login('ficticio@example.com', 'contraseña ficticia');
  return auth;
}
http.Response state(String status, {bool approved = false}) => http.Response(
  jsonEncode({'processing': {'status': status, 'approved': approved}}), 200);
void main() {
  test('consulta y solicitud usan la sesión sin propietario ni modelo', () async {
    final methods = <String>[];
    final auth = await session((req) async {
      methods.add(req.method);
      if (req.method == 'POST') expect(jsonDecode(req.body), isEmpty);
      return state(req.method == 'POST' ? 'queued' : 'not_requested');
    });
    final api = ProcesamientoApi(auth);
    expect(await api.consultar(id), 'not_requested');
    expect(await api.solicitar(id), 'queued');
    expect(methods, ['GET', 'POST']);
    auth.close();
  });
  test('estado desconocido o aprobación inesperada se rechazan', () async {
    for (final response in [state('inventado'), state('requires_review', approved: true)]) {
      final auth = await session((_) async => response);
      await expectLater(ProcesamientoApi(auth).consultar(id), throwsA(isA<AuthFailure>()));
      auth.close();
    }
  });
  test('rutas ajenas no reciben token', () async {
    final auth = await session((_) async => throw StateError('No debe enviar'));
    expect(() => auth.documentUri('$id/result'), throwsA(isA<AuthFailure>()));
    auth.close();
  });
  testWidgets('solicita una vez y luego muestra pendiente sin botón de solicitud', (tester) async {
    var current = 'not_requested';
    var posts = 0;
    final auth = await session((req) async {
      if (req.method == 'POST') { posts++; current = 'queued'; }
      return state(current);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProcesamientoPanel(
      auth: auth, documentId: id, onExpired: () {},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitar procesamiento'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.text('Procesamiento pendiente'), findsOneWidget);
    expect(find.text('Solicitar procesamiento'), findsNothing);
    current = 'requires_review';
    await tester.tap(find.text('Actualizar estado'));
    await tester.pumpAndSettle();
    expect(find.text('Extracción pendiente de revisión profesional'), findsOneWidget);
    expect(find.text('Los datos extraídos aún no están aprobados.'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('sesión vencida avisa a la pantalla y elimina token', (tester) async {
    var expired = 0;
    final auth = await session((_) async => http.Response('', 401));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProcesamientoPanel(
      auth: auth, documentId: id, onExpired: () { expired++; },
    ))));
    await tester.pumpAndSettle();
    expect(expired, 1);
    expect(auth.hasSession, isFalse);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('error de conexión no habilita solicitud incierta', (tester) async {
    final auth = await session((_) async => throw Exception('sin conexión'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProcesamientoPanel(
      auth: auth, documentId: id, onExpired: () {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Solicitar procesamiento'), findsNothing);
    expect(find.text('Actualizar estado'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
}
