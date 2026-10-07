import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/profesional/profesional_api.dart';
import 'package:vitalia_health/features/profesional/profesional_documentos_page.dart';
import 'package:vitalia_health/features/asignaciones/asignaciones_page.dart';

// Las respuestas JSON reales de Express declaran UTF-8.
http.Response jsonResponse(String body, int status) => http.Response(
  body, status, headers: {'content-type': 'application/json; charset=utf-8'});

const patientId = '22222222-2222-4222-8222-222222222222';
const docId = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> doc() => {'id': docId, 'examName': 'Examen ficticio', 'examType': 'Laboratorio',
  'examDate': '2026-09-29', 'originalName': 'ficticio.pdf', 'contentType': 'application/pdf', 'sizeBytes': 3};
Map<String, dynamic> processing() => {'status': 'requires_review', 'approved': false,
  'sourceText': 'Texto ficticio original', 'extraction': {'examen': 'Examen ficticio', 'fecha': '29-09-2026',
    'resultados': [{'nombre': 'Alfa', 'valor': '15,2', 'unidad': 'g/dL', 'rango_referencia': '14,0–16,0 g/dL'}]},
  'incidents': {'reading': [], 'ocr': [], 'ai': []}};
Future<AuthApi> session(Future<http.Response> Function(http.Request) work) async {
  final token = List.filled(64, 'a').join();
  final auth = AuthApi(client: MockClient((req) async {
    if (req.url.path.endsWith('/login')) return jsonResponse(jsonEncode({'token': token,
      'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String()}), 200);
    if (req.url.path.endsWith('/me')) return jsonResponse('{"user":{"role":"profesional"}}', 200);
    expect(req.headers['Authorization'], 'Bearer $token');
    return work(req);
  }));
  await auth.login('r@example.com', 'contraseña ficticia');
  return auth;
}
void main() {
  test('API consulta historial, extracción y archivo con sesión', () async {
    final auth = await session((req) async {
      expect(req.method, 'GET');
      if (req.url.path.endsWith('/file')) return http.Response.bytes([1, 2, 3], 200);
      if (req.url.path.endsWith('/extraction')) return jsonResponse(jsonEncode({'processing': processing()}), 200);
      expect(req.url.path, '/api/professional/patients/$patientId/documents');
      expect(req.url.queryParameters, {'limit': '20', 'offset': '20'});
      return jsonResponse(jsonEncode({'documents': [doc()]}), 200);
    });
    final api = ProfesionalApi(auth);
    final item = (await api.listar(patientId, offset: 20)).single;
    expect((await api.consultar(patientId, docId)).extraction!['fecha'], '29-09-2026');
    expect(await api.descargar(patientId, item), [1, 2, 3]);
    auth.close();
  });
  test('no envía token a otro origen ni permite POST', () async {
    var calls = 0;
    final auth = await session((_) async { calls++; return jsonResponse('{}', 200); });
    await expectLater(auth.sendProfessionalRequest(http.Request('GET', Uri.parse('https://example.com/api/professional/patients/$patientId/documents'))), throwsA(isA<AuthFailure>()));
    await expectLater(auth.sendProfessionalRequest(http.Request('POST', auth.professionalUri(patientId))), throwsA(isA<AuthFailure>()));
    expect(() => auth.professionalUri(patientId, documentId: docId, action: 'approve'), throwsA(isA<AuthFailure>()));
    expect(calls, 0);
    auth.close();
  });
  test('rechaza aprobación inesperada y extracción malformada', () async {
    for (final bad in [{...processing(), 'approved': true}, {...processing(), 'extraction': {'resultados': 'bad'}}]) {
      final auth = await session((_) async => jsonResponse(jsonEncode({'processing': bad}), 200));
      await expectLater(ProfesionalApi(auth).consultar(patientId, docId), throwsA(isA<AuthFailure>()));
      auth.close();
    }
  });
  testWidgets('consulta muestra extracción original y revisión profesional separada', (tester) async {
    final auth = await session((req) async => jsonResponse(jsonEncode(
      req.url.path.endsWith('/review')
        ? {'processingId': docId, 'originalExtraction': processing()['extraction'],
            'canReview': true, 'review': null}
        : req.url.path.endsWith('/extraction')
          ? {'processing': processing()} : {'documents': [doc()]}), 200));
    await tester.pumpWidget(MaterialApp(home: ProfesionalDocumentosPage(auth: auth,
      patientId: patientId, patientEmail: 'p@example.com', onExpired: () {}, onBack: () {}, onLogout: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar extracción'));
    await tester.pumpAndSettle();
    expect(find.text('Extracción pendiente de revisión profesional'), findsOneWidget);
    expect(find.text('Valor: 15,2'), findsOneWidget);
    expect(find.text('Texto ficticio original'), findsOneWidget);
    expect(find.text('Aprobar y guardar revisión'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,
      'Aprobar y guardar revisión')).onPressed, isNull);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('revocación oculta historial y extracción al actualizar', (tester) async {
    var active = true;
    final auth = await session((req) async {
      if (!active) return jsonResponse('', 404);
      return jsonResponse(jsonEncode(req.url.path.endsWith('/extraction')
        ? {'processing': processing()} : {'documents': [doc()]}), 200);
    });
    await tester.pumpWidget(MaterialApp(home: ProfesionalDocumentosPage(auth: auth,
      patientId: patientId, patientEmail: 'p@example.com', onExpired: () {}, onBack: () {}, onLogout: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar extracción'));
    await tester.pumpAndSettle();
    active = false;
    await tester.tap(find.text('Actualizar historial'));
    await tester.pumpAndSettle();
    expect(find.text('Valor: 15,2'), findsNothing);
    expect(find.text('Consultar extracción'), findsNothing);
    expect(find.textContaining('Paciente o documento no disponible'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('vencimiento llama al cierre de sesión del contenedor', (tester) async {
    var expired = 0;
    final auth = await session((_) async => jsonResponse('', 401));
    await tester.pumpWidget(MaterialApp(home: ProfesionalDocumentosPage(auth: auth,
      patientId: patientId, patientEmail: 'p@example.com', onExpired: () { expired++; }, onBack: () {}, onLogout: () {})));
    await tester.pumpAndSettle();
    expect(expired, 1);
    expect(auth.hasSession, isFalse);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('lista de asignados abre historial y vuelve sin ruta separada', (tester) async {
    final auth = await session((req) async => jsonResponse(jsonEncode(req.url.path == '/api/assignments'
      ? {'patients': [{'id': patientId, 'email': 'p@example.com'}]}
      : {'documents': [doc()]}), 200));
    await tester.pumpWidget(MaterialApp(home: AsignacionesPage(auth: auth, email: 'r@example.com', role: 'profesional', onExpired: () {}, onLogout: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver exámenes'));
    await tester.pumpAndSettle();
    expect(find.text('Exámenes del paciente'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver a mis pacientes'));
    await tester.pumpAndSettle();
    expect(find.text('Mis pacientes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
}
