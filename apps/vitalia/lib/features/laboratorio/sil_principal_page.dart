import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';
import 'sil_workspace.dart';
import 'sil_main_clinical_panel.dart';
import 'operator_design.dart';
import 'operator_guided_flow.dart';

/// Estación de trabajo integrada a Vitalia original.
/// Sin simuladores ni entidades ficticias de laboratorio.
class SilPrincipalPage extends StatefulWidget {
  const SilPrincipalPage({
    super.key,
    required this.api,
    required this.role,
    required this.onExpired,
    required this.onLogout,
  });

  final AuthApi api;
  final String role;
  final VoidCallback onExpired;
  final VoidCallback onLogout;

  @override
  State<SilPrincipalPage> createState() => _SilPrincipalPageState();
}

enum _StationSection { dashboard, orders, requests, patients, clinical, review }
enum _AdminSection { laboratories, operators, activity }

class _SilPrincipalPageState extends State<SilPrincipalPage> {
  final _name = TextEditingController();
  final _inviteEmail = TextEditingController();
  final _staffAccount = TextEditingController();
  List<Map<String,dynamic>> _labStaff = [];
  bool _staffLoaded = false;
  final _invitedPatientEmail = TextEditingController();
  final _patientSearch = TextEditingController();
  List<Map<String,dynamic>> _patients = [];
  int _patientOffset = 0;
  bool _morePatients = false;
  String _activePatientSearch = '';
  final _evidence = TextEditingController();
  final _orderPatient = TextEditingController();
  final _orderPatientSearch = TextEditingController();
  Map<String,dynamic>? _manualPatient;
  String? _patientInviteStatus;
  final _requestPatient = TextEditingController();
  final _requestInviteEmail = TextEditingController();
  final _requestIdentityEvidence = TextEditingController();
  bool _requestPatientVerified = false;
  String? _requestPatientStatus;
  List<Map<String,dynamic>> _pendingRequests = [];
  String? _pendingRequestId;
  Map<String,dynamic> _requestIdentitySuggestions = {};
  final _requestExams = <String>{};
  bool _attachToExistingOrder = false;
  String? _requestPreviewNotice;
  final _requestPrescriber = TextEditingController();
  final _requestDate = TextEditingController();
  final _reportProfessional = TextEditingController();
  final _reportReference = TextEditingController();
  final _reportDate = TextEditingController();
  _StationSection _activeSection = _StationSection.dashboard;
  _AdminSection _adminSection = _AdminSection.laboratories;
  bool _verifiedPatient = false;
  bool _externallyAuthorized = false;
  bool _confirmedMatch = false;
  bool _reviewConfirmed = false;
  bool _reviewPdfDownloaded = false;
  String? _labId;
  String? _requestOrderId;
  XFile? _medicalRequestFile;
  bool _requestIdentityChecked=false;
  bool _requestHumanChecked=false;
  String? _uploadOrderId;
  String? _reviewOrderId;
  Map<String,dynamic>? _reviewSelectedOrder;
  List<Map<String,dynamic>> _reviewOrders = [];
  int _reviewOffset = 0;
  bool _moreReviewOrders = false;
  static const _reviewPageSize = 20;
  XFile? _pdf;
  List<Map<String,dynamic>> _labs = [];
  List<Map<String,dynamic>> _orders = [];
  // Totales calculados por PostgreSQL; null = aún no disponible.
  Map<String,int>? _operatorSummary;
  int _summaryCount(String key,int fallback) =>
      _operatorSummary?[key] ?? fallback;
  final _orderSearch = TextEditingController();
  List<Map<String,dynamic>> _orderPage = [];
  Map<String,dynamic>? _clinicalOrder;
  String _activeOrderSearch = '';
  String _orderStatus = '';
  Map<String,dynamic>? _ordersPatient;
  int _orderOffset = 0;
  bool _moreOrders = false;
  static const _orderPageSize = 20;

  Iterable<Map<String,dynamic>> get _workflowOrders => {
    if (_clinicalOrder != null) _clinicalOrder!['id']: _clinicalOrder!,
    for (final order in _orderPage) order['id']: order,
    for (final order in _orders) order['id']: order,
  }.values;

  final _codes = <String>{'glicemia'};
  bool _busy = false;
  String? _notice;
  String? _error;
  static const _catalog = [
    ('hemograma','Hemograma'),
    ('perfil_lipidico','Perfil lipídico'),
    ('glicemia','Glicemia'),
    ('hba1c','HbA1c'),
    ('perfil_renal','Perfil renal'),
    ('perfil_hepatico','Perfil hepático'),
  ];

  bool get _mobileDevice => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  bool get _admin => widget.role=='administrador';
  bool get _operator => widget.role=='operador_laboratorio';
  bool get _canReview => _operator && _labs.any(
    (lab)=>lab['id']==_labId && lab['canReviewReports']==true,
  );
  bool _isReviewable(Map<String,dynamic> order) =>
    order['status']=='report_attached';

  @override
  void initState(){
    super.initState();
    if (_mobileDevice) return;
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)_execute(_loadLabs,showNotice:false);
    });
  }

  @override
  void dispose(){
    for(final ctrl in [
      _name,_inviteEmail,_staffAccount,_invitedPatientEmail,_patientSearch,_orderSearch,_evidence,_orderPatient,_orderPatientSearch,
      _requestPatient,_requestInviteEmail,_requestIdentityEvidence,
      _requestPrescriber,_requestDate,
      _reportProfessional,_reportReference,_reportDate,
    ]){ctrl.dispose();}
    super.dispose();
  }

  Future<void> _execute(Future<void> Function() task,
      {bool showNotice=true}) async {
    if(_busy)return;
    setState((){_busy=true;_error=null;_notice=null;});
    try{
      await task();
      if(mounted && showNotice)setState(()=>_notice='Operación registrada correctamente.');
    }on AuthFailure catch(error){
      if(!mounted)return;
      if(error.status==401){
        widget.onExpired();
      }else{
        setState(()=>_error=error.message);
      }
    }catch(_){
      if(mounted)setState(()=>_error='No pudimos completar la operación. Comprueba la conexión.');
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  Future<void> _loadLabs() async {
    final data=await widget.api.silMainRequest('/labs');
    final labs=(data['laboratories'] as List? ?? [])
      .map((v)=>Map<String,dynamic>.from(v as Map)).toList();
    if(!mounted)return;
    final selected=labs.any((lab)=>lab['id']==_labId)
      ? _labId
      : labs.isEmpty?null:labs.first['id'] as String?;
    setState((){
      _labs=labs;
      if (selected != _labId) _resetLab(selected);
    });
    // Administración carga el personal del laboratorio de forma independiente.
    // Órdenes y derivaciones se consultan desde la estación del operador.
    if (_operator) {
      await _loadOrders();
      await _loadPendingRequests();
    } else if (_admin && _labId != null) {
      await _loadStaff();
    }
  }

  /// Consulta cifras completas del laboratorio; nunca se atribuyen totales
  /// al subconjunto de 50 órdenes visible en la estación.
  Future<void> _refreshOperatorSummary() async {
    final lab = _labId;
    if (!_operator || lab == null) {
      if (mounted) setState(() => _operatorSummary = null);
      return;
    }
    // Al cambiar de laboratorio o refrescar, no mostrar cifras caducadas.
    if (mounted) setState(() => _operatorSummary = null);
    try {
      final response = await widget.api.silMainRequest('/labs/$lab/summary');
      if (!mounted || lab != _labId) return;
      final raw = response['summary'];
      if (raw is! Map) return;
      const fields = [
        'ordersTotal','registered','inReview','published','pendingRequests',
      ];
      final parsed = <String,int>{};
      for (final field in fields) {
        final value = raw[field];
        if (value is! int || value < 0) return;
        parsed[field] = value;
      }
      setState(() => _operatorSummary = parsed);
    } on AuthFailure catch (error) {
      if (error.status == 401) rethrow;
      // El trabajo operativo sigue disponible, pero no se presentan
      // estimaciones como estadísticas completas.
    } catch (_) {
      // Las listas recientes siguen disponibles con su alcance identificado.
    }
  }

  Future<void> _loadPendingRequests() async {
    final lab=_labId;
    if(!_operator||lab==null) {
      if(mounted)setState(()=>_pendingRequests=[]);
      return;
    }
    final data=await widget.api.silMainRequest(
      '/labs/$lab/medical-requests/pending?limit=50&offset=0');
    if(!mounted||_labId!=lab)return;
    setState(()=>_pendingRequests=(data['pending'] as List? ?? [])
      .map((row)=>Map<String,dynamic>.from(row as Map)).toList());
    await _refreshOperatorSummary();
  }

  // Lista de operadores que ya tienen acceso al laboratorio actual.
  // Nunca incluye contraseñas ni códigos de invitación.
  Future<void> _loadStaff() async {
    final lab=_labId;
    if(!_admin || lab==null){
      if (mounted) setState(() {
        _labStaff = [];
        _staffLoaded = false;
      });
      return;
    }
    final result=await widget.api.silMainRequest('/labs/$lab/staff');
    if(!mounted || _labId!=lab)return;
    setState(() {
      _labStaff = (result['staff'] as List? ?? [])
        .map((value) => Map<String, dynamic>.from(value as Map)).toList();
      _staffLoaded = true;
    });
  }

  Future<void> _loadOrders() async {
    final lab=_labId;
    if(lab==null){
      if(mounted)setState(()=>_orders=[]);
      return;
    }
    final data=await widget.api.silMainRequest('/labs/$lab/orders?limit=50&offset=0');
    final orders=(data['orders'] as List? ?? [])
      .map((v)=>Map<String,dynamic>.from(v as Map)).toList();
    if(!mounted)return;
    setState(() {
      _orders = orders;
      _validateOrderSelections();
    });
    if (_activeSection == _StationSection.orders || _admin || _orderPage.isNotEmpty) {
      await _loadOrderPage(offset: _orderOffset);
    }
    if (_operator) await _refreshOperatorSummary();
  }

  void _validateOrderSelections() {
    if (!_workflowOrders.any((order) =>
        order['id'] == _uploadOrderId && order['status'] == 'registered')) {
      _uploadOrderId = null;
      _confirmedMatch = false;
    }
    if (!_workflowOrders.any((order) =>
        order['id'] == _requestOrderId && order['status'] == 'registered')) {
      _requestOrderId = null;
      _requestIdentityChecked = false;
      _requestHumanChecked = false;
    }
    if (!_workflowOrders.any((order) =>
        order['id'] == _reviewOrderId && _isReviewable(order)) &&
        !_reviewOrders.any((order) =>
            order['id'] == _reviewOrderId && _isReviewable(order)) &&
        (_reviewSelectedOrder == null ||
            _reviewSelectedOrder!['id'] != _reviewOrderId ||
            !_isReviewable(_reviewSelectedOrder!))) {
      _reviewOrderId = null;
      _reviewSelectedOrder = null;
      _reviewPdfDownloaded = false;
      _reviewConfirmed = false;
    }
  }

  Future<void> _loadOrderPage({required int offset, String? search, String? status}) async {
    final lab = _labId;
    if (lab == null) return;
    final term = search ?? _activeOrderSearch;
    final state = status ?? _orderStatus;
    final patient = _ordersPatient?['id'] as String?;
    final query = Uri(queryParameters: {
      'limit': '$_orderPageSize', 'offset': '$offset',
      if (term.isNotEmpty) 'search': term,
      if (state.isNotEmpty) 'status': state,
      if (patient != null) 'patientId': patient,
    }).query;
    final data = await widget.api.silMainRequest('/labs/$lab/orders?$query');
    if (!mounted || _labId != lab) return;
    final orders = (data['orders'] as List? ?? [])
        .map((entry) => Map<String,dynamic>.from(entry as Map)).toList();
    if (orders.isEmpty && offset > 0) {
      await _loadOrderPage(offset: 0, search: term, status: state);
      return;
    }
    setState(() {
      _orderPage = orders;
      _orderOffset = offset;
      _activeOrderSearch = term;
      _orderStatus = state;
      _moreOrders = data['hasMore'] == true;
      _validateOrderSelections();
    });
  }

  // La revisión consulta órdenes filtradas directamente al backend.
  // No depende de las últimas 50 órdenes que muestra el resumen.
  Future<void> _loadReviewPage({required int offset}) async {
    final lab = _labId;
    if (lab == null || !_canReview) {
      if (mounted) setState(() {
        _reviewOrders = [];
        _reviewOffset = 0;
        _moreReviewOrders = false;
      });
      return;
    }
    final query = Uri(queryParameters: {
      'limit': '$_reviewPageSize',
      'offset': '$offset',
      'status': 'report_attached',
    }).query;
    final data = await widget.api.silMainRequest('/labs/$lab/orders?$query');
    if (!mounted || _labId != lab || !_canReview) return;
    final orders = (data['orders'] as List? ?? [])
        .map((entry) => Map<String,dynamic>.from(entry as Map))
        .where(_isReviewable).toList();
    if (orders.isEmpty && offset > 0) {
      await _loadReviewPage(offset: 0);
      return;
    }
    setState(() {
      _reviewOrders = orders;
      _reviewOffset = offset;
      _moreReviewOrders = data['hasMore'] == true;
      if (_reviewOrderId != null &&
          !orders.any((order) => order['id'] == _reviewOrderId) &&
          _reviewSelectedOrder?['id'] != _reviewOrderId) {
        _reviewOrderId = null;
        _reviewPdfDownloaded = false;
        _reviewConfirmed = false;
      }
    });
  }

  Future<void> _changeReviewPage(int offset) async {
    if (offset != _reviewOffset) {
      // Nunca arrastrar una confirmación de revisión entre páginas.
      setState(() {
        _reviewOrderId = null;
        _reviewSelectedOrder = null;
        _reviewPdfDownloaded = false;
        _reviewConfirmed = false;
      });
    }
    await _loadReviewPage(offset: offset);
  }

  void _showPatientOrders(Map<String,dynamic>? patient) {
    if (_busy) return;
    setState(() {
      _ordersPatient = patient;
      _orderSearch.clear();
      _activeOrderSearch = '';
      _orderStatus = '';
      _orderOffset = 0;
      _orderPage = [];
      _moreOrders = false;
      _validateOrderSelections();
      _activeSection = _StationSection.orders;
    });
    _execute(() => _loadOrderPage(offset: 0), showNotice: false);
  }

  void _resetLab(String? value) {
    _labId = value;
    _labStaff = [];
    _staffLoaded = false;
    _staffAccount.clear();
    _activeSection = _StationSection.dashboard;
    _patients = [];
    _patientSearch.clear();
    _activePatientSearch = '';
    _patientOffset = 0;
    _morePatients = false;
    _orders = [];
    _operatorSummary = null;
    _orderPage = [];
    _clinicalOrder = null;
    _ordersPatient = null;
    _orderSearch.clear();
    _orderPatient.clear();
    _orderPatientSearch.clear();
    _manualPatient = null;
    _patientInviteStatus = null;
    _activeOrderSearch = '';
    _orderStatus = '';
    _orderOffset = 0;
    _moreOrders = false;
    for (final controller in [
      _invitedPatientEmail, _evidence, _orderPatient, _requestPatient,
      _requestInviteEmail, _requestIdentityEvidence, _requestPrescriber,
      _requestDate, _reportProfessional, _reportReference, _reportDate,
    ]) {
      controller.clear();
    }
    _verifiedPatient = false;
    _requestPatientVerified = false;
    _requestPatientStatus = null;
    _pendingRequestId = null;
    _pendingRequests = [];
    _requestIdentitySuggestions = {};
    _requestOrderId = null;
    _attachToExistingOrder = false;
    _requestExams.clear();
    _requestPreviewNotice = null;
    _medicalRequestFile = null;
    _requestIdentityChecked = false;
    _requestHumanChecked = false;
    _uploadOrderId = null;
    _pdf = null;
    _externallyAuthorized = false;
    _confirmedMatch = false;
    _reviewOrderId = null;
    _reviewSelectedOrder = null;
    _reviewOrders = [];
    _reviewOffset = 0;
    _moreReviewOrders = false;
    _reviewPdfDownloaded = false;
    _reviewConfirmed = false;
  }

  void _selectLab(String? value) {
    if (value == _labId || _busy) return;
    setState(() => _resetLab(value));
    _execute(() async {
      if (_operator) {
        await _loadOrders();
        await _loadPendingRequests();
      } else if (_admin) {
        await _loadStaff();
      }
    },showNotice:false);
  }

  String? _requireUuid(String value) {
    final normalized=value.trim().toLowerCase();
    return RegExp(r'^[a-f0-9-]{36}$').hasMatch(normalized)
      ?normalized:null;
  }

  Future<void> _createLab() async {
    final name=_name.text.trim();
    if(name.length<3)throw const AuthFailure('Ingresa el nombre del laboratorio.');
    await widget.api.silMainRequest('/labs',body:{'displayName':name});
    _name.clear();
    await _loadLabs();
  }

  Future<void> _inviteOperator() async {
    final lab=_labId;
    final email=_inviteEmail.text.trim().toLowerCase();
    if(lab==null||!email.contains('@')||email.length>254){
      throw const AuthFailure('Selecciona laboratorio e ingresa un correo válido.');
    }
    final response=await widget.api.silMainRequest(
      '/labs/$lab/operator-invitations',
      body:{'email':email},
    );
    final invitation=Map<String,dynamic>.from(response['invitation'] as Map);
    final code=invitation['code'] as String;
    if(!mounted)return;
    await showDialog<void>(
      context:context,
      barrierDismissible:false,
      builder:(dialogContext)=>AlertDialog(
        title:const Text('Invitación creada'),
        content:SingleChildScrollView(
          child:ConstrainedBox(
            constraints:const BoxConstraints(maxWidth:480),
            child:Column(
              mainAxisSize:MainAxisSize.min,
              crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                const Text(
                  'El código se muestra solo esta vez. Entrégalo al operador '
                  'por un canal oficial verificado, nunca por un chat público.',
                ),
                const SizedBox(height:15),
                SelectableText(
                  code,
                  style:const TextStyle(
                    fontWeight:FontWeight.w800,
                    fontSize:14,
                  ),
                ),
                const SizedBox(height:12),
                Text('Destinatario: $email'),
                const SizedBox(height:7),
                const Text(
                  'El operador debe acceder a /#/activar-operador '
                  'y crear su contraseña. La invitación vence en 24 horas.',
                  style:TextStyle(fontSize:12,height:1.45),
                ),
              ],
            ),
          ),
        ),
        actions:[
          TextButton.icon(
            onPressed:()=>Clipboard.setData(ClipboardData(text:code)),
            icon:const Icon(Icons.copy_outlined),
            label:const Text('Copiar código'),
          ),
          FilledButton(
            onPressed:()=>Navigator.of(dialogContext).pop(),
            child:const Text('He guardado el código'),
          ),
        ],
      ),
    );
    _inviteEmail.clear();
  }

  Future<void> _grantStaff() async {
    final lab=_labId,accountId=_requireUuid(_staffAccount.text);
    if(lab==null||accountId==null)
      throw const AuthFailure('Selecciona laboratorio y escribe el UUID de la cuenta.');
    await widget.api.silMainRequest('/labs/$lab/staff',body:{
      'accountId':accountId,
    });
    _staffAccount.clear();
    await _loadStaff();
  }

  Future<void> _setReviewPermission(String rawAccountId,bool enabled) async {
    final lab=_labId,accountId=_requireUuid(rawAccountId);
    if(lab==null||accountId==null){
      throw const AuthFailure('Selecciona laboratorio y escribe el UUID del operador.');
    }
    await widget.api.silMainRequest('/labs/$lab/staff/review-permission',body:{
      'accountId':accountId,'enabled':enabled,
    });
    await _loadStaff();
  }

  Future<void> _invitePatient({bool fromRequest = false}) async {
    final lab = _labId;
    final email = (fromRequest ? _requestInviteEmail : _invitedPatientEmail)
        .text.trim().toLowerCase();
    final reference = (fromRequest ? _requestIdentityEvidence : _evidence)
        .text.trim();
    final verified = fromRequest ? _requestPatientVerified : _verifiedPatient;
    if (fromRequest && _medicalRequestFile == null && _pendingRequestId == null) {
      throw const AuthFailure('Selecciona primero el PDF de la derivación.');
    }
    if (lab == null || !email.contains('@') || reference.length < 6 || !verified) {
      throw const AuthFailure('Verifica la identidad e ingresa el correo y la referencia.');
    }
    final invite = await widget.api.silMainRequest('/labs/$lab/patient-invitations', body: {
      'email': email, 'identityReference': reference, 'identityConfirmed': true,
    });
    if (!mounted) return;
    setState(() {
      if (fromRequest) {
        _requestPatientVerified = false;
        _requestIdentityEvidence.clear();
        _requestPatientStatus =
            'Invitación emitida. El paciente debe activar su cuenta antes de crear la orden.';
      } else {
        _verifiedPatient = false;
        _evidence.clear();
        _patientInviteStatus = 'Invitación generada. Entrega el código por un canal verificado. La cuenta estará disponible cuando el paciente la active.';
      }
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Invitación de paciente'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Entrega el código a $email por un canal verificado. Vence en 24 horas.'),
            const SizedBox(height: 12),
            SelectableText(invite['code'] as String),
            if (fromRequest) ...[
              const SizedBox(height: 12),
              const Text('El paciente debe abrir «Activar cuenta de paciente», ingresar su correo y código, y crear una contraseña personal. Después vuelve aquí y pulsa «Buscar paciente activado». El código no se envía automáticamente por correo.'),
            ],
          ]),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(
              ClipboardData(text: invite['code'] as String)),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copiar código'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('He guardado el código'),
          ),
        ],
      ),
    );
  }

  // El correo se usa solo para localizar una cuenta YA activada y vinculada
  // a este laboratorio. No se toma por sí solo como evidencia de identidad.
  Future<void> _findRequestPatient() async {
    final lab = _labId;
    final email = _requestInviteEmail.text.trim().toLowerCase();
    if (lab == null || !email.contains('@') || email.length > 254) {
      throw const AuthFailure('Ingresa el correo del paciente para buscar su cuenta.');
    }
    final query = Uri(queryParameters:{
      'limit':'50', 'offset':'0', 'search':email,
    }).query;
    final found = await widget.api.silMainRequest('/labs/$lab/patients?$query');
    if (!mounted || lab != _labId) return;
    final matches = (found['patients'] as List? ?? [])
        .map((row) => Map<String,dynamic>.from(row as Map))
        .where((row) => (row['email'] as String?)?.toLowerCase() == email)
        .toList();
    if (matches.length != 1 || matches.single['id'] is! String) {
      setState(() {
        _requestPatient.clear();
        _requestPatientStatus =
            'Aún no encontramos una cuenta activa para ese correo en este laboratorio. '
            'Si es un paciente nuevo, verifica su identidad, entrega una invitación y conserva el PDF pendiente. '
            'Cuando termine la activación, vuelve a buscarlo aquí.';
        _requestIdentityChecked = false;
        _requestHumanChecked = false;
      });
      return;
    }
    setState(() {
      _requestPatient.text = matches.single['id'] as String;
      _requestPatientStatus =
          'Cuenta activada y vinculada. Coteja la identidad del PDF antes de crear la orden.';
      _requestIdentityChecked = false;
      _requestHumanChecked = false;
    });
  }

  Future<void> _createOrder() async {
    final lab=_labId,patientId=_requireUuid(_orderPatient.text);
    if(lab==null||patientId==null||_codes.isEmpty){
      throw const AuthFailure('Selecciona laboratorio, paciente y al menos un examen.');
    }
    await widget.api.silMainRequest('/labs/$lab/orders',body:{
      'patientId':patientId,
      'examCodes':_codes.toList(),
    });
    _orderPatient.clear();
    if (mounted) setState(() => _manualPatient = null);
    await _loadOrders();
  }

  Future<void> _pickPdf() async {
    final selection=await openFile(acceptedTypeGroups:const [
      XTypeGroup(label:'Documento PDF',extensions:['pdf'],mimeTypes:['application/pdf']),
    ]);
    if(selection==null||!mounted)return;
    setState(() {
      _pdf = selection;
      _externallyAuthorized = false;
      _confirmedMatch = false;
    });
  }

  Future<void> _pickMedicalRequest() async {
    final file=await openFile(acceptedTypeGroups:const [
      XTypeGroup(label:'Solicitud PDF',extensions:['pdf'],mimeTypes:['application/pdf']),
    ]);
    if (file == null || !mounted) return;
    setState(() {
      _medicalRequestFile = file;
      _pendingRequestId = null;
      _requestIdentitySuggestions = {};
      _requestPatient.clear();
      _requestInviteEmail.clear();
      _requestIdentityEvidence.clear();
      _requestPatientVerified = false;
      _requestPatientStatus = null;
      _requestPrescriber.clear();
      _requestDate.clear();
      _requestExams.clear();
      _requestPreviewNotice = null;
      _requestIdentityChecked = false;
      _requestHumanChecked = false;
    });
  }

  // Usar la fecha del documento cuando se lee; en caso contrario, sugerir
  // la fecha local actual sin ocultar la obligación del cotejo humano.
  String _todayLocalDate() => DateTime.now().toIso8601String().substring(0, 10);

  void _useMedicalSuggestions(Map<String,dynamic> preview){
    _requestPrescriber.text=preview['suggestedPrescriberName'] as String? ?? '';
    final suggestedDate=preview['suggestedRequestDate'] as String?;
    _requestDate.text=suggestedDate != null && suggestedDate.isNotEmpty
      ? suggestedDate : _todayLocalDate();
    _requestExams
      ..clear()
      ..addAll((preview['suggestedExams'] as List? ?? [])
        .whereType<Map>().map((entry)=>entry['code'])
        .whereType<String>()
        .where((code)=>_catalog.any((item)=>item.$1==code)).take(6));
    _requestIdentitySuggestions=preview['suggestedPatient'] is Map
      ?Map<String,dynamic>.from(preview['suggestedPatient'] as Map)
      :{};
    final suggestedEmail=_requestIdentitySuggestions['email'];
    if(_requestInviteEmail.text.trim().isEmpty&&suggestedEmail is String){
      _requestInviteEmail.text=suggestedEmail;
    }
    _requestPreviewNotice=preview['state']=='text_ready'
      ?'Datos sugeridos desde el PDF. Coteja identidad y prestaciones antes de aceptar.'
      :'El PDF no tiene texto legible. Conservamos el archivo, pero los campos se completan manualmente.';
    _requestIdentityChecked=false;
    _requestHumanChecked=false;
  }

  Future<void> _previewMedicalRequest() async {
    final lab=_labId,file=_medicalRequestFile;
    if(lab==null||file==null)throw const AuthFailure('Selecciona el PDF de la solicitud.');
    final preview=await widget.api.silMainPreviewMedicalRequest(
      labId:lab,fileName:file.name,bytes:await file.readAsBytes());
    if(!mounted)return;
    setState(()=>_useMedicalSuggestions(preview));
  }

  Future<void> _savePendingRequest() async {
    final lab=_labId,file=_medicalRequestFile;
    if(lab==null||file==null||_attachToExistingOrder){
      throw const AuthFailure('Selecciona una derivación PDF para guardar pendiente.');
    }
    if(_pendingRequestId!=null){
      throw const AuthFailure('Esta derivación ya está guardada como pendiente.');
    }
    final response=await widget.api.silMainSavePendingRequest(
      labId:lab,fileName:file.name,bytes:await file.readAsBytes(),
      patientEmail:_requestInviteEmail.text.trim().isEmpty
        ?null:_requestInviteEmail.text.trim());
    if(!mounted||lab!=_labId)return;
    final saved=Map<String,dynamic>.from(response['pending'] as Map);
    setState((){
      _pendingRequestId=saved['id'] as String;
      _useMedicalSuggestions(Map<String,dynamic>.from(saved['suggestions'] as Map)
        ..['state']=saved['extractionStatus']);
      _requestPatientStatus='Derivación guardada en el laboratorio seleccionado. '
        'Puedes retomarla después de activar al paciente.';
    });
    await _loadPendingRequests();
  }

  void _selectPendingRequest(String? id){
    if(_busy||id==null)return;
    final matches=_pendingRequests.where((row)=>row['id']==id).toList();
    if(matches.length!=1)return;
    final pending=matches.single;
    final suggestions=Map<String,dynamic>.from(
      pending['suggestions'] as Map? ?? {});
    setState((){
      _pendingRequestId=id;
      _medicalRequestFile=null;
      _requestInviteEmail.text=pending['patientEmail'] as String? ?? '';
      _requestIdentityEvidence.clear();
      _requestPatientVerified=false;
      _requestPatient.clear();
      _requestOrderId=null;
      _attachToExistingOrder=false;
      _useMedicalSuggestions(suggestions..['state']=pending['extractionStatus']);
      _requestPatientStatus='Derivación pendiente recuperada. '
        'Revisa el PDF original antes de crear la orden.';
    });
  }

  Future<void> _downloadPendingRequest() async {
    final lab=_labId,id=_pendingRequestId;
    if(lab==null||id==null){
      throw const AuthFailure('Selecciona una derivación pendiente.');
    }
    final bytes=await widget.api.silMainDownloadPendingRequest(
      labId:lab,pendingId:id);
    final original=XFile.fromData(bytes,
      name:'derivacion-pendiente-$id.pdf',mimeType:'application/pdf');
    await original.saveTo('derivacion-pendiente-$id.pdf');
  }

  Future<void> _completePendingRequest() async {
    final lab=_labId,id=_pendingRequestId;
    final patientId=_requireUuid(_requestPatient.text);
    final email=_requestInviteEmail.text.trim().toLowerCase();
    if(lab==null||id==null||patientId==null||!email.contains('@')||
        _requestExams.isEmpty||!_requestIdentityChecked||!_requestHumanChecked){
      throw const AuthFailure('Selecciona una cuenta activada, las prestaciones '
        'y confirma que cotejaste la identidad y el PDF original.');
    }
    final completion=await widget.api.silMainRequest(
      '/labs/$lab/medical-requests/pending/$id/complete',body:{
        'patientId':patientId,'patientEmail':email,
        'examCodes':_requestExams.toList(),
        'prescriberName':_requestPrescriber.text.trim(),
        'requestDate':_requestDate.text.trim(),
        'patientIdentityConfirmed':true,'humanReviewConfirmed':true,
      });
    if(!mounted)return;
    final reference=(completion['request'] as Map?)?['documentReference'] as String?;
    setState((){
      _notice=reference==null
        ? 'Orden y solicitud registradas correctamente.'
        : 'Orden creada. Identificador de solicitud: $reference';
      _pendingRequestId=null;
      _medicalRequestFile=null;
      _requestPatient.clear();
      _requestInviteEmail.clear();
      _requestIdentityEvidence.clear();
      _requestIdentitySuggestions={};
      _requestPatientVerified=false;
      _requestPatientStatus=null;
      _requestExams.clear();
      _requestPreviewNotice=null;
      _requestIdentityChecked=false;
      _requestHumanChecked=false;
      _requestPrescriber.clear();
      _requestDate.clear();
    });
    await _loadPendingRequests();
    await _loadOrders();
  }

  Future<void> _attachMedicalRequest() async {
    final lab = _labId;
    final file = _medicalRequestFile;
    final orderId = _attachToExistingOrder ? _requestOrderId : null;
    final patientId = _attachToExistingOrder ? null : _requireUuid(_requestPatient.text);
    if (lab == null || file == null ||
        (_attachToExistingOrder ? orderId == null : patientId == null || _requestExams.isEmpty) ||
        !_requestIdentityChecked || !_requestHumanChecked) {
      throw const AuthFailure('Completa la orden o el paciente y las prestaciones. Confirma la identidad y la revisión del PDF.');
    }
    final attached=await widget.api.silMainAttachMedicalRequest(
      labId: lab, orderId: orderId, patientId: patientId, examCodes: _requestExams.toList(),
      fileName: file.name, bytes: await file.readAsBytes(),
      prescriberName: _requestPrescriber.text,
      requestDate: _requestDate.text.trim(),
    );
    if (!mounted) return;
    final reference=(attached['request'] as Map?)?['documentReference'] as String?;
    setState(() {
      _notice=reference==null
        ? 'Solicitud registrada correctamente.'
        : 'Solicitud registrada. Identificador: $reference';
      _medicalRequestFile = null;
      _requestOrderId = null;
      _requestPatient.clear();
      _requestInviteEmail.clear();
      _requestIdentityEvidence.clear();
      _requestPatientVerified = false;
      _requestPatientStatus = null;
      _requestExams.clear();
      _requestPreviewNotice = null;
      _requestIdentityChecked = false;
      _requestHumanChecked = false;
      _requestPrescriber.clear();
      _requestDate.clear();
    });
    await _loadOrders();
  }

  Future<void> _selectReportDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = DateTime(1900);
    final entered = DateTime.tryParse(_reportDate.text.trim());
    final date = await showDatePicker(
      context: context,
      initialDate: entered != null && !entered.isBefore(first) && !entered.isAfter(today)
          ? entered : today,
      firstDate: first,
      lastDate: today,
      confirmText: 'Usar fecha',
      cancelText: 'Cancelar',
    );
    if (date != null && mounted) {
      _reportDate.text = date.toIso8601String().split('T').first;
    }
  }

  Future<void> _attachReport() async {
    final lab=_labId,orderId=_uploadOrderId,file=_pdf;
    if(lab==null||orderId==null||file==null||
       !_externallyAuthorized||!_confirmedMatch){
      throw const AuthFailure('Selecciona orden y PDF, y confirma autorización y paciente.');
    }
    final date=DateTime.tryParse(_reportDate.text.trim());
    if(date==null||date.isAfter(DateTime.now())){
      throw const AuthFailure('Indica una fecha válida de autorización externa.');
    }
    await widget.api.silMainAttachReport(
      labId:lab,
      orderId:orderId,
      fileName:file.name,
      bytes:await file.readAsBytes(),
      authorizationReference:_reportReference.text,
      authorizedProfessionalName:_reportProfessional.text,
      externallyAuthorizedAt:date,
    );
    if(mounted)setState((){
      _pdf=null;
      _uploadOrderId=null;
      _externallyAuthorized=false;
      _confirmedMatch=false;
      _reportReference.clear();
      _reportProfessional.clear();
      _reportDate.clear();
    });
    await _loadOrders();
  }

  Future<void> _downloadReportForReview() async {
    final lab=_labId,orderId=_reviewOrderId;
    if(lab==null||orderId==null){
      throw const AuthFailure('Selecciona un informe pendiente.');
    }
    final bytes=await widget.api.silMainDownloadReportForReview(
      labId:lab,orderId:orderId,
    );
    final pdf=XFile.fromData(bytes,
      name:'informe-pendiente-$orderId.pdf',mimeType:'application/pdf');
    await pdf.saveTo('informe-pendiente-$orderId.pdf');
    if(mounted)setState(()=>_reviewPdfDownloaded=true);
  }

  Future<void> _publishReport() async {
    final lab=_labId,orderId=_reviewOrderId;
    if(lab==null||orderId==null||
       !_reviewPdfDownloaded||!_reviewConfirmed){
      throw const AuthFailure('Selecciona el informe y confirma la revisión del informe.');
    }
    await widget.api.silMainRequest(
      '/labs/$lab/orders/$orderId/report/publish',
      body:{'operatorReviewConfirmed':true},
    );
    if(mounted)setState((){
      _reviewOrderId=null;
      _reviewSelectedOrder=null;
      _reviewConfirmed=false;
      _reviewPdfDownloaded=false;
    });
    await _loadOrders();
    await _loadReviewPage(offset: _reviewOffset);
  }

  Widget _section(String title,String detail,IconData icon,List<Widget> children){
    return Card(
      clipBehavior:Clip.antiAlias,
      child:Padding(
        padding:const EdgeInsets.all(24),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Container(
              padding:const EdgeInsets.all(9),
              decoration:BoxDecoration(
                color:ColoresVitalia.azulSuave,
                borderRadius:BorderRadius.circular(11),
              ),
              child:Icon(icon,color:ColoresVitalia.azul,size:22),
            ),
            const SizedBox(width:11),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
              if (detail.isNotEmpty) ...[
                const SizedBox(height:5),
                Text(detail,style:const TextStyle(
                color:ColoresVitalia.textoSecundario,fontSize:14,height:1.4,
                )),
              ],
            ])),
          ]),
          const SizedBox(height:20),
          ...children,
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl,String label,{
    String? hint,int lines=1,String? identifier,ValueChanged<String>? onChanged
  })=>Padding(
    padding:const EdgeInsets.only(bottom:11),
    child:Semantics(
      identifier:identifier,
      child:TextField(
        controller:ctrl,
        onChanged:onChanged,
        maxLines:lines,
        enabled:!_busy,
        decoration:InputDecoration(
          labelText:label,
          hintText:hint,
          border:const OutlineInputBorder(),
          isDense:true,
        ),
      ),
    ),
  );

  Widget _action(String text,IconData icon,Future<void> Function() task,
      {bool showNotice=true})=>SizedBox(
    width:double.infinity,
    child:FilledButton.icon(
      onPressed:_busy?null:()=>_execute(task,showNotice:showNotice),
      icon:Icon(icon),
      label:Text(text),
    ),
  );

  String _folio(Map<String,dynamic> order) =>
      'VH-${order['orderNumber'].toString().padLeft(6,'0')}';

  String _orderLabel(Map<String,dynamic> order) =>
      '${_folio(order)} · ${_status(order['status'])}';

  String _status(dynamic value)=>switch(value){
    'registered'=>'Orden registrada',
    'report_attached'=>'PDF en revisión',
    'report_published'=>'Informe publicado',
    _=>'Estado pendiente',
  };

  Widget _orderStatusLabel(dynamic status) {
    final (background, foreground) = switch (status) {
      'report_attached' => (const Color(0xFFFFF0D5), const Color(0xFF75430C)),
      'report_published' => (const Color(0xFFDFEFE8), const Color(0xFF145341)),
      _ => (ColoresVitalia.azulSuave, ColoresVitalia.azulActivo),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(_status(status), style: TextStyle(
          fontSize: 12, color: foreground, fontWeight: FontWeight.w600,
        )),
      ),
    );
  }

  Widget _ordersPanel({bool recent = false}){
    final list=recent ? _orders.take(5) : _orderPage;
    return _section(
      recent ? 'Órdenes recientes' : 'Órdenes del laboratorio',
      '',
      Icons.assignment_outlined,
      [
        if (!recent) ...[
          if (_ordersPatient case final patient?)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: InputChip(
                label: Text(_patientName(patient)),
                onDeleted: _busy ? null : () => _showPatientOrders(null),
              ),
            ),
          LayoutBuilder(builder: (context, constraints) {
            final search = _field(_orderSearch, 'Folio o correo del paciente',
              identifier: 'sil-order-search');
            final statusFilter = DropdownButtonFormField<String>(
              key: ValueKey((_labId, _orderStatus)),
              initialValue: _orderStatus,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Estado de la orden'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Todos los estados')),
                for (final status in ['registered', 'report_attached', 'report_published'])
                  DropdownMenuItem(value: status, child: Text(_status(status))),
              ],
              onChanged: _busy ? null : (value) => _execute(
                () => _loadOrderPage(offset: 0, status: value, search: _orderSearch.text.trim()),
                showNotice: false,
              ),
            );
            final submit = OutlinedButton.icon(
              onPressed: _busy ? null : () => _execute(
                () => _loadOrderPage(offset: 0, search: _orderSearch.text.trim()),
                showNotice: false,
              ),
              icon: const Icon(Icons.search),
              label: const Text('Buscar órdenes'),
            );
            if (constraints.maxWidth < 640) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                search,
                statusFilter,
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerStart, child: submit),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: search),
              const SizedBox(width: 10),
              Expanded(flex: 4, child: statusFilter),
              const SizedBox(width: 10),
              submit,
            ]);
          }),
          const SizedBox(height: 12),
        ],
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OperatorNextStep(
              icon: Icons.assignment_outlined,
              title: 'No hay órdenes para mostrar',
              message: recent
                  ? 'Todavía no aparecen órdenes recientes en este laboratorio. Al completar una solicitud, podrás consultarla aquí.'
                  : 'No hay órdenes que coincidan con los filtros. Prueba otra búsqueda o comienza recibiendo una solicitud médica.',
              action: OutlinedButton.icon(
                onPressed: _busy ? null : () => _openSection(_StationSection.requests),
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Recibir una solicitud'),
              ),
            ),
          )
        else
          for(final order in list.take(50))
            Container(
              padding:const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: ColoresVitalia.bordeTenue)),
              ),
              child:Row(
                children:[
                  const Icon(Icons.description_outlined,
                      color:ColoresVitalia.azul,size:21),
                  const SizedBox(width:11),
                  Expanded(child:Column(
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Wrap(
                        spacing: 8, runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_folio(order), style: const TextStyle(fontWeight: FontWeight.w800)),
                          _orderStatusLabel(order['status']),
                        ],
                      ),
                      const SizedBox(height:4),
                      Text((order['examCodes'] as List? ?? []).join(' · '),
                        style:const TextStyle(
                          fontSize:12,color:ColoresVitalia.textoSecundario)),
                      if (_operator)
                        Wrap(spacing: 8, children: [
                          TextButton(
                            onPressed: _busy ? null : () => setState(() {
                              _clinicalOrder = order;
                              _activeSection = _StationSection.clinical;
                            }),
                            child: Text('Abrir ${_folio(order)}'),
                          ),
                          if (_canReview && _isReviewable(order))
                            TextButton(
                              onPressed: _busy ? null : () {
                                setState(() {
                                  _reviewOrderId = order['id'] as String;
                                  _reviewSelectedOrder = order;
                                  _reviewPdfDownloaded = false;
                                  _reviewConfirmed = false;
                                  _activeSection = _StationSection.review;
                                });
                                _execute(() => _loadReviewPage(offset: 0),
                                    showNotice: false);
                              },
                              child: const Text('Revisar informe'),
                            ),
                        ]),
                    ],
                  )),
                ],
              ),
            ),
        if (!recent && (_orderOffset > 0 || _moreOrders))
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton(
              onPressed: _busy || _orderOffset == 0 ? null : () => _execute(
                () => _loadOrderPage(offset: _orderOffset - _orderPageSize),
                showNotice: false,
              ),
              child: const Text('Órdenes anteriores'),
            ),
            Text('Página ${_orderOffset ~/ _orderPageSize + 1}'),
            OutlinedButton(
              onPressed: _busy || !_moreOrders || _orderOffset >= 10000 ? null : () => _execute(
                () => _loadOrderPage(offset: _orderOffset + _orderPageSize),
                showNotice: false,
              ),
              child: const Text('Órdenes siguientes'),
            ),
          ]),
        if (!recent)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _execute(_loadLabs, showNotice: false),
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar estación'),
          ),
      ],
    );
  }

  Future<void> _adminEditor({
    required String title,
    required String label,
    required String submitLabel,
    required TextEditingController controller,
    required Future<void> Function() submit,
    String? instruction,
    TextInputType? keyboardType,
  }) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (instruction != null) ...[
                Text(instruction),
                const SizedBox(height: 14),
              ],
              TextField(
                autofocus: true,
                controller: controller,
                keyboardType: keyboardType,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: label),
                onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(submitLabel),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted == true) await _execute(submit);
  }

  Widget _laboratoryDirectory() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SilWorkspaceHeading(
        title: 'Administración de laboratorios',
        actions: [
          if (_labId != null)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () =>
                        setState(() => _adminSection = _AdminSection.operators),
              icon: const Icon(Icons.people_outline),
              label: const Text('Gestionar operadores'),
            ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _adminEditor(
                    title: 'Registrar laboratorio',
                    label: 'Nombre del laboratorio',
                    submitLabel: 'Registrar laboratorio',
                    controller: _name,
                    submit: _createLab,
                  ),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Registrar laboratorio'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SilWorkspaceSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_labs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _busy
                      ? 'Cargando laboratorios…'
                      : 'Registra un laboratorio para comenzar.',
                ),
              ),
            for (final (index, lab) in _labs.indexed) ...[
              if (index > 0) const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                selected: lab['id'] == _labId,
                selectedTileColor: ColoresVitalia.azulSuave,
                leading: const Icon(Icons.business_outlined),
                title: Text(
                  lab['displayName'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(switch (lab['active']) {
                  true => 'Activo',
                  false => 'Inactivo',
                  _ => 'Estado sin informar',
                }),
                trailing: lab['id'] == _labId
                    ? const Tooltip(
                        message: 'Laboratorio seleccionado',
                        child: Icon(
                          Icons.check_circle_outline,
                          color: ColoresVitalia.verde,
                        ),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _busy || lab['id'] == _labId
                    ? null
                    : () => _selectLab(lab['id'] as String),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _staffRow(Map<String, dynamic> member, {required bool wide}) {
    final active = member['active'] == true;
    final canReview = member['canReviewReports'] == true;
    final email = Text(
      member['email'] as String,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    final accountState = SilWorkspaceStatus(
      label: active ? 'Activa' : 'Desactivada',
      positive: active,
    );
    final reviewState = SilWorkspaceStatus(
      label: active && canReview ? 'Autorizada' : 'Sin autorización',
      positive: active && canReview,
    );
    final action = OutlinedButton.icon(
      onPressed: _busy || !active
          ? null
          : () => _execute(
              () => _setReviewPermission(
                member['accountId'] as String,
                !canReview,
              ),
            ),
      icon: Icon(
        canReview
            ? Icons.remove_moderator_outlined
            : Icons.verified_user_outlined,
      ),
      label: Text(
        canReview ? 'Retirar permiso de revisión' : 'Autorizar revisión',
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 4, child: email),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: accountState,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: reviewState,
                  ),
                ),
                Flexible(
                  flex: 4,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: action,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                email,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    accountState,
                    SilWorkspaceStatus(
                      label: active && canReview
                          ? 'Revisión autorizada'
                          : 'Sin permiso de revisión',
                      positive: active && canReview,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                action,
              ],
            ),
    );
  }

  Widget _staffDirectory() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SilWorkspaceHeading(
        title: 'Directorio de operadores',
        actions: [
          _labSelector(),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _execute(_loadStaff, showNotice: false),
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar operadores'),
          ),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _adminEditor(
                    title: 'Vincular operador',
                    label: 'Identificador de la cuenta operadora',
                    submitLabel: 'Vincular al laboratorio',
                    controller: _staffAccount,
                    submit: _grantStaff,
                    instruction:
                        'La cuenta debe estar activa y tener rol de operador.',
                  ),
            icon: const Icon(Icons.link),
            label: const Text('Vincular cuenta'),
          ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _adminEditor(
                    title: 'Invitar operador',
                    label: 'Correo del nuevo operador',
                    submitLabel: 'Crear invitación',
                    controller: _inviteEmail,
                    submit: _inviteOperator,
                    keyboardType: TextInputType.emailAddress,
                    instruction: 'Entrega el código de un solo uso al destinatario por el canal oficial del laboratorio.',
                  ),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Invitar operador'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SilWorkspaceSurface(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 810 &&
                MediaQuery.textScalerOf(context).scale(14) <= 17;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_labStaff.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      !_staffLoaded
                          ? (_busy
                                ? 'Cargando operadores…'
                                : 'Actualiza para consultar el personal.')
                          : 'Todavía no hay operadores vinculados a este laboratorio.',
                    ),
                  ),
                if (_labStaff.isNotEmpty && wide)
                  ColoredBox(
                    color: ColoresVitalia.fondoAzul,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        child: const Row(
                          children: [
                            Expanded(flex: 4, child: Text('Cuenta')),
                            Expanded(flex: 2, child: Text('Estado')),
                            Expanded(
                              flex: 3,
                              child: Text('Revisión de informes'),
                            ),
                            Expanded(
                              flex: 4,
                              child: Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: Text('Permisos'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (final (index, member) in _labStaff.indexed) ...[
                  if (index > 0 || wide) const Divider(height: 1),
                  _staffRow(member, wide: wide),
                ],
              ],
            );
          },
        ),
      ),
    ],
  );

  Future<void> _checkPatientActivation() async {
    final lab = _labId;
    final email = _invitedPatientEmail.text.trim().toLowerCase();
    if (lab == null || !email.contains('@')) {
      throw const AuthFailure('Escribe el correo que utilizó el paciente para activar su cuenta.');
    }
    final query = Uri(queryParameters: {
      'limit': '20', 'offset': '0', 'search': email,
    }).query;
    final data = await widget.api.silMainRequest('/labs/$lab/patients?$query');
    if (!mounted || lab != _labId) return;
    final found = (data['patients'] as List? ?? [])
        .whereType<Map>()
        .any((row) => (row['email'] as String?)?.toLowerCase() == email);
    setState(() => _patientInviteStatus = found
        ? 'Cuenta activa y asociada al laboratorio. Ya puedes crear una orden para este paciente.'
        : 'Todavía no se encuentra una cuenta activada para este correo. El paciente debe ingresar su código y configurar una contraseña.');
    if (found) await _loadPatients(offset: 0, search: email);
  }

  Widget _patientLink() => _section(
    'Registrar paciente nuevo',
    '',
    Icons.person_add_alt_1_outlined, [
      _field(_invitedPatientEmail, 'Correo electrónico del paciente',
          onChanged: (_) => setState(() {
            _verifiedPatient = false;
            _patientInviteStatus = null;
          })),
      _field(_evidence, 'Referencia del procedimiento de verificación',
          onChanged: (_) => setState(() => _verifiedPatient = false)),
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Usa un folio o referencia no sensible que permita auditar la verificación de identidad. No escribas diagnósticos ni datos clínicos aquí.'),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _verifiedPatient,
        onChanged: _busy ? null : (value) =>
          setState(() => _verifiedPatient = value ?? false),
        title: const Text('He verificado la identidad del paciente'),
        subtitle: const Text('La coincidencia del correo por sí sola no confirma la identidad.'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      FilledButton.icon(
        onPressed: _busy || !_verifiedPatient || _evidence.text.trim().length < 6 ||
            !_invitedPatientEmail.text.contains('@')
            ? null : () => _execute(() => _invitePatient(), showNotice: false),
        icon: const Icon(Icons.mark_email_read_outlined),
        label: const Text('Emitir código de activación'),
      ),
      const SizedBox(height: 12),
      if (_patientInviteStatus != null) ...[
        OperatorNextStep(
          icon: Icons.mark_email_read_outlined,
          title: 'Estado de la invitación',
          message: _patientInviteStatus!,
          accent: OperatorPalette.teal,
          background: ColoresVitalia.verdeSuave,
        ),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _execute(_checkPatientActivation, showNotice: false),
        icon: const Icon(Icons.person_search_outlined),
        label: const Text('Comprobar si activó su cuenta'),
      ),
      if (_patientInviteStatus != null)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'Entrega el código por un canal verificado. El paciente ingresa '
            'su correo y código en «Activar cuenta» y crea su contraseña.',
          ),
        ),
    ],
  );

  Widget _newOrder() => _section(
    'Crear orden sin derivación PDF',
    'Usa esta opción solo cuando corresponda al procedimiento del laboratorio. Si recibiste una solicitud médica, comienza en «Recibir solicitud».',
    Icons.note_add_outlined, [
      const OperatorNextStep(
        title: 'Antes de registrar la orden',
        message: 'Selecciona una cuenta activa del laboratorio y verifica las prestaciones solicitadas. Nunca necesitas copiar un identificador técnico.',
      ),
      const SizedBox(height: 13),
      _field(_orderPatientSearch, 'Buscar paciente por nombre o correo'),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _execute(
          () => _loadPatients(offset: 0, search: _orderPatientSearch.text.trim()),
          showNotice: false,
        ),
        icon: const Icon(Icons.search_outlined),
        label: const Text('Buscar paciente'),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey((_labId, _manualPatient?['id'], _activePatientSearch)),
        initialValue: _manualPatient?['id'] as String?,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Paciente con cuenta activada',
          border: OutlineInputBorder(),
        ),
        items: [
          if (_manualPatient != null &&
              !_patients.any((p) => p['id'] == _manualPatient?['id']))
            DropdownMenuItem<String>(
              value: _manualPatient!['id'] as String,
              child: Text(_patientName(_manualPatient!),
                  overflow: TextOverflow.ellipsis),
            ),
          for (final patient in _patients)
            DropdownMenuItem<String>(
              value: patient['id'] as String,
              child: Text(
                _patientName(patient) + ' · ' + (patient['email'] as String),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _busy ? null : (value) => setState(() {
          _manualPatient = [
            ..._patients,
            if (_manualPatient != null) _manualPatient!,
          ].where((p) => p['id'] == value).firstOrNull;
          _orderPatient.text = value ?? '';
        }),
      ),
      if (_patients.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 9),
          child: Text('No aparecen pacientes activos en la lista. Puedes buscar por correo o iniciar una invitación desde «Pacientes».'),
        ),
      const SizedBox(height: 14),
      const Text('Seleccionar exámenes',
          style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      Wrap(spacing: 7, runSpacing: 4, children: [
        for (final (code, label) in _catalog)
          FilterChip(
            label: Text(label),
            selected: _codes.contains(code),
            onSelected: _busy ? null : (selected) => setState(() {
              if (selected) {
                _codes.add(code);
              } else {
                _codes.remove(code);
              }
            }),
          ),
      ]),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy || _orderPatient.text.isEmpty || _codes.isEmpty
            ? null
            : () => _execute(_createOrder),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Registrar orden'),
      ),
    ],
  );

  bool get _hasRequestDocument =>
      _medicalRequestFile != null || _pendingRequestId != null;

  bool get _hasRequestPatient => _attachToExistingOrder
      ? _requestOrderId != null
      : _requestPatient.text.isNotEmpty;

  Widget _requestGuide() {
    final documentReady = _hasRequestDocument;
    final patientReady = _hasRequestPatient;
    final reviewed =
        _requestIdentityChecked &&
        _requestHumanChecked &&
        (_attachToExistingOrder || _requestExams.isNotEmpty);
    final current = !documentReady
        ? 0
        : !patientReady
        ? 1
        : !reviewed
        ? 2
        : 3;
    const stages = [
      'Recibir solicitud',
      'Identificar paciente',
      'Revisar exámenes',
      'Crear orden',
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SilWorkspaceStatus(
          label: 'Paso ${current + 1} de ${stages.length}',
          positive: true,
        ),
        Semantics(liveRegion: true, child: Text(stages[current])),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Guía postanalítica'),
              scrollable: true,
              content: const SizedBox(width: 480, child: SilWorkspaceProcessPath()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ),
          child: const Text('Ver guía'),
        ),
      ],
    );
  }

  Widget _requestIntake() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _requestGuide(),
      const SizedBox(height: 14),
      _section(
        'Documento de origen',
        '',
        Icons.description_outlined,
        [
          if (_medicalRequestFile != null)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(_medicalRequestFile!.name),
              subtitle: const Text('PDF seleccionado'),
            ),
          if (!_hasRequestDocument)
            FilledButton.icon(
              onPressed: _busy ? null : _pickMedicalRequest,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Seleccionar solicitud PDF'),
            )
          else
            TextButton.icon(
              onPressed: _busy ? null : _pickMedicalRequest,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Cambiar PDF'),
            ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vincular a una orden existente'),
            value: _attachToExistingOrder,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _attachToExistingOrder = value;
                    _requestIdentityChecked = false;
                    _requestHumanChecked = false;
                    if (value) _pendingRequestId = null;
                  }),
          ),
          if (!_attachToExistingOrder) ...[
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _execute(_loadPendingRequests, showNotice: false),
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Actualizar derivaciones pendientes'),
            ),
            if (_pendingRequests.isNotEmpty) ...[
              const SizedBox(height: 9),
              DropdownButtonFormField<String>(
                key: ValueKey((_labId, _pendingRequestId, 'pending-referrals')),
                initialValue: _pendingRequestId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Derivación pendiente guardada',
                ),
                items: [
                  for (final pending in _pendingRequests)
                    DropdownMenuItem<String>(
                      value: pending['id'] as String,
                      child: Text(
                        '${pending['fileName']} · '
                        '${pending['patientEmail'] ?? 'Paciente por identificar'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy ? null : _selectPendingRequest,
              ),
            ],
          ],
          if (_medicalRequestFile != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () =>
                            _execute(_previewMedicalRequest, showNotice: false),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Leer PDF y sugerir datos'),
                ),
                if (!_attachToExistingOrder && _pendingRequestId == null)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _execute(_savePendingRequest),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar derivación pendiente'),
                  ),
              ],
            ),
          ],
          if (!_attachToExistingOrder) ...[
            if (_pendingRequestId != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () =>
                          _execute(_downloadPendingRequest, showNotice: false),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Descargar derivación pendiente original'),
              ),
              const SizedBox(height: 6),
              const Text(
                'El archivo está guardado en Vitalia. '
                'Puede retomar su recepción aunque cierre la sesión.',
              ),
            ],
          ],
          const SizedBox(height: 12),
          if (_requestPreviewNotice != null) Text(_requestPreviewNotice!),
          if (_requestIdentitySuggestions.values.any(
            (v) => v is String && v.isNotEmpty,
          ))
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Datos identificatorios sugeridos por el PDF'),
              subtitle: const Text(
                'Coteja estas sugerencias con el documento.',
              ),
              children: [
                for (final field in <(String, String)>[
                  ('fullName', 'Nombre completo'),
                  ('identifier', 'RUT/RUN'),
                  ('birthDate', 'Fecha de nacimiento'),
                  ('email', 'Correo'),
                  ('phone', 'Teléfono'),
                  ('sex', 'Sexo'),
                ])
                  if (_requestIdentitySuggestions[field.$1]
                      case final String value)
                    ListTile(
                      dense: true,
                      title: Text(field.$2),
                      subtitle: SelectableText(value),
                    ),
              ],
            ),
        ],
      ),
      if (_hasRequestDocument) ...[
        const SizedBox(height: 12),
        _section(
          '2. Identificar al paciente',
          'Comprueba a quién pertenece la solicitud.',
          Icons.badge_outlined,
          [
            if (_attachToExistingOrder)
              DropdownButtonFormField<String>(
                initialValue: _requestOrderId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Orden del paciente',
                ),
                items: [
                  for (final order in _workflowOrders.where(
                    (v) => v['status'] == 'registered',
                  ))
                    DropdownMenuItem<String>(
                      value: order['id'] as String,
                      child: Text(
                        _orderLabel(order),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _requestOrderId = value;
                        _requestIdentityChecked = false;
                        _requestHumanChecked = false;
                      }),
              )
            else ...[
              _field(
                _requestInviteEmail,
                'Correo del paciente',
                onChanged: (_) => setState(() {
                  _requestPatient.clear();
                  _requestIdentityEvidence.clear();
                  _requestPatientVerified = false;
                  _requestPatientStatus = null;
                  _requestIdentityChecked = false;
                  _requestHumanChecked = false;
                }),
              ),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _execute(_findRequestPatient, showNotice: false),
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Buscar paciente activado'),
              ),
              if (!_hasRequestPatient)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Invitar a un paciente nuevo'),
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  children: [
                    _field(
                      _requestIdentityEvidence,
                      'Referencia de verificación de identidad',
                      onChanged: (_) =>
                          setState(() => _requestPatientVerified = false),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Verifiqué la identidad antes de invitar',
                      ),
                      subtitle: const Text(
                        'El correo por sí solo no demuestra identidad. '
                        'No ingreses datos sensibles como evidencia.',
                      ),
                      value: _requestPatientVerified,
                      onChanged: _busy
                          ? null
                          : (value) => setState(
                              () => _requestPatientVerified = value ?? false,
                            ),
                    ),
                    OutlinedButton.icon(
                      // La invitación debe estar disponible tanto para un PDF local
                      // como para una derivación pendiente recuperada de PostgreSQL.
                      onPressed:
                          _busy ||
                              (_medicalRequestFile == null &&
                                  _pendingRequestId == null) ||
                              !_requestPatientVerified ||
                              _requestIdentityEvidence.text.trim().length < 6 ||
                              !_requestInviteEmail.text.contains('@')
                          ? null
                          : () => _execute(
                              () => _invitePatient(fromRequest: true),
                              showNotice: false,
                            ),
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: const Text('Emitir invitación de paciente'),
                    ),
                  ],
                ),
              if (_requestPatientStatus != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _requestPatientStatus!,
                    style: const TextStyle(color: ColoresVitalia.azul),
                  ),
                ),
            ],
          ],
        ),
      ],
      if (_hasRequestDocument && _hasRequestPatient) ...[
        const SizedBox(height: 12),
        SilWorkspaceColumns(
          primary: _section(
            '3. Revisar la solicitud y los exámenes',
            'Coteja y ajusta los datos y las prestaciones antes de registrar.',
            Icons.playlist_add_check_outlined,
            [
              if (!_attachToExistingOrder) ...[
                const Text('Prestaciones solicitadas'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (code, label) in _catalog)
                      FilterChip(
                        label: Text(label),
                        selected: _requestExams.contains(code),
                        onSelected: _busy
                            ? null
                            : (selected) => setState(() {
                                if (selected) {
                                  _requestExams.add(code);
                                } else {
                                  _requestExams.remove(code);
                                }
                              }),
                      ),
                  ],
                ),
              ],
              const Text(
                'Identificador administrativo: Vitalia lo asigna automáticamente al registrar la solicitud.',
              ),
              const SizedBox(height: 8),
              _field(_requestPrescriber, 'Profesional solicitante'),
              _field(_requestDate, 'Fecha de solicitud médica (AAAA-MM-DD)'),
              const Text(
                'Fecha sugerida desde el PDF o, si falta, la de hoy. Coteja siempre con la orden médica.',
                style: TextStyle(
                  fontSize: 12,
                  color: ColoresVitalia.textoSecundario,
                ),
              ),
            ],
          ),
          secondary: _section(
            '4. Confirmar y crear la orden',
            'Confirma el cotejo para guardar la solicitud en una orden.',
            Icons.fact_check_outlined,
            [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Identidad del paciente contrastada'),
                subtitle: const Text(
                  'Comprueba que la solicitud corresponde al paciente vinculado.',
                ),
                value: _requestIdentityChecked,
                onChanged: _busy
                    ? null
                    : (v) =>
                          setState(() => _requestIdentityChecked = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Revisé el contenido del PDF original'),
                value: _requestHumanChecked,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _requestHumanChecked = v ?? false),
              ),
              if (_attachToExistingOrder)
                FilledButton.icon(
                  onPressed:
                      _busy || !_requestIdentityChecked || !_requestHumanChecked
                      ? null
                      : () =>
                            _execute(_attachMedicalRequest, showNotice: false),
                  icon: const Icon(Icons.post_add_outlined),
                  label: const Text('Registrar solicitud'),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _busy ||
                            _pendingRequestId == null ||
                            _requestPatient.text.isEmpty ||
                            _requestExams.isEmpty ||
                            !_requestIdentityChecked ||
                            !_requestHumanChecked
                        ? null
                        : () => _execute(
                            _completePendingRequest,
                            showNotice: false,
                          ),
                    icon: const Icon(Icons.post_add_outlined),
                    label: const Text('Crear orden con solicitud'),
                  ),
                ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _reportUpload() => _section(
    'Documento y autorización',
    'Solo se reciben PDF ya validados externamente. '
        'El informe queda pendiente de revisión antes de publicarlo.',
    Icons.upload_file_outlined,
    [
      Semantics(
        identifier: 'sil-upload-order',
        child: DropdownButtonFormField<String>(
          initialValue: _uploadOrderId,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Orden disponible',
          ),
          items: [
            for (final order in _workflowOrders.where(
              (v) => v['status'] == 'registered',
            ))
              DropdownMenuItem<String>(
                value: order['id'] as String,
                child: Text(
                  _orderLabel(order),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  _uploadOrderId = v;
                  _confirmedMatch = false;
                }),
        ),
      ),
      if (_uploadOrderId != null) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_pdf?.name ?? 'Elegir archivo PDF (máx. 2 MiB)'),
        ),
      ],
      if (_uploadOrderId != null && _pdf != null) ...[
        const SizedBox(height: 8),
        _field(
          _reportProfessional,
          'Profesional que autorizó el PDF',
          identifier: 'sil-report-professional',
        ),
        _field(
          _reportReference,
          'Referencia de autorización externa',
          identifier: 'sil-report-reference',
        ),
        _field(_reportDate, 'Fecha de autorización (AAAA-MM-DD)'),
        OutlinedButton.icon(
          onPressed: _busy ? null : _selectReportDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: const Text('Elegir fecha de autorización'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('El informe ya fue autorizado fuera de Vitalia'),
          value: _externallyAuthorized,
          onChanged: _busy
              ? null
              : (v) => setState(() => _externallyAuthorized = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Confirmé que el PDF corresponde al paciente de la orden',
          ),
          value: _confirmedMatch,
          onChanged: _busy
              ? null
              : (v) => setState(() => _confirmedMatch = v ?? false),
        ),
        FilledButton.icon(
          onPressed: _busy || !_externallyAuthorized || !_confirmedMatch
              ? null
              : () => _execute(_attachReport),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Adjuntar para revisión'),
        ),
      ],
    ],
  );

  Widget _reviewPanel() {
    // Un acceso directo desde una orden reciente conserva esa selección,
    // incluso cuando la orden no esté en la página actual de la bandeja.
    final choices = <String, Map<String, dynamic>>{
      for (final order in _reviewOrders) order['id'] as String: order,
      if (_reviewSelectedOrder != null &&
          _reviewSelectedOrder!['id'] is String &&
          _isReviewable(_reviewSelectedOrder!))
        _reviewSelectedOrder!['id'] as String: _reviewSelectedOrder!,
    }.values.toList();
    return _section(
      'Validación y publicación',
      'Revisa el PDF y confirma su autorización externa antes de publicarlo.',
      Icons.fact_check_outlined,
      [
        if (choices.isNotEmpty)
          Semantics(
            identifier: 'sil-review-order',
            child: DropdownButtonFormField<String>(
              key: ValueKey((
                _labId,
                _reviewOffset,
                _reviewOrderId,
                'review-queue',
              )),
              initialValue: _reviewOrderId,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Informe pendiente de revisión',
              ),
              items: [
                for (final order in choices)
                  DropdownMenuItem<String>(
                    value: order['id'] as String,
                    child: Text(
                      _orderLabel(order),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _reviewOrderId = v;
                      _reviewSelectedOrder = v == null
                          ? null
                          : choices
                                .where((order) => order['id'] == v)
                                .firstOrNull;
                      _reviewPdfDownloaded = false;
                      _reviewConfirmed = false;
                    }),
            ),
          ),
        const SizedBox(height: 10),
        if (choices.isEmpty && !_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('No hay informes pendientes en esta página.'),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_reviewOffset > 0)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _execute(
                        () =>
                            _changeReviewPage(_reviewOffset - _reviewPageSize),
                        showNotice: false,
                      ),
                child: const Text('Revisiones anteriores'),
              ),
            if (_reviewOffset > 0 || _moreReviewOrders)
              Text('Página ${_reviewOffset ~/ _reviewPageSize + 1}'),
            if (_moreReviewOrders && _reviewOffset < 10000)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _execute(
                        () =>
                            _changeReviewPage(_reviewOffset + _reviewPageSize),
                        showNotice: false,
                      ),
                child: const Text('Revisiones siguientes'),
              ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _execute(
                      () => _loadReviewPage(offset: _reviewOffset),
                      showNotice: false,
                    ),
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Actualizar revisiones'),
            ),
          ],
        ),
        if (_reviewOrderId != null) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _execute(_downloadReportForReview, showNotice: false),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Descargar PDF para revisión'),
          ),
        ],
        if (_reviewOrderId != null && _reviewPdfDownloaded) ...[
          const SizedBox(height: 8),
          const Text(
            'Antes de publicar, revisa el PDF original y su autorización '
            'en el procedimiento clínico de tu laboratorio. '
            'Esta pantalla no sustituye ese procedimiento.',
            style: TextStyle(
              fontSize: 12,
              color: ColoresVitalia.textoSecundario,
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Confirmo que revisé el PDF y su autorización externa',
            ),
            value: _reviewConfirmed,
            onChanged: _busy || !_reviewPdfDownloaded
                ? null
                : (v) => setState(() => _reviewConfirmed = v ?? false),
          ),
          FilledButton.icon(
            onPressed: _busy || !_reviewConfirmed
                ? null
                : () => _execute(_publishReport),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Publicar informe'),
          ),
        ],
      ],
    );
  }

  Future<void> _loadPatients({required int offset, String? search}) async {
    final lab = _labId;
    if (lab == null) return;
    final term = search ?? _activePatientSearch;
    final query = Uri(queryParameters: {
      'limit': '20', 'offset': '$offset', if (term.isNotEmpty) 'search': term,
    }).query;
    final data = await widget.api.silMainRequest('/labs/$lab/patients?$query');
    if (!mounted || _labId != lab) return;
    setState(() {
      _patients = (data['patients'] as List? ?? [])
          .map((entry) => Map<String,dynamic>.from(entry as Map)).toList();
      _patientOffset = offset;
      _activePatientSearch = term;
      _morePatients = data['hasMore'] == true;
    });
  }

  void _openSection(_StationSection section, {String? orderStatus}) {
    if (_busy || section == _activeSection) return;
    setState(() {
      _activeSection = section;
      if (orderStatus != null) {
        _orderSearch.clear();
        _activeOrderSearch = '';
        _ordersPatient = null;
        _orderPage = [];
      }
    });
    if (section == _StationSection.patients) {
      _execute(() => _loadPatients(offset: 0), showNotice: false);
    } else if (section == _StationSection.orders) {
      _execute(() async {
        await _loadOrderPage(
          offset: orderStatus == null ? _orderOffset : 0,
          status: orderStatus,
        );
        await _loadPatients(offset: 0, search: _orderPatientSearch.text.trim());
      }, showNotice: false);
    } else if (section == _StationSection.review && _canReview) {
      _execute(() => _loadReviewPage(offset: 0), showNotice: false);
    }
  }

  String _patientName(Map<String,dynamic> patient) {
    final name = [patient['givenNames'], patient['familyNames']].whereType<String>().join(' ').trim();
    return name.isEmpty ? patient['email'] as String : name;
  }

  Widget _patientDirectory() => _section(
    'Directorio de pacientes', '',
    Icons.badge_outlined, [
      _field(_patientSearch, 'Buscar por nombre o correo'),
      _action('Buscar pacientes', Icons.search,
        () => _loadPatients(offset: 0, search: _patientSearch.text.trim())),
      if (_patients.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: OperatorNextStep(
            icon: Icons.person_search_outlined,
            title: 'Sin pacientes en esta búsqueda',
            message: 'Prueba otro nombre o correo. Si el paciente aún no tiene acceso, usa «Invitar paciente».',
          ),
        ),
      for (final patient in _patients)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_patientName(patient)),
          subtitle: _patientName(patient) == patient['email']
              ? null : Text(patient['email'] as String),
          trailing: PopupMenuButton<_StationSection>(
            tooltip: 'Acciones del paciente',
            enabled: !_busy,
            onSelected: (section) {
              if (section == _StationSection.patients) {
                _showPatientOrders(patient);
                return;
              }
              if (section == _StationSection.requests) {
                _requestPatient.text = patient['id'] as String;
                _requestInviteEmail.text = patient['email'] as String;
                _attachToExistingOrder = false;
                _requestIdentityChecked = false;
                _requestHumanChecked = false;
              } else {
                _orderPatient.text = patient['id'] as String;
                _manualPatient = patient;
              }
              _openSection(section);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: _StationSection.patients, child: Text('Ver órdenes del paciente')),
              PopupMenuItem(value: _StationSection.requests, child: Text('Recibir solicitud')),
              PopupMenuItem(value: _StationSection.orders, child: Text('Crear orden manual')),
            ],
          ),
        ),
      if (_patientOffset > 0 || _morePatients)
        Wrap(spacing: 8, children: [
          OutlinedButton(
            onPressed: _busy || _patientOffset == 0 ? null :
              () => _execute(() => _loadPatients(offset: _patientOffset - 20), showNotice: false),
            child: const Text('Anterior'),
          ),
          OutlinedButton(
            onPressed: _busy || !_morePatients || _patientOffset >= 10000 ? null :
              () => _execute(() => _loadPatients(offset: _patientOffset + 20), showNotice: false),
            child: const Text('Siguiente'),
          ),
        ]),
    ],
  );

  Widget _navigation() {
    final pending = _summaryCount(
      'inReview',_orders.where(_isReviewable).length);
    final destinations = [
      (_StationSection.dashboard, Icons.dashboard_outlined, 'Resumen'),
      (_StationSection.orders, Icons.assignment_outlined, 'Órdenes'),
      (_StationSection.requests, Icons.note_add_outlined, 'Recibir solicitud'),
      (_StationSection.patients, Icons.badge_outlined, 'Pacientes'),
      (_StationSection.clinical, Icons.science_outlined, 'Muestras y resultados'),
      if (_canReview)
        (_StationSection.review, Icons.fact_check_outlined, 'Revisión interna ($pending)'),
    ];
    return SilWorkspaceTopNavigation(
      label: 'Navegación del operador',
      tabs: [
        for (final (section, icon, label) in destinations)
          SilWorkspaceTab(
            label: label, icon: icon,
            selected: _activeSection == section,
            onPressed: _busy ? null : () => _openSection(section),
          ),
      ],
    );
  }

  Widget _adminNavigation() => SilWorkspaceTopNavigation(
    label: 'Navegación de administración',
    tabs: [
      SilWorkspaceTab(
        label: 'Laboratorios', icon: Icons.business_outlined,
        selected: _adminSection == _AdminSection.laboratories,
        onPressed: _busy ? null : () => setState(
          () => _adminSection = _AdminSection.laboratories),
      ),
      SilWorkspaceTab(
        label: 'Operadores y permisos', icon: Icons.admin_panel_settings_outlined,
        selected: _adminSection == _AdminSection.operators,
        onPressed: _busy ? null : () => setState(
          () => _adminSection = _AdminSection.operators),
      ),
      SilWorkspaceTab(
        label: 'Actividad', icon: Icons.history_outlined,
        selected: _adminSection == _AdminSection.activity,
        onPressed: _busy ? null : () => setState(
          () => _adminSection = _AdminSection.activity),
      ),
    ],
  );

  Widget _adminContent() => switch (_adminSection) {
    _AdminSection.laboratories => _laboratoryDirectory(),
    _AdminSection.operators =>
      _labId == null
          ? const SilWorkspaceHeading(
              section: true,
              title: 'Selecciona un laboratorio',
              description:
                  'Registra un laboratorio para gestionar su personal.',
            )
          : _staffDirectory(),
    _AdminSection.activity =>
      _labId == null
          ? const SilWorkspaceHeading(
              section: true,
              title: 'Selecciona un laboratorio',
              description: 'El estado administrativo corresponde al laboratorio seleccionado.',
            )
          : SilWorkspaceSurface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SilWorkspaceHeading(
                    section: true,
                    title: 'Estado administrativo',
                    description: 'Resumen del personal y sus permisos.',
                    actions: [
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _execute(_loadStaff, showNotice: false),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar estado administrativo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_staffLoaded)
                    Wrap(
                      spacing: 32,
                      runSpacing: 10,
                      children: [
                        Text('${_labStaff.length} operadores asociados'),
                        Text(
                          '${_labStaff.where((member) => member['active'] == true && member['canReviewReports'] == true).length} '
                          'operadores con permiso de revisión',
                        ),
                      ],
                    )
                  else
                    Text(
                      _busy
                          ? 'Cargando personal…'
                          : 'Datos de personal pendientes de consulta.',
                    ),
                  const Divider(height: 28),
                  const Text(
                    'El historial de auditoría administrativa requiere una fuente autorizada.',
                  ),
                ],
              ),
            ),
  };

  Widget _dashboard() {
    final isTotal = _operatorSummary != null;
    final tasks = [
      (
        Icons.note_add_outlined,
        'Derivaciones pendientes',
        _summaryCount('pendingRequests', _pendingRequests.length),
        _StationSection.requests,
      ),
      (
        Icons.inventory_2_outlined,
        'Órdenes registradas',
        _summaryCount(
          'registered',
          _orders.where((o) => o['status'] == 'registered').length,
        ),
        _StationSection.orders,
      ),
      if (_canReview)
        (
          Icons.fact_check_outlined,
          'Informes por revisar',
          _summaryCount('inReview', _orders.where(_isReviewable).length),
          _StationSection.review,
        ),
    ];
    final totals = [
      ('Total de órdenes', _summaryCount('ordersTotal', _orders.length)),
      (
        'Informes publicados',
        _summaryCount(
          'published',
          _orders.where((o) => o['status'] == 'report_published').length,
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SilWorkspaceHeading(
          title: 'Panel del laboratorio',
          actions: [
            _labSelector(),
            IconButton.outlined(
              onPressed: _busy
                  ? null
                  : () => _execute(_loadLabs, showNotice: false),
              tooltip: 'Actualizar estación',
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _openSection(_StationSection.requests),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Recibir solicitud de exámenes'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SilWorkspaceColumns(
          primaryFlex: 5,
          secondaryFlex: 7,
          primary: SilWorkspaceSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
                  child: SilWorkspaceHeading(
                    section: true,
                    title: 'Tareas del laboratorio',
                    description: isTotal
                        ? 'Totales actuales del laboratorio seleccionado.'
                        : 'Cifras parciales de los registros recientes cargados.',
                  ),
                ),
                for (final task in tasks) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(task.$1, color: ColoresVitalia.azul),
                    title: Text(
                      task.$2,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SilWorkspaceStatus(
                          label: '${task.$3}',
                          positive: task.$3 > 0,
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: _busy
                        ? null
                        : () => _openSection(
                            task.$4,
                            orderStatus: task.$4 == _StationSection.orders
                                ? 'registered'
                                : null,
                          ),
                  ),
                ],
                const Divider(height: 1),
                ColoredBox(
                  color: ColoresVitalia.fondoAzul,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        for (final total in totals)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${total.$2}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                total.$1,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          secondary: _ordersPanel(recent: true),
        ),
      ],
    );
  }

  Widget _operatorSubpage({
    required String title,
    String? description,
    required Widget child,
    Widget? support,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SilWorkspaceHeading(
        title: title,
        description: description,
        actions: [_labSelector()],
      ),
      const SizedBox(height: 14),
      if (support != null) ...[
        support,
        const SizedBox(height: 14),
      ],
      child,
    ],
  );

  Widget _station() {
    if (_labId == null) return const SizedBox.shrink();
    return switch (_activeSection) {
      _StationSection.dashboard => _dashboard(),
      _StationSection.orders => _operatorSubpage(
        title: 'Órdenes',
        child: SilWorkspaceColumns(
          primaryFlex: 7,
          secondaryFlex: 4,
          primary: _ordersPanel(),
          secondary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SilWorkspaceDisclosure(
                title: 'Adjuntar informe autorizado',
                icon: Icons.upload_file_outlined,
                child: _reportUpload(),
              ),
              const SizedBox(height: 16),
              SilWorkspaceDisclosure(
                title: 'Crear orden sin derivación PDF',
                icon: Icons.post_add_outlined,
                child: _newOrder(),
              ),
            ],
          ),
        ),
      ),
      _StationSection.requests => _operatorSubpage(
        title: 'Recibir solicitud',
        child: _requestIntake(),
      ),
      _StationSection.patients => _operatorSubpage(
        title: 'Pacientes',
        child: SilWorkspaceColumns(
          primaryFlex: 7,
          secondaryFlex: 4,
          primary: _patientDirectory(),
          secondary: SilWorkspaceDisclosure(
            title: 'Invitar paciente',
            icon: Icons.person_add_alt_1_outlined,
            child: _patientLink(),
          ),
        ),
      ),
      _StationSection.clinical => _operatorSubpage(
        title: 'Control de muestras y resultados',
        description: 'Selecciona una orden registrada para continuar con muestras y resultados.',
        support: _workflowOrders.isEmpty
            ? OperatorNextStep(
                icon: Icons.science_outlined,
                title: 'No hay órdenes disponibles',
                message: 'Primero recibe una solicitud médica y registra su orden. Después aparecerá aquí para continuar con el trabajo del laboratorio.',
                action: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openSection(_StationSection.requests),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Recibir solicitud médica'),
                ),
              )
            : null,
        child: _section(
          'Muestras y resultados',
          'Registra la recepción y revisa los analitos de la orden.',
          Icons.science_outlined, [
            SilMainClinicalPanel(
              key: ValueKey(_labId),
              api: widget.api,
              labId: _labId!,
              orders: _workflowOrders.toList(),
              initialOrderId: _clinicalOrder?['id'] as String?,
              onOrderChanged: (id) => _clinicalOrder =
                _workflowOrders.firstWhere((order) => order['id'] == id),
              canReview: _canReview,
              onExpired: widget.onExpired,
            ),
          ],
        ),
      ),
      _StationSection.review => _canReview
          ? _operatorSubpage(
              title: 'Bandeja de revisión',
              child: _reviewPanel(),
            )
          : _dashboard(),
    };
  }

  Widget _labSelector() {
    if (_labs.isEmpty) {
      if (_busy) return const SizedBox.shrink();
      return Text(_admin
          ? 'Registra un laboratorio para comenzar.'
          : 'No tienes laboratorios asociados. Solicita acceso a administración.');
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DropdownButtonFormField<String>(
        initialValue: _labId,
        isExpanded: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(), labelText: 'Laboratorio', isDense: true,
        ),
        items: [
          for (final lab in _labs)
            DropdownMenuItem<String>(
              value: lab['id'] as String,
              child: Text(lab['displayName'] as String, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _busy ? null : _selectLab,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mobileDevice) {
      return Scaffold(
        appBar: AppBar(title: const SilWorkspaceBrand()),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SilWorkspaceHeading(
                    title: 'Abre Vitalia en un computador',
                    description: 'La estación del laboratorio está disponible en escritorio.',
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: widget.onLogout,
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: ColoresVitalia.fondoAzul,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const SilWorkspaceBrand(),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 700)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: SilWorkspaceRoleLabel(
                label: _admin ? 'Administrador' : 'Operador',
                icon: _admin ? Icons.admin_panel_settings_outlined :
                  Icons.medical_services_outlined,
              )),
            ),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_operator) _navigation(),
            if (_admin) _adminNavigation(),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                return SingleChildScrollView(
                  key: ValueKey((_activeSection, _adminSection)),
                  padding: EdgeInsets.symmetric(
                    horizontal: constraints.maxWidth < 600 ? 16 : 36,
                    vertical: constraints.maxWidth < 600 ? 20 : 32,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_admin && _adminSection == _AdminSection.activity) ...[
                            SilWorkspaceHeading(
                              title: 'Actividad del laboratorio',
                              actions: [_labSelector()],
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_busy) const LinearProgressIndicator(
                            semanticsLabel: 'Cargando operación',
                          ),
                          if (_error != null || _notice != null)
                            Semantics(
                              liveRegion: true,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  _error ?? _notice!,
                                  style: TextStyle(color: _error != null
                                      ? Theme.of(context).colorScheme.error
                                      : ColoresVitalia.verde),
                                ),
                              ),
                            ),
                          if (_operator)
                            _labId == null ? _labSelector() : _station(),
                          if (_admin) _adminContent(),
                          const SizedBox(height: 20),
                          const Text(
                            'Vitalia Health · Entorno de integración. '
                            'No utilizar datos clínicos reales antes de aprobar '
                            'seguridad, procedimientos y cumplimiento.',
                            style: TextStyle(fontSize: 12, color: ColoresVitalia.textoSecundario),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
