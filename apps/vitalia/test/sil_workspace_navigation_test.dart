import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/features/laboratorio/sil_workspace.dart';

const _labels = [
  'Resumen',
  'Órdenes',
  'Recibir solicitud',
  'Pacientes',
  'Muestras y resultados',
  'Revisión interna',
];

Widget _navigation(ValueNotifier<int> selected) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, active, _) => SilWorkspaceTopNavigation(
            label: 'Navegación del operador',
            tabs: [
              for (var i = 0; i < _labels.length; i++)
                SilWorkspaceTab(
                  label: _labels[i],
                  icon: Icons.dashboard_outlined,
                  selected: active == i,
                  onPressed: () => selected.value = i,
                ),
            ],
          ),
        ),
        const Expanded(child: Center(child: Text('Contenido de estación'))),
      ],
    ),
  ),
);

void main() {
  testWidgets('en escritorio muestra las secciones sin flechas innecesarias',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = ValueNotifier<int>(0);
    addTearDown(selected.dispose);

    await tester.pumpWidget(_navigation(selected));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Mostrar más secciones'), findsNothing);
    expect(find.byTooltip('Mostrar secciones anteriores'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Recibir solicitud'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('móvil descubre pestañas ocultas con controles accesibles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = ValueNotifier<int>(0);
    addTearDown(selected.dispose);

    await tester.pumpWidget(_navigation(selected));
    await tester.pumpAndSettle();

    final forward = find.byTooltip('Mostrar más secciones');
    final back = find.byTooltip('Mostrar secciones anteriores');
    expect(forward, findsOneWidget);
    expect(back, findsOneWidget);

    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(SilWorkspaceTopNavigation),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.controller, isNotNull);
    expect(scroll.controller!.offset, 0);

    await tester.tap(forward);
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, greaterThan(0));

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un acceso externo hace visible la pestaña activa en móvil',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = ValueNotifier<int>(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(_navigation(selected));
    await tester.pumpAndSettle();

    // Simula cambiar de sección desde una tarjeta, no desde la navegación.
    selected.value = 5;
    await tester.pumpAndSettle();

    final target = find.widgetWithText(TextButton, 'Revisión interna');
    expect(target, findsOneWidget);
    final rect = tester.getRect(target);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(390));
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(SilWorkspaceTopNavigation),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('al ampliar la ventana desaparecen las flechas sobrantes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = ValueNotifier<int>(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(_navigation(selected));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mostrar más secciones'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mostrar más secciones'), findsNothing);
    expect(find.byTooltip('Mostrar secciones anteriores'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
