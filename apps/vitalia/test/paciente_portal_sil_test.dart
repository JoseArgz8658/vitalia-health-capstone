import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/core/tema_vitalia.dart';
import 'package:vitalia_health/features/acceso/acceso_page.dart';
import 'package:vitalia_health/features/acceso/credenciales_paciente.dart';
import 'package:vitalia_health/features/acceso/recuperar_portal_sil_page.dart';
import 'package:vitalia_health/features/laboratorio/paciente_informes_sil_page.dart';

const _email = 'portal-qa@example.invalid';
const _password = 'Contraseña DEMO nueva';
const _id = '00000000-0000-4000-8000-000000000001';
final _key = List.filled(43, 'a').join();

class _PatientApi extends AuthApi {
  final calls = <String>[];

  @override
  bool get hasSession => true;

  @override
  Future<void> register(String email, String password) async {
    expect(email, _email);
    expect(password, _password);
    calls.add('register');
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password,
      {String mode = 'paciente'}) async {
    expect(email, _email);
    expect(password, _password);
    expect(mode, 'paciente');
    calls.add('login');
    return {'id': _id, 'role': mode, 'email': email};
  }

  @override
  Future<void> recoverSilPassword(
      String email, String key, String password) async {
    expect(email, _email);
    expect(key, _key);
    expect(password, _password);
    calls.add('recover');
  }

  @override
  Future<Map<String, dynamic>> generateSilRecoveryKey(
      String currentPassword) async {
    expect(currentPassword, _password);
    calls.add('generate');
    return {'recoveryKey': _key};
  }

  @override
  Future<Map<String, dynamic>> silRequest(String path,
      {Map<String, dynamic>? body}) async {
    if (path == '/patient/profile') {
      calls.add('profile');
      return {
        'profile': {
          'hasProfile': true,
          'givenNames': 'Paciente',
          'familyNames': 'De prueba',
          'birthDate': '1990-01-01',
        },
      };
    }
    if (path == '/patient/reports/overview') {
      expect(body?['reportIds'], [_id]);
      return {
        'reports': [
          {
            'orderNumber': 'VH-000001',
            'laboratory': 'Laboratorio ficticio',
            'measurements': [
              {'analyte': 'Glucosa', 'value': 91, 'unit': 'mg/dL'},
            ],
            'observation': 'Control de seguimiento.',
            'reference': 'SOL-DEMO',
          },
        ],
        'statistics': [],
      };
    }
    if (path.endsWith('/chat')) {
      expect(path, '/patient/reports/$_id/chat');
      expect(body?['question'], '¿Qué significa rango de referencia?');
      expect(body?['simple'], true);
      calls.add('chat');
      return {
        'response': {
          'answer': 'Es un intervalo que orienta la lectura.',
          'source': 'catalogo'
        },
      };
    }
    expect(path, '/patient/reports');
    return {
      'reports': [
        {
          'id': _id,
          'fileName': 'prueba.pdf',
          'examNames': ['Glicemia'],
          'orderNumber': 'VH-000001',
          'issuingLaboratory': 'Laboratorio ficticio',
          'prescriberName': 'Dra. Elisa Muñoz',
          'publishedAt': '2026-10-20',
        },
      ],
    };
  }
}

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 680);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.pumpAndSettle();
  final target = find.text(text).last;
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.4);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder field, String value) async {
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('registro en celular devuelve el correo al login de paciente',
      (tester) async {
    _phone(tester);
    final api = _PatientApi();
    await tester.pumpWidget(
        MaterialApp(theme: temaVitalia(), home: AccesoPage(api: api)));
    await _tap(tester, 'Crear cuenta de paciente');
    await _type(tester,
        find.widgetWithText(TextFormField, 'Correo electrónico').last, _email);
    await _type(tester, find.widgetWithText(TextFormField, 'Contraseña').last,
        _password);
    await _type(tester,
        find.widgetWithText(TextFormField, 'Confirmar contraseña'), _password);
    await _tap(tester, 'Crear cuenta');
    await _tap(tester, 'Volver a iniciar sesión');
    expect(find.text(_email), findsOneWidget);
    await _type(
        tester, find.widgetWithText(TextFormField, 'Contraseña'), _password);
    await _tap(tester, 'Iniciar sesión');
    expect(api.calls, ['register', 'login']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'recupera acceso en celular y borra los campos sensibles al terminar',
      (tester) async {
    _phone(tester);
    final api = _PatientApi();
    await tester.pumpWidget(MaterialApp(
        theme: temaVitalia(),
        home: silPatientDemo
            ? AccesoPage(api: api)
            : RecuperarPortalSilPage(api: api, email: _email)));
    if (silPatientDemo) {
      await _type(tester,
          find.widgetWithText(TextFormField, 'Correo electrónico'), _email);
      await _tap(tester, 'Olvidé mi contraseña');
    }
    await _type(tester,
        find.widgetWithText(TextFormField, 'Clave de recuperación'), _key);
    await _type(tester, find.widgetWithText(TextFormField, 'Nueva contraseña'),
        _password);
    await _type(
        tester,
        find.widgetWithText(TextFormField, 'Confirmar nueva contraseña'),
        _password);
    await _tap(tester, 'Actualizar contraseña');
    expect(find.text('Contraseña actualizada'), findsOneWidget);
    expect(find.text(_key), findsNothing);
    expect(api.calls, ['recover']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'portal móvil busca informes, abre prompts y genera clave solo una vez',
      (tester) async {
    _phone(tester);
    final api = _PatientApi();
    await tester.pumpWidget(MaterialApp(
      theme: temaVitalia(),
      home: PacienteInformesSilPage(
          api: api, email: _email, onExpired: () {}, onLogout: () {}),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mi cuenta'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Mi perfil');
    expect(find.text('Nombre: Paciente De prueba'), findsOneWidget);
    await _tap(tester, 'Cerrar');
    expect(find.textContaining('Dra. Elisa Muñoz'), findsOneWidget);
    final search = find.widgetWithText(
        TextField, 'Buscar por orden, examen o laboratorio');
    await _type(tester, search, 'inexistente');
    expect(find.text('No encontramos informes que coincidan con tu búsqueda.'),
        findsOneWidget);
    await _type(tester, search, 'VH-000001');
    await _tap(tester, 'Ver resultados');
    await _tap(tester, 'Leer informes');
    expect(find.text('Glucosa · 91 mg/dL'), findsOneWidget);
    await _tap(tester, '¿Qué dice la derivación?');
    expect(find.text('«Control de seguimiento.»'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tap(tester, 'Preguntar sobre el informe');
    await _tap(tester, 'Lectura fácil');
    await _tap(tester, 'Rango de referencia');
    await _tap(tester, 'Preguntar al asistente');
    expect(
        find.text('Es un intervalo que orienta la lectura.'), findsOneWidget);
    await tester.tap(find.byTooltip('Mi cuenta'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Configurar recuperación');
    await _type(
        tester, find.widgetWithText(TextField, 'Contraseña actual'), _password);
    await _tap(tester, 'Generar clave');
    expect(find.text(_key), findsOneWidget);
    await _tap(tester, 'Ya guardé la clave');
    expect(find.text(_key), findsNothing);
    expect(api.calls, ['profile', 'chat', 'generate']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portal de escritorio aprovecha ancho y muestra nombre real de ficha',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _PatientApi();
    await tester.pumpWidget(MaterialApp(
      theme: temaVitalia(),
      home: PacienteInformesSilPage(
        api: api,
        email: _email,
        onExpired: () {},
        onLogout: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Hola, Paciente'), findsOneWidget);
    expect(find.text('Ir a mis informes'), findsOneWidget);
    expect(find.text('Informes disponibles'), findsOneWidget);
    expect(find.text('Última publicación'), findsOneWidget);
    expect(find.text('Consulta conjunta'), findsOneWidget);
    // La imagen es vectorial y no muestra información clínica falsa.
    expect(find.byIcon(Icons.family_restroom), findsOneWidget);
    // Con un único PDF, la ayuda no duplica el acceso a la comparación.
    expect(find.text('Cómo leer mis resultados'), findsOneWidget);
    expect(find.text('Comparar informes'), findsNothing);
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Actualizar informes'), findsOneWidget);
    // En pantallas de escritorio intermedias, la recuperación se
    // conserva en el menú superior para evitar desbordamientos.
    expect(find.byTooltip('Mi cuenta'), findsOneWidget);
    await tester.tap(find.byTooltip('Mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Configurar recuperación'), findsOneWidget);
    await tester.tapAt(const Offset(600, 450));
    await tester.pumpAndSettle();
    expect(find.text('Ver resultados'), findsOneWidget);
    expect(find.text('Ir a mis informes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
