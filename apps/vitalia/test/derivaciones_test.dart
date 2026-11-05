import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/profesional/atenciones_api.dart';
import 'package:vitalia_health/features/profesional/derivar_atencion_page.dart';
import 'package:vitalia_health/features/documentos_reales/seguimiento_atencion_page.dart';

const id = '11111111-1111-4111-8111-111111111111';

class ReferralAuth extends AuthApi {
  bool empty = false, fail = false, expireHistory = false;
  final sent = <Map<String, dynamic>>[];
  @override
  Future<http.Response> careInboxRequest({
    String? id,
    String? action,
    int offset = 0,
    Map<String, dynamic>? body,
  }) async {
    if (action == 'referrals') {
      sent.add(Map<String, dynamic>.from(body!));
      if (fail) throw const AuthFailure('Reintenta sin cambiar los datos', 503);
      return http.Response('{"referred":true}', 201);
    }
    return http.Response(
      jsonEncode({
        'expectedRevision': 0,
        'clinicName': 'Clínica sintética',
        'nextOffset': null,
        'items': empty
            ? []
            : [
                {
                  'membershipId': '22222222-2222-4222-8222-222222222222',
                  'branchId': '33333333-3333-4333-8333-333333333333',
                  'specialtyId': '44444444-4444-4444-8444-444444444444',
                  'professionalName': 'Profesional destino',
                  'specialtyName': 'General',
                  'branchName': 'Sucursal destino',
                  'street': 'Calle sintética',
                  'addressNumber': '123',
                  'communeName': 'Quilicura',
                },
              ],
      }),
      200,
    );
  }

  @override
  Future<http.Response> sendDocumentRequest(http.BaseRequest request) async {
    if (expireHistory) throw const AuthFailure('Sesión terminada', 401);
    return http.Response(
      jsonEncode({
        'items': [
          {
            'professionalName': 'Profesional anterior',
            'clinicName': 'Clínica sintética',
            'branchName': 'Sucursal origen',
            'specialtyName': 'General',
            'status': 'referred',
          },
          {
            'professionalName': 'Profesional destino',
            'clinicName': 'Clínica sintética',
            'branchName': 'Sucursal destino',
            'specialtyName': 'General',
            'status': 'requested',
            'referralReason': 'Continuidad sintética',
          },
        ],
        'nextOffset': null,
      }),
      200,
    );
  }
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> mount(WidgetTester t, ReferralAuth auth) async {
  await t.pumpWidget(
    MaterialApp(
      home: DerivarAtencionPage(
        api: AtencionesApi(auth),
        id: id,
        onExpired: () {},
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> prepare(WidgetTester t) async {
  final f = find.byType(DropdownButtonFormField<String>);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
  await t.tap(find.textContaining('Profesional destino').last);
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextFormField), 'Continuidad sintética');
  t.testTextInput.hide();
  await t.pumpAndSettle();
  final check = find.byType(CheckboxListTile);
  await t.ensureVisible(check);
  await t.pumpAndSettle();
  await t.tap(check);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sin destinatario no permite confirmar', (t) async {
    final auth = ReferralAuth()..empty = true;
    await mount(t, auth);
    expect(
      find.textContaining('No hay otro profesional habilitado'),
      findsOneWidget,
    );
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirmar derivación'),
          )
          .onPressed,
      isNull,
    );
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('elección explícita y confirmación muestran recibo', (t) async {
    final auth = ReferralAuth();
    await mount(t, auth);
    await prepare(t);
    await tapText(t, 'Confirmar derivación');
    expect(auth.sent.single['confirmed'], true);
    expect(auth.sent.single['expectedRevision'], 0);
    expect(auth.sent.single.containsKey('clinicId'), false);
    expect(find.textContaining('Derivación registrada.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('reintento sin cambios conserva identificador de solicitud', (
    t,
  ) async {
    final auth = ReferralAuth()..fail = true;
    await mount(t, auth);
    await prepare(t);
    await tapText(t, 'Confirmar derivación');
    auth.fail = false;
    await tapText(t, 'Confirmar derivación');
    expect(auth.sent, hasLength(2));
    expect(auth.sent[0]['requestId'], auth.sent[1]['requestId']);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('sin confirmación el botón permanece deshabilitado', (t) async {
    final auth = ReferralAuth();
    await mount(t, auth);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirmar derivación'),
          )
          .onPressed,
      isNull,
    );
    expect(auth.sent, isEmpty);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('paciente ve origen, destino y motivo sin editar', (t) async {
    final auth = ReferralAuth();
    await t.pumpWidget(
      MaterialApp(
        home: SeguimientoAtencionPage(
          auth: auth,
          documentId: id,
          onExpired: () {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Profesional anterior'), findsOneWidget);
    expect(find.text('Profesional destino'), findsOneWidget);
    expect(find.text('Derivada'), findsOneWidget);
    expect(
      find.text('Motivo de derivación: Continuidad sintética'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('seguimiento vencido entrega cierre y no muestra datos', (
    t,
  ) async {
    final auth = ReferralAuth()..expireHistory = true;
    var count = 0;
    await t.pumpWidget(
      MaterialApp(
        home: SeguimientoAtencionPage(
          auth: auth,
          documentId: id,
          onExpired: () => count++,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(count, 1);
    expect(find.text('Profesional destino'), findsNothing);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
}
