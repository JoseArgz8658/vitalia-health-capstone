import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets('Validar datos ficticios no crea sesión ni navega', (tester) async {
    await tester.pumpWidget(const VitaliaMvpApp());
    await tester.enterText(find.byType(TextFormField).at(0), 'demo@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-ficticia');
    final boton = find.text('Validar formulario de acceso');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(find.textContaining('No se ha iniciado una sesión.'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Panel profesional'), findsNothing);
    final campo = tester.widget<TextFormField>(find.byType(TextFormField).at(1));
    expect(campo.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
