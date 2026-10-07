import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/documentos_reales/revision_paciente_panel.dart';

const id = '33333333-3333-4333-8333-333333333333';
http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value), status, headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> review() => {'approved': true, 'reviewedAt': '2026-10-01T18:00:00Z',
  'observations': 'Cifra cotejada – prueba.', 'extraction': {'examen': 'Perfil ficticio',
    'fecha': '29-09-2026', 'resultados': [{'nombre': 'Alfa', 'valor': '0,00',
      'unidad': null, 'rango_referencia': null}]}};
Future<AuthApi> session(Future<http.Response> Function(http.Request) work) async {
  final auth = AuthApi(client: MockClient((req) async {
    if (req.url.path.endsWith('/login')) return jsonResponse({'token': 'a' * 64,
      'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String()});
    if (req.url.path.endsWith('/me')) return jsonResponse({'user': {'role': 'paciente'}});
    expect(req.headers['Authorization'], 'Bearer ${'a' * 64}');
    return work(req);
  }));
  await auth.login('p@example.com', 'clave ficticia');
  return auth;
}
Widget panel(AuthApi auth, {VoidCallback? onExpired}) => MaterialApp(home: Scaffold(
  body: SingleChildScrollView(child: RevisionPacientePanel(auth: auth,
    documentId: id, onExpired: onExpired ?? () {}))));
Future<void> consultar(WidgetTester tester) async {
  final finder = find.text('Ver resultados revisados');
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
void main() {
  test('consulta GET con sesión; no envía token fuera de origen ni permite aprobar', () async {
    var calls = 0;
    final auth = await session((req) async {
      calls++; expect(req.method, 'GET'); expect(req.url.path, '/api/documents/$id/review');
      return jsonResponse({'review': review()});
    });
    await auth.sendDocumentRequest(http.Request('GET', auth.documentUri('$id/review')));
    await expectLater(auth.sendDocumentRequest(http.Request('POST', auth.documentUri('$id/review'))), throwsA(isA<AuthFailure>()));
    await expectLater(auth.sendDocumentRequest(http.Request('GET', Uri.parse('https://example.com/api/documents/$id/review'))), throwsA(isA<AuthFailure>()));
    expect(calls, 1); auth.close();
  });
  testWidgets('muestra copia humana, cero, ausencias y observaciones sin edición', (tester) async {
    final auth = await session((_) async => jsonResponse({'review': review()}));
    await tester.pumpWidget(panel(auth)); await consultar(tester);
    expect(find.text('Resultados revisados por un profesional'), findsOneWidget);
    expect(find.text('Valor: 0,00'), findsOneWidget);
    expect(find.text('Unidad: No disponible'), findsOneWidget);
    expect(find.text('Cifra cotejada – prueba.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.binding.setSurfaceSize(const Size(360, 800)); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null); await tester.pumpWidget(const SizedBox()); auth.close();
  });
  testWidgets('sin aprobación muestra espera y no resultados', (tester) async {
    final auth = await session((_) async => jsonResponse({'review': null}));
    await tester.pumpWidget(panel(auth)); await consultar(tester);
    expect(find.text('Todavía no hay una revisión aprobada para este documento.'), findsOneWidget);
    expect(find.text('Resultados revisados por un profesional'), findsNothing);
    await tester.pumpWidget(const SizedBox()); auth.close();
  });
  testWidgets('error de acceso retira la copia de la consulta anterior', (tester) async {
    var active = true;
    final auth = await session((_) async => active ? jsonResponse({'review': review()}) : jsonResponse({}, 404));
    await tester.pumpWidget(panel(auth)); await consultar(tester);
    active = false; await consultar(tester);
    expect(find.text('Valor: 0,00'), findsNothing);
    expect(find.text('Documento no disponible.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); auth.close();
  });
  testWidgets('401 cierra sesión y no muestra revisión', (tester) async {
    var expired = 0;
    final auth = await session((_) async => jsonResponse({}, 401));
    await tester.pumpWidget(panel(auth, onExpired: () { expired++; })); await consultar(tester);
    expect(expired, 1); expect(auth.hasSession, isFalse);
    expect(find.text('Valor: 0,00'), findsNothing);
    await tester.pumpWidget(const SizedBox()); auth.close();
  });
  testWidgets('respuesta sin aprobación se rechaza aunque incluya datos', (tester) async {
    final auth = await session((_) async => jsonResponse({'review': {...review(), 'approved': false}}));
    await tester.pumpWidget(panel(auth)); await consultar(tester);
    expect(find.text('No se pudo consultar la revisión aprobada.'), findsOneWidget);
    expect(find.text('Valor: 0,00'), findsNothing);
    await tester.pumpWidget(const SizedBox()); auth.close();
  });
}
