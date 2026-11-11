import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/laboratorio/sil_principal_page.dart';

class _StationApi extends AuthApi {
  final reviewActions=<Map<String,dynamic>>[];
  final pendingCompletions=<Map<String,dynamic>>[];
  bool showPending=false;
  bool pendingWithoutDate=false;
  static const allowedLab = '11111111-1111-4111-8111-111111111111';
  static const restrictedLab = '22222222-2222-4222-8222-222222222222';
  static const ownOrder = '33333333-3333-4333-8333-333333333333';
  static const otherOrder = '44444444-4444-4444-8444-444444444444';

  @override
  Future<Map<String, dynamic>> silMainRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final requestPath=Uri.parse(path).path;
    if(requestPath=='/labs/$allowedLab/medical-requests/pending'){
      return {'pending':showPending?[{
        'id':'66666666-6666-4666-8666-666666666666',
        'fileName':'derivacion-ejemplo.pdf',
        'status':'pending',
        'extractionStatus':'text_ready',
        'patientEmail':'prueba@example.invalid',
        'suggestions':{
          'suggestedDocumentReference':'SOL-2001',
          'suggestedPrescriberName':'Persona Solicitante',
          'suggestedRequestDate':pendingWithoutDate?null:'2024-01-01',
          'suggestedExams':[{'code':'glicemia','name':'Glicemia'}],
          'suggestedPatient':{
            'fullName':'Ana Prueba','identifier':null,
            'birthDate':'1990-01-01','email':'prueba@example.invalid',
            'phone':null,'sex':null,
          },
        },
      }]:[]};
    }
    if(requestPath=='/labs/$allowedLab/medical-requests/pending/66666666-6666-4666-8666-666666666666/complete'){
      pendingCompletions.add(body??{});
      return {'order':{'id':ownOrder},'pending':{'status':'completed'}};
    }
    if(requestPath=='/labs/$restrictedLab/medical-requests/pending'){
      return {'pending':[]};
    }
    if(requestPath=='/labs/$allowedLab/patients'){
      return {
        'patients':[
          {
            'id':ownOrder,
            'email':'prueba@example.invalid',
            'givenNames':'Ana',
            'familyNames':'Prueba',
          },
        ],
        'hasMore':false,
      };
    }
    if(requestPath=='/labs/$allowedLab/staff/review-permission' && body!=null){
      reviewActions.add(body);
      return {'membership':{'canReviewReports':body['enabled']}};
    }
    return switch (requestPath) {
      '/labs' => {
        'laboratories': [
          {
            'id': allowedLab,
            'displayName': 'Laboratorio Norte',
            'canReviewReports': true,
          },
          {
            'id': restrictedLab,
            'displayName': 'Laboratorio Sur',
            'canReviewReports': false,
          },
        ],
      },
      '/labs/$allowedLab/orders' => {
        'orders': [
          {
            'id': ownOrder,
            'orderNumber': 1,
            'status': 'report_attached',
          },
          {
            'id': otherOrder,
            'orderNumber': 2,
            'status': 'report_attached',
          },
        ],
      },
      '/labs/$allowedLab/staff' => {
        'staff':[
          {
            'accountId':'55555555-5555-4555-8555-555555555555',
            'email':'operador@laboratorio.invalid',
            'active':true,
            'canReviewReports':false,
          },
        ],
      },
      '/labs/$restrictedLab/staff' => {'staff':[]},
      '/labs/$restrictedLab/orders' => {'orders': []},
      '/labs/$restrictedLab/patients' => {
        'patients': [
          {'id': ownOrder, 'email': 'prueba@example.invalid', 'givenNames': 'Ana', 'familyNames': 'Prueba'},
        ],
        'hasMore': false,
      },
      _ => throw StateError('Ruta inesperada: $path'),
    };
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is InputDecorator && widget.decoration.labelText == label,
);


void main() {
  testWidgets('se recupera un PDF pendiente y no se crea orden sin validación', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final api=_StationApi()..showPending=true;
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home:SilPrincipalPage(
      api:api,role:'operador_laboratorio',
      onExpired:(){},onLogout:(){},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton,'Recibir solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar derivación pendiente'),findsOneWidget);
    final submit=find.widgetWithText(FilledButton,'Crear orden con solicitud');
    expect(tester.widget<FilledButton>(submit).onPressed,isNull);
    final stored=find.byWidgetPredicate((widget)=>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText=='Derivación pendiente guardada');
    await tester.ensureVisible(stored);
    await tester.tap(stored);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('derivacion-ejemplo.pdf').last);
    await tester.pumpAndSettle();
    expect(find.text('Datos identificatorios sugeridos por el PDF'),findsOneWidget);
    expect(find.text('Ana Prueba'),findsOneWidget);
    expect(find.text('Descargar derivación pendiente original'),findsOneWidget);
    expect(find.text('Referencia de solicitud'),findsNothing);
    final date=find.byWidgetPredicate((widget)=>widget is TextField &&
        widget.decoration?.labelText=='Fecha de solicitud médica (AAAA-MM-DD)');
    expect(tester.widget<TextField>(date).controller!.text,'2024-01-01');
    final invite = find.widgetWithText(OutlinedButton,'Emitir invitación de paciente');
    expect(tester.widget<OutlinedButton>(invite).onPressed, isNull,
      reason: 'Antes de invitar debe cotejarse la identidad.');
    final button = find.widgetWithText(FilledButton,'Crear orden con solicitud');
    expect(tester.widget<FilledButton>(button).onPressed, isNull,
      reason: 'La cuenta debe estar activada y el PDF cotejado.');
    expect(api.pendingCompletions, isEmpty);
    expect(tester.takeException(),isNull);
  });

  testWidgets('fecha médica propone hoy cuando el PDF pendiente carece de fecha legible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final api=_StationApi()..showPending=true..pendingWithoutDate=true;
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home:SilPrincipalPage(
      api:api,role:'operador_laboratorio',
      onExpired:(){},onLogout:(){},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton,'Recibir solicitud'));
    await tester.pumpAndSettle();
    final stored=find.byWidgetPredicate((widget)=>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText=='Derivación pendiente guardada');
    await tester.ensureVisible(stored);
    await tester.tap(stored);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('derivacion-ejemplo.pdf').last);
    await tester.pumpAndSettle();
    final date=find.byWidgetPredicate((widget)=>widget is TextField &&
      widget.decoration?.labelText=='Fecha de solicitud médica (AAAA-MM-DD)');
    final today=DateTime.now().toIso8601String().substring(0,10);
    expect(tester.widget<TextField>(date).controller!.text,today);
    expect(find.text('Referencia de solicitud'),findsNothing);
    expect(find.textContaining('Vitalia lo asigna automáticamente'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('desde derivación permite localizar paciente activado sin escribir UUID', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api=_StationApi();
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(
      home:SilPrincipalPage(
        api:api,role:'operador_laboratorio',
        onExpired:(){},onLogout:(){},
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);

    final requests=find.widgetWithText(TextButton,'Recibir solicitud');
    await tester.ensureVisible(requests);
    await tester.tap(requests);
    await tester.pumpAndSettle();

    expect(find.text('Paciente de esta derivación'),findsOneWidget);
    final invite=find.widgetWithText(OutlinedButton,'Emitir invitación de paciente');
    expect(invite,findsOneWidget);
    expect(tester.widget<OutlinedButton>(invite).onPressed,isNull,
      reason:'No se emiten invitaciones desde una derivación sin PDF.');
    final emailField=find.byWidgetPredicate((widget)=>
      widget is TextField && widget.decoration?.labelText=='Correo del paciente');
    await tester.ensureVisible(emailField);
    await tester.enterText(emailField,'prueba@example.invalid');
    await tester.pumpAndSettle();

    final search=find.widgetWithText(OutlinedButton,'Buscar paciente activado');
    await tester.ensureVisible(search);
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cuenta activada y vinculada'),findsOneWidget);
    // El identificador técnico queda en el estado del programa, no en el formulario.
    expect(find.text('Paciente encontrado en este laboratorio'), findsOneWidget);
    expect(find.text('Seleccionar paciente por identificador (avanzado)'), findsNothing);
    expect(find.text('UUID del paciente vinculado'), findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('órdenes manuales seleccionan paciente activo por nombre, nunca por UUID', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1050));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final api = _StationApi();
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home: SilPrincipalPage(
      api: api, role: 'operador_laboratorio',
      onExpired: (){}, onLogout: (){},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton,'Órdenes'));
    await tester.pumpAndSettle();
    expect(find.text('UUID del paciente vinculado'), findsNothing);
    final expansion = find.text('Crear orden sin derivación PDF');
    await tester.ensureVisible(expansion);
    await tester.tap(expansion);
    await tester.pumpAndSettle();
    final patientSelection = find.byWidgetPredicate((widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Paciente con cuenta activada');
    expect(patientSelection, findsOneWidget);
    expect(find.text('Buscar paciente por nombre o correo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('administración muestra operadores y autoriza revisión desde un botón', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final api=_StationApi();
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(
      home:SilPrincipalPage(
        api:api,role:'administrador',onExpired:(){},onLogout:(){},
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    // Un único panel administrativo en el SIL principal.
    expect(find.byTooltip('Abrir módulo original de Vitalia'),findsNothing);
    expect(find.text('Administración de laboratorios'),findsOneWidget);
    expect(find.text('Registrar laboratorio'),findsWidgets);
    expect(find.byType(NavigationRail),findsNothing);
    // La gestión de personas tiene una pestaña propia, sin perder sus acciones.
    await tester.tap(find.widgetWithText(TextButton,'Operadores y permisos'));
    await tester.pumpAndSettle();
    expect(find.text('Operadores y permisos de revisión'),findsOneWidget);
    expect(find.text('operador@laboratorio.invalid'),findsOneWidget);
    final authorize=find.widgetWithText(OutlinedButton,'Autorizar revisión');
    await tester.ensureVisible(authorize);
    await tester.tap(authorize);
    await tester.pumpAndSettle();
    expect(api.reviewActions,[
      {
        'accountId':'55555555-5555-4555-8555-555555555555',
        'enabled':true,
      }
    ]);
    expect(tester.takeException(),isNull);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('revisión incluye los informes propios del laboratorio a ${width.toInt()} px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _StationApi();
      addTearDown(api.close);

      await tester.pumpWidget(MaterialApp(
        home: SilPrincipalPage(
          api: api,
          role: 'operador_laboratorio',
          onExpired: () {},
          onLogout: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Panel del laboratorio'), findsOneWidget);
      final reviewTab = find.text('Revisión interna (2)');
      await tester.ensureVisible(reviewTab);
      await tester.tap(reviewTab);
      await tester.pumpAndSettle();
      final review = _field('Informe pendiente de revisión');
      expect(review, findsOneWidget);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.ancestor(
          of: review,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items?.map((item) => item.value), [
        _StationApi.ownOrder,
        _StationApi.otherOrder,
      ]);
      final reviewButton = find.widgetWithText(FilledButton, 'Publicar informe');
      expect(tester.widget<FilledButton>(reviewButton).onPressed, isNull);

      final laboratory = _field('Laboratorio');
      await tester.ensureVisible(laboratory);
      await tester.tap(laboratory);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laboratorio Sur').last);
      await tester.pumpAndSettle();
      expect(review, findsNothing);
      expect(reviewButton, findsNothing);
      final patientsTab = find.text('Pacientes');
      await tester.ensureVisible(patientsTab);
      await tester.tap(patientsTab);
      await tester.pumpAndSettle();
      expect(find.text('Directorio de pacientes'), findsOneWidget);
      expect(find.text('Ana Prueba'), findsOneWidget);
      expect(find.text('Emitir código de activación'), findsOneWidget);
      final requests = find.widgetWithText(TextButton, 'Recibir solicitud');
      await tester.ensureVisible(requests);
      await tester.tap(requests);
      await tester.pumpAndSettle();
      expect(find.text('Leer PDF y sugerir datos'), findsOneWidget);
      expect(find.text('Crear orden con solicitud'), findsOneWidget);
      final linkOrder = find.widgetWithText(SwitchListTile, 'Vincular a una orden existente');
      await tester.ensureVisible(linkOrder);
      await tester.tap(linkOrder);
      await tester.pumpAndSettle();
      expect(find.text('Registrar solicitud'), findsOneWidget);
      final clinicalTab = find.widgetWithText(TextButton, 'Muestras y resultados');
      await tester.ensureVisible(clinicalTab);
      await tester.tap(clinicalTab);
      await tester.pumpAndSettle();
      expect(_field('Orden para muestras y resultados'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
