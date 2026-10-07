import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/auth_api.dart';

class Asignacion {
  const Asignacion(this.id, this.patientEmail, this.professionalEmail, this.active);
  final String id;
  final String patientEmail;
  final String professionalEmail;
  final bool active;
  factory Asignacion.fromJson(Map<String, dynamic> data) => Asignacion(
    data['id'] as String, data['patientEmail'] as String,
    data['professionalEmail'] as String, data['active'] as bool);
}
class PacienteAsignado {
  const PacienteAsignado(this.id, this.email);
  final String id;
  final String email;
  factory PacienteAsignado.fromJson(Map<String, dynamic> data) =>
    PacienteAsignado(data['id'] as String, data['email'] as String);
}
class AsignacionesApi {
  AsignacionesApi(this.auth);
  final AuthApi auth;
  Future<Map<String, dynamic>> _send(http.Request request) async {
    final response = await auth.sendAssignmentRequest(request);
    try { return jsonDecode(response.body) as Map<String, dynamic>; }
    catch (_) { throw const AuthFailure('El servidor devolvió asignaciones inválidas.'); }
  }
  Future<List<Asignacion>> listar({int offset = 0}) async {
    final data = await _send(http.Request('GET', auth.assignmentUri('', {'limit': '20', 'offset': '$offset'})));
    try { return (data['assignments'] as List).map((item) => Asignacion.fromJson(item as Map<String, dynamic>)).toList(); }
    catch (_) { throw const AuthFailure('El servidor devolvió asignaciones inválidas.'); }
  }
  Future<List<PacienteAsignado>> pacientes({int offset = 0}) async {
    final data = await _send(http.Request('GET', auth.assignmentUri('', {'limit': '20', 'offset': '$offset'})));
    try { return (data['patients'] as List).map((item) => PacienteAsignado.fromJson(item as Map<String, dynamic>)).toList(); }
    catch (_) { throw const AuthFailure('El servidor devolvió pacientes inválidos.'); }
  }
  Future<void> asignar(String patientEmail, String professionalEmail) async {
    final request = http.Request('POST', auth.assignmentUri());
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({'patientEmail': patientEmail.trim(), 'professionalEmail': professionalEmail.trim()});
    await _send(request);
  }
  Future<void> desactivar(String id) async {
    final request = http.Request('POST', auth.assignmentUri('$id/deactivate'));
    request.headers['Content-Type'] = 'application/json';
    request.body = '{}';
    await _send(request);
  }
}
