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
      // Con VITALIA_API_SAME_ORIGIN=true el navegador envía /api al mismo
      // dominio HTTPS servido por Tailscale, sin llamar al localhost del
      // computador remoto. La DEMO local anterior conserva su configuración.
      _base = Uri.parse(
        baseUrl ??
            (const bool.fromEnvironment('VITALIA_API_SAME_ORIGIN',
                        defaultValue: false) &&
                    (Uri.base.scheme == 'https' || Uri.base.scheme == 'http')
                ? Uri.base.origin
                : const String.fromEnvironment(
                    'VITALIA_API_URL',
                    defaultValue: 'http://127.0.0.1:3000',
                  )),
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
      r'^/(?:labs(?:/[a-f0-9-]{36}(?:/(?:orders(?:/[a-f0-9-]{36}/(?:report/publish|clinical(?:/(?:samples|results|review|audit))?))?|summary|staff(?:/(?:review-permission|membership))?|patients|patient-invitations|operator-invitations(?:/revoke)?|administrative-audit))?)?|patient/(?:profile|reports(?:/overview|/[a-f0-9-]{36}/chat)?))$',
    );
    final pendingPath=RegExp(
      r'^/labs/[a-f0-9-]{36}/medical-requests/pending(?:/[a-f0-9-]{36}/(?:complete|cancel))?$',
    );
    final queries=candidate?.queryParametersAll ?? <String,List<String>>{};
    final isOrders=candidate?.path.endsWith('/orders') ?? false;
    final isPatients=candidate?.path.endsWith('/patients') ?? false;
    final isPending=candidate?.path.endsWith('/medical-requests/pending') ?? false;
    final isAdminHistory=candidate?.path.endsWith('/operator-invitations') == true ||
        candidate?.path.endsWith('/administrative-audit') == true;
    final allowedQuery = {
      'limit', 'offset',
      if (isPatients || isOrders) 'search',
      if (isOrders) ...{'status', 'patientId'},
    };
    if(candidate==null||candidate.hasScheme||candidate.hasAuthority||
       candidate.hasFragment||
       (!allowed.hasMatch(candidate.path)&&!pendingPath.hasMatch(candidate.path))||
       (queries.isNotEmpty&&(body!=null||(!isOrders&&!isPatients&&!isPending&&!isAdminHistory)))||
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

  /// Almacena una derivación incluso si el paciente todavía no tiene cuenta.
  Future<Map<String,dynamic>> silMainSavePendingRequest({
    required String labId,required String fileName,required Uint8List bytes,
    String? patientEmail,
  }) => _silMainPdfRequest(
    labId:labId,path:'medical-requests/pending',fileName:fileName,
    bytes:bytes,headers:{
      if(patientEmail!=null&&patientEmail.trim().isNotEmpty)
        'x-request-patient-email':Uri.encodeComponent(patientEmail.trim().toLowerCase()),
    },
  );

  /// PDF pendiente: solo operador autorizado del laboratorio correspondiente.
  Future<Uint8List> silMainDownloadPendingRequest({
    required String labId,required String pendingId,
  }) async {
    if(!_silMainMode)throw const AuthFailure('SIL principal no habilitado.');
    final uuid=RegExp(r'^[a-f0-9-]{36}$');
    if(!uuid.hasMatch(labId)||!uuid.hasMatch(pendingId)){
      throw const AuthFailure('Derivación inválida.');
    }
    final token=_token;
    if(token==null||expiresAt==null||!expiresAt!.isAfter(DateTime.now())){
      clear();
      throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
    }
    try{
      final response=await _client.get(
        _base.resolve('/api/sil/main/labs/$labId/medical-requests/pending/$pendingId/file'),
        headers:{'Authorization':'Bearer $token'},
      ).timeout(const Duration(seconds:35));
      if(token!=_token||response.statusCode==401){
        clear();throw const AuthFailure('La sesión terminó. Ingresa nuevamente.',401);
      }
      if(response.statusCode!=200||
        response.headers['content-type']?.startsWith('application/pdf')!=true||
        response.bodyBytes.length>2*1024*1024){
        throw AuthFailure('Derivación pendiente no disponible.',response.statusCode);
      }
      return response.bodyBytes;
    }on AuthFailure {rethrow;}
    on TimeoutException {throw const AuthFailure('La descarga tardó demasiado.');}
    catch(_){throw const AuthFailure('No fue posible descargar la derivación.');}
  }

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
    String? documentReference, // Compatibilidad: ya no se envía al backend.
    required String prescriberName,
    required String requestDate,
  }) {
    final id=RegExp(r'^[a-f0-9-]{36}$');
    if((orderId != null ? !id.hasMatch(orderId)
          : patientId == null || !id.hasMatch(patientId) || examCodes.isEmpty) ||
       prescriberName.trim().length<3||
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
        // ID administrativo: lo genera el servidor al registrar la derivación.
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
       …73804 tokens truncated…wait page.close();
    }
  };

  return stage('uploader',async ({page,id,button,click,select,confirm})=>{
    const captures=process.env.VITALIA_JOURNEY_SCREENSHOTS;
    const receive=button('Recibir solicitud');
    await receive.waitFor();
    const desktop=await receive.boundingBox();
    assert.ok(desktop && desktop.x < 100 && desktop.y < 340 && desktop.width > 0,
      'Navegación lateral visible en escritorio');
    if(captures)await page.screenshot({path:resolve(captures,'operador-escritorio.png')});

    // Una sesión sirve para ambos tamaños y mantiene disponible el cupo
    // de autenticación de la cuenta paciente en el mismo proceso de prueba.
    await page.setViewportSize({width:390,height:844});
    await receive.click();
    const pdfPicker = button('Seleccionar solicitud PDF');
    await pdfPicker.waitFor();
    const pickerPosition = await pdfPicker.boundingBox();
    assert.ok(pickerPosition && pickerPosition.y >= 0 &&
      pickerPosition.y + pickerPosition.height <= page.viewportSize().height,
      'El selector de PDF debe quedar visible sin desplazarse en móvil.');
    const pdfReader=button('Leer PDF y sugerir datos');
    assert.equal(await pdfReader.count(),0,'La lectura aparece al seleccionar un PDF');
    assert.equal(await button('Buscar paciente activado').count(),0);
    if(captures)await page.screenshot({path:resolve(captures,'recepcion-movil.png')});
    await page.setViewportSize({width:1440,height:1150});
    const requestChooser = page.waitForEvent('filechooser');
    await click(pdfPicker, 'Seleccionar solicitud PDF');
    await (await requestChooser).setFiles({
      name: 'solicitud-ensayo.pdf', mimeType: 'application/pdf', buffer: samplePdf,
    });
    await pdfReader.waitFor();
    await button('Buscar paciente activado').waitFor();
    assert.equal(await button('Crear orden con solicitud').count(),0);
    if(captures)await page.screenshot({path:resolve(captures,'recepcion-escritorio.png')});
    console.log('Microsoft Edge: navegación y recepción verificadas a 390 y 1440 px.');
    await click(button('Órdenes'),'Órdenes');
    const sampleFolio='VH-'+String(sampleOrder.orderNumber).padStart(6,'0');
    await click(button('Abrir '+sampleFolio),'Abrir orden desde la lista');
    const clinical='/api/sil/main'+base+'/orders/'+sampleOrder.id+'/clinical/results';
    const chooseResults=page.waitForEvent('filechooser');
    const preview=page.waitForResponse(r=>r.url().endsWith(clinical+'/preview') && r.request().method()==='POST');
    await click(button('Leer PDF de resultados'),'Leer PDF de resultados');
    await (await chooseResults).setFiles({
      name:'resultados-ficticios.pdf',mimeType:'application/pdf',buffer:samplePdf,
    });
    assert.equal((await preview).status(),200);
    await page.getByText('Sugerencia del PDF: 91.2',{exact:true}).waitFor();
    await click(button('Cotejé el PDF. Completar campos vacíos'),'Completar sugerencias');
    const saved=page.waitForResponse(r=>r.url().endsWith(clinical) && r.request().method()==='POST');
    await click(button('Guardar resultados para revisión'),'Guardar resultados');
    const recorded=await saved;
    assert.equal(recorded.status(),201);
    assert.equal(recorded.request().postDataJSON().values[0].numericValue,91.2);
    console.log('Microsoft Edge: el operador cotejó y guardó la sugerencia del PDF.');
    const requestDownload=page.waitForEvent('download');
    await click(button('Descargar solicitud original'),'Descargar solicitud original');
    const requestFile=await requestDownload;
    assert.deepEqual(readFileSync(await requestFile.path()),browserRequestPdf);
    assert.equal(requestFile.suggestedFilename(),
      'solicitud-VH-'+String(sampleOrder.orderNumber).padStart(6,'0')+'.pdf');
    await click(button('Ver historial de la orden'),'Ver historial de la orden');
    const closeHistory=button('Cerrar historial');
    await closeHistory.waitFor();
    await page.getByText('Resultados registrados',{exact:true}).waitFor();
    await page.getByText('Solicitud descargada',{exact:true}).waitFor();
    await page.getByText(/uploader@example[.]invalid/).first().waitFor();
    await closeHistory.click();
    await closeHistory.waitFor({state:'hidden'});
    console.log('Microsoft Edge: el operador consultó el evento real de la orden.');
    await click(button('Órdenes'),'Órdenes');
    assert.equal(await id('sil-upload-order').count(),0);
    await click(page.getByText('Adjuntar informe autorizado',{exact:true}), 'Adjuntar informe autorizado');
    await select('sil-upload-order');
    const choose=page.waitForEvent('filechooser');
    await click(button('Elegir archivo PDF (máx. 2 MiB)'),'Elegir archivo PDF');
    await (await choose).setFiles({name:'informe-operador.pdf',mimeType:'application/pdf',buffer:pdf});
    await button('informe-operador.pdf').waitFor({timeout:10000});
    console.log('Microsoft Edge: orden y archivo seleccionados.');
    for(const [key,value] of [
      ['sil-report-professional','Profesional Ficticio'],
      ['sil-report-reference','AUT-OPERADOR-EDGE'],
    ]){
      const input=id(key).locator('input[data-semantics-role="text-field"]');
      await reach(page,input,key);
      await input.focus();
      const focused=input.and(page.locator(':focus'));
      await focused.waitFor({timeout:7000});
      // Flutter activa el editor web al finalizar el cambio de foco.
      await focused.evaluate(()=>new Promise(done=>requestAnimationFrame(()=>requestAnimationFrame(done))));
      await focused.pressSequentially(value,{delay:18});
      if(await focused.inputValue()!==value){
        await focused.press('Control+a');
        await focused.pressSequentially(value,{delay:18});
      }
      assert.equal(await focused.inputValue(),value,key);
    }
    await click(button('Elegir fecha de autorización'),'Elegir fecha de autorización');
    await button('Usar fecha').click();
    await confirm('El informe ya fue autorizado fuera de Vitalia');
    await confirm('Confirmé que el PDF corresponde al paciente de la orden');
    console.log('Microsoft Edge: datos de autorización y paciente comprobados.');
    const response=page.waitForResponse(r=>r.url().endsWith(endpoint) && r.request().method()==='POST');
    const refresh=page.waitForResponse(r=>new URL(r.url()).pathname===('/api/sil/main'+base+'/orders')
      && r.request().method()==='GET');
    const [uploaded]=await Promise.all([
      response,click(button('Adjuntar para revisión'),'Adjuntar para revisión'),refresh,
    ]);
    assert.equal(uploaded.status(),201,'Carga del PDF desde la estación');
    const reportId=(await uploaded.json()).report.id;
    console.log('Microsoft Edge: se adjuntó el PDF desde la estación del operador.');

    await page.getByRole('button',{name:/^Revisión interna/}).click();
    await select('sil-review-order');
    const publication=button('Publicar informe');
    assert.equal(await publication.count(),0,'Se exige revisar antes de publicar');
    const download=page.waitForEvent('download');
    const reviewResponse=page.waitForResponse(r=>r.url().endsWith(endpoint+'/file') && r.request().method()==='GET');
    await click(button('Descargar PDF para revisión'),'Descargar para revisión');
    assert.equal((await reviewResponse).status(),200);
    assert.deepEqual(readFileSync(await (await download).path()),pdf);
    await publication.waitFor();
    assert.equal(await publication.isEnabled(),false,'Se exige confirmar el cotejo');
    await confirm('Confirmo que revisé el PDF y su autorización externa');
    const posted=page.waitForResponse(r=>r.url().endsWith(endpoint+'/publish') && r.request().method()==='POST');
    await click(publication,'Publicar informe');
    assert.equal((await posted).status(),201);
    console.log('Microsoft Edge: el mismo operador descargó, revisó y publicó el PDF.');
    return reportId;
  });
}

// La interfaz administrativa se comprueba con sesión real, no con mocks.
// Solo se leen los datos sintéticos y las acciones ya autorizadas; no
// se revocan permisos necesarios para el resto del recorrido.
async function adminJourney(browser, base) {
  const page=await browser.newPage({viewport:{width:1440,height:1050}});
  try {
    const responseLabs=page.waitForResponse(r=>
      new URL(r.url()).pathname==='/api/sil/main/labs' &&
      r.request().method()==='GET',{timeout:15000});
    await signIn(page,'admin','#/administracion');
    const labsHttp=await responseLabs;
    const labData=await labsHttp.json();
    console.log('Edge admin: GET /labs HTTP '+labsHttp.status()+
      ' cantidad='+String(labData.laboratories?.length ?? 'invalida'));
    assert.equal(labsHttp.status(),200);
    assert.ok(Array.isArray(labData.laboratories) &&
      labData.laboratories.length>=2,
      'La sesión de administración debe recibir ambos laboratorios de ensayo.');
    await page.getByText('Administración de laboratorios',{exact:true})
      .waitFor({timeout:15000});
    const nav=label=>page.getByRole('button',{name:label,exact:true});
    await nav('Laboratorios').waitFor();
    await nav('Operadores y permisos').waitFor();
    await nav('Actividad').waitFor();
    assert.equal(await nav('Recibir solicitud').count(),0,
      'Administración no debe presentar acciones clínicas de operador.');
    assert.equal(await nav('Publicar informe').count(),0,
      'El administrador no puede publicar informes desde su estación.');
    // Los resúmenes de la columna secundaria pueden estar fuera del
    // viewport; comprobamos controles operativos de la administración.
    await nav('Registrar laboratorio').waitFor({timeout:10000});
    if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
      await page.screenshot({path:resolve(
        process.env.VITALIA_JOURNEY_SCREENSHOTS, 'administrador-laboratorios.png')});
    }

    await nav('Operadores y permisos').click();
    // Flutter Canvas muestra los textos en pantalla, pero no todos son
    // localizadores HTML. Comprobar controles accesibles y la respuesta real.
    const refreshStaff=nav('Actualizar operadores');
    await refreshStaff.waitFor({timeout:10000});
    const staffResponse=page.waitForResponse(r=>
      new URL(r.url()).pathname==='/api/sil/main'+base+'/staff' &&
      r.request().method()==='GET');
    await refreshStaff.click();
    const staffHttp=await staffResponse;
    assert.equal(staffHttp.status(),200);
    const staffBody=await staffHttp.json();
    const entries=staffBody.staff ?? [];
    assert.equal(entries.length,2,'La administración debe listar ambos operadores.');
    assert.deepEqual(entries.map(m=>m.email).sort(),
      ['reviewer@example.invalid','uploader@example.invalid']);
    assert.ok(entries.every(m=>m.active && m.canReviewReports),
      'Ambos operadores tienen revisión autorizada inicialmente.');
    await nav('Retirar permiso de revisión').first().waitFor();
    if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
      await page.screenshot({
        path:resolve(process.env.VITALIA_JOURNEY_SCREENSHOTS,
          'administrador-operadores.png'),
      });
      await page.setViewportSize({width:390,height:844});
      await nav('Invitar operador').waitFor();
      await page.screenshot({path:resolve(
        process.env.VITALIA_JOURNEY_SCREENSHOTS, 'administrador-movil.png')});
      await page.setViewportSize({width:1440,height:1050});
    }
    // En esta copia sintética ambos operadores tienen permiso concedido.
    // Probar el ciclo de revocación y restitución, dejando el estado original
    // para que el recorrido del operador continúe sin cambios.
    const permissionPath='/api/sil/main'+base+'/staff/review-permission';
    const permissionResponse=()=>page.waitForResponse(r=>
      new URL(r.url()).pathname===permissionPath &&
      r.request().method()==='POST');
    const revoke=nav('Retirar permiso de revisión').first();
    const revoked=permissionResponse();
    await (await reach(page,revoke,'Revocar revisión')).click();
    const revokedResult=await revoked;
    assert.equal(revokedResult.status(),200);
    const revokedInput=revokedResult.request().postDataJSON();
    assert.equal(revokedInput.enabled,false);
    const grant=nav('Autorizar revisión');
    await (await reach(page,grant,'Restituir revisión')).waitFor();
    const granted=permissionResponse();
    await grant.click();
    const grantedResult=await granted;
    assert.equal(grantedResult.status(),200);
    assert.deepEqual(grantedResult.request().postDataJSON(),{
      accountId:revokedInput.accountId,enabled:true,
    },'Solo se restituye el permiso que se revocó en el ensayo.');

    await nav('Actividad').click();
    await nav('Actualizar estado administrativo').waitFor({timeout:10000});
    assert.equal(await nav('Descargar solicitud original').count(),0,
      'La actividad administrativa no muestra documentos de órdenes.');
    assert.equal(await nav('Descargar PDF').count(),0,
      'El administrador no debe ver el portal privado del paciente.');
    if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
      await page.screenshot({
        path:resolve(process.env.VITALIA_JOURNEY_SCREENSHOTS,
          'administrador-escritorio.png'),
      });
    }
    console.log('Microsoft Edge: administración, laboratorios, permisos y actividad verificados.');
  } finally {
    await page.close();
  }
}

async function browserJourney(order, base, sampleOrder, samplePdf) {
  const {chromium}=require(process.env.VITALIA_JOURNEY_PLAYWRIGHT);
  const browser=await chromium.launch({channel:'msedge'});
  try {
    await adminJourney(browser,base);
    const publishedId=await operatorJourney(browser,order,base,sampleOrder,samplePdf);
    const page=await browser.newPage({viewport:{width:390,height:844}});
    try {
      await signIn(page,'patient');
      const patientNav=page.getByLabel('Navegación del paciente');
      await patientNav.getByRole('button',
        {name:'Mis informes',exact:true}).waitFor();
      assert.equal(await page.getByRole('button',
        {name:'Recibir solicitud',exact:true}).count(),0,
        'El paciente no debe ver la estación interna del operador.');

      const help=patientNav.getByRole('button',{name:'Ayuda',exact:true});
      // La barra solo muestra flechas si realmente hay desbordamiento.
      // No reservar espacio para una flecha inexistente: con menos pestañas
      // el botón Ayuda puede caber íntegro a 390 px.
      const forward=page.getByRole('button',
        {name:'Mostrar más secciones',exact:true});
      for(let attempt=0;attempt<4;attempt++){
        const box=await help.boundingBox({timeout:500}).catch(()=>null);
        const arrowsVisible=await forward.count()>0;
        const rightEdge=page.viewportSize().width-(arrowsVisible?48:0);
        if(box && box.x>=0 && box.x+box.width<=rightEdge){
          break;
        }
        assert.ok(arrowsVisible && await forward.isEnabled(),
          'La ayuda debe ser alcanzable desde la navegación móvil.');
        await forward.click();
      }
      await help.click();
      // La presencia del botón del diálogo verifica que abrió Ayuda.
      const understood=page.getByRole('button',{name:'Entendido',exact:true});
      await understood.waitFor({timeout:10000});
      await understood.click();

      await page.getByRole('button',{name:'Mi cuenta'}).click();
      await page.getByRole('menuitem',{name:'Mi perfil'}).click();
      // El diálogo Mi perfil expone un control de cierre accesible. El
      // contenido se valida en el API real y en los tests de widgets.
      const closeProfile=page.getByRole('button',{name:'Cerrar',exact:true});
      await closeProfile.waitFor({timeout:10000});
      await closeProfile.click();

      const downloadButton=page.getByRole('button',{name:'Descargar PDF',exact:true}).first();
      assert.equal(await downloadButton.count(),0);
      await page.getByRole('button',{name:'Más opciones',exact:true}).first().click();
      await downloadButton.waitFor({timeout:20000});
      if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
        await page.setViewportSize({width:1440,height:1050});
        await downloadButton.waitFor();
        await page.screenshot({path:resolve(
          process.env.VITALIA_JOURNEY_SCREENSHOTS, 'paciente-escritorio.png')});
        await page.setViewportSize({width:390,height:844});
      }
      const downloaded=page.waitForEvent('download');
      const response=page.waitForResponse(r=>r.url().endsWith(
        '/patient/reports/'+publishedId+'/file'));
      await downloadButton.click();
      assert.equal((await response).status(),200);
      const file=await downloaded;
      assert.deepEqual(readFileSync(await file.path()),pdf);
      if(process.env.VITALIA_JOURNEY_SCREENSHOTS){
        await page.screenshot({
          path:resolve(process.env.VITALIA_JOURNEY_SCREENSHOTS,
            'paciente-movil.png'),
        });
      }
      console.log('Microsoft Edge: paciente consultó ayuda, perfil y descargó informe publicado.');
    } finally {
      await page.close();
    }
  } finally {
    await browser.close();
  }
}

function demoAccounts(manual) {
  const raw=process.env.VITALIA_JOURNEY_DEMO_PASSWORDS;
  delete process.env.VITALIA_JOURNEY_DEMO_PASSWORDS;
  if(raw===undefined)return {};
  if(!manual)throw new Error('Los accesos del DEMO requieren el modo manual.');
  const emails={
    admin:'admin.sil@example.invalid',
    uploader:'operador.sil@example.invalid',
    patient:'paciente.sil@example.invalid',
  };
  let passwords;
  try {
    passwords=JSON.parse(raw);
  } catch {
    throw new Error('No se pudieron leer las contraseñas del ensayo.');
  }
  return Object.fromEntries(Object.entries(emails).map(([key,email])=>{
    const value=passwords?.[key];
    if(typeof value!=='string'||value.length===0||Buffer.byteLength(value,'utf8')>1024){
      throw new Error('Ingresa una contraseña válida para '+email+'.');
    }
    return [key,{email,password:value}];
  }));
}

async function main() {
  if(process.env.VITALIA_ISOLATED_REHEARSAL!=='YES' ||
    process.env.PGHOST!=='127.0.0.1' ||
    process.env.PGUSER!=='vitalia_restore' ||
    process.env.PGDATABASE!=='vitalia_restored') {
    throw new Error('Se requiere PostgreSQL aislado, vacío y accesible por loopback.');
  }
  const container=process.env.VITALIA_JOURNEY_DB_CONTAINER;
  if(container && (!/^vitalia-edge-qa-[a-f0-9]{12}$/.test(container) || process.env.PGPORT!=='55439')){
    throw new Error('El contenedor local debe pertenecer al ensayo de Edge.');
  }
  const manual=process.env.VITALIA_JOURNEY_MANUAL==='YES';
  const demo=demoAccounts(manual);
  const fixture=process.env.VITALIA_JOURNEY_FIXTURE;
  if(manual && (!process.env.VITALIA_JOURNEY_WEB || !fixture)){
    throw new Error('El ensayo manual requiere una compilación web y una ruta para el PDF ficticio.');
  }
  const db=new Pool({connectionTimeoutMillis:5000});
  let server, webServer;
  try {
    await prepare(db,container);
    const roles={
      admin:'administrador', uploader:'operador_laboratorio',
      reviewer:'operador_laboratorio', patient:'paciente', other:'paciente',
    };
    const ids={};
    const credentials=Object.fromEntries(Object.keys(roles).map(name=>[
      name,demo[name]??{email:name+'@example.invalid',password},
    ]));
    const passwordHash=await hashPassword(password);
    for(const [name,role] of Object.entries(roles)){
      ids[name]=randomUUID();
      await db.query('INSERT INTO public.vitalia_accounts(id,email,password_hash,role_code) VALUES($1,$2,$3,$4)',
        [ids[name],credentials[name].email,demo[name]?await hashPassword(credentials[name].password):passwordHash,role]);
    }

    process.env.VITALIA_SIL_MAIN_MODE='YES';
    const host=express();
    const web=process.env.VITALIA_JOURNEY_WEB;
    host.use(createApp({
      authenticate:await createCredentialAuthenticator(db,{guardPatientSession:process.env.VITALIA_SIL_MAIN_MODE==='YES'}),
      issue:(id,mode,hash)=>issueSession(db,id,mode,hash),
      find:token=>findSessionAccount(db,token),
      revoke:token=>revokeSession(db,token),
    },...Array(18).fill(undefined),createSilMainService(db)));
    server=await new Promise((accept,reject)=>{
      const listener=host.listen(3119,'127.0.0.1',()=>accept(listener));
      listener.once('error',reject);
    });

    const tokens={};
    for(const [name,mode] of Object.entries(roles)){
      const login=await api('POST','/api/auth/login',200,{
        json:{mode,...credentials[name]},
      });
      const {token}=await login.json();
      tokens[name]=token;
      const me=await api('GET','/api/auth/me',200,{token});
      assert.equal((await me.json()).user.role,mode);
    }
    const call=(actor,method,path,status,data)=>api(method,'/api/sil/main'+path,status,
      {token:tokens[actor],...data});
    const admin=(path,status,json)=>call('admin','POST',path,status,{json});
    const lab=async name=>(await (await admin('/labs',201,{displayName:name})).json()).laboratory.id;
    const base='/labs/'+await lab('Laboratorio sintético Norte');
    const otherLab='/labs/'+await lab('Laboratorio sintético Sur');
    await admin(base+'/staff',201,{accountId:ids.uploader});
    await admin(base+'/staff',201,{accountId:ids.reviewer});
    await admin(otherLab+'/staff',201,{accountId:ids.reviewer});
    await admin(otherLab+'/staff/review-permission',200,{accountId:ids.reviewer,enabled:true});
    const northStaff = await (await call('admin', 'GET', base+'/staff', 200)).json();
    const southStaff = await (await call('admin', 'GET', otherLab+'/staff', 200)).json();
    assert.deepEqual(northStaff.staff.map(({email}) => email).sort(),
      [credentials.reviewer.email, credentials.uploader.email].sort());
    assert.deepEqual(southStaff.staff.map(({email}) => email), [credentials.reviewer.email]);
    assert.equal(northStaff.staff.find(({accountId}) => accountId === ids.reviewer)
      .canReviewReports, false, 'El permiso concedido en Sur no se aplica en Norte.');
    assert.equal(southStaff.staff[0].canReviewReports, true);
    await call('uploader', 'GET', base+'/staff', 403);
    await call('patient', 'GET', base+'/staff', 403);
    await call('admin', 'GET', base+'/medical-requests/pending', 403);
    const invitationPath=base+'/operator-invitations';
    const invitationEmail='operador-seguimiento@example.invalid';
    await admin(invitationPath,201,{email:invitationEmail});
    await admin(invitationPath,201,{email:invitationEmail});
    const invitations=await (await call('admin','GET',invitationPath,200)).json();
    assert.deepEqual(invitations.invitations.map(({status})=>status).sort(),['pending','revoked']);
    assert.ok(invitations.invitations.every(entry=>entry.email===invitationEmail &&
      !Object.hasOwn(entry,'code') && !Object.hasOwn(entry,'token_hash')));
    const otherInvitations=await (await call('admin','GET',otherLab+'/operator-invitations',200)).json();
    assert.deepEqual(otherInvitations.invitations,[]);
    const firstPage=await (await call('admin','GET',invitationPath+'?limit=1',200)).json();
    assert.equal(firstPage.invitations.length,1);
    assert.equal(firstPage.hasMore,true);
    await call('admin','GET',invitationPath+'?limit=51',400);
    await call('uploader','GET',invitationPath,403);
    const pendingInvitation=invitations.invitations.find(entry=>entry.status==='pending');
    const revokePath=invitationPath+'/revoke';
    const revoke={invitationId:pendingInvitation.id};
    await call('uploader','POST',revokePath,403,{json:revoke});
    await admin(otherLab+'/operator-invitations/revoke',404,revoke);
    await admin(revokePath,200,revoke);
    await admin(revokePath,404,revoke);
    const afterRevocation=await (await call('admin','GET',invitationPath,200)).json();
    assert.ok(afterRevocation.invitations.every(entry=>entry.status==='revoked'));
    const auditPath=base+'/administrative-audit';
    const northAudit=await (await call('admin','GET',auditPath,200)).json();
    assert.equal(northAudit.events.filter(event=>event.action==='operator_invited').length,2);
    assert.equal(northAudit.events.filter(event=>event.action==='operator_invitation_revoked').length,1);
    assert.ok(northAudit.events.every(event=>Object.keys(event).sort().join(',')===
      'action,actorEmail,createdAt,id'));
    const southAudit=await (await call('admin','GET',otherLab+'/administrative-audit',200)).json();
    assert.ok(southAudit.events.every(event=>event.action!=='operator_invited'));
    await call('patient','GET',auditPath,403);
    console.log('API: personal y permisos administrativos aislados por laboratorio.');
    await call('uploader','POST',base+'/patients',201,{json:{
      patientId:ids.patient,identityEvidenceReference:'verificacion-ficticia',identityVerified:true,
    }});
    const directory=await call('uploader','GET',base+'/patients?search='+encodeURIComponent(credentials.patient.email.toUpperCase())+'&limit=1',200);
    const linked=await directory.json();
    assert.deepEqual(linked.patients.map(patient=>patient.id),[ids.patient]);
    assert.equal(linked.hasMore,false);
    const otherDirectory=await call('reviewer','GET',otherLab+'/patients',200);
    assert.deepEqual((await otherDirectory.json()).patients,[]);
    await call('uploader','GET',otherLab+'/patients',403);
    const requestPdf=syntheticPdf([
      'Referencia: SOL-1002','Profesional solicitante: Persona Ficticia',
      'Fecha de solicitud: 2024-01-01','Glicemia',
    ]);
    const intake=base+'/medical-requests';
    const requestFile={bytes:requestPdf,headers:{
      'Content-Type':'application/pdf','x-request-filename':'solicitud.pdf',
    }};
    await call('uploader','POST',otherLab+'/medical-requests/preview',403,requestFile);
    const preview=await (await call('uploader','POST',intake+'/preview',200,requestFile)).json();
    assert.equal(preview.state,'text_ready');
    assert.equal(preview.suggestedDocumentReference,'SOL-1002');
    assert.equal(preview.suggestedPrescriberName,'Persona Ficticia');
    assert.equal(preview.suggestedRequestDate,'2024-01-01');
    assert.ok(preview.suggestedExams.some(exam=>exam.code==='glicemia'));
    assert.equal((await (await call('uploader','GET',base+'/orders',200)).json()).orders.length,0);
    const confirmation={bytes:requestPdf,headers:{
      ...requestFile.headers,
      'x-request-patient-id':ids.patient,'x-request-exam-codes':'glicemia',
      'x-request-reference':'SOL-1002','x-request-prescriber':'Persona Ficticia',
      'x-request-date':'2024-01-01','x-request-identity-confirmed':'true',
      'x-request-reviewed':'true',
    }};
    await call('uploader','POST',intake,400,{...confirmation,headers:{
      ...confirmation.headers,'x-request-reviewed':'false',
    }});
    await call('uploader','POST',intake,404,{...confirmation,headers:{
      ...confirmation.headers,'x-request-patient-id':ids.other,
    }});
    const created=await call('uploader','POST',intake,201,confirmation);
    const registered=await created.json();
    const orderId=registered.order.id;
    const adminOrders = await (await call('admin', 'GET', base+'/orders', 200)).json();
    assert.ok(adminOrders.orders.some(order => order.id === orderId));
    await call('admin', 'GET', base+'/orders?patientId='+ids.patient, 403);
    await call('admin', 'GET', base+'/orders/'+orderId+'/medical-request/file', 403);
    assert.match(registered.request.documentReference,
      /^SOL-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    assert.equal(registered.request.documentReference, 'SOL-'+registered.request.id);
    assert.notEqual(registered.request.documentReference,'SOL-1002',
      'El backend debe generar una referencia interna, no aceptar la del cliente.');
    const storedRequestReference=await db.query(
      'SELECT document_reference FROM public.vitalia_sil_main_medical_requests WHERE id=$1',
      [registered.request.id]);
    assert.equal(storedRequestReference.rows[0].document_reference,
      registered.request.documentReference);
    await call('uploader','POST',intake,409,confirmation);
    assert.equal((await (await call('uploader','GET',base+'/orders',200)).json()).orders.length,1);
    const summaryPath=base+'/summary';
    const summary=(await (await call('uploader','GET',summaryPath,200)).json()).summary;
    assert.deepEqual(summary,{
      ordersTotal:1,registered:1,inReview:0,published:0,pendingRequests:0,
    },'El resumen debe contar la tabla completa del laboratorio.');
    await call('patient','GET',summaryPath,403);
    await call('admin','GET',summaryPath,403);
    await call('uploader','GET',otherLab+'/summary',403);
    const requestPath='/orders/'+orderId+'/medical-request/file';
    await call('patient','GET',base+requestPath,403);
    await call('uploader','GET',otherLab+requestPath,403);
    await call('reviewer','GET',otherLab+requestPath,404);
    const original=await call('uploader','GET',base+requestPath,200);
    assert.deepEqual(Buffer.from(await original.arrayBuffer()),requestPdf);
    console.log('API: lectura, confirmación y registro atómico de solicitud verificados.');
    const clinical=base+'/orders/'+orderId+'/clinical';
    assert.equal((await (await call('uploader','GET',clinical,200)).json()).hasMedicalRequest,true);
    const sample=code=>({json:{containerCode:code}});
    const values={json:{values:[{examCode:'glicemia',analyte:'Glucosa',numericValue:91.2}]}};
    await call('uploader','GET',otherLab+'/orders/'+orderId+'/clinical',403);
    await call('reviewer','GET',otherLab+'/orders/'+orderId+'/clinical',404);
    await call('uploader','POST',clinical+'/results',409,values);
    await call('uploader','POST',clinical+'/samples',409,sample('edta'));
    const resultsPreview=clinical+'/results/preview';
    const resultsPdf=(barcode,...lines)=>({bytes:syntheticPdf([
      'Vitalia - resultados ficticios','Muestra: '+barcode,...lines,
    ]),headers:{'Content-Type':'application/pdf'}});
    const wrongBarcode='LAB-'+randomUUID().toUpperCase();
    await call('uploader','POST',resultsPreview,409,resultsPdf(wrongBarcode,'Glucosa 91,2 mg/dL'));
    const {barcode}=await (await call('uploader','POST',clinical+'/samples',201,sample('fluoride'))).json();
    const matching=resultsPdf(barcode,'Glucosa 91,2 mg/dL');
    await call('patient','POST',resultsPreview,403,matching);
    await call('uploader','POST',otherLab+'/orders/'+orderId+'/clinical/results/preview',403,matching);
    await call('reviewer','POST',otherLab+'/orders/'+orderId+'/clinical/results/preview',404,matching);
    const resultPreview=async file=>(await call('uploader','POST',resultsPreview,200,file)).json();
    assert.deepEqual(await resultPreview(matching),{
      state:'text_ready',items:[{examCode:'glicemia',analyte:'Glucosa',unit:'mg/dL',suggestedValue:91.2}],
    });
    for(const file of [
      resultsPdf(wrongBarcode,'Glucosa 91,2 mg/dL'),
      resultsPdf(barcode,'Muestra: '+wrongBarcode,'Glucosa 91,2 mg/dL'),
    ]){
      assert.deepEqual(await resultPreview(file),{state:'sample_mismatch',items:[]});
    }
    for(const lines of [
      ['Glucosa 5 mmol/L'],
      ['Glucosa 90 mg/dL','Glucosa 91 mg/dL'],
      ['Glucosa 1.234 mg/dL'],
      ['Glucosa 90 mg/dL 70-110'],
    ]){
      assert.equal((await resultPreview(resultsPdf(barcode,...lines))).items[0].suggestedValue,null);
    }
    assert.equal((await (await call('uploader','GET',clinical,200)).json()).results,null);
    console.log('API: vista previa de resultados sin persistencia, con muestras y unidades cotejadas.');
    await call('uploader','POST',clinical+'/samples',409,sample('fluoride'));
    await call('uploader','POST',clinical+'/results',201,values);
    await call('uploader','POST',resultsPreview,409,matching);
    await call('uploader','POST',clinical+'/review',403,{json:{decision:'approved'}});
    await admin(base+'/staff/review-permission',200,{accountId:ids.uploader,enabled:true});
    await call('uploader','POST',clinical+'/review',200,{json:{decision:'returned',reason:'Revisar valor transcrito'}});
    await call('uploader','POST',clinical+'/results',201,{json:{values:[
      {examCode:'glicemia',analyte:'Glucosa',numericValue:93.1},
    ]}});
    await call('uploader','POST',clinical+'/review',200,{json:{decision:'approved'}});
    const recorded=await (await call('uploader','GET',clinical,200)).json();
    assert.equal(recorded.results.status,'approved');
    assert.equal(recorded.results.values[0].numericValue,93.1);
    console.log('API: muestras, resultados por analito, devolución, corrección y aprobación verificados.');
    const path=base+'/orders/'+orderId+'/report';
    const attached=await call('uploader','POST',path,201,{bytes:pdf,headers:{
      'Content-Type':'application/pdf','X-Report-Filename':'informe-sintetico.pdf',
      'X-Report-Authorized-Professional':'Profesional Ficticio',
      'X-Report-Authorization-Ref':'AUT-FICTICIA',
      'X-Report-Authorized-At':'2024-01-01T12:00:00Z','X-Report-Patient-Confirmed':'true',
    }});
    const reportId=(await attached.json()).report.id;
    const patientFile='/patient/reports/'+reportId+'/file';
    await call('patient','GET',patientFile,404);
    await call('reviewer','GET',path+'/file',403);
    await call('reviewer','GET',otherLab+'/orders/'+orderId+'/report/file',404);
    await admin(base+'/staff/review-permission',200,{accountId:ids.uploader,enabled:true});
    const publish=(actor,status)=>call(actor,'POST',path+'/publish',status,{json:{operatorReviewConfirmed:true}});
    await publish('uploader',409);
    await admin(base+'/staff/review-permission',200,{accountId:ids.reviewer,enabled:true});
    await publish('reviewer',409);
    await call('reviewer','GET',path+'/file',200);
    await publish('uploader',409); // La revisión de otra cuenta no habilita esta publicación.
    const pending=await call('uploader','GET',path+'/file',200);
    assert.deepEqual(Buffer.from(await pending.arrayBuffer()),pdf);
    await admin(base+'/staff/review-permission',200,{accountId:ids.uploader,enabled:false});
    await publish('uploader',403);
    await admin(base+'/staff/review-permission',200,{accountId:ids.uploader,enabled:true});
    await publish('uploader',201);
    await publish('uploader',409);
    await call('other','GET',patientFile,404);
    const patient=await call('patient','GET',patientFile,200);
    assert.deepEqual(Buffer.from(await patient.arrayBuffer()),pdf);
    const historyPath=clinical+'/audit';
    await api('GET','/api/sil/main'+historyPath,401);
    await call('patient','GET',historyPath,403);
    await call('uploader','GET',otherLab+'/orders/'+orderId+'/clinical/audit',403);
    await call('reviewer','GET',otherLab+'/orders/'+orderId+'/clinical/audit',404);
    const historyResponse=await call('uploader','GET',historyPath,200);
    assert.equal(historyResponse.headers.get('cache-control'),'private, no-store');
    const {events,hasOlder}=await historyResponse.json();
    assert.equal(hasOlder,false);
    assert.ok(events.length>1);
    assert.ok(events.every((event,index)=>index===0||event.createdAt<=events[index-1].createdAt));
    assert.ok(events.some(event=>event.action==='results_recorded'&&event.staffEmail===credentials.uploader.email));
    assert.ok(events.some(event=>event.action==='report_downloaded'&&event.staffEmail===null));
    assert.ok(events.every(event=>Object.keys(event).sort().join(',')==='action,createdAt,staffEmail'));
    console.log('API: historial de la orden verificado con aislamiento por laboratorio y datos mínimos.');
    const audit=await db.query(`SELECT action,actor_id FROM public.vitalia_sil_main_audit
      WHERE order_id=$1 ORDER BY created_at,id`,[orderId]);
    for(const [action,actor] of [
      ['report_attached','uploader'],['report_review_accessed','uploader'],
      ['report_published','uploader'],['report_downloaded','patient'],
    ]){
      assert.ok(audit.rows.some(row=>row.action===action && row.actor_id===ids[actor]),action);
    }
    await api('POST','/api/auth/logout',204,{token:tokens.patient});
    await call('patient','GET',patientFile,401);
    // El operador recibe una derivación y la guarda SIN una cuenta paciente.
    const pendingEmail='patient-invited@example.invalid';
    const pendingPdf=syntheticPdf([
      'Paciente: Ana María Pérez Soto','RUT: 12.345.678-5',
      'Fecha de nacimiento: 12/04/1990',
      'Correo electrónico: patient-invited@example.invalid',
      'Teléfono: +56 9 1234 5678',
      'Sexo: Femenino',
      'Referencia: SOL-PEND-0042',
      'Profesional solicitante: Persona Ficticia',
      'Fecha de solicitud: 2024-01-01','Glicemia',
    ]);
    const pendingPath=base+'/medical-requests/pending';
    const pendingUpload={bytes:pendingPdf,headers:{
      'Content-Type':'application/pdf',
      'x-request-filename':'derivacion-pendiente.pdf',
      'x-request-patient-email':pendingEmail,
    }};
    // La sesión del paciente fue revocada arriba: debe recibir 401, no 403.
    await call('patient','POST',pendingPath,401,pendingUpload);
    await call('uploader','POST',otherLab+'/medical-requests/pending',403,pendingUpload);
    const savedPending=await (await call('uploader','POST',pendingPath,201,pendingUpload)).json();
    const pendingId=savedPending.pending.id;
    assert.equal(savedPending.pending.status,'pending');
    assert.equal(savedPending.pending.patientEmail,pendingEmail);
    assert.ok(Object.hasOwn(savedPending.pending.suggestions,'suggestedPatient'));
    await call('uploader','POST',pendingPath,409,pendingUpload);
    const savedList=await (await call('uploader','GET',pendingPath,200)).json();
    assert.ok(savedList.pending.some(item=>item.id===pendingId));
    const beforeComplete=(await (await call('uploader','GET',summaryPath,200)).json()).summary;
    assert.equal(beforeComplete.pendingRequests,1,
      'Una derivación guardada debe sumar en el total del laboratorio.');
    await call('patient','GET',pendingPath,401);
    await call('reviewer','GET',otherLab+'/medical-requests/pending/'+pendingId+'/file',404);
    const savedPdf=await call('uploader','GET',
      pendingPath+'/'+pendingId+'/file',200);
    assert.deepEqual(Buffer.from(await savedPdf.arrayBuffer()),pendingPdf);
    const pendingBeforeActivation=await db.query(
      'SELECT status,order_id FROM public.vitalia_sil_main_pending_requests WHERE id=$1',
      [pendingId]);
    assert.equal(pendingBeforeActivation.rows[0].status,'pending');
    assert.equal(pendingBeforeActivation.rows[0].order_id,null);
    const pendingOrdersBefore=await db.query(
      'SELECT count(*)::int AS total FROM public.vitalia_sil_main_orders WHERE lab_id=$1',[base.slice(6)]);
    assert.ok(pendingOrdersBefore.rows[0].total>=1);
    console.log('API: derivación con identidad sugerida guardada sin cuenta ni orden.');


    const inviteEmail='patient-invited@example.invalid';
    const inviteInput={email:inviteEmail,identityReference:'verificacion-ficticia-invitacion',identityConfirmed:true};
    const oldInvite=await (await call('uploader','POST',base+'/patient-invitations',201,{json:inviteInput})).json();
    const invite=await (await call('uploader','POST',base+'/patient-invitations',201,{json:inviteInput})).json();
    await api('POST','/api/sil/main/patients/activate',403,{json:{email:inviteEmail,code:oldInvite.code,password}});
    const activation={email:inviteEmail,code:invite.code,password};
    await api('POST','/api/sil/main/patients/activate',201,{json:activation});
    await call('uploader','POST',base+'/patient-invitations',409,{json:inviteInput});
    await api('POST','/api/sil/main/patients/activate',403,{json:activation});
    const invited=await (await api('POST','/api/auth/login',200,{json:{
      mode:'paciente',email:inviteEmail,password,
    }})).json();
    const recovery=await (await api('POST','/api/sil/main/patient/recovery/key',201,{
      token:invited.token,json:{currentPassword:password},
    })).json();
    const recovered={email:inviteEmail,recoveryKey:recovery.recoveryKey,password:'ClaveNueva-SoloPrueba-2026!'};
    await api('POST','/api/sil/main/patient/recovery/complete',204,{json:recovered});
    await api('POST','/api/sil/main/patient/recovery/complete',422,{json:recovered});
    await api('GET','/api/auth/me',401,{token:invited.token});
    // Mantener el límite real de 10 intentos/IP. El ensayo ya autentica
    // cinco cuentas iniciales, una invitada y tres roles en Edge. Verificar
    // la clave anterior/nueva con el mismo servicio de credenciales evita
    // agotar la cuota por una comprobación redundante de HTTP.
    const verifyRecovered=await createCredentialAuthenticator(db,{
      guardPatientSession:true,
    });
    assert.equal(await verifyRecovered({
      mode:'paciente',email:inviteEmail,password,
    }),null,'La contraseña anterior no debe autenticar después de la recuperación.');
    const newCredential=await verifyRecovered({
      mode:'paciente',email:inviteEmail,password:recovered.password,
    });
    assert.equal(newCredential?.email,inviteEmail);
    assert.equal(newCredential?.role,'paciente');
    const pendingPatient=(await db.query(
      'SELECT id FROM public.vitalia_accounts WHERE email=$1',[pendingEmail])).rows[0];
    assert.ok(pendingPatient?.id,'La activación debe crear cuenta paciente.');
    const pendingComplete=pendingPath+'/'+pendingId+'/complete';
    const pendingData={
      patientId:pendingPatient.id,patientEmail:pendingEmail,
      examCodes:['glicemia'],
      // Sin documentReference: el servidor asigna una ID única.
      prescriberName:'Persona Ficticia',
      requestDate:'2024-01-01',
      patientIdentityConfirmed:true,humanReviewConfirmed:true,
    };
    await call('uploader','POST',pendingComplete,400,{json:{
      ...pendingData,patientIdentityConfirmed:false,
    }});
    // Bloquear reutilización de la derivación para otro correo,
    // antes incluso de comprobar si existe la cuenta del paciente.
    await call('uploader','POST',pendingComplete,409,{json:{
      ...pendingData,patientEmail:'equivocado@example.invalid',
    }});
    await call('reviewer','POST',otherLab+'/medical-requests/pending/'+pendingId+'/complete',404,{
      json:pendingData,
    });
    const completed=await (await call('uploader','POST',pendingComplete,201,{
      json:pendingData,
    })).json();
    assert.equal(completed.pending.status,'completed');
    assert.equal(completed.order.patientId,pendingPatient.id);
    assert.equal(completed.request.documentReference,'SOL-'+completed.request.id);
    assert.notEqual(completed.request.documentReference,registered.request.documentReference);
    await call('uploader','POST',pendingComplete,404,{json:pendingData});
    const pendingAfter=await (await call('uploader','GET',pendingPath,200)).json();
    assert.ok(!pendingAfter.pending.some(item=>item.id===pendingId));
    const afterComplete=(await (await call('uploader','GET',summaryPath,200)).json()).summary;
    assert.equal(afterComplete.pendingRequests,0);
    assert.ok(afterComplete.ordersTotal>=2);
    const pendingSaved=await db.query(
      'SELECT status,order_id FROM public.vitalia_sil_main_pending_requests WHERE id=$1',
      [pendingId]);
    assert.equal(pendingSaved.rows[0].status,'completed');
    assert.equal(pendingSaved.rows[0].order_id,completed.order.id);
    const completedPdf=await call('uploader','GET',
      base+'/orders/'+completed.order.id+'/medical-request/file',200);
    assert.deepEqual(Buffer.from(await completedPdf.arrayBuffer()),pendingPdf);
    const pendingAudit=await db.query(
      "SELECT action FROM public.vitalia_sil_main_audit WHERE lab_id=$1 AND action LIKE 'pending_request_%'",
      [base.slice(6)]);
    assert.ok(pendingAudit.rows.some(row=>row.action==='pending_request_saved'));
    assert.ok(pendingAudit.rows.some(row=>row.action==='pending_request_downloaded'));
    assert.ok(pendingAudit.rows.some(row=>row.action==='pending_request_completed'));
    // Cierre de una derivación distinta, sin activar paciente ni crear orden.
    const rejectedPdf=syntheticPdf([
      'Solicitud administrativa ficticia SOL-PEND-CLOSE-01',
      'Paciente: Caso Sintético Vitalia',
      'Profesional: Persona de prueba',
      'Documento ilegible en verificación administrativa',
    ]);
    const rejectedUpload={bytes:rejectedPdf,headers:{
      'Content-Type':'application/pdf',
      'x-request-filename':'solicitud-para-cerrar.pdf',
    }};
    const rejected=(await (await call('uploader','POST',pendingPath,201,
      rejectedUpload)).json()).pending;
    const closePath=pendingPath+'/'+rejected.id+'/cancel';
    const closure={reason:'unreadable_document'};
    const beforeClosureOrders=(await db.query(
      'SELECT count(*)::int AS total FROM public.vitalia_sil_main_orders WHERE lab_id=$1',
      [base.slice(6)])).rows[0].total;
    await call('admin','POST',closePath,403,{json:closure});
    await call('reviewer','POST',
      otherLab+'/medical-requests/pending/'+rejected.id+'/cancel',404,
      {json:closure});
    await call('uploader','POST',closePath,400,{json:{
      ...closure,patientEmail:'no-enviar@example.invalid',
    }});
    const closed=(await (await call('uploader','POST',closePath,200,
      {json:closure})).json()).pending;
    assert.equal(closed.status,'cancelled');
    assert.equal(closed.reason,'unreadable_document');
    await call('uploader','POST',closePath,409,{json:closure});
    await call('uploader','POST',
      pendingPath+'/'+rejected.id+'/complete',404,{json:pendingData});
    await call('uploader','GET',pendingPath+'/'+rejected.id+'/file',404);
    const afterClosureOrders=(await db.query(
      'SELECT count(*)::int AS total FROM public.vitalia_sil_main_orders WHERE lab_id=$1',
      [base.slice(6)])).rows[0].total;
    assert.equal(afterClosureOrders,beforeClosureOrders,
      'Cerrar una derivación no debe generar órdenes.');
    const closedRow=(await db.query(
      `SELECT status,order_id,closure_reason,closed_by,closed_at
       FROM public.vitalia_sil_main_pending_requests WHERE id=$1`,
      [rejected.id])).rows[0];
    assert.equal(closedRow.status,'cancelled');
    assert.equal(closedRow.order_id,null);
    assert.equal(closedRow.closure_reason,'unreadable_document');
    assert.ok(closedRow.closed_by && closedRow.closed_at);
    const closedAudit=(await db.query(
      `SELECT details FROM public.vitalia_sil_main_audit
       WHERE action='pending_request_cancelled' AND lab_id=$1
         AND details->>'pendingId'=$2`,
      [base.slice(6),rejected.id])).rows;
    assert.equal(closedAudit.length,1);
    assert.equal(closedAudit[0].details.reason,'unreadable_document');
    const outstanding=(await (await call('uploader','GET',
      pendingPath,200)).json()).pending;
    assert.ok(!outstanding.some(p=>p.id===rejected.id));
    console.log('API: cierre pendiente transaccional y auditado sin crear orden.');

    console.log('API: derivación pendiente recuperada, activación y orden atómica aprobadas.');

    console.log('API: activación y recuperación del paciente de un solo uso verificadas.');
    console.log('API y PostgreSQL: recorrido con credenciales y sesiones reales aprobado.');
    if(web){
      const site=express();
      site.use(express.static(resolve(web)));
      webServer=await new Promise((accept,reject)=>{
        const listener=site.listen(5173,'127.0.0.1',()=>accept(listener));
        listener.once('error',reject);
      });
      const browserOrder=await call('uploader','POST',base+'/orders',201,{json:{
        patientId:ids.patient,examCodes:['glicemia'],
      }});
      const {order:ready}=await browserOrder.json();
      const {order:sampleOrder}=await (await call('uploader','POST',base+'/orders',201,{json:{
        patientId:ids.patient,examCodes:['glicemia'],
      }})).json();
      const queryOrders=async (actor,labPath,query,status=200)=>(await call(actor,'GET',
        labPath+'/orders?'+new URLSearchParams(query),status)).json();
      const page1=await queryOrders('uploader',base,{limit:1});
      const page2=await queryOrders('uploader',base,{limit:1,offset:1});
      assert.equal(page1.hasMore,true);
      assert.notEqual(page1.orders[0].id,page2.orders[0].id);
      const folio='VH-'+String(sampleOrder.orderNumber).padStart(6,'0');
      const found=await queryOrders('uploader',base,{
        search:folio.toLowerCase(),status:'registered',patientId:ids.patient,
      });
      assert.deepEqual(found.orders.map(order=>order.id),[sampleOrder.id]);
      const email=await queryOrders('uploader',base,{search:credentials.patient.email.toUpperCase()});
      assert.ok(email.orders.some(order=>order.id===sampleOrder.id));
      assert.deepEqual((await queryOrders('uploader',base,{search:folio,status:'report_published'})).orders,[]);
      assert.deepEqual((await queryOrders('uploader',base,{patientId:ids.other})).orders,[]);
      assert.deepEqual((await queryOrders('reviewer',otherLab,{search:folio})).orders,[]);
      await queryOrders('uploader',otherLab,{search:folio},403);
      await queryOrders('admin',base,{search:credentials.patient.email},403);
      await queryOrders('uploader',base,{status:'missing'},400);
      console.log('API: búsqueda, filtros y paginación de órdenes verificados.');
      const samplePath=base+'/orders/'+sampleOrder.id;
      assert.equal((await (await call('uploader','GET',samplePath+'/clinical',200)).json()).hasMedicalRequest,false);
      await call('uploader','POST',samplePath+'/medical-request',201,{
        bytes:browserRequestPdf,headers:{
          ...requestFile.headers,'x-request-reference':'SOL-1004',
          'x-request-prescriber':'Persona Ficticia','x-request-date':'2024-01-01',
          'x-request-identity-confirmed':'true','x-request-reviewed':'true',
        },
      });
      const {barcode:sampleCode}=await (await call('uploader','POST',
        base+'/orders/'+sampleOrder.id+'/clinical/samples',201,sample('fluoride'))).json();
      const samplePdf=resultsPdf(sampleCode,'Glucosa 91,2 mg/dL').bytes;
      if(manual){
        writeFileSync(fixture,pdf,{flag:'wx'});
        const newRequest=resolve(dirname(fixture),'solicitud-ficticia.pdf');
        writeFileSync(newRequest,syntheticPdf([
          'Referencia: SOL-1003','Profesional solicitante: Persona Ficticia',
          'Fecha de solicitud: 2024-01-01','Glicemia',
        ]),{flag:'wx'});
        const resultsFixture=resolve(dirname(fixture),'resultados-ficticios.pdf');
        writeFileSync(resultsFixture,samplePdf,{flag:'wx'});
        console.log('PDF para crear una orden desde Recibir solicitud: '+newRequest);
        console.log('Orden para probar la lectura de resultados: VH-'+String(sampleOrder.orderNumber).padStart(6,'0'));
        console.log('PDF para Muestras y resultados > Leer PDF de resultados: '+resultsFixture);
        console.log('\nSIL temporal listo en http://localhost:5173/#/laboratorio');
        console.log('Orden disponible: VH-'+String(ready.orderNumber).padStart(6,'0'));
        console.log('Adjunta el PDF con '+credentials.uploader.email+'.');
        console.log('Con esa misma cuenta, descarga el PDF de revisión, confirma y publica.');
        console.log('Consulta el informe con '+credentials.patient.email+' en http://localhost:5173/.');
        if(demo.admin){
          console.log('Acceso de administración de prueba: '+credentials.admin.email+'.');
          console.log('Usa las contraseñas del DEMO que ingresaste en PowerShell.');
        } else {
          console.log('Contraseña de estas cuentas ficticias: '+password);
        }
        console.log('PDF para adjuntar: '+fixture);
        const input=createInterface({input:process.stdin,output:process.stdout});
        try {
          await input.question('Pulsa Enter para cerrar el ensayo.\n');
        } finally {
          input.close();
        }
      } else {
        await browserJourney(ready,base,sampleOrder,samplePdf);
      }
    }
    if(!manual) {
      // Ensayo real de suspensión por laboratorio, después del recorrido Edge.
      const membership=base+'/staff/membership';
      await call('uploader','POST',membership,403,{json:{
        accountId:ids.uploader,active:false,
      }});
      await call('admin','POST',membership,400,{json:{
        accountId:ids.uploader,active:'false',
      }});
      const suspended=(await (await call('admin','POST',membership,200,{json:{
        accountId:ids.uploader,active:false,
      }})).json()).membership;
      assert.equal(suspended.active,false);
      assert.equal(suspended.canReviewReports,false);
      await call('uploader','GET',base+'/summary',403);
      await call('admin','POST',membership,409,{json:{
        accountId:ids.uploader,active:false,
      }});
      const restored=(await (await call('admin','POST',membership,200,{json:{
        accountId:ids.uploader,active:true,
      }})).json()).membership;
      assert.equal(restored.active,true);
      assert.equal(restored.canReviewReports,false,
        'Reactivar no debe recuperar permisos de revisión.');
      await call('uploader','GET',base+'/summary',200);
      const history=(await db.query(
        `SELECT action,details FROM public.vitalia_sil_main_audit
         WHERE lab_id=$1 AND action IN
         ('operator_membership_disabled','operator_membership_enabled')
         ORDER BY created_at`,[base.slice(6)])).rows;
      assert.deepEqual(history.map(x=>x.action),
        ['operator_membership_disabled','operator_membership_enabled']);
      assert.ok(history.every(x=>x.details.accountId===ids.uploader));
      console.log('API: suspensión y reactivación por laboratorio auditadas.');
    }
  } finally {
    if(webServer)await new Promise(done=>webServer.close(done));
    if(server)await new Promise(done=>server.close(done));
    await db.end();
  }
}

main().catch(error=>{console.error(error.message);process.exitCode=1;});
