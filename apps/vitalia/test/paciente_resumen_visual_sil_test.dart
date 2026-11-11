import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/core/tema_vitalia.dart';
import 'package:vitalia_health/features/laboratorio/resumen_informes_sil_page.dart';

const _id = '00000000-0000-4000-8000-000000000001';

class _ResumenApi extends AuthApi {
  @override
  Future<Map<String, dynamic>> silRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    expect(path, '/patient/reports/overview');
    expect(body?['reportIds'], [_id]);
    return {
      'reports': [
        {
          'orderNumber': 'VH-000001',
          'laboratory': 'Laboratorio ficticio',
          'authorizedAt': '2026-11-08',
          'measurements': [
            {'analyte': 'Glucosa', 'value': 91, 'unit': 'mg/dL'},
          ],
          'observation': 'Control de seguimiento.',
          'reference': 'SOL-DEMO',
        },
      ],
      'statistics': [],
    };
  }
}

final _reports = [
  {
    'id': _id,
    'orderNumber': 'VH-000001',
    'issuingLaboratory': 'Laboratorio ficticio',
    'externallyAuthorizedAt': '2026-11-08',
  },
];

void main() {
  for (final size in [
    const Size(320, 680),
    const Size(1366, 900),
  ]) {
    testWidgets(
      'explorador SIL muestra resultados y derivación sin overflow '
      'en ${size.width.toInt()} px',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: temaVitalia(),
            home: ResumenInformesSilPage(
              api: _ResumenApi(),
              reports: _reports,
              initialReportId: _id,
              onExpired: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Comprende mejor tus exámenes'), findsOneWidget);
        expect(find.text('Elige hasta cuatro informes'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final read = find.text('Leer informes');
        await tester.ensureVisible(read);
        await tester.tap(read);
        await tester.pumpAndSettle();
        expect(find.text('Glucosa · 91 mg/dL'), findsOneWidget);

        final referral = find.text('¿Qué dice la derivación?');
        await tester.ensureVisible(referral);
        await tester.tap(referral);
        await tester.pumpAndSettle();

        expect(find.text('«Control de seguimiento.»'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
