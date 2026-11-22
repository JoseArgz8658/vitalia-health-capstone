import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/laboratorio/paciente_informes_sil_page.dart';

const mainSil = bool.fromEnvironment('VITALIA_SIL_MAIN_MODE');
final code = List<String>.filled(43, 'A').join();

class _UnlinkedPatientApi extends AuthApi {
  int issued = 0;

  @override
  bool get hasSession => true;

  @override
  Future<Map<String, dynamic>> silRequest(
    String path, {Map<String, dynamic>? body}
  ) async {
    if (path == '/patient/profile') {
      return {'profile': {'hasProfile': false}};
    }
    if (path == '/patient/reports') {
      return {'reports': []};
    }
    throw StateError('Ruta inesperada en prueba: $path');
  }

  @override
  Future<Map<String, dynamic>> silMainRequest(
    String path, {Map<String, dynamic>? body}
  ) async {
    expect(path, '/patient/link-code');
    expect(body, isEmpty);
    issued++;
    return {'code': code, 'expiresAt': '2026-11-22T12:00:00Z'};
  }
}

void main() {
  testWidgets(
    'Camino B: paciente sin informes cancela o emite código desde móvil',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _UnlinkedPatientApi();
      await tester.pumpWidget(MaterialApp(
        home: PacienteInformesSilPage(
          api: api,
          email: 'paciente-camino-b@example.invalid',
          onExpired: () {},
          onLogout: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mi cuenta'), findsOneWidget);
      // La ausencia de informes no impide vincular una cuenta nueva.
      await tester.tap(find.byTooltip('Mi cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vincular mi cuenta').last);
      await tester.pumpAndSettle();
      expect(find.text('Generar código'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(api.issued, 0);

      await tester.tap(find.byTooltip('Mi cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vincular mi cuenta').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generar código'));
      await tester.pumpAndSettle();
      expect(api.issued, 1);
      expect(find.text('Código de vinculación'), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text(code), findsNothing);
      expect(tester.takeException(), isNull);
    },
    skip: !mainSil,
  );
}
