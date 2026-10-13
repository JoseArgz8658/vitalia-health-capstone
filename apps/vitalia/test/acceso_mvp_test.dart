import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/app/vitalia_mvp_app.dart';

void main() {
  testWidgets('Arranque no permite elegir roles ni explorar demo', (tester) async {
    await tester.pumpWidget(const VitaliaMvpApp());
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Explorar demostración'), findsNothing);
    expect(find.text('Explorar paciente'), findsNothing);
    expect(find.text('Explorar profesional'), findsNothing);
    expect(find.text('Explorar administrador'), findsNothing);
  });
  testWidgets('Credenciales rechazadas no crean sesión ni navegan', (tester) async {
    final paths = <String>[];
    final api = AuthApi(client: MockClient((request) async {
      paths.add(request.url.path);
      return http.Response('{}', 401);
    }));
    await tester.pumpWidget(VitaliaMvpApp(api: api));
    await tester.enterText(find.byType(TextFormField).at(0), 'demo@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-ficticia');
    final boton = find.text('Iniciar sesión');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    expect(paths, ['/api/auth/login']);
    expect(api.hasSession, isFalse);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Panel profesional'), findsNothing);
    final campo = tester.widget<TextFormField>(find.byType(TextFormField).at(1));
    expect(campo.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}

