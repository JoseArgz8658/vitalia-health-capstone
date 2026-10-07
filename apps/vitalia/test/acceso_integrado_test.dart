import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/app/vitalia_mvp_app.dart';
import 'package:vitalia_health/core/auth_api.dart';

void main() {
  testWidgets('acceso inválido permanece en formulario, sin selector de roles', (tester) async {
    final api = AuthApi(client: MockClient((_) async => http.Response('{}', 401)));
    await tester.pumpWidget(VitaliaMvpApp(api: api));
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Sesión iniciada'), findsNothing);
    await tester.enterText(find.byType(TextFormField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'incorrecta');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    expect(find.text('Sesión iniciada'), findsNothing);
    await tester.tap(find.text('Crear cuenta de paciente'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar contraseña'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
