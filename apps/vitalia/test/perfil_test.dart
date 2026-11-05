import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/perfil/perfil_page.dart';

class ProfileFake extends AuthApi {
  @override
  Future<Map<String, dynamic>> territories() async => {'version':'test','regions':[{'code':'13','name':'Metropolitana'}],'provinces':[{'code':'131','name':'Santiago','regionCode':'13'}],'communes':[{'code':'13101','name':'Santiago','provinceCode':'131'}]};
  Map<String, dynamic>? saved;
  int? failure;
  @override
  Future<Map<String, dynamic>?> profile({Map<String, dynamic>? update}) async {
    if (failure != null) throw AuthFailure('Perfil no disponible.', failure);
    if (update != null) saved = update;
    return saved;
  }
}
void main() {
  testWidgets('perfil opcional guarda datos propios sin elegir rol', (tester) async {
    final api = ProfileFake();
    await tester.pumpWidget(MaterialApp(home: PerfilPage(api: api, onExpired: () {})));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Editar datos personales'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Primer nombre'), 'Ana');
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Primer apellido'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Primer apellido'), 'Prueba');
    await tester.ensureVisible(find.text('Guardar perfil'));
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();
    expect(api.saved?['firstName'], 'Ana');
    expect(api.saved?['rut'], isNull);
    expect(api.saved?.containsKey('role'), isFalse);
    expect(find.textContaining('Perfil guardado.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Ana'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('cancelar restaura datos guardados sin enviar cambios', (tester) async {
    final api = ProfileFake()..saved = {'firstName':'Ana','firstSurname':'Prueba'};
    await tester.pumpWidget(MaterialApp(home: PerfilPage(api: api, onExpired: () {})));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Contacto'), findsOneWidget);
    expect(find.text('Identificación'), findsOneWidget);
    await tester.tap(find.text('Editar datos personales'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Primer nombre'), 'Borrador');
    await tester.ensureVisible(find.text('Cancelar edición'));
    await tester.tap(find.text('Cancelar edición'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Ana'), findsOneWidget);
    expect(api.saved?['firstName'], 'Ana');
    final edit = find.text('Editar datos personales');
    await tester.ensureVisible(edit);await tester.tap(edit);await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Primer nombre')).controller!.text, 'Ana');
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('perfil oculta formulario cuando falla consulta y anuncia expiración', (tester) async {
    final api = ProfileFake()..failure = 401;var expired = false;
    await tester.pumpWidget(MaterialApp(home: PerfilPage(api: api, onExpired: () { expired = true; })));
    await tester.pumpAndSettle();
    expect(expired, isTrue);expect(find.byType(TextFormField), findsNothing);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  test('API perfil utiliza su sesión y ruta fija', () async {
    final token = List.filled(64, 'a').join();
    final api = AuthApi(client: MockClient((req) async {
      if (req.url.path.endsWith('/login')) return http.Response(jsonEncode({'token':token,'expiresAt':DateTime.now().add(const Duration(minutes:30)).toIso8601String()}),200);
      if (req.url.path.endsWith('/me')) return http.Response('{"user":{"role":"paciente"}}',200);
      expect(req.url.path, '/api/profile');expect(req.headers['Authorization'], 'Bearer $token');
      return http.Response('{"profile":null}',200);
    }));
    await api.login('test@example.invalid','synthetic');expect(await api.profile(), isNull);api.close();
  });
}

