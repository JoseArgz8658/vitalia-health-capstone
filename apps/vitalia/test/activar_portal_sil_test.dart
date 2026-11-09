import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/acceso/activar_portal_sil_page.dart';

class _DemoActivationApi extends AuthApi {
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> silPortalPublic(String path,
      {Map<String, dynamic>? body}) async {
    calls.add({'path': path, 'body': body});
    if (path == '/portal/activate') {
      expect(body!['email'], 'nuevo@example.invalid');
      expect(body['emailCode'], 'a' * 12);
      expect(body['handoffCode'], 'b' * 12);
      expect(body['password'], 'UnaClaveSeguraNueva2026');
      expect(body['confirmedDetails'], true);
      return {'activated': true, 'loginRequired': true};
    }
    return {'emailCode': 'a' * 12};
  }
}

void main() {
  for (final (width, height, scale) in [
    (430.0, 920.0, 1.0),
    (320.0, 640.0, 1.25),
    (1440.0, 900.0, 1.0)
  ]) {
    testWidgets(
        'activación guiada requiere dos códigos y contraseña a ${width.toInt()} px',
        (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, height);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _DemoActivationApi();
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
          home: ActivarPortalSilPage(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Activa tu acceso privado'), findsOneWidget);
      expect(find.text('Cuenta'), findsOneWidget);
      Future<void> tapVisible(Finder finder) async {
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(finder), alignment: 0.35);
        await tester.pumpAndSettle();
        expect(finder.hitTestable(), findsOneWidget);
        await tester.tap(finder);
      }

      await tester.enterText(
          find.widgetWithText(TextField, 'Correo de contacto'),
          'nuevo@example.invalid');
      await tapVisible(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Comprueba los dos canales'), findsOneWidget);
      expect(find.text('Paso A · Código de correo'), findsOneWidget);
      expect(find.text('Paso B · Clave entregada en el laboratorio'),
          findsOneWidget);
      final emailCode =
          find.widgetWithText(TextField, 'Código recibido por correo');
      final handoff =
          find.widgetWithText(TextField, 'Clave de entrega presencial');
      if (const bool.fromEnvironment('VITALIA_SIL_DEMO_MODE')) {
        await tapVisible(find.text('Abrir buzón ficticio de prueba'));
        await tester.pumpAndSettle();
        expect(find.text('Correo de activación DEMO'), findsOneWidget);
        await tapVisible(find.text('Usar código de correo'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(emailCode).controller?.text, 'a' * 12);
        expect(tester.widget<TextField>(handoff).controller?.text, isEmpty);
      } else {
        await tester.enterText(emailCode, 'a' * 12);
      }
      await tester.ensureVisible(handoff);
      await tester.enterText(
          find.widgetWithText(TextField, 'Clave de entrega presencial'),
          'b' * 12);
      await tapVisible(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Tu acceso, tu contraseña'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nueva contraseña'),
          'UnaClaveSeguraNueva2026');
      await tester.ensureVisible(
          find.widgetWithText(TextFormField, 'Repetir contraseña'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Repetir contraseña'),
          'UnaClaveSeguraNueva2026');
      await tapVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tapVisible(find.text('Activar mi cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Cuenta activada'), findsOneWidget);
      expect(api.calls.where((x) => x['path'] == '/portal/activate'),
          hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}
