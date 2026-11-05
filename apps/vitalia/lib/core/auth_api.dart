import 'assistant_failure_message.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthFailure implements Exception {
  const AuthFailure(this.message, [this.status]);
  final String message;
  final int? status;
}

class ProfessionalPasswordSetupRequired extends AuthFailure {
  const ProfessionalPasswordSetupRequired(this.token)
    : super('Configura tu contraseña profesional para continuar.');
  final String token;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _base = Uri.parse(
        baseUrl ??
            const String.fromEnvironment(
              'VITALIA_API_URL',
              defaultValue: 'http://127.0.0.1:3000',
            ),
      );
  final http.Client _client;
  final Uri _base;
  String? _token;
  DateTime? expiresAt;
  bool get hasSession => _token != null;
  void clear() {
    _token = null;
    expiresAt = null;
  }

  void close() {
    clear();
    _client.close();
  }

  Future<Map<String, dynamic>?> profile({Map<String, dynamic>? update}) async {
    final data = await _profileRequest(update: update);
    return data['profile'] as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> territories() => _profileRequest(catalog: true);
  Future<List<Map<String, dynamic>>> measurements() async {
    final data = await _profileRequest(measures: true);
    return (data['measurements'] as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
  }

  Future<Map<String, dynamic>> recordMeasurement(
    Map<String, dynamic> value,
  ) async {
    final data = await _profileRequest(measures: true, update: value);
    return Map<String, dynamic>.from(data['measurement'] as Map);
  }

  Future<Map<String, dynamic>> _profileRequest({
    bool measures = false,
    bool catalog = false,
    Map<String, dynamic>? update,
  }) async {
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    try {
      final uri = _base.resolve(
        catalog
            ? '/api/profile/territories'
            : measures
            ? '/api/profile/measurements'
            : '/api/profile',
      );
      final response =
          await (update == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(update),
                    ))
              .timeout(const Duration(seconds: 15));
      if (_token != token) throw const AuthFailure('La sesión cambió.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          400 =>
            measures
                ? 'Ingresa peso en kg o altura en cm, mayores que cero, y una fecha que no sea futura.'
                : 'Revisa los nombres, la fecha y el dígito verificador del RUT.',
          403 => 'Esta cuenta no tiene acceso a este perfil.',
          409 =>
            measures
                ? 'Guarda primero tus datos personales. Si ya lo hiciste, actualiza el historial antes de repetir.'
                : 'El perfil cambió o no se pudo guardar la identificación. Actualiza y revisa los datos. Un RUT registrado no se puede dejar vacío.',
          503 =>
            catalog
                ? 'El catálogo de ubicación aún no está disponible. Puedes conservar la ubicación actual e intentar después.'
                : 'El perfil aún no está disponible. Revisa con el equipo la migración y sus permisos.',
          _ => 'No se pudo guardar o consultar el perfil.',
        }, response.statusCode);
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La consulta tardó demasiado. Actualiza antes de repetir el guardado.',
      );
    } catch (_) {
      throw const AuthFailure(
        'No se pudo consultar el perfil. Intenta nuevamente.',
      );
    }
  }

  Future<Map<String, dynamic>> institutionTerritories() =>
      _institutionRequest('/territories');
  Future<List<Map<String, dynamic>>> institutions({
    String? clinicId,
    int offset = 0,
  }) async {
    final suffix = clinicId == null
        ? ''
        : '/${_institutionId(clinicId)}/branches';
    final data = await _institutionRequest(suffix, offset: offset);
    return (data['items'] as List)
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createInstitution(
    Map<String, dynamic> value, {
    String? clinicId,
  }) async {
    final data = await _institutionRequest(
      clinicId == null ? '' : '/${_institutionId(clinicId)}/branches',
      update: value,
    );
    return Map<String, dynamic>.from(data['item'] as Map);
  }

  String _institutionId(String id) {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id))
      throw const AuthFailure('Institución inválida.');
    return id;
  }

  Future<Map<String, dynamic>> _institutionRequest(
    String suffix, {
    int? offset,
    Map<String, dynamic>? update,
  }) async {
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final uri = _base
          .resolve('/api/institutions$suffix')
          .replace(
            queryParameters: offset == null
                ? null
                : {'limit': '20', 'offset': '$offset'},
          );
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response =
          await (update == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(update),
                    ))
              .timeout(const Duration(seconds: 15));
      if (_token != token) throw const AuthFailure('La sesión cambió.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400)
        throw AuthFailure(switch (response.statusCode) {
          400 => 'Revisa el nombre, contacto, dirección y comuna.',
          403 => 'Esta cuenta no puede gestionar instituciones.',
          404 => 'La clínica ya no está disponible. Actualiza la lista.',
          409 => 'La clínica está inactiva o la solicitud cambió. Actualiza antes de repetir.',
          503 => 'La gestión institucional aún no está disponible. Revisa migración y permisos con el equipo.',
          _ => 'No se pudo completar la gestión institucional.',
        }, response.statusCode);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La solicitud tardó demasiado. Reintenta el mismo formulario para evitar duplicados.',
      );
    } catch (_) {
      throw const AuthFailure(
        'No se pudo conectar. Conserva el formulario y reintenta.',
      );
    }
  }

  String get invitationActivationUrl {
    const configured = String.fromEnvironment('VITALIA_WEB_URL');
    final base = configured.isNotEmpty
        ? Uri.parse(configured)
        : (['http', 'https'].contains(Uri.base.scheme)
              ? Uri.base
              : Uri.parse('http://localhost:5173'));
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/',
      fragment: '/activar-invitacion',
    ).toString();
  }

  Future<Map<String, dynamic>> onboarding(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final activation = path == '/activate';
    if (!activation &&
        path != '/context' &&
        path != '/accept' &&
        path != '/professional-password' &&
        !RegExp(
          r'^/[a-f0-9-]{36}(?:/(?:authorizations(?:/[a-f0-9-]{36}/(?:verify|revoke))?|specialties|invitations(?:/[a-f0-9-]{36}/revoke)?))?$',
        ).hasMatch(path)) {
      throw const AuthFailure('Solicitud institucional inválida.');
    }
    final token = _token;
    if (!activation &&
        (token == null ||
            expiresAt == null ||
            !expiresAt!.isAfter(DateTime.now()))) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final uri = _base.resolve('/api/onboarding$path');
      final headers = {
        'Content-Type': 'application/json',
        if (!activation) 'Authorization': 'Bearer $token',
      };
      final response =
          await (body == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 30));
      if (!activation && (_token != token || response.statusCode == 401)) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = (data['error'] as Map?)?['code'];
        throw AuthFailure(
          code == 'PASSWORD_REUSED'
              ? 'La contraseña profesional debe ser diferente a la de paciente.'
              : code == 'CURRENT_PASSWORD_INVALID'
              ? 'La contraseña actual no es correcta.'
              : code == 'PROFESSIONAL_PASSWORD_REQUIRED'
              ? 'Ingresa y confirma una nueva contraseña profesional de al menos 12 caracteres.'
              : code == 'PROFESSIONAL_PASSWORD_EXISTS'
              ? 'Ya tienes contraseña profesional. Ingresa con tu perfil profesional para aceptar otra clínica.'
              : code == 'INVITATION_ACCOUNT_MISMATCH'
              ? 'La invitación no corresponde a la cuenta con la que ingresaste.'
              : code == 'EXISTING_ACCOUNT'
              ? 'El correo ya tiene una cuenta. No se modificó su contraseña ni su rol. Solicita al equipo la incorporación de esa cuenta.'
              : switch (response.statusCode) {
                  400 =>
                    activation
                        ? 'Revisa el código, nombres y contraseña. El código puede estar vencido, revocado o utilizado.'
                        : 'Revisa los datos y las sucursales o especialidades seleccionadas.',
                  403 => 'Solo el administrador o el jefe autorizado de esta clínica pueden realizar esta operación.',
                  409 => 'La autorización o invitación no está disponible. Actualiza antes de repetir; revoca la invitación anterior si necesitas emitir otra.',
                  429 => 'Hay otra activación en curso. Espera un momento e intenta nuevamente.',
                  503 => 'La incorporación institucional aún no está disponible. Revisa migración y permisos con el equipo.',
                  _ => 'No se pudo completar la incorporación institucional.',
                },
          response.statusCode,
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La solicitud tardó demasiado. Actualiza antes de repetir. Si se creó una invitación y perdiste su código, revócala antes de emitir otra.',
      );
    } catch (_) {
      throw const AuthFailure(
        'No se pudo conectar. Actualiza antes de repetir la solicitud.',
      );
    }
  }

  Future<Map<String, dynamic>> team(
    String clinicId, {
    String? memberId,
    bool history = false,
    int offset = 0,
    Map<String, dynamic>? update,
  }) async {
    final clinic = _institutionId(clinicId);
    final member = memberId == null ? null : _institutionId(memberId);
    if ((history && member == null) ||
        (update != null && (member == null || history)) ||
        (member != null && !history && update == null)) {
      throw const AuthFailure('Solicitud de equipo inválida.');
    }
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final path =
          '/api/team/$clinic${member == null ? '' : '/$member'}${history ? '/history' : ''}';
      final uri = _base
          .resolve(path)
          .replace(
            queryParameters: update == null
                ? {'limit': '20', 'offset': '$offset'}
                : null,
          );
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response =
          await (update == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(update),
                    ))
              .timeout(const Duration(seconds: 15));
      if (_token != token || response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = (data['error'] as Map?)?['code'];
        throw AuthFailure(
          code == 'NO_MEMBERSHIP_CHANGE'
              ? 'No hiciste cambios en la pertenencia.'
              : switch (response.statusCode) {
                  400 => 'Revisa el motivo y las sucursales o especialidades seleccionadas.',
                  403 => 'Solo el jefe activo de esta clínica puede modificar pertenencias de profesionales ordinarios.',
                  404 => 'La pertenencia no está disponible en esta clínica.',
                  409 => 'La pertenencia cambió o la clínica no está disponible. Actualiza la lista antes de editar nuevamente.',
                  503 => 'La gestión del equipo aún no está disponible. Revisa migración y permisos con el equipo.',
                  _ => 'No se pudo completar la gestión del equipo.',
                },
          response.statusCode,
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La solicitud tardó demasiado. Reintenta el mismo formulario para comprobar el resultado sin duplicar cambios, o actualiza la lista.',
      );
    } catch (_) {
      throw const AuthFailure(
        'No se pudo conectar. Conserva el formulario para reintentar o actualiza la lista.',
      );
    }
  }

  Future<Map<String, dynamic>> professionalCredentials(
    String clinicId,
    String memberId, {
    String? requestId,
    Map<String, dynamic>? body,
  }) async {
    final clinic = _institutionId(clinicId), member = _institutionId(memberId);
    if (requestId != null) _institutionId(requestId);
    if (requestId != null && body == null)
      throw const AuthFailure('Solicitud inválida.');
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final path =
          '/api/professional-credentials/$clinic/$member${body == null
              ? ''
              : requestId == null
              ? '/requests'
              : '/requests/$requestId/decision'}';
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response =
          await (body == null
                  ? _client.get(_base.resolve(path), headers: headers)
                  : _client.post(
                      _base.resolve(path),
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 20));
      if (_token != token || response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400)
        throw AuthFailure(switch (response.statusCode) {
          400 =>
            'Revisa las referencias, la fecha de consulta y la confirmación.',
          403 => 'No tienes permiso para esta verificación. El jefe registra antecedentes y el administrador decide.',
          404 =>
            'La solicitud o pertenencia no está disponible en esta clínica.',
          409 => 'El perfil cambió, existe una solicitud pendiente o ya fue resuelta. Actualiza antes de continuar.',
          503 => 'La verificación profesional aún no está disponible. Revisa migración y permisos con el equipo.',
          _ => 'No se pudo completar la verificación profesional.',
        }, response.statusCode);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La solicitud tardó demasiado. Reintenta sin cambiar los datos o actualiza para comprobar el resultado.',
      );
    } catch (_) {
      throw const AuthFailure(
        'No se pudo conectar. Conserva los datos para reintentar.',
      );
    }
  }

  Future<http.Response> careInboxRequest({
    String? id,
    String? action,
    int offset = 0,
    Map<String, dynamic>? body,
  }) async {
    if ((id != null && !RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) ||
        (action != null &&
            ![
              'file',
              'begin',
              'review',
              'referral-options',
              'referrals',
            ].contains(action)) ||
        (action != null && id == null) ||
        (['begin', 'referrals'].contains(action) && body == null) ||
        (!['begin', 'review', 'referrals'].contains(action) && body != null)) {
      throw const AuthFailure('Solicitud de atención inválida.');
    }
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    final uri = _base
        .resolve(
          '/api/care-inbox${id == null ? '' : '/$id'}${action == null ? '' : '/$action'}',
        )
        .replace(
          queryParameters: id == null || action == 'referral-options'
              ? {'offset': '$offset'}
              : null,
        );
    try {
      final response =
          await (body == null
                  ? _client.get(
                      uri,
                      headers: {'Authorization': 'Bearer $token'},
                    )
                  : _client.post(
                      uri,
                      headers: {
                        'Authorization': 'Bearer $token',
                        'Content-Type': 'application/json',
                      },
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 60));
      if (_token != token) throw const AuthFailure('La sesión cambió.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400)
        throw AuthFailure(switch (response.statusCode) {
          400 =>
            action == 'referrals'
                ? 'Revisa el destinatario, el motivo y la confirmación.'
                : 'Revisa fechas, resultados, observaciones y confirmación del original.',
          403 => 'Ingresa en modo profesional para consultar tus atenciones.',
          404 => 'Esta atención ya no está disponible para tu cuenta. Actualiza la bandeja.',
          409 => 'La atención cambió. Actualiza antes de continuar.',
          503 =>
            'La bandeja no está disponible temporalmente. Intenta nuevamente.',
          _ => 'No se pudo consultar la atención.',
        }, response.statusCode);
      return response;
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        'No se pudo completar la solicitud. Actualiza la atención antes de repetir.',
      );
    }
  }

  Future<Map<String, dynamic>> careContext() => _careGet('context');

  Future<Map<String, dynamic>> careCatalog(
    String communeCode, {
    int offset = 0,
  }) => _careGet(
    'catalog',
    query: {'communeCode': communeCode, 'offset': '$offset'},
  );

  Future<Map<String, dynamic>> _careGet(
    String path, {
    Map<String, String>? query,
  }) async {
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final response = await _client
          .get(
            _base.resolve('/api/care/$path').replace(queryParameters: query),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (_token != token) throw const AuthFailure('La sesión cambió.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          409 => 'Completa primero tus datos personales en Mi perfil.',
          400 => 'Selecciona una comuna válida para consultar atención.',
          403 => 'Ingresa en modo paciente para enviar un examen.',
          _ => 'No se pudo consultar la atención. Intenta nuevamente.',
        }, response.statusCode);
      }
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        'No se pudo consultar la atención. Intenta nuevamente.',
      );
    }
  }

  Uri documentUri([String suffix = '', Map<String, String>? query]) {
    if (suffix.isNotEmpty &&
        !RegExp(
          r'^[a-f0-9-]{36}/(file|processing|review|care|explanation|assistant(?:/explanation)?)$',
        ).hasMatch(suffix)) {
      throw const AuthFailure('Documento inválido.');
    }
    return _base
        .resolve('/api/documents${suffix.isEmpty ? '' : '/$suffix'}')
        .replace(queryParameters: query);
  }

  Future<http.Response> sendDocumentRequest(http.BaseRequest request) async {
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    if (request.url.origin != _base.origin ||
        !(request.url.path == '/api/documents' ||
            RegExp(
              r'^/api/documents/[a-f0-9-]{36}/(file|processing|review|care|explanation|assistant(?:/explanation)?)$',
            ).hasMatch(request.url.path))) {
      throw const AuthFailure('Solicitud de documento inválida.');
    }
    if ((request.url.path.endsWith('/review') ||
            request.url.path.endsWith('/care')) &&
        request.method != 'GET') {
      throw const AuthFailure('La revisión del paciente es solo de consulta.');
    }
    if ((request.url.path.endsWith('/explanation') ||
            request.url.path.endsWith('/assistant')) &&
        !['GET', 'POST'].contains(request.method)) {
      throw const AuthFailure('Solicitud de explicación inválida.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response =
          await (() async {
            final streamed = await _client.send(request);
            return http.Response.fromStream(streamed);
          })().timeout(
            Duration(
              seconds:
                  (request.url.path.endsWith('/explanation') ||
                      request.url.path.endsWith('/assistant'))
                  ? 150
                  : 60,
            ),
          );
      if (_token != token)
        throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        final message = switch (response.statusCode) {
          400 =>
            request.url.path.contains('/assistant')
                ? 'Pregunta o examen fuera de los límites del asistente.'
                : 'Revisa el archivo y los datos del examen.',
          403 => 'No tienes permiso para acceder a estos documentos.',
          404 => 'Documento no disponible.',
          409 =>
            request.url.path.contains('/assistant')
                ? 'Comprueba la revisión aprobada y el límite de treinta preguntas. Actualiza antes de repetir.'
                : request.url.path == '/api/documents' &&
                      request.method == 'POST'
                ? 'La selección de atención o tu perfil cambió. Actualiza los datos antes de enviar.'
                : 'Primero se requiere una revisión profesional aprobada.',
          413 => 'El archivo supera 10 MiB.',
          503 =>
            request.url.path.contains('/assistant')
                ? assistantFailureMessage(response.body)
                : 'El servicio está ocupado. Intenta nuevamente.',
          _ => 'No se pudo completar la solicitud.',
        };
        throw AuthFailure(message, response.statusCode);
      }
      return response;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw AuthFailure(
        request.url.path.contains('/assistant')
            ? 'El asistente tardó demasiado. Actualiza la conversación antes de repetir.'
            : 'La solicitud tardó demasiado. Actualiza el historial antes de repetir una carga.',
      );
    } catch (_) {
      throw AuthFailure(
        request.url.path.contains('/assistant')
            ? 'No se pudo conectar con el asistente. Actualiza la conversación antes de repetir.'
            : 'No se pudo conectar. Si estabas subiendo un archivo, actualiza el historial antes de repetir.',
      );
    }
  }

  Uri assignmentUri([String suffix = '', Map<String, String>? query]) {
    if (suffix.isNotEmpty &&
        !RegExp(r'^[a-f0-9-]{36}/deactivate$').hasMatch(suffix)) {
      throw const AuthFailure('Asignación inválida.');
    }
    return _base
        .resolve('/api/assignments${suffix.isEmpty ? '' : '/$suffix'}')
        .replace(queryParameters: query);
  }

  Future<http.Response> sendAssignmentRequest(http.Request request) async {
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    if (request.url.origin != _base.origin ||
        !['GET', 'POST'].contains(request.method) ||
        !(request.url.path == '/api/assignments' ||
            RegExp(r'^/api/assignments/[a-f0-9-]{36}/deactivate$')
                .hasMatch(request.url.path))) {
      throw const AuthFailure('Solicitud de asignación inválida.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await (() async {
        return http.Response.fromStream(await _client.send(request));
      })().timeout(const Duration(seconds: 15));
      if (_token != token)
        throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
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
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La solicitud tardó demasiado. Actualiza la lista antes de repetir.',
      );
    } catch (_) {
      throw const AuthFailure(
        'No se pudo conectar. Actualiza la lista antes de repetir.',
      );
    }
  }

  Uri professionalUri(
    String patientId, {
    String? documentId,
    String? action,
    Map<String, String>? query,
  }) {
    final identifier = RegExp(r'^[a-f0-9-]{36}$');
    if (!identifier.hasMatch(patientId) ||
        (documentId != null &&
            (!identifier.hasMatch(documentId) ||
                !['file', 'extraction'].contains(action))) ||
        (documentId == null && action != null)) {
      throw const AuthFailure('Solicitud profesional inválida.');
    }
    return _base
        .resolve(
          '/api/professional/patients/$patientId/documents'
          '${documentId == null ? '' : '/$documentId/$action'}',
        )
        .replace(queryParameters: query);
  }

  Future<http.Response> sendProfessionalRequest(http.Request request) async {
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    if (request.url.origin != _base.origin ||
        request.method != 'GET' ||
        !RegExp(
          r'^/api/professional/patients/[a-f0-9-]{36}/documents(?:/[a-f0-9-]{36}/(?:file|extraction))?$',
        ).hasMatch(request.url.path)) {
      throw const AuthFailure('Solicitud profesional inválida.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await (() async {
        return http.Response.fromStream(await _client.send(request));
      })().timeout(const Duration(seconds: 60));
      if (_token != token)
        throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          403 => 'No tienes permiso para consultar estos exámenes.',
          404 =>
            'Paciente o documento no disponible. Comprueba tus asignaciones.',
          503 => 'Las descargas están ocupadas. Intenta nuevamente.',
          _ => 'No se pudo consultar el documento.',
        }, response.statusCode);
      }
      return response;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La consulta tardó demasiado. Intenta nuevamente.',
      );
    } catch (_) {
      throw const AuthFailure('No se pudo conectar con el servidor.');
    }
  }

  Uri reviewUri(String patientId, String documentId) {
    final identifier = RegExp(r'^[a-f0-9-]{36}$');
    if (!identifier.hasMatch(patientId) || !identifier.hasMatch(documentId)) {
      throw const AuthFailure('Revisión inválida.');
    }
    return _base.resolve(
      '/api/professional/patients/$patientId/documents/$documentId/review',
    );
  }

  Future<http.Response> sendReviewRequest(http.Request request) async {
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    if (request.url.origin != _base.origin ||
        !['GET', 'POST'].contains(request.method) ||
        !RegExp(
          r'^/api/professional/patients/[a-f0-9-]{36}/documents/[a-f0-9-]{36}/review$',
        ).hasMatch(request.url.path)) {
      throw const AuthFailure('Solicitud de revisión inválida.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await (() async {
        return http.Response.fromStream(await _client.send(request));
      })().timeout(const Duration(seconds: 15));
      if (_token != token)
        throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
      if (response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          400 => 'Revisa la fecha, los resultados, las observaciones y la confirmación.',
          403 => 'No tienes permiso para revisar este documento.',
          404 =>
            'Paciente o documento no disponible. Comprueba tus asignaciones.',
          409 => 'Ya existe una revisión o cambió el procesamiento. Actualiza la revisión.',
          413 => 'La revisión supera el tamaño permitido.',
          _ => 'No se pudo guardar o consultar la revisión. Actualiza antes de repetir.',
        }, response.statusCode);
      }
      return response;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La solicitud tardó demasiado. Actualiza la revisión antes de repetir.',
      );
    } catch (_) {
      throw const AuthFailure(
        'No se pudo conectar. Actualiza la revisión antes de repetir.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? body,
    bool get = false,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
    try {
      final uri = _base.resolve('/api/auth/$path');
      final response =
          await (get
                  ? _client.get(uri, headers: headers)
                  : _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    ))
              .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        if (path != 'login') clear();
        throw AuthFailure(
          path == 'login'
              ? 'Correo, contraseña o modo de acceso incorrectos.'
              : 'La sesión terminó. Ingresa nuevamente.',
          401,
        );
      }
      if (response.statusCode == 429) {
        throw const AuthFailure('Espera antes de volver a intentar.', 429);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(
          'No se pudo completar la solicitud. Intenta nuevamente.',
          response.statusCode,
        );
      }
      if (response.statusCode == 204) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure('El servidor tardó demasiado en responder.');
    } catch (_) {
      throw const AuthFailure('No se pudo conectar con el servidor.');
    }
  }

  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String mode = 'paciente',
  }) async {
    if (!['paciente', 'profesional', 'administrador'].contains(mode))
      throw const AuthFailure('Modo de acceso inválido.');
    clear();
    try {
      final data = await _request(
        'login',
        body: {'email': email.trim(), 'password': password, 'mode': mode},
      );
      if (data['professionalPasswordSetup'] is Map) {
        final setup = data['professionalPasswordSetup'] as Map;
        final token = setup['token'];
        if (token is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
          throw const AuthFailure(
            'No se pudo preparar la configuración profesional.',
          );
        }
        throw ProfessionalPasswordSetupRequired(token);
      }
      _token = data['token'] as String;
      expiresAt = DateTime.parse(data['expiresAt'] as String);
      if (!expiresAt!.isAfter(DateTime.now()))
        throw const AuthFailure('La sesión terminó.');
      return await me();
    } catch (_) {
      clear();
      rethrow;
    }
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

  Future<void> saveProfessionalPassword({
    required String currentPassword,
    required String password,
    required String confirmation,
    String? setupToken,
  }) async {
    final session = _token;
    if (setupToken == null &&
        (session == null ||
            expiresAt == null ||
            !expiresAt!.isAfter(DateTime.now()))) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final response = await _client
          .post(
            _base.resolve(
              '/api/onboarding/professional-password/${setupToken == null ? 'change' : 'setup'}',
            ),
            headers: {
              'Content-Type': 'application/json',
              if (setupToken != null)
                'Authorization': 'ProfessionalSetup $setupToken',
              if (setupToken == null) 'Authorization': 'Bearer $session',
            },
            body: jsonEncode({
              'currentPassword': currentPassword,
              'professionalPassword': password,
              'professionalConfirmation': confirmation,
              'confirmed': true,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (setupToken == null && session != _token)
        throw const AuthFailure('La sesión cambió.', 401);
      if (response.statusCode >= 400) {
        final code = (jsonDecode(response.body) as Map)['error']?['code'];
        if (response.statusCode == 401 && setupToken == null) clear();
        throw AuthFailure(switch (code) {
          'CURRENT_PASSWORD_INVALID' => 'La contraseña actual no es correcta.',
          'PASSWORD_REUSED' =>
            'La contraseña profesional debe ser diferente a la de paciente.',
          'PASSWORD_UNCHANGED' =>
            'La nueva contraseña debe ser diferente a la actual.',
          'SETUP_EXPIRED' => 'La configuración venció. Vuelve a iniciar sesión como profesional.',
          'PROFESSIONAL_PASSWORD_EXISTS' => 'Tu contraseña profesional ya está configurada. Vuelve a iniciar sesión.',
          _ => 'No se pudo cambiar la contraseña. Revisa los datos e intenta nuevamente.',
        }, response.statusCode);
      }
      if (setupToken == null) clear();
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La solicitud tardó demasiado. Comprueba el acceso con la nueva contraseña antes de repetir.',
      );
    } catch (_) {
      throw const AuthFailure('No se pudo conectar con el servidor.');
    }
  }

  Future<void> register(String email, String password) async {
    await _request(
      'register',
      body: {'email': email.trim(), 'password': password},
    );
  }

  Future<void> logout() async {
    try {
      await _request('logout');
    } finally {
      clear();
    }
  }
}
