import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';
import 'sil_workspace.dart';
import 'sil_main_clinical_panel.dart';
import 'operator_design.dart';

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
  final _invitedPatientEmail = TextEditingController();
  final _patientSearch = TextEditingController();
  List<Map<String,dynamic>> _patients = [];
  int _patientOffset = 0;
  bool _morePatients = false;
  String _activePatientSearch = '';
  final _patientAccount = TextEditingController();
  final _evidence = TextEditingController();
  final _orderPatient = TextEditingController();
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
  final _requestReference = TextEditingController();
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
  XFile? _pdf;
  List<Map<String,dynamic>> _labs = [];
  List<Map<String,dynamic>> _orders = [];
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
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)_execute(_loadLabs,showNotice:false);
    });
  }

  @override
  void dispose(){
    for(final ctrl in [
      _name,_inviteEmail,_staffAccount,_invitedPatientEmail,_patientSearch,_orderSearch,_patientAccount,_evidence,_orderPatient,
      _requestPatient,_requestInviteEmail,_requestIdentityEvidence,
      _requestPrescriber,_requestReference,_requestDate,
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
    await _loadOrders();
    if(_operator) await _loadPendingRequests();
    if(_admin && _labId!=null) await _loadStaff();
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
  }

  // Lista de operadores que ya tienen acceso al laboratorio actual.
  // Nunca incluye contraseñas ni códigos de invitación.
  Future<void> _loadStaff() async {
    final lab=_labId;
    if(!_admin || lab==null){
      if(mounted)setState(()=>_labStaff=[]);
      return;
    }
    final result=await widget.api.silMainRequest('/labs/$lab/staff');
    if(!mounted || _labId!=lab)return;
    setState(()=>_labStaff=(result['staff'] as List? ?? [])
      .map((value)=>Map<String,dynamic>.from(value as Map)).toList());
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
        order['id'] == _reviewOrderId && _isReviewable(order))) {
      _reviewOrderId = null;
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
    _staffAccount.clear();
    _activeSection = _StationSection.dashboard;
    _patients = [];
    _patientSearch.clear();
    _activePatientSearch = '';
    _patientOffset = 0;
    _morePatients = false;
    _orders = [];
    _orderPage = [];
    _clinicalOrder = null;
    _ordersPatient = null;
    _orderSearch.clear();
    _activeOrderSearch = '';
    _orderStatus = '';
    _orderOffset = 0;
    _moreOrders = false;
    for (final controller in [
      _patientAccount, _invitedPatientEmail, _evidence, _orderPatient, _requestPatient,
      _requestInviteEmail, _requestIdentityEvidence, _requestPrescriber,
      _requestReference, _requestDate, _reportProfessional, _reportReference, _reportDate,
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
    _reviewPdfDownloaded = false;
    _reviewConfirmed = false;
  }

  void _selectLab(String? value) {
    if (value == _labId || _busy) return;
    setState(() => _resetLab(value));
    _execute(() async {
      await _loadOrders();
      if(_operator)await _loadPendingRequests();
      if(_admin)await _loadStaff();
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
        _invitedPatientEmail.clear();
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
              const Text('El paciente se activa en /#/activar-portal. '
                  'Después vuelve a esta derivación y pulsa «Buscar paciente activado».'),
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
      throw const AuthFailure('No aparece una cuenta activada y vinculada a '
          'este laboratorio. Comprueba la activación o usa Pacientes '
          'para vincular una cuenta existente.');
    }
    setState(() {
      _requestPatient.text = matches.single['id'] as String;
      _requestPatientStatus =
          'Cuenta activada y vinculada. Coteja la identidad del PDF antes de crear la orden.';
      _requestIdentityChecked = false;
      _requestHumanChecked = false;
    });
  }

  Future<void> _linkPatient() async {
    final lab=_labId,patientId=_requireUuid(_patientAccount.text);
    final evidence=_evidence.text.trim();
    if(lab==null||patientId==null||evidence.length<6||!_verifiedPatient){
      throw const AuthFailure('Confirma la identidad por un medio oficial y registra su referencia.');
    }
    await widget.api.silMainRequest('/labs/$lab/patients',body:{
      'patientId':patientId,
      'identityEvidenceReference':evidence,
      'identityVerified':true,
    });
    if (!mounted) return;
    _patientAccount.clear();
    _evidence.clear();
    setState(()=>_verifiedPatient=false);
    await _loadPatients(offset: 0);
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
    await _loadOrders();
  }

  Future<void> _pickPdf() async {
    final selection=await openFile(acceptedTypeGroups:const [
      XTypeGroup(label:'Documento PDF',extensions:['pdf'],mimeTypes:['application/pdf']),
    ]);
    if(selection==null||!mounted)return;
    setState(()=>_pdf=selection);
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
      _requestReference.clear();
      _requestPrescriber.clear();
      _requestDate.clear();
      _requestExams.clear();
      _requestPreviewNotice = null;
      _requestIdentityChecked = false;
      _requestHumanChecked = false;
    });
  }

  void _useMedicalSuggestions(Map<String,dynamic> preview){
    _requestReference.text=preview['suggestedDocumentReference'] as String? ?? '';
    _requestPrescriber.text=preview['suggestedPrescriberName'] as String? ?? '';
    _requestDate.text=preview['suggestedRequestDate'] as String? ?? '';
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
    await widget.api.silMainRequest('/labs/$lab/medical-requests/pending/$id/complete',
      body:{
        'patientId':patientId,'patientEmail':email,
        'examCodes':_requestExams.toList(),
        'documentReference':_requestReference.text.trim(),
        'prescriberName':_requestPrescriber.text.trim(),
        'requestDate':_requestDate.text.trim(),
        'patientIdentityConfirmed':true,'humanReviewConfirmed':true,
      });
    if(!mounted)return;
    setState((){
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
      _requestReference.clear();
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
    await widget.api.silMainAttachMedicalRequest(
      labId: lab, orderId: orderId, patientId: patientId, examCodes: _requestExams.toList(),
      fileName: file.name, bytes: await file.readAsBytes(),
      prescriberName: _requestPrescriber.text,
      documentReference: _requestReference.text,
      requestDate: _requestDate.text.trim(),
    );
    if (!mounted) return;
    setState(() {
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
      _requestReference.clear();
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
      _reviewConfirmed=false;
      _reviewPdfDownloaded=false;
    });
    await _loadOrders();
  }

  Widget _section(String title,String detail,IconData icon,List<Widget> children){
    return Card(
      clipBehavior:Clip.antiAlias,
      child:Padding(
        padding:const EdgeInsets.all(21),
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
              const SizedBox(height:3),
              Text(detail,style:const TextStyle(
                color:ColoresVitalia.textoSecundario,fontSize:12,height:1.4,
              )),
            ])),
          ]),
          const SizedBox(height:16),
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

  Widget _action(String text,IconData icon,Future<void> Function() task)=>SizedBox(
    width:double.infinity,
    child:FilledButton.icon(
      onPressed:_busy?null:()=>_execute(task),
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
      recent ? 'Actividad reciente' : 'Órdenes del laboratorio',
      'Consulta postanalítica del laboratorio seleccionado.',
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
          if (_operator)
            _field(_orderSearch, 'Folio o correo del paciente',
              identifier: 'sil-order-search'),
          DropdownButtonFormField<String>(
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
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _execute(
              () => _loadOrderPage(offset: 0, search: _orderSearch.text.trim()),
              showNotice: false,
            ),
            icon: const Icon(Icons.search),
            label: const Text('Buscar órdenes'),
          ),
          const SizedBox(height: 8),
        ],
        if(list.isEmpty)
          const Padding(
            padding:EdgeInsets.only(bottom:12),
            child:Text('No hay órdenes para mostrar.'),
          )
        else
          for(final order in list.take(50))
            Container(
              margin:const EdgeInsets.only(bottom:8),
              padding:const EdgeInsets.all(12),
              decoration:BoxDecoration(
                color:ColoresVitalia.fondoAzul,
                borderRadius:BorderRadius.circular(10),
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
                              onPressed: _busy ? null : () => setState(() {
                                _reviewOrderId = order['id'] as String;
                                _reviewPdfDownloaded = false;
                                _reviewConfirmed = false;
                                _activeSection = _StationSection.review;
                              }),
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
        OutlinedButton.icon(
          onPressed:_busy?null:()=>_execute(_loadLabs,showNotice:false),
          icon:const Icon(Icons.refresh),
          label:const Text('Actualizar estación'),
        ),
      ],
    );
  }

  Widget _adminPanel({bool showLaboratory = true, bool showOperators = true}){
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
      if (showLaboratory) _section('Registrar laboratorio',
        'Crea una organización real del sistema, sin generar datos clínicos.',
        Icons.add_business_outlined,[
        _field(_name,'Nombre del laboratorio'),
        _action('Registrar laboratorio',Icons.add,_createLab),
      ]),
      if(showOperators && _labId!=null)
        _section('Invitar operador de laboratorio',
          'Crea una invitación con código de un solo uso. El destinatario '
          'activa una cuenta nueva con rol de operador.',
          Icons.mark_email_read_outlined,[
          _field(_inviteEmail,'Correo del nuevo operador'),
          const Text(
            'El código de acceso debe entregarse por un canal '
            'oficial. No se envían correos automáticamente.',
            style:TextStyle(fontSize:12,
              color:ColoresVitalia.textoSecundario),
          ),
          const SizedBox(height:12),
          _action('Crear invitación',Icons.person_add_alt_1,_inviteOperator),
        ]),
      if(showOperators && _labId!=null)
        _section('Operadores y permisos de revisión',
          'Cada operador autorizado aparece aquí después de activar su invitación. '
          'La revisión requiere un permiso explícito del administrador.',
          Icons.admin_panel_settings_outlined,[
          OutlinedButton.icon(
            onPressed:_busy?null:()=>_execute(_loadStaff,showNotice:false),
            icon:const Icon(Icons.refresh),
            label:const Text('Actualizar operadores'),
          ),
          const SizedBox(height:10),
          if(_labStaff.isEmpty)
            const Padding(
              padding:EdgeInsets.symmetric(vertical:12),
              child:Text('Todavía no hay operadores vinculados a este laboratorio. '
                'Crea una invitación y pide al destinatario que active su acceso.'),
            ),
          for(final member in _labStaff)
            Card(
              child:Padding(
                padding:const EdgeInsets.all(14),
                child:Column(
                  crossAxisAlignment:CrossAxisAlignment.stretch,
                  children:[
                    Text(member['email'] as String,
                      overflow:TextOverflow.ellipsis,
                      style:const TextStyle(fontWeight:FontWeight.w700)),
                    const SizedBox(height:6),
                    Text(member['active']==true
                      ?member['canReviewReports']==true
                        ?'Operador activo · revisión autorizada'
                        :'Operador activo · sin permiso de revisión'
                      :'Operador desactivado',
                      style:const TextStyle(fontSize:12)),
                    const SizedBox(height:8),
                    Align(
                      alignment:Alignment.centerRight,
                      child:OutlinedButton.icon(
                        onPressed:_busy||member['active']!=true?null
                          :()=>_execute(()=>_setReviewPermission(
                            member['accountId'] as String,
                            member['canReviewReports']!=true,
                          )),
                        icon:Icon(member['canReviewReports']==true
                          ?Icons.remove_moderator_outlined
                          :Icons.verified_user_outlined),
                        label:Text(member['canReviewReports']==true
                          ?'Retirar permiso de revisión'
                          :'Autorizar revisión'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height:12),
          ExpansionTile(
            tilePadding:EdgeInsets.zero,
            title:const Text('Vincular una cuenta operadora existente'),
            subtitle:const Text('Solo cuentas ya activas con rol de operador'),
            children:[
              _field(_staffAccount,'UUID de una cuenta operadora existente'),
              const SizedBox(height:8),
              _action('Vincular al laboratorio',Icons.person_add_alt_1,_grantStaff),
            ],
          ),
        ]),
    ]);
  }

  Widget _patientLink() => _section('Vincular paciente verificado',
        'Primero comprueba la identidad por el procedimiento autorizado '
        'del laboratorio. Un correo coincidente no es verificación suficiente.',
        Icons.person_add_alt_1_outlined,[
        _field(_patientAccount,'UUID de la cuenta del paciente'),
        _field(_evidence,'Referencia de verificación de identidad'),
        CheckboxListTile(
          contentPadding:EdgeInsets.zero,
          value:_verifiedPatient,
          onChanged:_busy?null:(v)=>setState(()=>_verifiedPatient=v??false),
          title:const Text('Identidad contrastada con evidencia externa'),
          subtitle:const Text('No almacenes datos sensibles en este campo.'),
          controlAffinity:ListTileControlAffinity.leading,
        ),
        _action('Vincular paciente',Icons.verified_outlined,_linkPatient),
        const Divider(),
        _field(_invitedPatientEmail, 'Correo de un paciente nuevo'),
        _action('Emitir código de activación', Icons.person_add_alt_1_outlined,
          () => _invitePatient()),
      ]);

  Widget _newOrder() => _section('Crear orden postanalítica',
        'Selecciona prestaciones del catálogo para un paciente '
        'previamente vinculado al laboratorio.',
        Icons.note_add_outlined,[
        _field(_orderPatient,'UUID del paciente vinculado'),
        Wrap(spacing:7,runSpacing:4,children:[
          for(final (code,label) in _catalog)
            FilterChip(
              label:Text(label),
              selected:_codes.contains(code),
              onSelected:_busy?null:(v)=>setState((){
                if(v){_codes.add(code);}else{_codes.remove(code);}
              }),
            ),
        ]),
        const SizedBox(height:12),
        _action('Registrar orden',Icons.add_circle_outline,_createOrder),
      ]);

  Widget _requestIntake() => SilWorkspaceColumns(
    primary: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('1. Documento de derivación',
        'Carga una solicitud o retoma un PDF guardado en el laboratorio.',
        Icons.description_outlined, [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vincular a una orden existente'),
          value: _attachToExistingOrder,
          onChanged: _busy ? null : (value) => setState(() {
            _attachToExistingOrder = value;
            _requestIdentityChecked = false;
            _requestHumanChecked = false;
            if(value)_pendingRequestId=null;
          }),
        ),
        if(!_attachToExistingOrder)...[
          OutlinedButton.icon(
            onPressed:_busy?null:()=>_execute(_loadPendingRequests,showNotice:false),
            icon:const Icon(Icons.refresh_outlined),
            label:const Text('Actualizar derivaciones pendientes'),
          ),
          if(_pendingRequests.isNotEmpty)...[
            const SizedBox(height:9),
            DropdownButtonFormField<String>(
              key:ValueKey((_labId,_pendingRequestId,'pending-referrals')),
              value:_pendingRequestId,
              isExpanded:true,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Derivación pendiente guardada',
              ),
              items:[
                for(final pending in _pendingRequests)
                  DropdownMenuItem<String>(
                    value:pending['id'] as String,
                    child:Text(
                      '${pending['fileName']} · '
                      '${pending['patientEmail'] ?? 'Paciente por identificar'}',
                      overflow:TextOverflow.ellipsis),
                  ),
              ],
              onChanged:_busy?null:_selectPendingRequest,
            ),
          ],
        ],
        const SizedBox(height:10),
        OutlinedButton.icon(
          onPressed:_busy?null:_pickMedicalRequest,
          icon:const Icon(Icons.picture_as_pdf_outlined),
          label:Text(_medicalRequestFile?.name ??
            (_pendingRequestId==null?'Seleccionar solicitud PDF':
              'Seleccionar un PDF distinto')),
        ),
        const SizedBox(height:8),
        OutlinedButton.icon(
          onPressed: _busy || _medicalRequestFile == null ? null :
            () => _execute(_previewMedicalRequest, showNotice: false),
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Leer PDF y sugerir datos'),
        ),
        if(!_attachToExistingOrder)...[
          const SizedBox(height:8),
          OutlinedButton.icon(
            onPressed:_busy||_medicalRequestFile==null||_pendingRequestId!=null
              ?null:()=>_execute(_savePendingRequest),
            icon:const Icon(Icons.save_outlined),
            label:const Text('Guardar derivación pendiente'),
          ),
          if(_pendingRequestId!=null)...[
            const SizedBox(height:8),
            OutlinedButton.icon(
              onPressed:_busy?null:()=>_execute(_downloadPendingRequest,showNotice:false),
              icon:const Icon(Icons.download_outlined),
              label:const Text('Descargar derivación pendiente original'),
            ),
            const SizedBox(height:6),
            const Text('El archivo está guardado en Vitalia. '
              'Puede retomar su recepción aunque cierre la sesión.'),
          ],
        ],
        const SizedBox(height:12),
        if (_requestPreviewNotice != null) Text(_requestPreviewNotice!),
        if(_requestIdentitySuggestions.values.any((v)=>v is String&&v.isNotEmpty))
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: true,
            title: const Text('Datos identificatorios sugeridos por el PDF'),
            subtitle: const Text('Coteja estas sugerencias con el documento.'),
            children: [
              for(final field in <(String,String)>[
                ('fullName','Nombre completo'),('identifier','RUT/RUN'),
                ('birthDate','Fecha de nacimiento'),('email','Correo'),
                ('phone','Teléfono'),('sex','Sexo'),
              ])
                if(_requestIdentitySuggestions[field.$1] case final String value)
                  ListTile(
                    dense:true,
                    title:Text(field.$2),
                    subtitle:SelectableText(value),
                  ),
            ],
          ),
      ]),
      _section('2. Datos de la solicitud',
        'Coteja y ajusta los datos y las prestaciones antes de registrar.',
        Icons.playlist_add_check_outlined, [
        if (!_attachToExistingOrder) ...[
          const Text('Prestaciones solicitadas'),
          Wrap(spacing: 8, children: [
            for (final (code,label) in _catalog)
              FilterChip(
                label: Text(label),
                selected: _requestExams.contains(code),
                onSelected: _busy ? null : (selected) => setState(() {
                  if (selected) {
                    _requestExams.add(code);
                  } else {
                    _requestExams.remove(code);
                  }
                }),
              ),
          ]),
        ],
        _field(_requestReference,'Referencia de solicitud'),
        _field(_requestPrescriber,'Profesional solicitante'),
        _field(_requestDate,'Fecha de solicitud (AAAA-MM-DD)'),
      ]),
    ]),
    secondary: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('3. Identificación del paciente',
        'Comprueba a quién pertenece la solicitud.',
        Icons.badge_outlined, [
        if (_attachToExistingOrder)
          DropdownButtonFormField<String>(
            value:_requestOrderId,
            isExpanded:true,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Orden del paciente',
            ),
            items:[
              for(final order in _workflowOrders.where((v)=>v['status']=='registered'))
                DropdownMenuItem<String>(
                  value:order['id'] as String,
                  child:Text(_orderLabel(order),overflow:TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy ? null : (value) => setState(() {
              _requestOrderId = value;
              _requestIdentityChecked = false;
              _requestHumanChecked = false;
            }),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.only(bottom:10),
            child:Text('Paciente de esta derivación',
              style:TextStyle(fontWeight:FontWeight.w700)),
          ),
          const Text('Busca la cuenta activada. Si aún no existe, '
              'verifica la identidad y emite una invitación.'),
          const SizedBox(height:10),
          _field(_requestInviteEmail,'Correo del paciente',onChanged: (_) => setState(() {
            _requestPatient.clear();
            _requestIdentityEvidence.clear();
            _requestPatientVerified = false;
            _requestPatientStatus = null;
            _requestIdentityChecked = false;
            _requestHumanChecked = false;
          })),
          _field(_requestIdentityEvidence,'Referencia de verificación de identidad',
            onChanged: (_) => setState(() => _requestPatientVerified = false)),
          CheckboxListTile(
            contentPadding:EdgeInsets.zero,
            controlAffinity:ListTileControlAffinity.leading,
            title:const Text('Verifiqué la identidad antes de invitar'),
            subtitle:const Text('El correo por sí solo no demuestra identidad. '
                'No ingreses datos sensibles como evidencia.'),
            value:_requestPatientVerified,
            onChanged:_busy?null:(value)=>setState(
              ()=>_requestPatientVerified=value??false),
          ),
          OutlinedButton.icon(
            // La invitación debe estar disponible tanto para un PDF local
            // como para una derivación pendiente recuperada de PostgreSQL.
            onPressed:_busy||(_medicalRequestFile==null&&_pendingRequestId==null)
              ?null:()=>_execute(()=>_invitePatient(fromRequest:true),showNotice:false),
            icon:const Icon(Icons.mark_email_read_outlined),
            label:const Text('Emitir invitación de paciente'),
          ),
          const SizedBox(height:8),
          OutlinedButton.icon(
            onPressed:_busy?null:()=>_execute(_findRequestPatient,showNotice:false),
            icon:const Icon(Icons.person_search_outlined),
            label:const Text('Buscar paciente activado'),
          ),
          if(_requestPatientStatus!=null)
            Padding(
              padding:const EdgeInsets.symmetric(vertical:8),
              child:Text(_requestPatientStatus!,
                style:const TextStyle(color:ColoresVitalia.azul)),
            ),
          ExpansionTile(
            tilePadding:EdgeInsets.zero,
            title:const Text('Seleccionar paciente por identificador (avanzado)'),
            children:[
              _field(_requestPatient,'UUID del paciente vinculado',
                onChanged: (_) => setState(() {
                  _requestIdentityChecked=false;
                  _requestHumanChecked=false;
                })),
            ],
          ),
        ],
      ]),
      _section('4. Confirmación y registro',
        'Confirma el cotejo para guardar la solicitud en una orden.',
        Icons.fact_check_outlined, [
        CheckboxListTile(
          contentPadding:EdgeInsets.zero,
          controlAffinity:ListTileControlAffinity.leading,
          title:const Text('Identidad del paciente contrastada'),
          subtitle:const Text('Comprueba que la solicitud corresponde al paciente vinculado.'),
          value:_requestIdentityChecked,
          onChanged:_busy?null:(v)=>setState(()=>_requestIdentityChecked=v??false),
        ),
        CheckboxListTile(
          contentPadding:EdgeInsets.zero,
          controlAffinity:ListTileControlAffinity.leading,
          title:const Text('Revisé el contenido del PDF original'),
          value:_requestHumanChecked,
          onChanged:_busy?null:(v)=>setState(()=>_requestHumanChecked=v??false),
        ),
        if(_attachToExistingOrder)
          _action('Registrar solicitud',Icons.post_add_outlined,_attachMedicalRequest)
        else SizedBox(
          width:double.infinity,
          child:FilledButton.icon(
            onPressed:_busy||_pendingRequestId==null?null:
              ()=>_execute(_completePendingRequest),
            icon:const Icon(Icons.post_add_outlined),
            label:const Text('Crear orden con solicitud'),
          ),
        ),
      ]),
    ]),
  );

  Widget _reportUpload() => _section('Adjuntar informe autorizado',
        'Solo se reciben PDF ya validados externamente. '
        'El informe queda pendiente de revisión antes de publicarlo.',
        Icons.upload_file_outlined,[
        Semantics(
          identifier:'sil-upload-order',
          child:DropdownButtonFormField<String>(
            value:_uploadOrderId,
            isExpanded:true,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Orden disponible',
            ),
            items:[
              for(final order in _workflowOrders.where((v)=>v['status']=='registered'))
                DropdownMenuItem<String>(
                  value:order['id'] as String,
                  child:Text(_orderLabel(order),overflow:TextOverflow.ellipsis),
                ),
            ],
            onChanged:_busy?null:(v)=>setState(() {
              _uploadOrderId = v;
              _confirmedMatch = false;
            }),
          ),
        ),
        const SizedBox(height:10),
        OutlinedButton.icon(
          onPressed:_busy?null:_pickPdf,
          icon:const Icon(Icons.picture_as_pdf_outlined),
          label:Text(_pdf?.name??'Elegir archivo PDF (máx. 2 MiB)'),
        ),
        const SizedBox(height:8),
        _field(_reportProfessional,'Profesional que autorizó el PDF',
          identifier:'sil-report-professional'),
        _field(_reportReference,'Referencia de autorización externa',
          identifier:'sil-report-reference'),
        _field(_reportDate,'Fecha de autorización (AAAA-MM-DD)'),
        OutlinedButton.icon(
          onPressed: _busy ? null : _selectReportDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: const Text('Elegir fecha de autorización'),
        ),
        CheckboxListTile(
          contentPadding:EdgeInsets.zero,
          controlAffinity:ListTileControlAffinity.leading,
          title:const Text('El informe ya fue autorizado fuera de Vitalia'),
          value:_externallyAuthorized,
          onChanged:_busy?null:(v)=>setState(()=>_externallyAuthorized=v??false),
        ),
        CheckboxListTile(
          contentPadding:EdgeInsets.zero,
          controlAffinity:ListTileControlAffinity.leading,
          title:const Text('Confirmé que el PDF corresponde al paciente de la orden'),
          value:_confirmedMatch,
          onChanged:_busy?null:(v)=>setState(()=>_confirmedMatch=v??false),
        ),
        _action('Adjuntar para revisión',Icons.upload_file,_attachReport),
      ]);

  Widget _reviewPanel(){
    return _section('Validación y publicación',
      'Revisa el PDF y confirma su autorización externa antes de publicarlo.',
      Icons.fact_check_outlined,[
      Semantics(
        identifier:'sil-review-order',
        child:DropdownButtonFormField<String>(
          value:_reviewOrderId,
          isExpanded:true,
          decoration:const InputDecoration(
            border:OutlineInputBorder(),labelText:'Informe pendiente de revisión',
          ),
          items:[
            for(final order in _workflowOrders.where(_isReviewable))
              DropdownMenuItem<String>(
                value:order['id'] as String,
                child:Text(_orderLabel(order),overflow:TextOverflow.ellipsis),
              ),
          ],
          onChanged:_busy?null:(v)=>setState((){
            _reviewOrderId=v;
            _reviewPdfDownloaded=false;
            _reviewConfirmed=false;
          }),
        ),
      ),
      const SizedBox(height:10),
      OutlinedButton.icon(
        onPressed:_busy||_reviewOrderId==null
            ?null
            :()=>_execute(_downloadReportForReview,showNotice:false),
        icon:const Icon(Icons.picture_as_pdf_outlined),
        label:const Text('Descargar PDF para revisión'),
      ),
      const SizedBox(height:8),
      const Text(
        'Antes de publicar, revisa el PDF original y su autorización '
        'en el procedimiento clínico de tu laboratorio. '
        'Esta pantalla no sustituye ese procedimiento.',
        style:TextStyle(fontSize:12,color:ColoresVitalia.textoSecundario),
      ),
      CheckboxListTile(
        contentPadding:EdgeInsets.zero,
        controlAffinity:ListTileControlAffinity.leading,
        title:const Text('Confirmo que revisé el PDF y su autorización externa'),
        value:_reviewConfirmed,
        onChanged:_busy||!_reviewPdfDownloaded
            ?null
            :(v)=>setState(()=>_reviewConfirmed=v??false),
      ),
      FilledButton.icon(
        onPressed:_busy||!_reviewConfirmed?null:()=>_execute(_publishReport),
        icon:const Icon(Icons.verified_outlined),
        label:const Text('Publicar informe'),
      ),
    ]);
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

  void _openSection(_StationSection section) {
    if (_busy || section == _activeSection) return;
    setState(() => _activeSection = section);
    if (section == _StationSection.patients) {
      _execute(() => _loadPatients(offset: 0), showNotice: false);
    } else if (section == _StationSection.orders) {
      _execute(() => _loadOrderPage(offset: _orderOffset), showNotice: false);
    }
  }

  String _patientName(Map<String,dynamic> patient) {
    final name = [patient['givenNames'], patient['familyNames']].whereType<String>().join(' ').trim();
    return name.isEmpty ? patient['email'] as String : name;
  }

  Widget _patientDirectory() => _section(
    'Directorio de pacientes', 'Pacientes vinculados al laboratorio activo.',
    Icons.badge_outlined, [
      _field(_patientSearch, 'Buscar por nombre o correo'),
      _action('Buscar pacientes', Icons.search,
        () => _loadPatients(offset: 0, search: _patientSearch.text.trim())),
      if (_patients.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('No hay pacientes para mostrar.')),
      for (final patient in _patients)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_patientName(patient)),
          subtitle: Text(patient['email'] as String),
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
                _attachToExistingOrder = false;
                _requestIdentityChecked = false;
                _requestHumanChecked = false;
              } else {
                _orderPatient.text = patient['id'] as String;
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
    final pending = _orders.where(_isReviewable).length;
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
    _AdminSection.laboratories => SilWorkspaceColumns(
      primary: _adminPanel(showOperators: false),
      primaryFlex: 6,
      secondaryFlex: 5,
      secondary: _section(
        'Laboratorio seleccionado',
        'Consulta el contexto sobre el que trabajarás.',
        Icons.business_outlined,
        [
          Text(_labs.where((lab) => lab['id'] == _labId)
              .map((lab) => lab['displayName'] as String).firstOrNull
              ?? 'Todavía no hay un laboratorio seleccionado.'),
          const SizedBox(height: 10),
          Text('${_labs.length} laboratorio(s) registrados en esta cuenta.'),
          if (_labId != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => setState(
                () => _adminSection = _AdminSection.operators),
              icon: const Icon(Icons.people_outline),
              label: const Text('Gestionar operadores'),
            ),
          ],
        ],
      ),
    ),
    _AdminSection.operators => _labId == null
        ? _section('Selecciona un laboratorio',
            'Registra primero un laboratorio para habilitar operadores.',
            Icons.info_outline, [])
        : SilWorkspaceColumns(
            primary: _adminPanel(showLaboratory: false),
            secondary: _section('Estado de operadores',
                'Información del laboratorio seleccionado.',
                Icons.people_outline, [
                  Text('${_labStaff.length} operadores en la lista'),
                  const SizedBox(height: 8),
                  Text('${_labStaff.where((staff) => staff['active'] == true && staff['canReviewReports'] == true).length} con permiso de revisión'),
                ]),
            primaryFlex: 7, secondaryFlex: 4,
          ),
    _AdminSection.activity => _labId == null
        ? _section('Selecciona un laboratorio',
            'La actividad requiere un laboratorio seleccionado.',
            Icons.info_outline, [])
        : _ordersPanel(),
  };


  Widget _operatorMetrics() {
    // El API entrega hasta 50 órdenes y 50 derivaciones pendientes.
    // Las tarjetas muestran solo el recuento del conjunto consultado.
    final counts = <({IconData icon, String label, int value,
      _StationSection destination, Color color, Color tint})>[
      (icon: Icons.note_add_outlined, label: 'Derivaciones pendientes',
        value: _pendingRequests.length, destination: _StationSection.requests,
        color: const Color(0xFFB54B5D), tint: ColoresVitalia.errorSuave),
      (icon: Icons.assignment_outlined, label: 'Órdenes consultadas',
        value: _orders.length, destination: _StationSection.orders,
        color: OperatorPalette.blue, tint: ColoresVitalia.azulSuave),
      (icon: Icons.inventory_2_outlined, label: 'Órdenes registradas',
        value: _orders.where((o) => o['status'] == 'registered').length,
        destination: _StationSection.orders,
        color: const Color(0xFF99630F), tint: ColoresVitalia.advertenciaSuave),
      (icon: Icons.fact_check_outlined, label: 'PDF pendientes de revisión',
        value: _orders.where(_isReviewable).length,
        destination: _canReview ? _StationSection.review : _StationSection.orders,
        color: const Color(0xFF7454A8), tint: ColoresVitalia.pendienteSuave),
      (icon: Icons.picture_as_pdf_outlined, label: 'Informes publicados',
        value: _orders.where((o) => o['status'] == 'report_published').length,
        destination: _StationSection.orders,
        color: OperatorPalette.teal, tint: ColoresVitalia.verdeSuave),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1060 ? 5 :
          constraints.maxWidth >= 700 ? 3 :
          constraints.maxWidth >= 430 ? 2 : 1;
      const gap = 10.0;
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final item in counts)
          SizedBox(
            width: width,
            child: OperatorMetricCard(
              icon: item.icon,
              label: item.label,
              count: item.value,
              accent: item.color,
              tint: item.tint,
              caption: 'En listas recientes (máx. 50)',
              onTap: _busy ? null : () => _openSection(item.destination),
            ),
          ),
      ]);
    });
  }

  Widget _dashboard() {
    final pending = _orders.where(_isReviewable).length;
    final shortcuts = _section('Accesos rápidos',
      'Inicia o continúa una tarea desde el mismo panel.',
      Icons.bolt_outlined, [
        OperatorActionTile(
          icon: Icons.note_add_outlined,
          label: 'Iniciar recepción',
          subtitle: 'Adjuntar y comprobar una solicitud PDF',
          onTap: _busy ? null : () => _openSection(_StationSection.requests),
        ),
        const SizedBox(height: 9),
        OperatorActionTile(
          icon: Icons.post_add_outlined,
          label: 'Gestionar órdenes',
          subtitle: 'Buscar o crear una orden interna',
          onTap: _busy ? null : () => _openSection(_StationSection.orders),
        ),
        const SizedBox(height: 9),
        OperatorActionTile(
          icon: Icons.people_outline,
          label: 'Consultar pacientes',
          subtitle: 'Directorio del laboratorio activo',
          onTap: _busy ? null : () => _openSection(_StationSection.patients),
        ),
        if (_canReview) ...[
          const SizedBox(height: 9),
          OperatorActionTile(
            icon: Icons.fact_check_outlined,
            label: 'Revisar informes',
            subtitle: 'Validación y autorización externa',
            count: pending,
            onTap: _busy ? null : () => _openSection(_StationSection.review),
          ),
        ],
      ]);
    final queues = _section('Colas del laboratorio',
      'Recuentos de las listas cargadas, no del histórico completo.',
      Icons.work_outline, [
        _queueLink(Icons.note_add_outlined, 'Derivaciones pendientes',
          _pendingRequests.length, _StationSection.requests),
        _queueLink(Icons.assignment_outlined, 'Órdenes consultadas',
          _orders.length, _StationSection.orders),
        if (_canReview)
          _queueLink(Icons.fact_check_outlined, 'Informes por revisar',
            pending, _StationSection.review),
      ]);
    final notices = _section('Trabajo seguro',
      'La publicación es una acción independiente.',
      Icons.shield_outlined, [
        const OperatorInfoNote(
          icon: Icons.verified_user_outlined,
          title: 'Comprobación humana',
          description: 'Las sugerencias del PDF no crean ni autorizan órdenes automáticamente. Antes de publicar, verifica el documento original.',
          color: OperatorPalette.teal,
          background: ColoresVitalia.verdeSuave,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _execute(_loadLabs,showNotice:false),
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Actualizar estación'),
        ),
      ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OperatorHero(
        eyebrow: 'Estación del operador',
        title: 'Panel del laboratorio',
        subtitle: 'Recibe derivaciones, organiza órdenes y continúa el trabajo postanalítico desde un mismo espacio.',
        actions: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _openSection(_StationSection.requests),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Recibir solicitud de exámenes'),
            style: FilledButton.styleFrom(
              foregroundColor: OperatorPalette.navy,
              backgroundColor: Colors.white,
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openSection(_StationSection.orders),
            icon: const Icon(Icons.assignment_outlined),
            label: const Text('Ver órdenes'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFA5D0DC)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _operatorMetrics(),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 1020) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _ordersPanel(recent: true),
            const SizedBox(height: 12),
            queues,
            const SizedBox(height: 12),
            shortcuts,
            const SizedBox(height: 12),
            notices,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 7, child: Column(children: [
            _ordersPanel(recent: true),
            const SizedBox(height: 12),
            queues,
          ])),
          const SizedBox(width: 14),
          Expanded(flex: 3, child: Column(children: [
            shortcuts,
            const SizedBox(height: 12),
            notices,
          ])),
        ]);
      }),
    ]);
  }

  Widget _queueLink(IconData icon, String title, int count, _StationSection section) =>
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: ColoresVitalia.azul),
      title: Text(title),
      subtitle: Text('$count en la lista'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _busy ? null : () => _openSection(section),
    );

  Widget _operatorSubpage({
    required String title,
    required String description,
    required Widget child,
    Widget? support,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OperatorHero(
        eyebrow: 'Estación del operador',
        title: title,
        subtitle: description,
        compact: true,
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
        description: 'Encuentra una orden y continúa su seguimiento en el laboratorio activo.',
        support: _operatorMetrics(),
        child: SilWorkspaceColumns(
          primary: _ordersPanel(),
          secondary: Column(children: [_newOrder(), _reportUpload()]),
          primaryFlex: 6, secondaryFlex: 5,
        ),
      ),
      _StationSection.requests => _operatorSubpage(
        title: 'Recibir solicitud',
        description: 'Carga una derivación PDF, coteja la identidad y confirma su vinculación.',
        support: const OperatorInfoNote(
          icon: Icons.file_present_outlined,
          title: 'Recepción segura',
          description: 'La solicitud puede guardarse como pendiente. La extracción automática no confirma la identidad ni autoriza órdenes.',
        ),
        child: _requestIntake(),
      ),
      _StationSection.patients => _operatorSubpage(
        title: 'Pacientes',
        description: 'Consulta cuentas asociadas al laboratorio y continúa sus órdenes.',
        child: SilWorkspaceColumns(
          primary: _patientDirectory(),
          secondary: _patientLink(),
          primaryFlex: 6, secondaryFlex: 5,
        ),
      ),
      _StationSection.clinical => _operatorSubpage(
        title: 'Control de muestras y resultados',
        description: 'Consulta una orden y registra su información postanalítica.',
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
              description: 'Verifica el PDF y su autorización externa antes de publicar.',
              support: OperatorInfoNote(
                icon: Icons.fact_check_outlined,
                title: 'Revisión y publicación',
                description: 'Pendientes en órdenes recientes: ' +
                    _orders.where(_isReviewable).length.toString() +
                    '. La publicación requiere autorización.',
                color: OperatorPalette.teal,
                background: ColoresVitalia.verdeSuave,
              ),
              child: _reviewPanel(),
            )
          : _dashboard(),
    };
  }

  String get _sectionTitle => switch (_activeSection) {
    _StationSection.dashboard => 'Panel del laboratorio',
    _StationSection.orders => 'Gestión de órdenes',
    _StationSection.requests => 'Recepción de derivaciones',
    _StationSection.patients => 'Pacientes del laboratorio',
    _StationSection.clinical => 'Seguimiento de muestras',
    _StationSection.review => 'Revisión y publicación',
  };

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
        value: _labId,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const SilWorkspaceBrand(),
        actions: [
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
                    horizontal: constraints.maxWidth < 600 ? 12 : 24,
                    vertical: 20,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 24,
                            runSpacing: 14,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Semantics(header: true, child: Text(
                                _admin ? switch (_adminSection) {
                                  _AdminSection.laboratories => 'Administración de laboratorios',
                                  _AdminSection.operators => 'Operadores y permisos',
                                  _AdminSection.activity => 'Actividad del laboratorio',
                                } : 'Área operativa',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: ColoresVitalia.texto,
                                ),
                              )),
                              _labSelector(),
                            ],
                          ),
                          const SizedBox(height: 14),
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
                          if (_operator) _station(),
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
