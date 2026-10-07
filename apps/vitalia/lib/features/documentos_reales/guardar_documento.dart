import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import '../../core/auth_api.dart';
import 'documento.dart';

bool get descargaDisponible => kIsWeb ||
  [TargetPlatform.android, TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux].contains(defaultTargetPlatform);

Future<bool> guardarDocumento(Documento item, Uint8List bytes) async {
  final file = XFile.fromData(bytes, name: item.archivo, mimeType: item.mime);
  if (kIsWeb) {
    await file.saveTo(item.archivo);
    return true;
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      return await const MethodChannel('cl.vitalia/documents')
        .invokeMethod<bool>('saveDocument', {
          'bytes': bytes, 'name': item.archivo, 'mime': item.mime,
        }) ?? false;
    } on MissingPluginException {
      throw const AuthFailure('La descarga Android requiere preparar la plataforma '
        'y reiniciar la aplicación.');
    } on PlatformException {
      throw const AuthFailure('No se pudo guardar el documento en Android.');
    }
  }
  if (!descargaDisponible) {
    throw const AuthFailure('La descarga aún no está disponible en este dispositivo.');
  }
  final location = await getSaveLocation(suggestedName: item.archivo);
  if (location == null) return false;
  await file.saveTo(location.path);
  return true;
}
