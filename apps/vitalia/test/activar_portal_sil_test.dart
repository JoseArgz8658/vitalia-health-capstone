import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/acceso/activar_portal_sil_page.dart';

class _DemoActivationApi extends AuthApi {
  final calls=<Map<String,dynamic>>[];
  @override
  Future<Map<String,dynamic>> silPortalPublic(
    String path,{Map<String,dynamic>? body}
  ) async {
    calls.add({'path':path,'body':body});
    if(path=='/portal/activate'){
      expect(body!['email'],'nuevo@example.invalid');
      expect(body['emailCode'],'a'*24);
      expect(body['handoffCode'],'b'*24);
      expect(body['password'],'UnaClaveSeguraNueva2026');
      expect(body['confirmedDetails'],true);
      return {'activated':true,'loginRequired':true};
    }
    return {'emailCode':'a'*24};
  }
}
void main(){
  testWidgets('activación guiada requiere dos códigos y contraseña',(
    tester,
  )async{
    tester.view.devicePixelRatio=1;
    tester.view.physicalSize=const Size(430,920);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api=_DemoActivationApi();
    await tester.pumpWidget(MaterialApp(
      home:ActivarPortalSilPage(api:api)));
    await tester.pumpAndSettle();
    expect(find.text('Activa tu acceso privado'),findsOneWidget);
    expect(find.text('Cuenta'),findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField,'Correo de contacto'),
      'nuevo@example.invalid');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Comprueba los dos canales'),findsOneWidget);
    expect(find.text('Paso A · Código de correo'),findsOneWidget);
    expect(find.text('Paso B · Clave entregada en el laboratorio'),findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField,'Código recibido por correo'),'a'*24);
    await tester.enterText(
      find.widgetWithText(TextField,'Clave de entrega presencial'),'b'*24);
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Tu acceso, tu contraseña'),findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField,'Nueva contraseña'),
      'UnaClaveSeguraNueva2026');
    await tester.enterText(
      find.widgetWithText(TextFormField,'Repetir contraseña'),
      'UnaClaveSeguraNueva2026');
    await tester.ensureVisible(find.text(
      'Confirmo que este acceso es para mi cuenta y que los datos proporcionados para la invitación me corresponden.'));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Activar mi cuenta'));
    await tester.tap(find.text('Activar mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Cuenta activada'),findsOneWidget);
    expect(api.calls.where((x)=>x['path']=='/portal/activate'),hasLength(1));
    expect(tester.takeException(),isNull);
  });
}
