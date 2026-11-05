import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/perfil/medidas_panel.dart';

class MeasuresFake extends AuthApi {
  @override
  Future<Map<String, dynamic>> territories() async => {'version':'test','regions':[{'code':'13','name':'Metropolitana'}],'provinces':[{'code':'131','name':'Santiago','regionCode':'13'}],'communes':[{'code':'13101','name':'Santiago','provinceCode':'131'}]};
  final List<Map<String, dynamic>> saved = [];
  int failures = 0;
  @override
  Future<List<Map<String, dynamic>>> measurements() async => [];
  @override
  Future<Map<String, dynamic>> recordMeasurement(Map<String, dynamic> value) async {
    saved.add(Map<String, dynamic>.from(value));
    if (failures > 0) { failures--; throw const AuthFailure('Conexión interrumpida.'); }
    return {'id':value['requestId'],'measuredAt':value['measuredAt'],'weightKg':value['weightKg'],
      'heightCm':value['heightCm'],'source':'patient_reported'};
  }
}
void main() {
  testWidgets('medidas abre en consulta y registra peso opcional con coma', (tester) async {
    final api = MeasuresFake();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MedidasPanel(api: api, onExpired: () {})))));
    await tester.pumpAndSettle();expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Registrar medidas'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Peso en kg (opcional)'), '70,5');
    await tester.ensureVisible(find.text('Guardar medidas'));await tester.tap(find.text('Guardar medidas'));await tester.pumpAndSettle();
    expect(api.saved.single['weightKg'], 70.5);expect(api.saved.single['heightCm'], isNull);
    expect(find.byType(TextFormField), findsNothing);expect(find.textContaining('70.5 kg'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('cancelar medidas no envía datos y reintentar conserva identificador', (tester) async {
    final api = MeasuresFake()..failures = 1;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MedidasPanel(api: api, onExpired: () {})))));
    await tester.pumpAndSettle();await tester.tap(find.text('Registrar medidas'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Peso en kg (opcional)'), '70');
    await tester.ensureVisible(find.text('Cancelar registro'));await tester.tap(find.text('Cancelar registro'));await tester.pumpAndSettle();
    expect(api.saved, isEmpty);await tester.ensureVisible(find.text('Registrar medidas'));await tester.tap(find.text('Registrar medidas'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Peso en kg (opcional)'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Peso en kg (opcional)'), '71');
    await tester.ensureVisible(find.text('Guardar medidas'));await tester.tap(find.text('Guardar medidas'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar medidas'));await tester.tap(find.text('Guardar medidas'));await tester.pumpAndSettle();
    expect(api.saved.length, 2);expect(api.saved[0]['requestId'], api.saved[1]['requestId']);
    await tester.pumpWidget(const SizedBox());api.close();
  });
}

