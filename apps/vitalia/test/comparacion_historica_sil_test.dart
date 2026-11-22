import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/features/laboratorio/comparacion_historica_sil.dart';

Widget _screen(List<Map> measurements) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ComparacionHistoricaSil(
            analyte: 'Glucosa',
            unit: 'mg/dL',
            measurements: measurements,
          ),
        ),
      ),
    );

void main() {
  testWidgets('grafica cronológicamente mediciones compatibles en móvil',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 680);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_screen([
      {
        'authorizedAt': '2026-11-08',
        'orderNumber': 'VH-000002',
        'value': 93,
      },
      {
        'authorizedAt': '2026-11-02',
        'orderNumber': 'VH-000001',
        'value': 91,
      },
    ]));
    expect(find.text('Evolución visual por fecha'), findsOneWidget);
    expect(
      find.byKey(const Key('sil-comparacion-historica-grafico')),
      findsOneWidget,
    );
    expect(find.text('2/11/2026'), findsOneWidget);
    expect(find.text('8/11/2026'), findsOneWidget);
    expect(find.textContaining('no son límites clínicos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dos mediciones en la misma fecha no simulan intervalo temporal',
      (tester) async {
    await tester.pumpWidget(_screen([
      {
        'authorizedAt': '2026-11-08',
        'orderNumber': 'VH-000001',
        'value': 91,
      },
      {
        'authorizedAt': '2026-11-08',
        'orderNumber': 'VH-000002',
        'value': 91,
      },
    ]));
    expect(find.textContaining('Las fechas coinciden'), findsOneWidget);
    expect(
      find.byKey(const Key('sil-comparacion-historica-grafico')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no grafica mediciones con fecha o valor inválido',
      (tester) async {
    await tester.pumpWidget(_screen([
      {
        'authorizedAt': '2026-11-08',
        'orderNumber': 'VH-000001',
        'value': 91,
      },
      {
        'authorizedAt': 'fecha incorrecta',
        'orderNumber': 'VH-000002',
        'value': 92,
      },
    ]));
    expect(find.textContaining('No hay suficientes mediciones'), findsOneWidget);
    expect(find.byKey(const Key('sil-comparacion-historica-grafico')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
