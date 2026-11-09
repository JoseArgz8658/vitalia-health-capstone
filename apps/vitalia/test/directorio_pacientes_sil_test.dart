import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/laboratorio/directorio_pacientes_sil.dart';

class _PatientsApi extends AuthApi {
  final calls = <Uri>[];

  @override
  Future<Map<String, dynamic>> silRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(path);
    calls.add(uri);
    expect(uri.path, '/patients/list');
    final offset = int.parse(uri.queryParameters['offset'] ?? '0');
    return {
      'total': 100,
      'limit': 20,
      'offset': offset,
      'patients': [
        for (var i = offset; i < offset + 20; i++)
          {
            'id': 'demo-$i',
            'email': 'prueba$i@example.invalid',
            'givenNames': 'Paciente',
            'familyNames': 'Ficticio $i',
            'syntheticIdentifier': 'DEMO-$i',
            'birthDate': '1990-01-01',
            'sexForReference': 'not_specified',
            'orderCount': i.isEven ? 2 : 0,
            'lastOrderNumber': i.isEven ? 'VH-000001' : null,
          },
      ],
    };
  }
}

void main() {
  testWidgets('100 fichas se solicitan en páginas de 20 en celular',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 840);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _PatientsApi();
    String? openedEmail;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DirectorioPacientesSil(
            api: api,
            onExpired: () {},
            onOpenProfile: (email) => openedEmail = email,
            onPrepareRequest: (_) {},
            onViewOrders: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(api.calls.length, 1);
    expect(api.calls.first.queryParameters['limit'], '20');
    expect(api.calls.first.queryParameters['offset'], '0');
    expect(find.textContaining('100 resultados'), findsOneWidget);
    expect(find.text('Paciente'), findsNothing);
    expect(tester.takeException(), isNull);

    final first = find.text('Ficha').first;
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(openedEmail, 'prueba0@example.invalid');

    final next = find.byTooltip('Página siguiente de pacientes');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(api.calls.last.queryParameters['offset'], '20');
    expect(find.text('Página 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('búsqueda se ejecuta en servidor, no sobre resultados locales',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _PatientsApi();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DirectorioPacientesSil(
            api: api,
            onExpired: () {},
            onOpenProfile: (_) {},
            onPrepareRequest: (_) {},
            onViewOrders: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    final search = find.widgetWithText(TextField, 'Buscar paciente');
    await tester.enterText(search, 'Prueba 45');
    await tester.tap(find.byTooltip('Buscar pacientes'));
    await tester.pumpAndSettle();
    expect(api.calls.last.queryParameters['search'], 'Prueba 45');
    expect(api.calls.last.queryParameters['offset'], '0');
    expect(tester.takeException(), isNull);
  });
}
