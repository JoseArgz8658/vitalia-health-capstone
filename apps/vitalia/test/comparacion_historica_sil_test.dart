import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/features/laboratorio/comparacion_historica_sil.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/laboratorio/resumen_informes_sil_page.dart';

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


const _firstReportId = '00000000-0000-4000-8000-000000000001';
const _secondReportId = '00000000-0000-4000-8000-000000000002';

class _HistoryOverviewApi extends AuthApi {
  @override
  Future<Map<String, dynamic>> silRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    expect(path, '/patient/reports/overview');
    expect(body?['reportIds'], [_firstReportId, _secondReportId]);
    return {
      'reports': [],
      'statistics': [
        {
          'analyte': 'Glucosa',
          'unit': 'mg/dL',
          'laboratory': 'Laboratorio ficticio',
          'count': 2,
          'minimum': 91,
          'mean': 92,
          'maximum': 93,
          'measurements': [
            {
              'authorizedAt': '2026-11-02',
              'orderNumber': 'VH-000001',
              'value': 91,
            },
            {
              'authorizedAt': '2026-11-08',
              'orderNumber': 'VH-000002',
              'value': 93,
            },
          ],
        },
      ],
    };
  }
}

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
  testWidgets('el explorador integra la comparación visual al elegir dos PDF',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: ResumenInformesSilPage(
        api: _HistoryOverviewApi(),
        reports: [
          {
            'id': _firstReportId,
            'orderNumber': 'VH-000001',
            'issuingLaboratory': 'Laboratorio ficticio',
            'externallyAuthorizedAt': '2026-11-02',
          },
          {
            'id': _secondReportId,
            'orderNumber': 'VH-000002',
            'issuingLaboratory': 'Laboratorio ficticio',
            'externallyAuthorizedAt': '2026-11-08',
          },
        ],
        onExpired: () {},
      ),
    ));
    await tester.pumpAndSettle();
    for (final title in [
      'VH-000001 · Laboratorio ficticio',
      'VH-000002 · Laboratorio ficticio',
    ]) {
      final report = find.text(title);
      await tester.ensureVisible(report);
      await tester.tap(report);
      await tester.pumpAndSettle();
    }
    expect(find.text('2 seleccionados'), findsOneWidget);
    final read = find.text('Leer informes');
    await tester.ensureVisible(read);
    await tester.tap(read);
    await tester.pumpAndSettle();
    final compare = find.text('¿Cómo se comparan?');
    await tester.ensureVisible(compare);
    await tester.tap(compare);
    await tester.pumpAndSettle();

    expect(find.text('Evolución visual por fecha'), findsOneWidget);
    expect(find.byKey(const Key('sil-comparacion-historica-grafico')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
