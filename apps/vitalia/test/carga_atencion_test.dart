import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/documentos_reales/documentos_api.dart';
import 'package:vitalia_health/features/documentos_reales/subir_documento_form.dart';

class CareAuth extends AuthApi {
  bool empty = false, expired = false;
  String phone = '+56912345678';
  final searches = <String>[];
  @override
  Future<Map<String, dynamic>> careContext() async {
    if (expired) throw const AuthFailure('Sesión terminada', 401);
    return {
      'email': 'paciente@example.invalid',
      'phone': phone,
      'street': 'Calle sintética',
      'addressNumber': '123',
      'residenceCommuneCode': '13125',
      'preferredCommuneCode': '13101',
      'revision': 'synthetic',
    };
  }

  @override
  Future<Map<String, dynamic>> territories() async => {
    'regions': [
      {'code': '13', 'name': 'Metropolitana'},
    ],
    'provinces': [
      {'code': '131', 'name': 'Santiago', 'regionCode': '13'},
    ],
    'communes': [
      {'code': '13125', 'name': 'Quilicura', 'provinceCode': '131'},
      {'code': '13101', 'name': 'Santiago', 'provinceCode': '131'},
    ],
  };
  @override
  Future<Map<String, dynamic>> careCatalog(
    String communeCode, {
    int offset = 0,
  }) async {
    searches.add(communeCode);
    return {
      'items': empty
          ? []
          : [
              {
                'clinicId': 'clinic',
                'clinicName': 'Clínica sintética',
                'branchId': 'branch',
                'branchName': 'Sucursal sintética',
                'specialtyId': 'specialty',
                'specialtyName': 'Medicina general',
                'membershipId': 'member',
                'professionalName': 'Profesional sintético',
                'communeCode': communeCode,
                'street': 'Calle de la sucursal',
                'addressNumber': '456',
              },
            ],
      'nextOffset': null,
    };
  }
}

Future<void> mount(
  WidgetTester t,
  CareAuth auth, {
  VoidCallback? onExpired,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SubirDocumentoForm(
              api: DocumentosApi(auth),
              onSaved: () {},
              onCancel: () {},
              onExpired: onExpired ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text) async {
  final finder = find.text(text).last;
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, String key, String label) async {
  final field = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.key is ValueKey &&
        (w.key as ValueKey).value.toString().startsWith('$key-'),
  );
  await t.ensureVisible(field);
  await t.pumpAndSettle();
  await t.tap(field);
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('precarga contacto y domicilio sin confundir comuna preferida', (
    t,
  ) async {
    final auth = CareAuth();
    await mount(t, auth);
    expect(find.text('paciente@example.invalid'), findsOneWidget);
    expect(find.text('Calle sintética'), findsOneWidget);
    expect(find.text('Quilicura'), findsOneWidget);
    expect(find.text('Paso 1 de 4 · Ubicación y contacto'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('teléfono obligatorio impide avanzar', (t) async {
    final auth = CareAuth()..phone = '';
    await mount(t, auth);
    await tapText(t, 'Continuar');
    expect(find.text('Completa este dato.'), findsOneWidget);
    expect(find.text('Paso 1 de 4 · Ubicación y contacto'), findsOneWidget);
    expect(auth.searches, isEmpty);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('elección explícita conserva profesional al retroceder', (
    t,
  ) async {
    final auth = CareAuth();
    await mount(t, auth);
    await tapText(t, 'Continuar');
    await tapText(t, 'Buscar atención');
    expect(auth.searches, ['13125']);
    await choose(t, 'clinicId', 'Clínica sintética');
    await choose(t, 'branchId', 'Sucursal sintética');
    await choose(t, 'specialtyId', 'Medicina general');
    await choose(t, 'membershipId', 'Profesional sintético');
    await tapText(t, 'Continuar');
    expect(find.text('Paso 3 de 4 · Adjuntar examen'), findsOneWidget);
    await tapText(t, 'Anterior');
    expect(find.text('Profesional sintético'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('otra zona no borra el domicilio ingresado', (t) async {
    final auth = CareAuth();
    await mount(t, auth);
    await tapText(t, 'Continuar');
    await tapText(t, 'Buscar en la comuna de mi domicilio');
    expect(
      find.text('Zona de atención: esta selección no cambia tu domicilio.'),
      findsOneWidget,
    );
    await tapText(t, 'Anterior');
    expect(find.text('Calle sintética'), findsOneWidget);
    expect(find.text('Quilicura'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('sin opciones explica otra zona y no permite avanzar', (t) async {
    final auth = CareAuth()..empty = true;
    await mount(t, auth);
    await tapText(t, 'Continuar');
    await tapText(t, 'Buscar atención');
    expect(
      find.textContaining('No hay profesionales habilitados'),
      findsOneWidget,
    );
    await tapText(t, 'Continuar');
    expect(
      find.text('Busca atención y selecciona un profesional.'),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets(
    'sesión expirada en precarga llama al cierre sin mostrar contactos',
    (t) async {
      final auth = CareAuth()..expired = true;
      var count = 0;
      await mount(t, auth, onExpired: () => count++);
      expect(count, 1);
      expect(find.text('paciente@example.invalid'), findsNothing);
      await t.pumpWidget(const SizedBox());
      auth.close();
    },
  );
}
