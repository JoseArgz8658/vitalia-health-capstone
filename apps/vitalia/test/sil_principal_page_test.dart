import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/laboratorio/sil_principal_page.dart';

class _StationApi extends AuthApi {
  static const allowedLab = '11111111-1111-4111-8111-111111111111';
  static const restrictedLab = '22222222-2222-4222-8222-222222222222';
  static const ownOrder = '33333333-3333-4333-8333-333333333333';
  static const otherOrder = '44444444-4444-4444-8444-444444444444';

  @override
  Future<Map<String, dynamic>> silMainRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return switch (Uri.parse(path).path) {
      '/labs' => {
        'laboratories': [
          {
            'id': allowedLab,
            'displayName': 'Laboratorio Norte',
            'canReviewReports': true,
          },
          {
            'id': restrictedLab,
            'displayName': 'Laboratorio Sur',
            'canReviewReports': false,
          },
        ],
      },
      '/labs/$allowedLab/orders' => {
        'orders': [
          {
            'id': ownOrder,
            'orderNumber': 1,
            'status': 'report_attached',
          },
          {
            'id': otherOrder,
            'orderNumber': 2,
            'status': 'report_attached',
          },
        ],
      },
      '/labs/$restrictedLab/orders' => {'orders': []},
      '/labs/$restrictedLab/patients' => {
        'patients': [
          {'id': ownOrder, 'email': 'prueba@example.invalid', 'givenNames': 'Ana', 'familyNames': 'Prueba'},
        ],
        'hasMore': false,
      },
      _ => throw StateError('Ruta inesperada: $path'),
    };
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is InputDecorator && widget.decoration.labelText == label,
);

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('revisión incluye los informes propios del laboratorio a ${width.toInt()} px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _StationApi();
      addTearDown(api.close);

      await tester.pumpWidget(MaterialApp(
        home: SilPrincipalPage(
          api: api,
          role: 'operador_laboratorio',
          onExpired: () {},
          onLogout: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Panel del laboratorio'), findsOneWidget);
      final reviewTab = find.text('Revisión interna (2)');
      await tester.ensureVisible(reviewTab);
      await tester.tap(reviewTab);
      await tester.pumpAndSettle();
      final review = _field('Informe pendiente de revisión');
      expect(review, findsOneWidget);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.ancestor(
          of: review,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items?.map((item) => item.value), [
        _StationApi.ownOrder,
        _StationApi.otherOrder,
      ]);
      final reviewButton = find.widgetWithText(FilledButton, 'Publicar informe');
      expect(tester.widget<FilledButton>(reviewButton).onPressed, isNull);

      final laboratory = _field('Laboratorio');
      await tester.ensureVisible(laboratory);
      await tester.tap(laboratory);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laboratorio Sur').last);
      await tester.pumpAndSettle();
      expect(review, findsNothing);
      expect(reviewButton, findsNothing);
      final patientsTab = find.text('Pacientes');
      await tester.ensureVisible(patientsTab);
      await tester.tap(patientsTab);
      await tester.pumpAndSettle();
      expect(find.text('Directorio de pacientes'), findsOneWidget);
      expect(find.text('Ana Prueba'), findsOneWidget);
      expect(find.text('Emitir código de activación'), findsOneWidget);
      final requests = find.widgetWithText(TextButton, 'Recibir solicitud');
      await tester.ensureVisible(requests);
      await tester.tap(requests);
      await tester.pumpAndSettle();
      expect(find.text('Leer PDF y sugerir datos'), findsOneWidget);
      expect(find.text('Crear orden con solicitud'), findsOneWidget);
      final linkOrder = find.widgetWithText(SwitchListTile, 'Vincular a una orden existente');
      await tester.ensureVisible(linkOrder);
      await tester.tap(linkOrder);
      await tester.pumpAndSettle();
      expect(find.text('Registrar solicitud'), findsOneWidget);
      final clinicalTab = find.widgetWithText(TextButton, 'Muestras y resultados');
      await tester.ensureVisible(clinicalTab);
      await tester.tap(clinicalTab);
      await tester.pumpAndSettle();
      expect(_field('Orden para muestras y resultados'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
