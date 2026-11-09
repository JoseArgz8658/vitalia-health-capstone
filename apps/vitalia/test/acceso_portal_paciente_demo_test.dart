import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/laboratorio/acceso_portal_paciente_demo.dart';

class _PortalOperatorApi extends AuthApi {
  final calls=<String>[];
  var invited=false;
  @override
  Future<Map<String,dynamic>> silPortalRequest(
    String path,{Map<String,dynamic>? body}
  )async{
    calls.add(path);
    if(path.endsWith('/invitations')){
      expect(body,{'contactConfirmed':true,'identityChecked':true});
      invited=true;
      return {
        'invitation':{'status':'invited','delivery':'simulated_outbox'},
        'handoffCode':'C'*12,
        'recipient':{
          'email':'nuevo@example.invalid',
          'givenNames':'Paciente','familyNames':'Ficticio',
          'birthDate':'1990-01-01','syntheticIdentifier':'DEMO-TEST',
        },
      };
    }
    return {
      'patient':{
        'id':'11111111-1111-4111-8111-111111111111',
        'email':'nuevo@example.invalid',
        'givenNames':'Paciente','familyNames':'Ficticio',
        'birthDate':'1990-01-01','syntheticIdentifier':'DEMO-TEST',
        'portalStatus':invited?'invited':'pending',
      },
      'canInvite':true,
    };
  }
}
void main(){
  testWidgets('destinatario explícito y doble confirmación antes de invitar',(
    tester,
  )async{
    tester.view.devicePixelRatio=1;
    tester.view.physicalSize=const Size(800,1040);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api=_PortalOperatorApi();
    await tester.pumpWidget(MaterialApp(
      home:Scaffold(body:SingleChildScrollView(
        padding:const EdgeInsets.all(16),
        child:AccesoPortalPacienteDemo(
          api:api,onExpired:(){},
          patientId:'11111111-1111-4111-8111-111111111111',
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Acceso al portal'),findsOneWidget);
    expect(find.text('Sin activar'),findsOneWidget);
    expect(find.text('Paciente Ficticio'),findsOneWidget);
    expect(find.text('nuevo@example.invalid'),findsOneWidget);
    expect(find.text('DEMO-TEST'),findsOneWidget);
    await tester.ensureVisible(find.text('Preparar invitación DEMO'));
    await tester.tap(find.text('Preparar invitación DEMO'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar destinatario'),findsOneWidget);
    expect(find.text('Generar invitación DEMO'),findsOneWidget);
    expect(api.calls.where((v)=>v.endsWith('/invitations')),isEmpty);
    final boxes=find.byType(CheckboxListTile);
    expect(boxes,findsNWidgets(2));
    for(var i=0;i<2;i++){
      final box=boxes.at(i);
      await tester.ensureVisible(box);
      await tester.tap(box);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Generar invitación DEMO'));
    await tester.tap(find.text('Generar invitación DEMO'));
    await tester.pumpAndSettle();
    expect(api.calls.where((v)=>v.endsWith('/invitations')),hasLength(1));
    expect(find.text('CLAVE DE ENTREGA PRESENCIAL'),findsOneWidget);
    expect(find.text('C'*12),findsOneWidget);
    expect(find.text('emailCode'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
