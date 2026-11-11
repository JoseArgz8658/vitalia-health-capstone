import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/app/vitalia_demo_app.dart';

void main() {
  testWidgets('Portal abre registro de documentos y permite volver', (tester) async {
    await tester.pumpWidget(const VitaliaDemoApp());
    final boton = find.text('Explorar paciente');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(find.text('Exámenes con archivo asociado'), findsOneWidget);
    expect(find.text('Seleccionar archivo y registrar'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Tus exámenes, en un solo lugar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Portal estrecho abre administración sin desbordes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const VitaliaDemoApp());
    final boton = find.text('Explorar administrador');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(find.text('Administración'), findsOneWidget);
    expect(find.text('Paciente demo 001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
