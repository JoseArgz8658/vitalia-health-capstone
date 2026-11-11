import 'dart:convert';
import 'dart:typed_data';

import '../../core/auth_api.dart';
import '../documentos_reales/documento.dart';

class AtencionesApi {
  AtencionesApi(this.auth);
  final AuthApi auth;
  Future<Map<String, dynamic>> list({int offset = 0}) async {
    final r = await auth.careInboxRequest(offset: offset);
    return _json(r.body);
  }

  Future<Map<String, dynamic>> details(String id) async {
    final r = await auth.careInboxRequest(id: id);
    return _json(r.body);
  }

  Future<void> begin(String id, int revision) async {
    await auth.careInboxRequest(
      id: id,
      action: 'begin',
      body: {'expectedRevision': revision},
    );
  }

  Future<Map<String, dynamic>> referralOptions(
    String id, {
    int offset = 0,
  }) async {
    final r = await auth.careInboxRequest(
      id: id,
      action: 'referral-options',
      offset: offset,
    );
    return _json(r.body);
  }

  Future<Map<String, dynamic>> refer(
    String id,
    Map<String, dynamic> body,
  ) async {
    final r = await auth.careInboxRequest(
      id: id,
      action: 'referrals',
      body: body,
    );
    return _json(r.body);
  }

  Future<Uint8List> download(String id, Documento item) async {
    final r = await auth.careInboxRequest(id: id, action: 'file');
    if (r.bodyBytes.length != item.bytes ||
        r.bodyBytes.length > 10 * 1024 * 1024) {
      throw const AuthFailure('El archivo recibido está incompleto.');
    }
    return r.bodyBytes;
  }

  Map<String, dynamic> _json(String body) {
    try {
      return Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      throw const AuthFailure('El servidor devolvió una atención inválida.');
    }
  }
}
