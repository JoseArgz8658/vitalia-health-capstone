import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/tema_vitalia.dart';
import 'package:vitalia_health/features/laboratorio/portal_ayuda_sil.dart';

void main() {
  final reports = <Map<String, dynamic>>[
    {
      'issuingLaboratory': 'Laboratorio Pérez (ficticio)',
      'orderNumber': 'VH-000011',
    },
  ];

  for (final size in [
    const Size(320, 680),
    const Size(1366, 900),
  ]) {
    testWidgets(
      'ayuda SIL permite contactar y consultar FAQ en '
      '${size.width.toInt()} px sin exponer canales inventados',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: temaVitalia(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: PortalAyudaFooterSil(
                  reports: reports,
                  onProfile: () {},
                  onRecovery: () {},
                  onReports: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('¿Necesitas ayuda con tus informes?'),
            findsOneWidget);

        final contact = find.text('Contacto del laboratorio').first;
        await tester.ensureVisible(contact);
        await tester.tap(contact);
        await tester.pumpAndSettle();

        expect(find.text('Contacto con tu laboratorio'), findsOneWidget);
        expect(find.text('Laboratorio Pérez (ficticio)'), findsOneWidget);
        expect(
          find.textContaining(
            'aún no hay teléfono, dirección, correo institucional'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Entendido'));
        await tester.pumpAndSettle();

        final faq = find.text('Preguntas frecuentes').first;
        await tester.ensureVisible(faq);
        await tester.tap(faq);
        await tester.pumpAndSettle();
        expect(find.text('¿Qué informes puedo consultar?'), findsOneWidget);

        await tester.tap(find.text('Entendido'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
