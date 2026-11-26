import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/tema_vitalia.dart';
import 'package:vitalia_health/features/laboratorio/sil_record_picker.dart';

double contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  test('contraste de texto, bordes de formulario y foco de Vitalia', () {
    final theme = temaVitalia();
    final input = theme.inputDecorationTheme;
    final field = input.enabledBorder as OutlineInputBorder;
    final focused = input.focusedBorder as OutlineInputBorder;
    final keyboard = theme.textButtonTheme.style!.side!.resolve({
      WidgetState.focused,
    })!;
    expect(contrast(ColoresVitalia.textoSecundario, ColoresVitalia.blanco),
        greaterThanOrEqualTo(4.5));
    expect(contrast(theme.colorScheme.error, ColoresVitalia.errorSuave),
        greaterThanOrEqualTo(4.5));
    expect(contrast(field.borderSide.color, input.fillColor!),
        greaterThanOrEqualTo(3));
    expect(contrast(focused.borderSide.color, input.fillColor!),
        greaterThanOrEqualTo(3));
    expect(contrast(keyboard.color, ColoresVitalia.fondoAzul),
        greaterThanOrEqualTo(3));
    expect(keyboard.width, greaterThanOrEqualTo(2));
  });

  testWidgets('selector legible a 320 px y texto al 200 %', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? chosen;
    await tester.pumpWidget(MaterialApp(
      theme: temaVitalia(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: SilRecordPicker(
          label: 'Buscar orden',
          searchLabel: 'Buscar por folio, paciente o sede',
          options: const [
            (id: '1', title: 'VH-000101', detail: 'Casa matriz · Ana Prueba'),
            (id: '2', title: 'VH-000102', detail: 'Sede Sur · Bruno Prueba'),
          ],
          selectedId: null,
          onSelected: (id) => chosen = id,
        ),
      ),
    ));
    await tester.tap(find.text('Buscar orden'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).decoration!.labelText,
        'Buscar por folio, paciente o sede');
    await tester.enterText(field, 'Bruno sur');
    await tester.pumpAndSettle();
    final count = find.text('Resultados 1 a 1 de 1');
    expect(count, findsOneWidget);
    expect(
        find.ancestor(
          of: count,
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true),
        ),
        findsWidgets);
    expect(find.text('VH-000101'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen, '2');
    expect(tester.takeException(), isNull);
  });
}
