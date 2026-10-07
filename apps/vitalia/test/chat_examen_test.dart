import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/documentos_reales/chat_examen_api.dart';
import 'package:vitalia_health/features/documentos_reales/chat_examen_panel.dart';
const id='33333333-3333-4333-8333-333333333333';
final reviewed={'examen':'Hemograma','fecha':'29-09-2026','resultados':[{'nombre':'Hemoglobina','valor':'14,2','unidad':'g/dL','rango_referencia':null}]};
http.Response response(Object value,[int status=200])=>http.Response(jsonEncode(value),status,headers:{'content-type':'application/json; charset=utf-8'});
Map<String,dynamic> turn(String requestId,{String kind='education'})=>{'id':requestId,'mode':'chat','question':'¿Qué es hemoglobina?','status':'ready','approved':false,
 'response':{'kind':kind,'answer':kind=='restricted'?'No doy tratamientos.':'La hemoglobina transporta oxígeno.','indices':[0],'definitions':[]}};
Map<String,dynamic> history(List<Map<String,dynamic>> turns)=>{'status':'available','approved':false,'notice':'IA puede equivocarse.','turns':turns};
Future<AuthApi> session(Future<http.Response> Function(http.Request) work)async{
 final token=List.filled(64,'a').join();final auth=AuthApi(client:MockClient((req)async{
  if(req.url.path.endsWith('/login'))return response({'token':token,'expiresAt':DateTime.now().add(const Duration(minutes:30)).toIso8601String()});
  if(req.url.path.endsWith('/me'))return response({'user':{'role':'paciente'}});
  expect(req.headers['Authorization'],'Bearer $token');return work(req);
 }));await auth.login('p@example.com','clave ficticia');return auth;
}
Widget panel(AuthApi auth,{VoidCallback? expired})=>MaterialApp(home:Scaffold(body:SingleChildScrollView(child:ChatExamenPanel(auth:auth,documentId:id,reviewedExtraction:reviewed,onExpired:expired??(){}))));
Future<void> tap(WidgetTester tester,String text)async{final finder=find.text(text);await tester.ensureVisible(finder);await tester.pumpAndSettle();await tester.tap(finder);await tester.pumpAndSettle();}
void main(){
 test('UUIDs distintos y API solo envía pregunta y requestId al documento fijado',()async{
  expect(nuevaSolicitudChat(),isNot(nuevaSolicitudChat()));final requestId=nuevaSolicitudChat();
  final auth=await session((req)async{
   expect(req.url.path,'/api/documents/$id/assistant');final body=jsonDecode(req.body) as Map<String,dynamic>;
   expect(body.keys.toSet(),{'requestId','question'});expect(body['requestId'],requestId);return response({'turn':turn(requestId)});
  });
  expect((await ChatExamenApi(auth).preguntar(id,requestId,'¿Qué es hemoglobina?'))['status'],'ready');
  await expectLater(auth.sendDocumentRequest(http.Request('POST',Uri.parse('https://example.com/api/documents/$id/assistant'))),throwsA(isA<AuthFailure>()));auth.close();
 });
 testWidgets('abre historial, envía pregunta y distingue datos revisados de respuesta IA',(tester)async{
  final turns=<Map<String,dynamic>>[];final auth=await session((req)async{
   if(req.method=='GET')return response(history(turns));final body=jsonDecode(req.body);final value=turn(body['requestId']);turns.add(value);return response({'turn':value});
  });
  await tester.pumpWidget(panel(auth));await tap(tester,'Abrir conversación');
  await tester.enterText(find.byType(TextField),'¿Qué es hemoglobina?');await tap(tester,'Enviar pregunta');
  expect(find.text('La hemoglobina transporta oxígeno.'),findsOneWidget);
  expect(find.text('Dato revisado: Hemoglobina — 14,2 g/dL'),findsOneWidget);
  expect(find.text('Respuesta de IA, sin aprobación profesional'),findsOneWidget);
  await tester.binding.setSurfaceSize(const Size(360,800));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  await tester.binding.setSurfaceSize(null);await tester.pumpWidget(const SizedBox());auth.close();
 });
 testWidgets('respuesta perdida conserva requestId al actualizar y repetir',(tester)async{
  String? requestId;var posts=0;final auth=await session((req)async{
   if(req.method=='GET')return response(history(requestId==null?[]:[turn(requestId!)]));
   final body=jsonDecode(req.body);posts++;
   if(requestId==null){requestId=body['requestId'];throw Exception('conexión perdida');}
   expect(body['requestId'],requestId);return response({'turn':turn(requestId!)});
  });
  await tester.pumpWidget(panel(auth));await tap(tester,'Abrir conversación');
  await tester.enterText(find.byType(TextField),'¿Qué es hemoglobina?');await tap(tester,'Enviar pregunta');
  await tap(tester,'Actualizar conversación');await tap(tester,'Enviar pregunta');
  expect(posts,2);expect(find.text('La hemoglobina transporta oxígeno.'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());auth.close();
 });
 testWidgets('revocación oculta conversación y formulario',(tester)async{
  var allowed=true;final auth=await session((_)async=>allowed?response(history([turn(nuevaSolicitudChat())])):response({},404));
  await tester.pumpWidget(panel(auth));await tap(tester,'Abrir conversación');allowed=false;await tap(tester,'Actualizar conversación');
  expect(find.text('La hemoglobina transporta oxígeno.'),findsNothing);expect(find.byType(TextField),findsNothing);
  await tester.pumpWidget(const SizedBox());auth.close();
 });
 testWidgets('401 llama al cierre y retira datos',(tester)async{
  var expired=0;final auth=await session((_)async=>response({},401));await tester.pumpWidget(panel(auth,expired:(){expired++;}));await tap(tester,'Abrir conversación');
  expect(expired,1);expect(auth.hasSession,isFalse);expect(find.byType(TextField),findsNothing);
  await tester.pumpWidget(const SizedBox());auth.close();
 });
 testWidgets('referencia a otro índice de examen no se presenta',(tester)async{
  final bad=turn(nuevaSolicitudChat());bad['response']['indices']=[1];final auth=await session((_)async=>response(history([bad])));
  await tester.pumpWidget(panel(auth));await tap(tester,'Abrir conversación');
  expect(find.text('La hemoglobina transporta oxígeno.'),findsNothing);expect(find.byType(TextField),findsNothing);
  await tester.pumpWidget(const SizedBox());auth.close();
 });
 test('no acepta turnos aprobados por IA',()async{
  final bad=turn(nuevaSolicitudChat())..['approved']=true;final auth=await session((_)async=>response(history([bad])));
  await expectLater(ChatExamenApi(auth).consultar(id),throwsA(isA<AuthFailure>()));auth.close();
 });
}
