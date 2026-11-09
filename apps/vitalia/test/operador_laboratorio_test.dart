import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/laboratorio/operador_laboratorio_page.dart';

class _OperatorApi extends AuthApi {
  static const _id = '11111111-1111-4111-8111-111111111111';
  static const _exam = {
    'code': 'glicemia',
    'name': 'Glicemia',
    'analytes': [
      {'analyte': 'Glucosa', 'unit': 'mg/dL'},
    ],
  };

  bool failNextSave = true;
  var status = 'sampled';
  final calls = <Uri>[];

  Map<String, dynamic> get _order => {
        'id': _id,
        'orderNumber': 'VH-000013',
        'patientEmail': 'paciente.sil@example.invalid',
        'status': status,
        'examCodes': ['glicemia'],
      };

  @override
  Future<Map<String, dynamic>> silRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(path);
    calls.add(uri);
    switch (uri.path) {
      case '/catalog':
        return {
          'exams': [_exam],
        };
      case '/branches':
        return {'branches': []};
      case '/summary':
        return {
          'summary': {
            'total': 1,
            'pendingResults': status == 'sampled' ? 1 : 0
          },
        };
      case '/orders':
        return {
          'orders': [_order],
          'total': 1,
        };
      case '/orders/$_id':
        return {
          'order': _order,
          'exams': [_exam],
          if (status == 'registered')
            'requiredContainers': [
              {'code': 'fluoride', 'label': 'Fluoruro'},
            ],
        };
      case '/orders/$_id/sample':
        expect(body, {'containerCode': 'fluoride'});
        status = 'sampled';
        return {
          'sample': {'barcode': 'LAB-AUTOMATICO'},
        };
      case '/orders/$_id/results':
        expect(body?['results'], [
          {'examCode': 'glicemia', 'analyte': 'Glucosa', 'numericValue': 91.0},
        ]);
        if (failNextSave) {
          failNextSave = false;
          throw const AuthFailure('No se pudo guardar.');
        }
        status = 'results_recorded';
        return {};
      default:
        throw StateError('Ruta inesperada: $path');
    }
  }
}

void main() {
  testWidgets('recibe un tubo sin etiqueta y muestra el código asignado', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _OperatorApi()..status = 'registered';
    await tester.pumpWidget(MaterialApp(
      home: OperadorLaboratorioPage(api: api, onExpired: () {}),
    ));
    await tester.pumpAndSettle();
    final receive = find.text('Recibir muestra');
    await tester.ensureVisible(receive);
    await tester.tap(receive);
    await tester.pumpAndSettle();
    expect(
        find.text('Código de etiqueta existente (opcional)'), findsOneWidget);
    final register = find.text('Registrar recepción del tubo');
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    expect(find.textContaining('Código LAB-AUTOMATICO'), findsOneWidget);
    expect(find.text('Resultados de la orden'), findsOneWidget);
  });

  testWidgets(
      'bandeja de resultados abre el filtro y la orden en vista estrecha', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 840);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _OperatorApi();
    await tester.pumpWidget(MaterialApp(
      home: OperadorLaboratorioPage(
        api: api,
        onExpired: () {},
        onLogout: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);

    final pending = find.text('Pendientes de resultados');
    await tester.ensureVisible(pending);
    await tester.tap(pending);
    await tester.pumpAndSettle();

    expect(api.calls.last.queryParameters, containsPair('status', 'sampled'));
    expect(api.calls.last.queryParameters, containsPair('offset', '0'));
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('VH-000013'), findsOneWidget);
    final action = find.text('Ingresar resultados');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Ingresa los resultados de las prestaciones solicitadas.'),
        findsOneWidget);

    await tester.tap(find.text('Volver a órdenes'));
    await tester.pumpAndSettle();
    expect(api.calls.last.queryParameters, containsPair('status', 'sampled'));
  });

  testWidgets('conserva el ingreso si falla y vuelve a órdenes al guardar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _OperatorApi();
    await tester.pumpWidget(
      MaterialApp(
        home: OperadorLaboratorioPage(api: api, onExpired: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(4));
    final orders = find.text('Ver todas las órdenes');
    await tester.ensureVisible(orders);
    await tester.tap(orders);
    await tester.pumpAndSettle();

    final search = find.widgetWithText(TextField, 'Buscar orden o correo');
    await tester.enterText(search, 'VH-000013');
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();
    expect(api.calls.last.queryParameters['search'], 'VH-000013');

    await tester.tap(find.text('Ingresar resultados'));
    await tester.pumpAndSettle();
    expect(find.text('Volver a órdenes'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Muestras'));
    await tester.pumpAndSettle();
    expect(find.text('Recepción y seguimiento de muestras'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Resultados'));
    await tester.pumpAndSettle();
    final glucose = find.widgetWithText(TextField, 'Glucosa');
    await tester.enterText(glucose, '91');

    final save = find.text('Registrar resultados');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('No se pudo guardar.'), findsOneWidget);
    expect(tester.widget<TextField>(glucose).controller?.text, '91');

    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(save, findsNothing);
    expect(find.text('Buscar y gestionar órdenes'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('Pendiente de revisión'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Resultados registrados para VH-000013'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(search).controller?.text, isEmpty);
    expect(
      api.calls.where((call) => call.path == '/orders/${_OperatorApi._id}'),
      hasLength(1),
    );
  });
}
