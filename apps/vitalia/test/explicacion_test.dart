import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/documentos_reales/explicacion_api.dart';
import 'package:vitalia_health/features/documentos_reales/explicacion_panel.dart';
const id='33333333-3333-4333-8333-333333333333';
final reviewed={'examen':'Ficticio','fecha':'29-09-2026','resultados':[{'nombre':'Indicador Alfa','valor':'0,00','unidad':null,'rango_referencia':null}]};
Map<String,dynamic> ready()=>{'status':'ready','approved':false,'generatedAt':'2026-10-01T18:00:00Z','explanation':{
 'exam':'Ficticio','date':'29-09-2026','approved':false,'notice':'No es un diagnóstico.',
 'items':[{'index':0,'name':'Indicador Alfa','value':'0,00','unit':null,'reference':null,'concept':'desconocido',
 'explanation':'No hay información suficiente para explicar este indicador.','source':null}]}};
http.Response response(Object value,[int status=200])=>http.Response(jsonEncode(value),status,headers:{'content-type':'application/json; charset=utf-8'});
Future<AuthApi> session(Future<http.Response> Function(http.Request) work)async{
 final auth=AuthApi(client:MockClient((req)async{
  if(req.url.path.endsWith('/login'))return response({'token':List.filled(64,'a').join(),'expiresAt':DateTime.now().add(const Duration(minutes:30)).toIso8601String()});
  if(req.url.path.endsWith('/me'))return response({'user':{'role':'paciente'}});
  expect(req.headers['Authorization'],'Bearer ${List.filled(64,'a').join()}');return work(req);
 }));await auth.login('p@example.com','clave ficticia');return auth;
}
Widget panel(AuthApi auth,{VoidCallback? expired})=>MaterialApp(home:Scaffold(body:SingleChildScrollView(child:
 ExplicacionPanel(auth:auth,documentId:id,reviewedExtraction:reviewed,onExpired:expired??(){}))));
Future<void> tap(WidgetTester tester,String label)async{
 final finder=find.text(label);await tester.ensureVisible(finder);await tester.pumpAndSettle();await tester.tap(finder);await tester.pumpAndSettle();
}
void main(){
 test('API usa GET/POST vacío con sesión, rechaza aprobación y origen ajeno',()async{
  var calls=0;final auth=await session((req)async{
   calls++;expect(req.url.path,'/api/documents/$id/assistant/explanation');if(req.method=='POST')expect(jsonDecode(req.body),{});return response(ready());
  });
  final api=ExplicacionApi(auth);expect((await api.consultar(id))['status'],'ready');await api.generar(id);
  await expectLater(auth.sendDocumentRequest(http.Request('POST',Uri.parse('https://example.com/api/documents/$id/assistant/explanation'))),throwsA(isA<AuthFailure>()));
  await expectLater(auth.sendDocumentRequest(http.Request('DELETE',auth.documentUri('$id/assistant/explanation'))),throwsA(isA<AuthFailure>()));
  expect(calls,2);auth.close();
 });
 testWidgets('consulta y generación explícitas; distingue explicación de aprobación', (tester)async{
  var done=false,posts=0;final auth=await session((req)async{
   if(req.method=='POST'){posts++;done=true;}return response(done?ready():{'status':'not_requested','approved':false,'explanation':null});
  });
  await tester.pumpWidget(panel(auth));expect(posts,0);
  await tap(tester,'Consultar explicación');await tap(tester,'Generar explicación');
  expect(posts,1);expect(find.text('No hay información suficiente para explicar este indicador.'),findsOneWidget);
  expect(find.text('Generar explicación'),findsNothing);expect(find.textContaining('no está aprobada por un profesional'),findsOneWidget);
  await tester.binding.setSurfaceSize(const Size(360,800));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  await tester.binding.setSurfaceSize(null);await tester.pumpWidget(const SizedBox());auth.close();
 });
 testWidgets('sin aprobación no ofrece generar', (tester)async{
  final auth=await session((_)async=>response({'status':'not_available','approved':false,'explanation':null}));
  await tester.pumpWidget(panel(auth));await tap(tester,'Consultar explicación');expect(find.text('Generar explicación'),findsNothing);
  expect(find.text('Se requiere una revisión profesional aprobada.'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());auth.close();
 });
 testWidgets('dato alterado no se presenta como explicación del examen', (tester)async{
  final bad=ready();bad['explanation']['items'][0]['value']='99';final auth=await session((_)async=>response(bad));
  await tester.pumpWidget(panel(auth));await tap(tester,'Consultar explicación');
  expect(find.text('No hay información suficiente para explicar este indicador.'),findsNothing);
  expect(find.text('La explicación no corresponde a los datos revisados disponibles.'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());auth.close();
 });
 testWidgets('consulta fallida borra explicación anterior y sesión vencida cierra acceso', (tester)async{
  var valid=true,expired=0;final auth=await session((_)async=>valid?response(ready()):response({},401));
  await tester.pumpWidget(panel(auth,expired:(){expired++;}));await tap(tester,'Consultar explicación');valid=false;
  await tap(tester,'Consultar explicación');expect(expired,1);expect(auth.hasSession,isFalse);
  expect(find.text('No hay información suficiente para explicar este indicador.'),findsNothing);
  await tester.pumpWidget(const SizedBox());auth.close();
 });
 test('API no acepta explicación marcada como aprobada',()async{
  final bad=ready();bad['explanation']['approved']=true;final auth=await session((_)async=>response(bad));
  await expectLater(ExplicacionApi(auth).consultar(id),throwsA(isA<AuthFailure>()));auth.close();
 });
}
