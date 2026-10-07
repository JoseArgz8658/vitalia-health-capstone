import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';
import 'documento.dart';

class DocumentosApi {
  DocumentosApi(this.auth);
  final AuthApi auth;
  Future<List<Documento>> list({int offset = 0, int limit = 20}) async {
    final response = await auth.sendDocumentRequest(http.Request('GET',
      auth.documentUri('', {'limit': '$limit', 'offset': '$offset'})));
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['documents'] as List).map((item) =>
        Documento.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) { throw const AuthFailure('El servidor devolvió un historial inválido.'); }
  }
  Future<void> upload({required String nombre, required String tipo,
    required String fecha, required String archivo, required String mime,
    required Uint8List bytes}) async {
    if (!['application/pdf', 'image/jpeg', 'image/png'].contains(mime) ||
        bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const AuthFailure('Selecciona un PDF, JPEG o PNG de hasta 10 MiB.');
    }
    // Multipart acotado a tres campos y un archivo, sin dependencias nuevas.
    final random = Random.secure();
    final boundary = 'vitalia' + List.generate(24, (_) =>
      random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final data = BytesBuilder(copy: false);
    void add(String text) => data.add(utf8.encode(text));
    final fields = {'examName': nombre.trim(), 'examType': tipo, 'examDate': fecha};
    for (final field in fields.entries) {
      add('--$boundary\r\nContent-Disposition: form-data; name="${field.key}"\r\n\r\n${field.value}\r\n');
    }
    add('--$boundary\r\nContent-Disposition: form-data; name="file"; '
      'filename="document"; filename*=UTF-8\'\'${Uri.encodeComponent(archivo)}\r\n'
      'Content-Type: $mime\r\n\r\n');
    data.add(bytes);
    add('\r\n--$boundary--\r\n');
    final request = http.Request('POST', auth.documentUri());
    request.headers['Content-Type'] = 'multipart/form-data; boundary=$boundary';
    request.bodyBytes = data.takeBytes();
    await auth.sendDocumentRequest(request);
  }
  Future<Uint8List> download(Documento item) async {
    final response = await auth.sendDocumentRequest(http.Request('GET',
      auth.documentUri('${item.id}/file')));
    if (response.bodyBytes.length != item.bytes) {
      throw const AuthFailure('El archivo recibido está incompleto.');
    }
    return response.bodyBytes;
  }
}
