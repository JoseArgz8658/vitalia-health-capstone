import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/clinicas/clinicas_page.dart';

class InstitutionFake extends AuthApi {
  final rows = <Map<String, dynamic>>[];
  final sent = <Map<String, dynamic>>[];
  bool failOnce = false;
  @override
  Future<List<Map<String, dynamic>>> institutions({
    String? clinicId,
    int offset = 0,
  }) async => rows;
  @override
  Future<Map<String, dynamic>> createInstitution(
    Map<String, dynamic> value, {
    String? clinicId,
  }) async {
    sent.add(Map.from(value));
    if (failOnce) {
      failOnce = false;
      throw const AuthFailure('Tiempo agotado.');
    }
    final item = {
      'id': value['requestId'],
      'name': value['name'],
      'active': true,
      'contactPhone': value['contactPhone'],
    };
    rows.add(item);
    return item;
  }

  @override
  Future<Map<String, dynamic>> institutionTerritories() async => {
    'regions': [],
    'provinces': [],
    'communes': [],
  };
}

void main() {
  testWidgets(
    'crear clínica conserva solicitud al reintentar y muestra confirmación',
    (tester) async {
      final api = InstitutionFake()..failOnce = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ClinicasPage(api: api, onExpired: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar clínica'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la clínica'),
        'Clínica ficticia',
      );
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Tiempo agotado.'), findsOneWidget);
      expect(api.sent.length, 1);
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(api.sent.length, 2);
      expect(api.sent[0]['requestId'], api.sent[1]['requestId']);
      expect(find.text('Clínica guardada.'), findsOneWidget);
      expect(find.text('Ver sucursales'), findsOneWidget);
      expect(api.sent[0].containsKey('actorId'), isFalse);
      expect(api.sent[0].containsKey('clinicalRole'), isFalse);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('cancelar creación no envía solicitud', (tester) async {
    final api = InstitutionFake();
    await tester.pumpWidget(
      MaterialApp(
        home: ClinicasPage(api: api, onExpired: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar clínica'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre de la clínica'),
      'Borrador',
    );
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty);
    expect(find.byType(TextFormField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('sucursal exige dirección y comuna antes de enviar', (
    tester,
  ) async {
    final api = InstitutionFake();
    await tester.pumpWidget(
      MaterialApp(
        home: ClinicasPage(
          api: api,
          onExpired: () {},
          clinic: const {
            'id': '22222222-2222-4222-8222-222222222222',
            'name': 'Clínica A',
            'active': true,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar sucursal'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty);
    expect(find.text('Completa este dato.'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  test(
    'API institucional utiliza sesión, paginación y ruta sin datos de pacientes',
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
            return http.Response('{"user":{"role":"administrador"}}', 200);
          expect(req.url.path, '/api/institutions');
          expect(req.headers['Authorization'], 'Bearer ${'a' * 64}');
          if (req.method == 'GET') {
            expect(req.url.queryParameters, {'limit': '20', 'offset': '0'});
            return http.Response('{"items":[]}', 200);
          }
          expect(req.url.hasQuery, isFalse);
          expect((jsonDecode(req.body) as Map).containsKey('actorId'), isFalse);
          return http.Response('{"item":{"id":"saved"}}', 201);
        }),
      );
      await api.login('admin@example.invalid', 'synthetic');
      expect(await api.institutions(), isEmpty);
      expect(
        (await api.createInstitution({
          'requestId': '22222222-2222-4222-8222-222222222222',
          'name': 'Ficticia',
          'contactPhone': null,
        }))['id'],
        'saved',
      );
      api.close();
    },
  );
}
