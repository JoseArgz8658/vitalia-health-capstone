import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/app/vitalia_mvp_app.dart';

final token = List.filled(64, 'a').join();
void main() {
  testWidgets('paciente autenticado ve historial real vacío y formulario de carga', (tester) async {
    final auth = AuthApi(client: MockClient((req) async {
      if (req.url.path.endsWith('/login')) return http.Response(jsonEncode({
        'token': token, 'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String()}), 200);
      if (req.url.path.endsWith('/me')) return http.Response(
        '{"user":{"id":"11111111-1111-4111-8111-111111111111","email":"test@example.com","role":"paciente"}}', 200);
      if (req.url.path == '/api/documents') return http.Response('{"documents":[]}', 200);
      return http.Response('', 204);
    }));
    await tester.pumpWidget(VitaliaMvpApp(api: auth));
    await tester.enterText(find.byType(TextFormField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'contraseña ficticia');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Mis exámenes'), findsOneWidget);
    expect(find.textContaining('No hay exámenes'), findsOneWidget);
    await tester.tap(find.text('Subir examen'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar examen'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
    await tester.pumpAndSettle();
    final volverAlHistorial = find.text('Volver al historial');
    await tester.ensureVisible(volverAlHistorial);
    await tester.pumpAndSettle();
    await tester.tap(volverAlHistorial);
    await tester.pumpAndSettle();
    expect(find.text('Mis exámenes'), findsOneWidget);
    expect(find.text('Guardar examen'), findsNothing);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Mis exámenes'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    auth.close();
  });
}
