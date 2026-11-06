import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/profesional/atenciones_api.dart';
import 'package:vitalia_health/features/profesional/atenciones_page.dart';

const careId = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> care(String status, int revision) => {
  'id': careId,
  'status': status,
  'revision': revision,
  'clinicName': 'Clínica sintética',
  'branchName': 'Sucursal sintética',
  'specialtyName': 'Medicina general',
  'patientName': 'Paciente sintético',
  'document': {
    'id': '22222222-2222-4222-8222-222222222222',
    'examName': 'Examen sintético',
    'examType': 'Laboratorio',
    'examDate': '2026-01-01',
    'originalName': 'synthetic.pdf',
    'contentType': 'application/pdf',
    'sizeBytes': 8,
  },
};

class InboxAuth extends AuthApi {
  bool empty = false, unavailable = false, expired = false;
  int revision = 0, starts = 0;
  String status = 'requested';
  @override
  Future<http.Response> careInboxRequest({
    String? id,
    String? action,
    int offset = 0,
    Map<String, dynamic>? body,
  }) async {
    if (expired) throw const AuthFailure('Sesión terminada', 401);
    if (unavailable) throw const AuthFailure('Atención no disponible.', 404);
    if (action == 'review')
      return http.Response(
        jsonEncode({
          'processingId': null,
          'originalExtraction': null,
          'canReview': false,
          'review': null,
          'expectedRevision': revision,
          'processingStatus': 'not_requested',
        }),
        200,
      );
    if (action == 'begin') {
      expect(body, {'expectedRevision': 0});
      starts++;
      status = 'active';
      revision = 1;
      return http.Response('{"started":true}', 200);
    }
    if (id == null)
      return http.Response(
        jsonEncode({
          'items': empty ? [] : [care(status, revision)],
          'nextOffset': null,
        }),
        200,
      );
    return http.Response(
      jsonEncode({
        'care': care(status, revision),
        'contact': {
          'phone': '+56900000000',
          'email': 'paciente@example.invalid',
          'street': 'Calle sintética',
          'addressNumber': '123',
          'residenceCommune': 'Quilicura',
          'consultationCommune': 'Santiago',
          'confirmedAt': '2026-01-01T12:00:00Z',
        },
      }),
      200,
    );
  }
}

Future<void> tapText(WidgetTester t, String value) async {
  final f = find.text(value).last;
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> mount(
  WidgetTester t,
  InboxAuth auth, {
  bool detail = false,
  VoidCallback? expired,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: detail
          ? AtencionDetallePage(
              api: AtencionesApi(auth),
              id: careId,
              onExpired: expired ?? () {},
            )
          : AtencionesPage(auth: auth, onExpired: expired ?? () {}),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('bandeja muestra examen e institución sin contacto personal', (
    t,
  ) async {
    final auth = InboxAuth();
    await mount(t, auth);
    expect(find.text('Examen sintético'), findsOneWidget);
    expect(find.text('Paciente sintético'), findsOneWidget);
    expect(find.textContaining('+56900000000'), findsNothing);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('bandeja vacía tiene explicación y actualizar', (t) async {
    final auth = InboxAuth()..empty = true;
    await mount(t, auth);
    expect(
      find.textContaining('No tienes atenciones pendientes'),
      findsOneWidget,
    );
    expect(find.text('Actualizar bandeja'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('detalle conserva domicilio y zona de atención distintos', (
    t,
  ) async {
    final auth = InboxAuth();
    await mount(t, auth, detail: true);
    expect(
      find.text('Domicilio: Calle sintética 123, Quilicura'),
      findsOneWidget,
    );
    expect(find.text('Zona de atención: Santiago'), findsOneWidget);
    expect(find.text('Comenzar atención'), findsOneWidget);
    await t.binding.setSurfaceSize(const Size(360, 800));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.binding.setSurfaceSize(null);
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('inicio refresca estado y retira botón de iniciar', (t) async {
    final auth = InboxAuth();
    await mount(t, auth, detail: true);
    await tapText(t, 'Comenzar atención');
    expect(auth.starts, 1);
    expect(find.text('En atención'), findsOneWidget);
    expect(find.text('Comenzar atención'), findsNothing);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('revocación retira contacto al actualizar', (t) async {
    final auth = InboxAuth();
    await mount(t, auth, detail: true);
    auth.unavailable = true;
    await tapText(t, 'Actualizar atención');
    expect(find.text('Atención no disponible.'), findsOneWidget);
    expect(find.textContaining('+56900000000'), findsNothing);
    expect(find.text('Descargar examen'), findsNothing);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('sesión expirada entrega cierre y no muestra datos', (t) async {
    final auth = InboxAuth()..expired = true;
    var count = 0;
    await mount(t, auth, expired: () => count++);
    expect(count, 1);
    expect(find.text('Examen sintético'), findsNothing);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
}
