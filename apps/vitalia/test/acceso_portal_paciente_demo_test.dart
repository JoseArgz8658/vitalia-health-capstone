import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/laboratorio/acceso_portal_paciente_demo.dart';
import 'package:vitalia_health/features/laboratorio/nuevo_paciente_sil_dialog.dart';

class _PortalOperatorApi extends AuthApi {
  final calls = <String>[];
  var invited = false;
  @override
  Future<Map<String, dynamic>> silPortalRequest(String path,
      {Map<String, dynamic>? body}) async {
    calls.add(path);
    if (path.endsWith('/invitations')) {
      expect(body, {
        'contactConfirmed': true,
        'identityChecked': true,
        'recipientRevision': 'a' * 64
      });
      invited = true;
      return {
        'invitation': {'status': 'invited', 'delivery': 'simulated_outbox'},
        'handoffCode': 'C' * 12,
        'recipient': {
          'email': 'nuevo@example.invalid',
          'givenNames': 'Paciente',
          'familyNames': 'Ficticio',
          'birthDate': '1990-01-01',
          'syntheticIdentifier': 'DEMO-TEST',
        },
      };
    }
    return {
      'patient': {
        'id': '11111111-1111-4111-8111-111111111111',
        'email': 'nuevo@example.invalid',
        'givenNames': 'Paciente',
        'familyNames': 'Ficticio',
        'birthDate': '1990-01-01',
        'syntheticIdentifier': 'DEMO-TEST',
        'portalStatus': invited ? 'invited' : 'pending',
      },
      'canInvite': true,
      'recipientRevision': 'a' * 64,
    };
  }
}

class _NewPatientApi extends AuthApi {
  final response = Completer<Map<String, dynamic>>();
  int saves = 0;

  @override
  Future<Map<String, dynamic>> silPortalRequest(String path,
      {Map<String, dynamic>? body}) {
    expect(path, '/portal/patients');
    expect(body?['email'], 'alta@example.invalid');
    expect(body?['syntheticConfirmed'], true);
    saves++;
    return response.future;
  }
}

void main() {
  testWidgets('alta DEMO se completa en móvil y conserva el diálogo al guardar',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 560);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _NewPatientApi();
    Map<String, dynamic>? created;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            created = await showDialog<Map<String, dynamic>>(
              context: context,
              barrierDismissible: false,
              builder: (_) => NuevoPacienteSilDialog(api: api),
            );
          },
          child: const Text('Nueva ficha'),
        );
      })),
    ));
    await tester.tap(find.text('Nueva ficha'));
    await tester.pumpAndSettle();
    for (final (label, value) in [
      ('Nombres ficticios', 'Paciente'),
      ('Apellidos ficticios', 'De prueba'),
      ('Nacimiento ficticio (AAAA-MM-DD)', '1990-01-01'),
      ('Correo ficticio', 'alta@example.invalid'),
    ]) {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
    }
    final check = find.byType(Checkbox);
    await Scrollable.ensureVisible(tester.element(check), alignment: 0.35);
    await tester.pumpAndSettle();
    await tester.tap(check);
    await tester.pumpAndSettle();
    final save = find.text('Crear ficha sin activar');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(api.saves, 1);
    expect(find.text('Creando ficha…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(NuevoPacienteSilDialog), findsOneWidget);
    api.response.complete({'portalStatus': 'pending'});
    await tester.pumpAndSettle();
    expect(created, {'portalStatus': 'pending'});
    expect(tester.takeException(), isNull);
  });
  for (final (width, height) in [(800.0, 1040.0), (320.0, 560.0)]) {
    testWidgets(
        'destinatario explícito y doble confirmación a ${width.toInt()} px', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, height);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _PortalOperatorApi();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AccesoPortalPacienteDemo(
            api: api,
            onExpired: () {},
            patientId: '11111111-1111-4111-8111-111111111111',
          ),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Acceso al portal'), findsOneWidget);
      expect(find.text('Sin activar'), findsOneWidget);
      expect(find.text('Paciente Ficticio'), findsOneWidget);
      expect(find.text('nuevo@example.invalid'), findsOneWidget);
      expect(find.text('DEMO-TEST'), findsOneWidget);
      await tester.ensureVisible(find.text('Preparar invitación DEMO'));
      await tester.tap(find.text('Preparar invitación DEMO'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar destinatario'), findsOneWidget);
      expect(find.text('Generar invitación DEMO'), findsOneWidget);
      expect(api.calls.where((v) => v.endsWith('/invitations')), isEmpty);
      final boxes = find.byType(Checkbox);
      expect(boxes, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final box = boxes.at(i);
        await Scrollable.ensureVisible(tester.element(box), alignment: 0.35);
        await tester.pumpAndSettle();
        expect(box.hitTestable(), findsOneWidget);
        await tester.tap(box);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Generar invitación DEMO'));
      await tester.tap(find.text('Generar invitación DEMO'));
      await tester.pumpAndSettle();
      expect(api.calls.where((v) => v.endsWith('/invitations')), hasLength(1));
      expect(find.text('CLAVE DE ENTREGA PRESENCIAL'), findsOneWidget);
      expect(find.text('C' * 12), findsOneWidget);
      expect(find.text('emailCode'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
