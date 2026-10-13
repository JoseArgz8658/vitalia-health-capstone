import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/features/profesional/extraccion_panel.dart';
import 'package:vitalia_health/features/profesional/profesional_api.dart';

void main() {
  for (final status in ['queued', 'processing', 'failed']) {
    testWidgets('consulta distingue estado $status y actividad', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExtraccionPanel(
        value: ExtraccionPendiente(status, null, null, [])))));
      expect(find.byType(LinearProgressIndicator), status == 'failed' ? findsNothing : findsOneWidget);
      if (status != 'failed') {
        expect(find.text('Sin incidencias registradas. Esto no garantiza exactitud.'), findsNothing);
        expect(find.textContaining('Actualizar extracción'), findsOneWidget);
      } else {
        expect(find.text('El procesamiento no se pudo completar'), findsOneWidget);
      }
    });
  }
}
