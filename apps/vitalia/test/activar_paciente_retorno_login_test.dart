import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/app/vitalia_mvp_app.dart';
import 'package:vitalia_health/core/auth_api.dart';

const _email = 'ana.perez.demo@example.invalid';
const _password = 'Clave-Segura-Demo-2026!';

class _ActivationApi extends AuthApi {
  int activated = 0;

  @override
  Future<void> silMainActivateOperator({
    required String email,
    required String code,
    required String password,
    bool patient = false,
  }) async {
    expect(patient, isTrue);
    expect(email, _email);
    expect(code, 'a' * 43);
    expect(password, _password);
    activated++;
  }
}

Future<void> _activateAndReturn(WidgetTester t, _ActivationApi api) async {
  expect(find.text('Activar acceso de paciente'), findsOneWidget);
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(4));
  await t.enterText(fields.at(0), _email);
  await t.enterText(fields.at(1), 'a' * 43);
  await t.enterText(fields.at(2), _password);
  await t.enterText(fields.at(3), _password);
  await t.ensureVisible(find.text('Activar acceso'));
  await t.tap(find.text('Activar acceso'));
  await t.pumpAndSettle();
  expect(api.activated, 1);
  expect(find.text('Acceso activado'), findsOneWidget);

  await t.tap(find.text('Ir al inicio de sesión'));
  await t.pumpAndSettle();
  expect(find.text('Acceso de pacientes'), findsOneWidget);

  final loginFields = find.byType(TextFormField);
  expect(loginFields, findsNWidgets(2));
  expect(t.widget<TextFormField>(loginFields.at(0)).controller!.text, _email);
  expect(t.widget<TextFormField>(loginFields.at(1)).enabled, isTrue);

  // Regresión: la contraseña debe aceptar escritura inmediatamente,
  // sin recargar la página ni crear otra cuenta.
  await t.enterText(loginFields.at(1), _password);
  await t.pumpAndSettle();
  expect(t.widget<TextFormField>(loginFields.at(1)).controller!.text, _password);
  expect(find.text('Escribe tu contraseña.'), findsNothing);
}

void main() {
  // El proyecto prueba también el modo general: ejecutar estas rutas
  // específicas solo en el job que habilita VITALIA_SIL_MAIN_MODE.
  const mainMode = bool.fromEnvironment('VITALIA_SIL_MAIN_MODE', defaultValue: false);
  testWidgets('ruta directa: tras activar paciente se puede escribir clave sin refrescar', (t) async {
    final api = _ActivationApi();
    await t.pumpWidget(VitaliaMvpApp(
      api: api,
      initialRoute: '/activar-portal',
    ));
    await t.pumpAndSettle();
    await _activateAndReturn(t, api);
    await t.pumpWidget(const SizedBox());
    api.close();
  }, skip: !mainMode);

  testWidgets('inicio: regresar de activación reabre login con correo y campo editable', (t) async {
    final api = _ActivationApi();
    await t.pumpWidget(VitaliaMvpApp(api: api));
    await t.pumpAndSettle();
    await t.tap(find.text('Activar acceso con invitación'));
    await t.pumpAndSettle();
    await _activateAndReturn(t, api);
    await t.pumpWidget(const SizedBox());
    api.close();
  }, skip: !mainMode);
}
