import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/perfil/ubicacion_panel.dart';

const catalog = <String, dynamic>{
  'version': 'test',
  'regions': [
    {'code': '13', 'name': 'Metropolitana'},
    {'code': '16', 'name': 'Ñuble'},
  ],
  'provinces': [
    {'code': '131', 'name': 'Santiago', 'regionCode': '13'},
    {'code': '132', 'name': 'Cordillera', 'regionCode': '13'},
    {'code': '161', 'name': 'Diguillín', 'regionCode': '16'},
  ],
  'communes': [
    {'code': '13125', 'name': 'Quilicura', 'provinceCode': '131'},
    {'code': '13201', 'name': 'Puente Alto', 'provinceCode': '132'},
    {'code': '16101', 'name': 'Chillán', 'provinceCode': '161'},
  ],
};

class CatalogFake extends AuthApi {
  bool fails = false;
  @override
  Future<Map<String, dynamic>> territories() async {
    if (fails) throw const AuthFailure('Catálogo no disponible.', 503);
    return catalog;
  }
}

void main() {
  testWidgets(
    'cambio de región y provincia limpia comuna y exige selección coherente',
    (tester) async {
      final api = CatalogFake();
      String? value = '13125';
      final form = GlobalKey<FormState>();
      var valid = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) => Form(
                  key: form,
                  child: Column(
                    children: [
                      UbicacionPanel(
                        api: api,
                        value: value,
                        editing: true,
                        enabled: true,
                        onChanged: (next) => update(() => value = next),
                        onExpired: () {},
                      ),
                      TextButton(
                        onPressed: () {
                          valid = form.currentState!.validate();
                        },
                        child: const Text('Guardar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quilicura'), findsOneWidget);
      final province = find.byType(DropdownButtonFormField<String>).at(1);
      await tester.ensureVisible(province);
      await tester.tap(province);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cordillera').last);
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(find.text('Quilicura'), findsNothing);
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(valid, isFalse);
      final commune = find.byType(DropdownButtonFormField<String>).at(2);
      await tester.ensureVisible(commune);
      await tester.tap(commune);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Puente Alto').last);
      await tester.pumpAndSettle();
      expect(value, '13201');
      final region = find.byType(DropdownButtonFormField<String>).at(0);
      await tester.ensureVisible(region);
      await tester.tap(region);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ñuble').last);
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(find.text('Puente Alto'), findsNothing);
      expect(find.text('Cordillera'), findsNothing);
      await tester.ensureVisible(find.text('Quitar ubicación'));
      await tester.tap(find.text('Quitar ubicación'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(valid, isTrue);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'consulta muestra nombres y cancelar edición restaura la ubicación guardada',
    (tester) async {
      final api = CatalogFake();
      String? value = '13125';
      var editing = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) => Column(
                  children: [
                    UbicacionPanel(
                      api: api,
                      value: value,
                      editing: editing,
                      enabled: true,
                      onChanged: (next) => update(() => value = next),
                      onExpired: () {},
                    ),
                    TextButton(
                      onPressed: () => update(() {
                        editing = !editing;
                        value = '13125';
                      }),
                      child: const Text('Alternar edición'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quilicura, Santiago, Metropolitana'), findsOneWidget);
      await tester.tap(find.text('Alternar edición'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Quitar ubicación'));
      await tester.tap(find.text('Quitar ubicación'));
      await tester.pumpAndSettle();
      expect(value, isNull);
      await tester.ensureVisible(find.text('Alternar edición'));
      await tester.tap(find.text('Alternar edición'));
      await tester.pumpAndSettle();
      expect(find.text('Quilicura, Santiago, Metropolitana'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'fallo del catálogo conserva código existente y permite reintentar',
    (tester) async {
      final api = CatalogFake()..fails = true;
      var changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UbicacionPanel(
              api: api,
              value: '13125',
              editing: true,
              enabled: true,
              onChanged: (_) {
                changed = true;
              },
              onExpired: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('La ubicación guardada se conserva.'),
        findsOneWidget,
      );
      expect(changed, isFalse);
      api.fails = false;
      await tester.tap(find.text('Reintentar catálogo'));
      await tester.pumpAndSettle();
      expect(find.text('Quilicura'), findsOneWidget);
      expect(changed, isFalse);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  test(
    'API catálogo usa sesión y ruta fija sin identificadores de pacientes',
    () async {
      final api = AuthApi(
        client: MockClient((req) async {
          if (req.url.path.endsWith('/login'))
            return http.Response(
              jsonEncode({
                'token': 'a' * 64,
                'expiresAt': DateTime.now()
                    .add(const Duration(minutes: 30))
                    .toIso8601String(),
              }),
              200,
            );
          if (req.url.path.endsWith('/me'))
            return http.Response('{"user":{"role":"paciente"}}', 200);
          expect(req.method, 'GET');
          expect(req.url.path, '/api/profile/territories');
          expect(req.url.hasQuery, isFalse);
          expect(req.headers['Authorization'], 'Bearer ${'a' * 64}');
          return http.Response(jsonEncode(catalog), 200);
        }),
      );
      await api.login('test@example.invalid', 'synthetic');
      expect(await api.territories(), catalog);
      api.close();
    },
  );
}
