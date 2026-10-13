import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/features/documentos_reales/informe_fields.dart';

void main() {
  test('informe valida tipos y mantiene compatibilidad anterior', () {
    expect(informeValido(null), isTrue);
    final data = <String, dynamic>{for (final key in informeLabels.keys) key: null};
    expect(informeValido(data), isTrue);
    expect(informeValido({...data, 'nombre_paciente': 1}), isFalse);
    expect(informeValido({...data, 'extra': 'dato'}), isFalse);
  });
  testWidgets('datos del informe se muestran con procedencia explícita', (tester) async {
    final data = <String, dynamic>{for (final key in informeLabels.keys) key: null};
    data['nombre_paciente'] = 'Paciente ficticio';
    data['medico_solicitante'] = 'Solicitante ficticio';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: InformeFields(value: data)))));
    expect(find.text('Nombre completo del paciente: Paciente ficticio'), findsOneWidget);
    expect(find.text('Médico solicitante: Solicitante ficticio'), findsOneWidget);
    expect(find.textContaining('no se deducen de la cuenta'), findsOneWidget);
  });
}
