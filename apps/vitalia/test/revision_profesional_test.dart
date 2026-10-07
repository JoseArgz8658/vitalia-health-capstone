import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/profesional/revision_panel.dart';
import 'package:vitalia_health/features/profesional/revision_api.dart';
import 'package:vitalia_health/features/documentos_reales/procesamiento_panel.dart';

// Las respuestas JSON reales de Express declaran UTF-8.
http.Response jsonResponse(String body, int status) => http.Response(
  body, status, headers: {'content-type': 'application/json; charset=utf-8'});

const patientId = '22222222-2222-4222-8222-222222222222';
const docId = '33333333-3333-4333-8333-333333333333';
const processingId = '44444444-4444-4444-8444-444444444444';
Map<String, dynamic> extraction() => {'examen': 'Prueba ficticia', 'fecha': '29-09-2026',
  'resultados': [{'nombre': 'Alfa', 'valor': '15,2', 'unidad': ' g/dL', 'rango_referencia': '14,0–16,0 g/dL'}]};
Map<String, dynamic> saved(Map<String, dynamic> data) => {'id': docId, 'processingId': processingId,
  'reviewerEmail': 'r@example.com', 'reviewedAt': '2026-10-01T18:00:00Z',
  'approved': true, 'extraction': data, 'observations': 'Unidad cotejada.'};
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
Widget panel(AuthApi auth, {void Function(AuthFailure)? failure, void Function(bool)? saving}) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16),
    child: RevisionPanel(auth: auth, patientId: patientId, documentId: docId,
      onFailure: failure ?? (_) {}, onSaving: saving ?? (_) {})))));
Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
void main() {
  test('API no envía identidad o aprobación decidida por el cliente', () async {
    final auth = await session((req) async {
      expect(req.url.path, '/api/professional/patients/$patientId/documents/$docId/review');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'processingId', 'extraction', 'observations', 'confirmedOriginal'});
      expect(body['confirmedOriginal'], isTrue);
      return jsonResponse(jsonEncode({'review': saved(body['extraction'] as Map<String, dynamic>)}), 201);
    });
    expect((await RevisionApi(auth).aprobar(patientId, docId, processingId: processingId,
      extraction: extraction(), observations: 'Unidad cotejada.', confirmedOriginal: true))['approved'], isTrue);
    auth.close();
  });
  test('revisión no envía credenciales fuera del origen ni a otra ruta', () async {
    var calls = 0;
    final auth = await session((_) async { calls++; return jsonResponse('{}', 200); });
    await expectLater(auth.sendReviewRequest(http.Request('POST', Uri.parse('https://example.com/api/professional/patients/$patientId/documents/$docId/review'))), throwsA(isA<AuthFailure>()));
    await expectLater(auth.sendReviewRequest(http.Request('POST', auth.professionalUri(patientId, documentId: docId, action: 'file'))), throwsA(isA<AuthFailure>()));
    expect(calls, 0);
    auth.close();
  });
  testWidgets('confirmación habilita aprobación y conserva copia revisada', (tester) async {
    Map<String, dynamic>? review;
    var posts = 0;
    final busy = <bool>[];
    final auth = await session((req) async {
      if (req.method == 'GET') return jsonResponse(jsonEncode({'processingId': processingId,
        'originalExtraction': extraction(), 'canReview': review == null, 'review': review}), 200);
      posts++;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['extraction']['resultados'][0]['unidad'], 'g/dL');
      expect(body['observations'], 'Unidad cotejada.');
      review = saved(body['extraction'] as Map<String, dynamic>);
      return jsonResponse(jsonEncode({'review': review}), 201);
    });
    await tester.pumpWidget(panel(auth, saving: busy.add));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Aprobar y guardar revisión')).onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(4), 'g/dL');
    await tester.enterText(find.byType(TextField).at(6), 'Unidad cotejada.');
    await tap(tester, 'Confirmo que cotejé estos datos con el documento original.');
    await tap(tester, 'Aprobar y guardar revisión');
    expect(posts, 1);
    expect(busy, [true, false]);
    expect(find.text('Revisión aprobada y registrada'), findsOneWidget);
    expect(find.text('Aprobar y guardar revisión'), findsNothing);
    expect(find.text('Unidad: g/dL'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('conflicto exige actualizar y no permite sobrescribir', (tester) async {
    var approved = false;
    final auth = await session((req) async {
      if (req.method == 'POST') { approved = true; return jsonResponse('', 409); }
      return jsonResponse(jsonEncode({'processingId': processingId, 'originalExtraction': extraction(),
        'canReview': !approved, 'review': approved ? saved(extraction()) : null}), 200);
    });
    await tester.pumpWidget(panel(auth));
    await tester.pumpAndSettle();
    await tap(tester, 'Confirmo que cotejé estos datos con el documento original.');
    await tap(tester, 'Aprobar y guardar revisión');
    expect(find.text('Aprobar y guardar revisión'), findsNothing);
    await tap(tester, 'Actualizar revisión');
    expect(find.text('Revisión aprobada y registrada'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('revocación llama al contenedor sin mostrar datos', (tester) async {
    var denied = 0;
    final auth = await session((_) async => jsonResponse('', 404));
    await tester.pumpWidget(panel(auth, failure: (error) { expect(error.status, 404); denied++; }));
    await tester.pumpAndSettle();
    expect(denied, 1);
    expect(find.text('Aprobar y guardar revisión'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('paciente ve estado de revisión sin recibir la extracción', (tester) async {
    final auth = await session((_) async => jsonResponse(jsonEncode({'processing': {'status': 'requires_review',
      'approved': false, 'reviewStatus': 'approved', 'reviewedAt': '2026-10-01T18:00:00Z'}}), 200));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProcesamientoPanel(auth: auth, documentId: docId, onExpired: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('Revisión profesional registrada'), findsOneWidget);
    expect(find.text('Solicitar procesamiento'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
}
