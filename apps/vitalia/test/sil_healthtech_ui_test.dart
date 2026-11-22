import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/tema_vitalia.dart';
import 'package:vitalia_health/features/laboratorio/portal_visual_sil.dart';
import 'package:vitalia_health/features/laboratorio/sil_workspace.dart';

void main() {
  testWidgets('guía del proceso se adapta a una pantalla estrecha',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: temaVitalia(),
      home: const Scaffold(
        body: SingleChildScrollView(child: SilWorkspaceProcessPath()),
      ),
    ));
    expect(find.text('Etapas del proceso'), findsOneWidget);
    expect(find.text('Recepción'), findsOneWidget);
    expect(find.text('Publicación'), findsOneWidget);
    expect(find.textContaining('No representa el estado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('administración conserva contexto y cifras legibles',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: temaVitalia(),
      home: const Scaffold(
        body: Column(children: [
          SilWorkspaceRoleLabel(
            label: 'Administrador',
            icon: Icons.admin_panel_settings_outlined,
          ),
          SilWorkspaceSummaryStat(
            icon: Icons.business_outlined,
            label: 'Laboratorios administrados',
            value: '2',
          ),
        ]),
      ),
    ));
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Laboratorios administrados'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portada de paciente usa variante calmada accesible',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: temaVitalia(),
      home: const Scaffold(
        body: SingleChildScrollView(child: PortalHeroSil(
          eyebrow: 'Tu espacio personal',
          title: 'Hola, Ana',
          subtitle: 'Tus informes publicados',
          calm: true,
          compact: true,
          showLaboratoryArt: false,
        )),
      ),
    ));
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Tus informes publicados'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
