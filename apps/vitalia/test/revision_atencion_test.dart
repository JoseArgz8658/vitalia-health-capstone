import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/profesional/revision_api.dart';
import 'package:vitalia_health/features/profesional/revision_panel.dart';

const id = '11111111-1111-4111-8111-111111111111';
const doc = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> extracted() => {
  'examen': 'Examen sintético',
  'fecha': '01-01-2026',
  'resultados': [
    {
      'nombre': 'Glucosa',
      'valor': '90',
      'unidad': 'mg/dL',
      'rango_referencia': '70-100',
    },
    {
      'nombre': 'Indicador ficticio',
      'valor': '7',
      'unidad': 'g/L',
      'rango_referencia': '5-9',
    },
  ],
};

class ReviewAuth extends AuthApi {
  bool available = true, saved = false, revoked = false;
  Map<String, dynamic>? sent;
  Map<String, dynamic> approved() => {
    'approved': true,
    'extraction': sent?['extraction'] ?? extracted(),
    'reviewerEmail': 'profesional@example.invalid',
    'observations': sent?['observations'] ?? '',
    'reviewedAt': '2026-01-01T12:00:00Z',
  };
  @override
  Future<http.Response> careInboxRequest({
    String? id,
    String? action,
    int offset = 0,
    Map<String, dynamic>? body,
  }) async {
    if (revoked) throw const AuthFailure('Atención no disponible', 404);
    expect(action, 'review');
    if (body != null) {
      sent = body;
      saved = true;
      return http.Response(jsonEncode({'review': approved()}), 201);
    }
    return http.Response(
      jsonEncode({
        'processingId': available ? doc : null,
        'processingStatus': available ? 'requires_review' : 'not_requested',
        'expectedRevision': 1,
        'originalExtraction': available ? extracted() : null,
        'sourceText': 'Texto sintético original',
        'canReview': available && !saved,
        'review': saved ? approved() : null,
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

Future<void> mount(
  WidgetTester t,
  ReviewAuth auth, {
  void Function(AuthFailure)? onFailure,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RevisionPanel(
            auth: auth,
            patientId: '',
            documentId: doc,
            careId: id,
            onFailure: onFailure ?? (_) {},
            onSaving: (_) {},
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sin extracción no permite aprobar ni solicita procesamiento', (
    t,
  ) async {
    final auth = ReviewAuth()..available = false;
    await mount(t, auth);
    expect(find.text('Extracción aún no solicitada'), findsOneWidget);
    expect(find.text('Aprobar revisión y completar atención'), findsNothing);
    expect(auth.sent, isNull);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('pasos conservan datos y muestran un resultado a la vez', (
    t,
  ) async {
    final auth = ReviewAuth();
    await mount(t, auth);
    await tapText(t, 'Continuar revisión');
    expect(find.text('Resultado 1 de 2'), findsOneWidget);
    expect(find.text('Indicador ficticio'), findsNothing);
    await tapText(t, 'Resultado siguiente');
    expect(find.text('Resultado 2 de 2'), findsOneWidget);
    expect(find.text('Indicador ficticio'), findsOneWidget);
    await tapText(t, 'Paso anterior');
    expect(find.text('Examen sintético'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('aprobar requiere confirmación y envía revisión esperada', (
    t,
  ) async {
    final auth = ReviewAuth();
    await mount(t, auth);
    await tapText(t, 'Continuar revisión');
    await tapText(t, 'Continuar revisión');
    final button = find.widgetWithText(
      FilledButton,
      'Aprobar revisión y completar atención',
    );
    expect(t.widget<FilledButton>(button).onPressed, isNull);
    final check = find.byType(CheckboxListTile);
    await t.ensureVisible(check);
    await t.pumpAndSettle();
    await t.tap(check);
    await t.pumpAndSettle();
    await tapText(t, 'Aprobar revisión y completar atención');
    expect(auth.sent?['expectedRevision'], 1);
    expect(auth.sent?['confirmedOriginal'], true);
    expect(auth.sent!.containsKey('patientId'), false);
    expect(find.text('Revisión aprobada y registrada'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('revisión guardada no muestra editor', (t) async {
    final auth = ReviewAuth()..saved = true;
    await mount(t, auth);
    expect(find.text('Revisión aprobada y registrada'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  testWidgets('revocación notifica al contenedor y oculta formulario', (
    t,
  ) async {
    final auth = ReviewAuth();
    var count = 0;
    await mount(t, auth, onFailure: (_) => count++);
    auth.revoked = true;
    await tapText(t, 'Actualizar revisión');
    expect(count, 1);
    expect(find.text('Continuar revisión'), findsNothing);
    await t.pumpWidget(const SizedBox());
    auth.close();
  });
  test(
    'adaptador por atención no construye identidad de paciente para consultar',
    () async {
      final auth = ReviewAuth();
      final data = await RevisionApi(auth, careId: id).consultar('', doc);
      expect(data['expectedRevision'], 1);
      expect(data['canReview'], true);
      auth.close();
    },
  );
}
