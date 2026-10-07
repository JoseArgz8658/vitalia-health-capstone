import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/auth_api.dart';
import 'package:vitalia_health/features/documentos_reales/documento.dart';
import 'package:vitalia_health/features/documentos_reales/guardar_documento.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cl.vitalia/documents');
  const item = Documento(id: '22222222-2222-4222-8222-222222222222',
    nombre: 'Sintético', tipo: 'Laboratorio', fecha: '2026-01-01',
    archivo: 'sintetico.pdf', mime: 'application/pdf', bytes: 3);
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
  });
  test('Android envía bytes y metadatos al selector nativo', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveDocument');
        final data = call.arguments as Map;
        expect(data['name'], 'sintetico.pdf');
        expect(data['mime'], 'application/pdf');
        expect(data['bytes'], [1, 2, 3]);
        return true;
      });
    expect(descargaDisponible, true);
    expect(await guardarDocumento(item, Uint8List.fromList([1, 2, 3])), true);
  });
  test('cancelar el selector no indica descarga guardada', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => false);
    expect(await guardarDocumento(item, Uint8List.fromList([1, 2, 3])), false);
  });
  test('error nativo produce mensaje controlado', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'SAVE_FAILED'));
    await expectLater(guardarDocumento(item, Uint8List.fromList([1, 2, 3])),
      throwsA(isA<AuthFailure>()));
  });
}
