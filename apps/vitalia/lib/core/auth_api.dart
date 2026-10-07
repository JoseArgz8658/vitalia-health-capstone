import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthFailure implements Exception {
  const AuthFailure(this.message, [this.status]);
  final String message;
  final int? status;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = Uri.parse(baseUrl ?? const String.fromEnvironment(
          'VITALIA_API_URL', defaultValue: 'http://127.0.0.1:3000'));
  final http.Client _client;
  final Uri _base;
  String? _token;
  DateTime? expiresAt;
  bool get hasSession => _token != null;
  void clear() { _token = null; expiresAt = null; }
  void close() { clear(); _client.close(); }

  Uri documentUri([String suffix = '', Map<String, String>? query]) {
    if (suffix.isNotEmpty && !RegExp(r'^[a-f0-9-]{36}/(file|processing|review|explanation|assistant(?:/explanation)?)$').hasMatch(suffix)) {
      throw const AuthFailure('Documento inválido.');
    }
    return _base.resolve('/api/documents${suffix.isEmpty ? '' : '/$suffix'}')
      .replace(queryParameters: query);
  }

  Future<http.Response> sendDocumentRequest(http.BaseRequest request) async {
    final token = _token;
    if (token == null || expiresAt == null || !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    if (request.url.origin != _base.origin ||
        !(request.url.path == '/api/documents' ||
          RegExp(r'^/api/documents/[a-f0-9-]{36}/(file|processing|review|explanation|assistant(?:/explanation)?)$').hasMatch(request.url.path))) {
      throw const AuthFailure('Solicitud de documento inválida.');
    }
    if (request.url.path.endsWith('/review') && request.method != 'GET') {
      throw const AuthFailure('La revisión del paciente es solo de consulta.');
    }
    if ((request.url.path.endsWith('/explanation') || request.url.path.endsWith('/assistant')) && !['GET', 'POST'].contains(request.method)) {
      throw const AuthFailure('Solicitud de explicación inválida.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(Duration(seconds: (request.url.path.endsWith('/explanation') || request.url.path.endsWith('/assistant')) ? 150 : 60));
      if (_token != token) throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        final message = switch (response.statusCode) {
          400 => request.url.path.contains('/assistant') ? 'Pregunta o examen fuera de los límites del asistente.' : 'Revisa el archivo y los datos del examen.',
          403 => 'No tienes permiso para acceder a estos documentos.',
          404 => 'Documento no disponible.',
          409 => request.url.path.contains('/assistant') ? 'Comprueba la revisión aprobada y el límite de treinta preguntas. Actualiza antes de repetir.' : 'Primero se requiere una revisión profesional aprobada.',
          413 => 'El archivo supera 10 MiB.',
          503 => request.url.path.contains('/assistant') ? 'El asistente está ocupado o la respuesta no fue aceptada. Actualiza antes de repetir.' : 'El servicio está ocupado. Intenta nuevamente.',
          _ => 'No se pudo completar la solicitud.',
        };
        throw AuthFailure(message, response.statusCode);
      }
      return response;
    } on AuthFailure { rethrow; }
    on TimeoutException {
      throw AuthFailure(request.url.path.contains('/assistant')
        ? 'El asistente tardó demasiado. Actualiza la conversación antes de repetir.'
        : 'La solicitud tardó demasiado. Actualiza el historial antes de repetir una carga.');
    } catch (_) {
      throw AuthFailure(request.url.path.contains('/assistant')
        ? 'No se pudo conectar con el asistente. Actualiza la conversación antes de repetir.'
        : 'No se pudo conectar. Si estabas subiendo un archivo, actualiza el historial antes de repetir.');
    }
  }

  Uri assignmentUri([String suffix = '', Map<String, String>? query]) {
    if (suffix.isNotEmpty && !RegExp(r'^[a-f0-9-]{36}/deactivate$').hasMatch(suffix)) {
      throw const AuthFailure('Asignación inválida.');
    }
    return _base.resolve('/api/assignments${suffix.isEmpty ? '' : '/$suffix'}')
      .replace(queryParameters: query);
  }

  Future<http.Response> sendAssignmentRequest(http.Request request) async {
    final token = _token;
    if (token == null || expiresAt == null || !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    if (request.url.origin != _base.origin ||
        !['GET', 'POST'].contains(request.method) ||
        !(request.url.path == '/api/assignments' ||
          RegExp(r'^/api/assignments/[a-f0-9-]{36}/deactivate$').hasMatch(request.url.path))) {
      throw const AuthFailure('Solicitud de asignación inválida.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await (() async {
        return http.Response.fromStream(await _client.send(request));
      })().timeout(const Duration(seconds: 15));
      if (_token != token) throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          400 => 'Revisa los correos y la solicitud.',
          403 => 'No tienes permiso para gestionar estas asignaciones.',
          404 => 'Cuenta o asignación no disponible. Comprueba los correos y sus roles.',
          _ => 'No se pudo completar la solicitud.',
        }, response.statusCode);
      }
      return response;
    } on AuthFailure { rethrow; }
    on TimeoutException {
      throw const AuthFailure('La solicitud tardó demasiado. Actualiza la lista antes de repetir.');
    } catch (_) {
      throw const AuthFailure('No se pudo conectar. Actualiza la lista antes de repetir.');
    }
  }

  Uri professionalUri(String patientId, {String? documentId, String? action,
      Map<String, String>? query}) {
    final identifier = RegExp(r'^[a-f0-9-]{36}$');
    if (!identifier.hasMatch(patientId) ||
        (documentId != null && (!identifier.hasMatch(documentId) ||
          !['file', 'extraction'].contains(action))) ||
        (documentId == null && action != null)) {
      throw const AuthFailure('Solicitud profesional inválida.');
    }
    return _base.resolve('/api/professional/patients/$patientId/documents'
      '${documentId == null ? '' : '/$documentId/$action'}').replace(queryParameters: query);
  }

  Future<http.Response> sendProfessionalRequest(http.Request request) async {
    final token = _token;
    if (token == null || expiresAt == null || !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    if (request.url.origin != _base.origin || request.method != 'GET' ||
        !RegExp(r'^/api/professional/patients/[a-f0-9-]{36}/documents(?:/[a-f0-9-]{36}/(?:file|extraction))?$')
          .hasMatch(request.url.path)) {
      throw const AuthFailure('Solicitud profesional inválida.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await (() async {
        return http.Response.fromStream(await _client.send(request));
      })().timeout(const Duration(seconds: 60));
      if (_token != token) throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          403 => 'No tienes permiso para consultar estos exámenes.',
          404 => 'Paciente o documento no disponible. Comprueba tus asignaciones.',
          503 => 'Las descargas están ocupadas. Intenta nuevamente.',
          _ => 'No se pudo consultar el documento.',
        }, response.statusCode);
      }
      return response;
    } on AuthFailure { rethrow; }
    on TimeoutException { throw const AuthFailure('La consulta tardó demasiado. Intenta nuevamente.'); }
    catch (_) { throw const AuthFailure('No se pudo conectar con el servidor.'); }
  }

  Uri reviewUri(String patientId, String documentId) {
    final identifier = RegExp(r'^[a-f0-9-]{36}$');
    if (!identifier.hasMatch(patientId) || !identifier.hasMatch(documentId)) {
      throw const AuthFailure('Revisión inválida.');
    }
    return _base.resolve('/api/professional/patients/$patientId/documents/$documentId/review');
  }

  Future<http.Response> sendReviewRequest(http.Request request) async {
    final token = _token;
    if (token == null || expiresAt == null || !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    if (request.url.origin != _base.origin || !['GET', 'POST'].contains(request.method) ||
        !RegExp(r'^/api/professional/patients/[a-f0-9-]{36}/documents/[a-f0-9-]{36}/review$')
          .hasMatch(request.url.path)) {
      throw const AuthFailure('Solicitud de revisión inválida.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await (() async {
        return http.Response.fromStream(await _client.send(request));
      })().timeout(const Duration(seconds: 15));
      if (_token != token) throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          400 => 'Revisa la fecha, los resultados, las observaciones y la confirmación.',
          403 => 'No tienes permiso para revisar este documento.',
          404 => 'Paciente o documento no disponible. Comprueba tus asignaciones.',
          409 => 'Ya existe una revisión o cambió el procesamiento. Actualiza la revisión.',
          413 => 'La revisión supera el tamaño permitido.',
          _ => 'No se pudo guardar o consultar la revisión. Actualiza antes de repetir.',
        }, response.statusCode);
      }
      return response;
    } on AuthFailure { rethrow; }
    on TimeoutException { throw const AuthFailure('La solicitud tardó demasiado. Actualiza la revisión antes de repetir.'); }
    catch (_) { throw const AuthFailure('No se pudo conectar. Actualiza la revisión antes de repetir.'); }
  }

  Future<Map<String, dynamic>> _request(String path,
      {Map<String, String>? body, bool get = false}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
    try {
      final uri = _base.resolve('/api/auth/$path');
      final response = await (get
          ? _client.get(uri, headers: headers)
          : _client.post(uri, headers: headers, body: jsonEncode(body ?? {})))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        if (path != 'login') clear();
        throw AuthFailure(path == 'login' ? 'Correo o contraseña incorrectos.'
            : 'La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode == 429) {
        throw const AuthFailure('Espera antes de volver a intentar.', 429);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure('No se pudo completar la solicitud. Intenta nuevamente.',
            response.statusCode);
      }
      if (response.statusCode == 204) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure { rethrow; }
    on TimeoutException { throw const AuthFailure('El servidor tardó demasiado en responder.'); }
    catch (_) { throw const AuthFailure('No se pudo conectar con el servidor.'); }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    clear();
    try {
      final data = await _request('login', body: {'email': email.trim(), 'password': password});
      _token = data['token'] as String;
      expiresAt = DateTime.parse(data['expiresAt'] as String);
      if (!expiresAt!.isAfter(DateTime.now())) throw const AuthFailure('La sesión terminó.');
      return await me();
    } catch (_) { clear(); rethrow; }
  }
  Future<Map<String, dynamic>> me() async {
    final data = await _request('me', get: true);
    final user = data['user'] as Map<String, dynamic>;
    if (!['paciente', 'profesional', 'administrador'].contains(user['role'])) {
      clear();
      throw const AuthFailure('La cuenta no tiene un rol autorizado.');
    }
    return user;
  }
  Future<void> register(String email, String password) async {
    await _request('register', body: {'email': email.trim(), 'password': password});
  }
  Future<void> logout() async {
    try { await _request('logout'); } finally { clear(); }
  }
}

