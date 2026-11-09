import 'assistant_failure_message.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  static const bool _silMainMode =
      bool.fromEnvironment('VITALIA_SIL_MAIN_MODE',defaultValue:false);
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

  Future<Map<String, dynamic>> silRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.tryParse(path);
    final validPath = RegExp(
      r'^/(?:catalog|branches|summary|medical-requests/(?:confirm)|orders(?:/[a-f0-9-]{36}(?:/(?:sample|simulate|results|review|report(?:/publish)?))?)?|patients(?:/(?:profile|list))?|patient/profile|patient/reports/overview|patient/reports(?:/[a-f0-9-]{36}/(?:file|chat))?)$',
    );
    final allowedParams = uri?.path == '/patients/list'
        ? <String>{'limit', 'offset', 'search', 'profile', 'orders', 'sex', 'sort'}
        : (uri?.path == '/patients' || uri?.path == '/patients/profile')
            ? <String>{'email'}
            : uri?.path == '/orders'
                ? <String>{'limit', 'offset', 'status', 'search'}
                : <String>{};
    final query = uri?.queryParametersAll ?? <String, List<String>>{};
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        !validPath.hasMatch(uri.path) ||
        query.keys.any((key) => !allowedParams.contains(key)) ||
        query.values.any((values) => values.length != 1) ||
        ((uri.path == '/patients' || uri.path == '/patients/profile') &&
            body == null && !query.containsKey('email'))) {
      throw const AuthFailure('Ruta de laboratorio inválida.');
    }
    final token = _token;
    if (token == null ||
        expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final isPatientRoute = uri.path.startsWith('/patient/');
      final target = _base.resolve(
        isPatientRoute && _silMainMode ? '/api/sil/main$path' : '/api/sil$path',
      );
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await (body == null
              ? _client.get(target, headers: headers)
              : _client.post(target, headers: headers, body: jsonEncode(body)))
          .timeout(switch (target.path) {
            '/api/sil/patient/reports/overview' => const Duration(seconds: 130),
            '/api/sil/main/patient/reports/overview' => const Duration(seconds: 130),
            final path when path.endsWith('/chat') => const Duration(seconds: 38),
            _ => const Duration(seconds: 20),
          });
      if (_token != token || response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          400 => 'Datos inválidos. Comprueba el paciente, la orden o la muestra.',
          403 => 'Tu perfil no tiene permiso para realizar esta operación.',
          404 => 'No existe la orden o el paciente indicado.',
          409 => 'La orden cambió de estado. Consulta su estado antes de continuar.',
          429 => 'El asistente recibió demasiadas consultas. Intenta más tarde.',
          503 => 'El modelo educativo local no está disponible. Comprueba el servicio de IA.',
          _ => 'No se pudo completar la operación de laboratorio.',
        }, response.statusCode);
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La operación tardó demasiado. Consulta la orden antes de repetir.',
      );
    } catch (_) {
      throw const AuthFailure('No fue posible conectar con el laboratorio.');
    }
  }

  /// Operaciones autenticadas y explícitamente autorizadas del SIL principal.
  Future<Map<String,dynamic>> silMainRequest(
    String path,{Map<String,dynamic>? body}
  ) async {
    if(!_silMainMode){
      throw const AuthFailure('El SIL principal no está activado.');
    }
    final candidate=Uri.tryParse(path);
    final allowed=RegExp(
      r'^/(?:labs(?:/[a-f0-9-]{36}(?:/(?:orders(?:/[a-f0-9-]{36}/(?:report/publish|clinical(?:/(?:samples|results|review))?))?|staff(?:/review-permission)?|patients|patient-invitations|operator-invitations))?)?|patient/(?:profile|reports(?:/overview|/[a-f0-9-]{36}/chat)?))$',
    );
    final queries=candidate?.queryParametersAll ?? <String,List<String>>{};
    final isOrders=candidate?.path.endsWith('/orders') ?? false;
    final isPatients=candidate?.path.endsWith('/patients') ?? false;
    final allowedQuery = isPatients ? {'limit','offset','search'} : {'limit','offset'};
    if(candidate==null||candidate.hasScheme||candidate.hasAuthority||
       candidate.hasFragment||!allowed.hasMatch(candidate.path)||
       (queries.isNotEmpty&&(body!=null||(!isOrders&&!isPatients)))||
       queries.keys.any((key)=>!allowedQuery.contains(key))||
       queries.values.any((values)=>values.length!=1)){
      throw const AuthFailure('Ruta del SIL principal inválida.');
    }
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try{
      final target=_base.resolve('/api/sil/main${candidate.path}')
        .replace(queryParameters:queries.isEmpty?null:candidate.queryParameters);
      final headers={'Authorization':'Bearer $token','Content-Type':'application/json'};
      final response=await (body==null
          ?_client.get(target,headers:headers)
          :_client.post(target,headers:headers,body:jsonEncode(body)))
        .timeout(const Duration(seconds:30));
      if(token!=_token||response.statusCode==401){
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode>=400){
        throw AuthFailure(switch(response.statusCode){
          400=>'Revisa los datos del formulario.',
          403=>'No tienes permiso para acceder a este laboratorio.',
          404=>'El recurso no está disponible en este laboratorio.',
          409=>'El recurso cambió de estado o ya existe.',
          429=>'Demasiadas solicitudes. Intenta más tarde.',
          503=>'La función todavía no está disponible.',
          _=>'No pudimos completar la operación del SIL principal.',
        },response.statusCode);
      }
      return jsonDecode(response.body) as Map<String,dynamic>;
    }on AuthFailure {rethrow;}
    on TimeoutException {
      throw const AuthFailure('La consulta tardó demasiado.');
    }catch(_){
      throw const AuthFailure('No fue posible conectar con Vitalia principal.');
    }
  }

  /// Activación por invitación del operador. El código se entrega por un
  /// canal externo seguro, no por un buzón simulado.
  Future<void> silMainActivateOperator({
    required String email,
    required String code,
    required String password,
    bool patient = false,
  }) async {
    if(!_silMainMode)throw const AuthFailure('El SIL principal no está activo.');
    final address=email.trim().toLowerCase();
    if(!address.contains('@')||code.length!=43||password.runes.length<12){
      throw const AuthFailure('Revisa correo, código y contraseña de 12 caracteres o más.');
    }
    try{
      final response=await _client.post(
        _base.resolve(patient ? '/api/sil/main/patients/activate' : '/api/sil/main/operators/activate'),
        headers:{'Content-Type':'application/json'},
        body:jsonEncode({'email':address,'code':code,'password':password}),
      ).timeout(const Duration(seconds:30));
      if(response.statusCode>=400){
        throw AuthFailure(switch(response.statusCode){
          400=>'Revisa el formato de tus datos.',
          403=>'La invitación no es válida, expiró o ya fue utilizada.',
          409=>'La cuenta ya existe o la invitación cambió de estado.',
          429=>'Demasiados intentos. Intenta más tarde.',
          _=>'No se pudo activar el acceso.',
        },response.statusCode);
      }
    }on AuthFailure {rethrow;}
    on TimeoutException {throw const AuthFailure('La activación tardó demasiado.');}
    catch(_){throw const AuthFailure('No fue posible conectar con Vitalia.');}
  }

  Future<Map<String,dynamic>> silMainPreviewMedicalRequest({
    required String labId,
    required String fileName,
    required Uint8List bytes,
  }) => _silMainPdfRequest(
    labId: labId, path: 'medical-requests/preview', fileName: fileName, bytes: bytes,
  );

  Future<Map<String, dynamic>> silMainPreviewResults({
    required String labId,
    required String orderId,
    required String fileName,
    required Uint8List bytes,
  }) {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(orderId)) {
      throw const AuthFailure('Orden inválida.');
    }
    return _silMainPdfRequest(
      labId: labId,
      path: 'orders/$orderId/clinical/results/preview',
      fileName: fileName,
      bytes: bytes,
      resultsPreview: true,
    );
  }

  Future<Map<String,dynamic>> silMainAttachMedicalRequest({
    required String labId,
    String? orderId,
    String? patientId,
    List<String> examCodes = const [],
    required String fileName,
    required Uint8List bytes,
    required String documentReference,
    required String prescriberName,
    required String requestDate,
  }) {
    final id=RegExp(r'^[a-f0-9-]{36}$');
    if((orderId != null ? !id.hasMatch(orderId)
          : patientId == null || !id.hasMatch(patientId) || examCodes.isEmpty) ||
       documentReference.trim().length<6||prescriberName.trim().length<3||
       !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(requestDate)){
      throw const AuthFailure('Revisa el PDF y los datos de la solicitud.');
    }
    return _silMainPdfRequest(
      labId:labId,
      path:orderId == null ? 'medical-requests' : 'orders/$orderId/medical-request',
      fileName:fileName,
      bytes:bytes,
      headers:{
        'x-request-prescriber':Uri.encodeComponent(prescriberName.trim()),
        'x-request-reference':Uri.encodeComponent(documentReference.trim()),
        'x-request-date':requestDate,
        'x-request-identity-confirmed':'true',
        'x-request-reviewed':'true',
        if (orderId == null) ...{
          'x-request-patient-id':patientId!,
          'x-request-exam-codes':examCodes.join(','),
        },
      },
    );
  }

  Future<Map<String,dynamic>> _silMainPdfRequest({
    required String labId,
    required String path,
    required String fileName,
    required Uint8List bytes,
    Map<String,String> headers = const {},
    bool resultsPreview = false,
  }) async {
    if(!_silMainMode){
      throw const AuthFailure('El SIL principal no está habilitado.');
    }
    final id=RegExp(r'^[a-f0-9-]{36}$');
    if(!id.hasMatch(labId)||
       !fileName.toLowerCase().endsWith('.pdf')||
       fileName.length<5||fileName.length>120||
       bytes.length<8||bytes.length>2*1024*1024||
       bytes[0]!=37||bytes[1]!=80||bytes[2]!=68||bytes[3]!=70){
      throw AuthFailure(resultsPreview
        ? 'Elige un PDF de resultados de hasta 2 MiB.'
        : 'Revisa el PDF y los datos de la solicitud.');
    }
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try{
      final response=await _client.post(
        _base.resolve('/api/sil/main/labs/$labId/$path'),
        headers:{
          'Authorization':'Bearer $token',
          'Content-Type':'application/pdf',
          if (!resultsPreview) 'x-request-filename':Uri.encodeComponent(fileName),
          ...headers,
        },
        body:bytes,
      ).timeout(const Duration(seconds:40));
      if(token!=_token||response.statusCode==401){
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode>=400){
        throw AuthFailure(switch(response.statusCode){
          400=>resultsPreview ? 'El PDF de resultados es inválido.' : 'El PDF o los datos de la solicitud son inválidos.',
          403=>resultsPreview ? 'No tienes permiso para analizar este PDF.' : 'No tienes permiso para recibir esta solicitud.',
          404=>'El paciente o la orden no pertenece al laboratorio seleccionado.',
          409=>resultsPreview ? 'Hay otra lectura en curso o la orden dejó de admitir cambios.' : 'La solicitud está en uso, ya fue recibida o la orden cambió.',
          413=>'El PDF supera los 2 MiB.',
          _=>resultsPreview ? 'No se pudo leer el PDF de resultados.' : 'No se pudo recibir la solicitud.',
        },response.statusCode);
      }
      return jsonDecode(response.body) as Map<String,dynamic>;
    }on AuthFailure {rethrow;}
    on TimeoutException {
      throw AuthFailure(resultsPreview ? 'La lectura del PDF tardó demasiado.' : 'La recepción tardó demasiado.');
    }catch(_){
      throw const AuthFailure('No fue posible conectar con Vitalia.');
    }
  }

  /// Documento pendiente para revisión privada del operador autorizado.
  Future<Uint8List> silMainDownloadReportForReview({
    required String labId,
    required String orderId,
  }) async {
    if(!_silMainMode)throw const AuthFailure('SIL principal no habilitado.');
    final id=RegExp(r'^[a-f0-9-]{36}$');
    if(!id.hasMatch(labId)||!id.hasMatch(orderId)){
      throw const AuthFailure('Orden inválida.');
    }
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try{
      final response=await _client.get(
        _base.resolve('/api/sil/main/labs/$labId/orders/$orderId/report/file'),
        headers:{'Authorization':'Bearer $token'},
      ).timeout(const Duration(seconds:35));
      if(token!=_token||response.statusCode==401){
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode!=200||
         response.headers['content-type']?.startsWith('application/pdf')!=true||
         response.bodyBytes.length>2*1024*1024){
        throw AuthFailure('Informe pendiente no disponible.',response.statusCode);
      }
      return response.bodyBytes;
    }on AuthFailure {rethrow;}
    on TimeoutException {throw const AuthFailure('La descarga tardó demasiado.');}
    catch(_){throw const AuthFailure('No fue posible descargar el informe para revisión.');}
  }

  /// Consulta un archivo recibido desde el SIL principal, autenticado y
  /// limitado por laboratorio en el backend.
  Future<Uint8List> silMainDownloadMedicalRequest({
    required String labId,
    required String orderId,
  }) async {
    if(!_silMainMode)throw const AuthFailure('SIL principal no habilitado.');
    final id=RegExp(r'^[a-f0-9-]{36}$');
    if(!id.hasMatch(labId)||!id.hasMatch(orderId)){
      throw const AuthFailure('Orden inválida.');
    }
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try{
      final response=await _client.get(
        _base.resolve('/api/sil/main/labs/$labId/orders/$orderId/medical-request/file'),
        headers:{'Authorization':'Bearer $token'},
      ).timeout(const Duration(seconds:35));
      if(token!=_token||response.statusCode==401){
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode!=200||
         response.headers['content-type']?.startsWith('application/pdf')!=true||
         response.bodyBytes.length>2*1024*1024){
        throw AuthFailure('Solicitud no disponible en este laboratorio.',response.statusCode);
      }
      return response.bodyBytes;
    }on AuthFailure {rethrow;}
    on TimeoutException {throw const AuthFailure('La descarga tardó demasiado.');}
    catch(_){throw const AuthFailure('No fue posible descargar la solicitud.');}
  }

  /// Carga PDF autorizado al laboratorio seleccionado. Publica otro profesional.
  Future<Map<String,dynamic>> silMainAttachReport({
    required String labId,
    required String orderId,
    required String fileName,
    required Uint8List bytes,
    required String authorizationReference,
    required String authorizedProfessionalName,
    required DateTime externallyAuthorizedAt,
  }) async {
    if(!_silMainMode){
      throw const AuthFailure('El SIL principal no está habilitado.');
    }
    final id=RegExp(r'^[a-f0-9-]{36}$');
    if(!id.hasMatch(labId)||!id.hasMatch(orderId)||
       !fileName.toLowerCase().endsWith('.pdf')||
       fileName.length<5||fileName.length>120||
       bytes.length<8||bytes.length>2*1024*1024||
       bytes[0]!=37||bytes[1]!=80||bytes[2]!=68||bytes[3]!=70||
       authorizationReference.trim().length<6||
       authorizedProfessionalName.trim().length<3){
      throw const AuthFailure('Comprueba el PDF (máximo 2 MiB) y su autorización.');
    }
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try{
      final response=await _client.post(
        _base.resolve('/api/sil/main/labs/$labId/orders/$orderId/report'),
        headers:{
          'Authorization':'Bearer $token',
          'Content-Type':'application/pdf',
          'x-report-filename':Uri.encodeComponent(fileName),
          'x-report-authorized-professional':Uri.encodeComponent(authorizedProfessionalName.trim()),
          'x-report-authorization-ref':Uri.encodeComponent(authorizationReference.trim()),
          'x-report-authorized-at':externallyAuthorizedAt.toUtc().toIso8601String(),
          'x-report-patient-confirmed':'true',
        },
        body:bytes,
      ).timeout(const Duration(seconds:40));
      if(token!=_token||response.statusCode==401){
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode>=400){
        throw AuthFailure(switch(response.statusCode){
          400=>'PDF inválido o falta información de autorización.',
          403=>'No tienes permiso para adjuntar en este laboratorio.',
          404=>'La orden no existe en el laboratorio seleccionado.',
          409=>'La orden ya tiene informe o cambió de estado.',
          413=>'El PDF supera los 2 MiB.',
          _=>'No se pudo incorporar el informe.',
        },response.statusCode);
      }
      return jsonDecode(response.body) as Map<String,dynamic>;
    }on AuthFailure {rethrow;}
    on TimeoutException {
      throw const AuthFailure('La carga demoró demasiado.');
    }catch(_){
      throw const AuthFailure('No se pudo conectar al laboratorio.');
    }
  }

  /// Acceso controlado a las operaciones de activación del portal SIL DEMO.
  /// El navegador nunca consulta secretos de contraseñas existentes.
  Future<Map<String,dynamic>> silPortalRequest(
    String path,{Map<String,dynamic>? body}
  ) async {
    final uri=Uri.tryParse(path);
    if(uri==null||uri.hasScheme||uri.hasAuthority||uri.hasQuery||
       uri.hasFragment||
       !RegExp(r'^/portal/patients(?:/[a-f0-9-]{36}(?:/invitations)?)?$')
         .hasMatch(uri.path)){
      throw const AuthFailure('Acción de portal inválida.');
    }
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try{
      final target=_base.resolve('/api/sil${uri.path}');
      final headers={'Authorization':'Bearer $token',
        'Content-Type':'application/json'};
      final response=await (body==null
        ?_client.get(target,headers:headers)
        :_client.post(target,headers:headers,body:jsonEncode(body)))
        .timeout(const Duration(seconds:25));
      if(response.statusCode==401||token!=_token){
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode>=400){
        throw AuthFailure(switch(response.statusCode){
          400=>'Comprueba los datos del paciente y los requisitos.',
          403=>'Tu rol no puede gestionar invitaciones.',
          404=>'El registro no está disponible en este entorno.',
          409=>'La cuenta ya está activa, existe un conflicto o alcanzaste el límite de invitaciones.',
          429=>'Demasiados intentos. Vuelve a intentarlo más tarde.',
          _=>'No se pudo completar la gestión del portal.',
        },response.statusCode);
      }
      return jsonDecode(response.body) as Map<String,dynamic>;
    } on AuthFailure {rethrow;}
      on TimeoutException {throw const AuthFailure('La operación tardó demasiado.');}
      catch(_){throw const AuthFailure('No fue posible conectar con el portal DEMO.');}
  }

  /// Solo entorno SIL DEMO: simulación de correo (no envía emails reales).
  Future<Map<String,dynamic>> silPortalPublic(
    String path,{Map<String,dynamic>? body}
  ) async {
    final uri=Uri.tryParse(path);
    final mailbox=uri?.path=='/portal/demo-mailbox';
    final activate=uri?.path=='/portal/activate';
    if(uri==null||uri.hasScheme||uri.hasAuthority||uri.hasFragment||
      !(activate&&uri.query.isEmpty&&body!=null ||
        mailbox&&body==null&&uri.queryParameters.length==1&&
          uri.queryParameters.containsKey('email'))){
      throw const AuthFailure('Ruta pública inválida.');
    }
    try{
      final target=_base.resolve('/api/sil${uri.path}').replace(
        queryParameters:mailbox?uri.queryParameters:null);
      final response=await (body==null
        ?_client.get(target)
        :_client.post(target,headers:{'Content-Type':'application/json'},
          body:jsonEncode(body))).timeout(const Duration(seconds:25));
      if(response.statusCode>=400){
        throw AuthFailure(switch(response.statusCode){
          400=>'Comprueba el correo, los códigos y la contraseña.',
          404=>'El correo simulado no está habilitado.',
          409=>'La invitación no se encuentra disponible.',
          422=>'Código incorrecto, vencido o utilizado. Comprueba ambos canales.',
          429=>'Demasiados intentos. Intenta más tarde.',
          _=>'No fue posible activar el portal.',
        },response.statusCode);
      }
      return jsonDecode(response.body) as Map<String,dynamic>;
    } on AuthFailure {rethrow;}
      on TimeoutException {throw const AuthFailure('La consulta tardó demasiado.');}
      catch(_){throw const AuthFailure('No fue posible conectar con la activación.');}
  }

  /// Prelectura de solicitud médica ficticia: no crea órdenes.
  Future<Map<String,dynamic>> silPreviewMedicalRequest({
    required String email,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final address=email.trim().toLowerCase();
    if(!address.endsWith('@example.invalid')||
       !fileName.toLowerCase().endsWith('.pdf')||
       fileName.length>120 || fileName.length<5 ||
       bytes.length<8 || bytes.length>2*1024*1024){
      throw const AuthFailure('Utiliza un PDF ficticio válido, máximo 2 MiB.');
    }
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try {
      final response=await _client.post(
        _base.resolve('/api/sil/medical-requests/preview'),
        headers:{
          'Authorization':'Bearer $token',
          'Content-Type':'application/pdf',
          'x-request-patient-email':Uri.encodeComponent(address),
          'x-request-filename':Uri.encodeComponent(fileName),
        },
        body:bytes,
      ).timeout(const Duration(seconds:35));
      if(_token!=token||response.statusCode==401){
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode>=400){
        throw AuthFailure(switch(response.statusCode){
          400=>'PDF inválido o faltan datos del paciente.',
          403=>'Tu cuenta no tiene permiso para recibir solicitudes.',
          404=>'No existe la cuenta de paciente indicada.',
          409=>'La ficha del paciente está incompleta o el documento es inválido.',
          413=>'El archivo supera los 2 MiB.',
          _=>'No fue posible leer la solicitud médica de prueba.',
        },response.statusCode);
      }
      return jsonDecode(response.body) as Map<String,dynamic>;
    } on AuthFailure {rethrow;}
      on TimeoutException {
        throw const AuthFailure('La lectura demoró demasiado. Reintenta con un PDF de texto.');
      } catch (_) {
        throw const AuthFailure('No fue posible conectar con la lectura de solicitudes.');
      }
  }

  /// Solo DEMO: analiza un PDF ficticio y devuelve sugerencias.
  /// No guarda datos clínicos ni registra muestras hasta confirmación humana.
  Future<Map<String, dynamic>> silPreviewResultsFile({
    required String orderId,
    required Uint8List bytes,
  }) async {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(orderId) ||
        bytes.length < 8 || bytes.length > 2 * 1024 * 1024) {
      throw const AuthFailure('Selecciona un PDF de prueba de hasta 2 MiB.');
    }
    final token = _token;
    if (token == null || expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final response = await _client.post(
        _base.resolve('/api/sil/orders/$orderId/results/preview'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/pdf',
        },
        body: bytes,
      ).timeout(const Duration(seconds: 155));
      if (_token != token || response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode >= 400) {
        throw AuthFailure(switch(response.statusCode) {
          400 => 'Archivo no admitido. Selecciona un PDF de prueba.',
          403 => 'Tu cuenta no puede analizar este documento.',
          404 => 'La orden no está disponible.',
          409 => 'La orden debe tener todas sus muestras registradas.',
          413 => 'El PDF supera el límite de 2 MiB.',
          _ => 'No fue posible analizar el archivo.',
        },response.statusCode);
      }
      return jsonDecode(response.body) as Map<String,dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'La IA tardó demasiado. Puedes ingresar los valores manualmente.');
    } catch (_) {
      throw const AuthFailure('No se pudo consultar la extracción del archivo.');
    }
  }

  /// Solo flujo de demostración postanalítica: adjuntar PDF ya autorizado fuera de Vitalia.
  Future<Map<String, dynamic>> silUploadReport({
    required String orderId,
    required String fileName,
    required String branchCode,
    required String authorizedProfessionalName,
    required String patientIdentifierFromPdf,
    required String authorizationReference,
    required DateTime authorizedAt,
    required Uint8List bytes,
  }) async {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(orderId) ||
        bytes.isEmpty || bytes.length > 2 * 1024 * 1024 ||
        !fileName.toLowerCase().endsWith('.pdf') ||
        fileName.length > 120 || branchCode.trim().isEmpty ||
        authorizedProfessionalName.trim().length < 3 ||
        !RegExp(r'^DEMO-[A-Z0-9-]{3,16}$')
            .hasMatch(patientIdentifierFromPdf) ||
        authorizationReference.trim().length < 3) {
      throw const AuthFailure('Revisa los datos del informe PDF (máximo 2 MiB).');
    }
    final token = _token;
    if (token == null || expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final response = await _client.post(
        _base.resolve('/api/sil/orders/$orderId/report'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/pdf',
          'x-report-filename': Uri.encodeComponent(fileName),
          'x-report-branch-code': branchCode,
          'x-report-authorized-professional':
              Uri.encodeComponent(authorizedProfessionalName.trim()),
          'x-report-patient-identifier': patientIdentifierFromPdf,
          'x-report-authorization-ref':
              Uri.encodeComponent(authorizationReference.trim()),
          'x-report-authorized-at': authorizedAt.toUtc().toIso8601String(),
          'x-report-patient-confirmed': 'true',
          'x-report-externally-authorized': 'true',
        },
        body: bytes,
      ).timeout(const Duration(seconds: 30));
      if (_token != token || response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode != 201) {
        throw AuthFailure(switch (response.statusCode) {
          400 => 'PDF inválido o datos de autorización externa incompletos.',
          403 => 'Tu cuenta no puede adjuntar informes.',
          409 => 'La orden no permite adjuntar otro informe.',
          413 => 'El PDF supera el límite de 2 MiB.',
          _ => 'No se pudo adjuntar el informe.',
        }, response.statusCode);
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure('La carga tardó demasiado. Consulta la orden antes de repetir.');
    } catch (_) {
      throw const AuthFailure('No fue posible adjuntar el PDF.');
    }
  }

  Future<Uint8List> silDownloadMedicalRequest(String orderId) async {
    if(!RegExp(r'^[a-f0-9-]{36}$').hasMatch(orderId))
      throw const AuthFailure('Orden inválida.');
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try{
      final response=await _client.get(
        _base.resolve('/api/sil/orders/$orderId/medical-request/file'),
        headers:{'Authorization':'Bearer $token'},
      ).timeout(const Duration(seconds:30));
      if(_token!=token||response.statusCode==401){
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode!=200){
        throw AuthFailure(response.statusCode==403
            ? 'No tienes permiso para consultar esta solicitud.'
            : 'El documento de solicitud no está disponible.',
            response.statusCode);
      }
      if(response.bodyBytes.length>2*1024*1024||
         response.headers['content-type']?.startsWith('application/pdf')!=true)
        throw const AuthFailure('El archivo recibido no es un PDF válido.');
      return response.bodyBytes;
    } on AuthFailure {rethrow;}
      on TimeoutException {
        throw const AuthFailure('La descarga tardó demasiado.');
      }catch(_){
        throw const AuthFailure('No se pudo descargar el documento de solicitud.');
      }
  }

  Future<Uint8List> silDownloadReport(String reportId) async {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(reportId)) {
      throw const AuthFailure('Identificador de informe inválido.');
    }
    final token = _token;
    if (token == null || expiresAt == null ||
        !expiresAt!.isAfter(DateTime.now())) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final response = await _client.get(
        _base.resolve(
          _silMainMode
              ? '/api/sil/main/patient/reports/$reportId/file'
              : '/api/sil/patient/reports/$reportId/file',
        ),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
      if (_token != token || response.statusCode == 401) {
        clear();
        throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
      }
      if (response.statusCode != 200) {
        throw AuthFailure(response.statusCode == 404
            ? 'El informe no está disponible en tu cuenta.'
            : 'No fue posible descargar el informe.', response.statusCode);
      }
      if (response.bodyBytes.length > 2 * 1024 * 1024 ||
          response.headers['content-type']?.startsWith('application/pdf') != true) {
        throw const AuthFailure('El archivo recibido no es un PDF válido.');
      }
      return response.bodyBytes;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure('La descarga tardó demasiado.');
    } catch (_) {
      throw const AuthFailure('No fue posible descargar el informe.');
    }
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
    if (!['paciente', 'profesional', 'administrador', 'operador_laboratorio'].contains(mode))
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
    if (!['paciente', 'profesional', 'administrador', 'operador_laboratorio'].contains(user['role'])) {
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

  Future<Map<String, dynamic>> generateSilRecoveryKey(String currentPassword) =>
      _silRecoveryRequest('key', {'currentPassword': currentPassword}, authenticated: true);

  Future<void> recoverSilPassword(String email, String key, String password) async {
    await _silRecoveryRequest('complete', {
      'email': email.trim().toLowerCase(),
      'recoveryKey': key.trim(),
      'password': password,
    });
  }

  Future<Map<String, dynamic>> _silRecoveryRequest(
    String action,
    Map<String, String> body, {
    bool authenticated = false,
  }) async {
    final token = authenticated ? _token : null;
    if (authenticated &&
        (token == null || !(expiresAt?.isAfter(DateTime.now()) ?? false))) {
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.', 401);
    }
    try {
      final response = await _client.post(
        _base.resolve(_silMainMode ? '/api/sil/main/patient/recovery/$action' : '/api/sil/portal/recovery/$action'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));
      if (authenticated && token != _token) {
        throw const AuthFailure('La sesión cambió. Ingresa nuevamente.', 401);
      }
      if (authenticated && response.statusCode == 401) clear();
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          400 => 'Comprueba los datos ingresados.',
          401 => 'La sesión terminó. Ingresa nuevamente.',
          422 => authenticated
              ? 'Comprueba tu contraseña actual.'
              : 'La clave de recuperación es incorrecta, venció o ya se usó.',
          429 => 'Demasiados intentos. Espera antes de continuar.',
          503 => 'Hay otra solicitud en curso. Intenta en unos segundos.',
          _ => 'No se pudo completar la recuperación.',
        }, response.statusCode);
      }
      return response.statusCode == 204
          ? {}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw AuthFailure(authenticated
          ? 'La operación tardó demasiado. Puedes generar otra clave.'
          : 'La operación tardó demasiado. Comprueba el acceso con tu nueva contraseña.');
    } catch (_) {
      throw const AuthFailure('No se pudo conectar con el portal.');
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
