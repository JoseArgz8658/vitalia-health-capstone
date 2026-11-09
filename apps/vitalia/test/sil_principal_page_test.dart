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
            'uploadedByAnotherOperator': false,
          },
          {
            'id': otherOrder,
            'orderNumber': 2,
            'status': 'report_attached',
            'uploadedByAnotherOperator': true,
          },
        ],
      },
      '/labs/$restrictedLab/orders' => {'orders': []},
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
    testWidgets('revisión respeta el laboratorio activo a ${width.toInt()} px', (
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

      final review = _field('Informe pendiente de revisión');
      expect(review, findsOneWidget);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: review,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items?.map((item) => item.value), [_StationApi.otherOrder]);
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
      expect(tester.takeException(), isNull);
    });
  }
}
