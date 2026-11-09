import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_selector/file_selector.dart';

import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';
import 'directorio_pacientes_sil.dart';
import 'acceso_portal_paciente_demo.dart';
import 'nuevo_paciente_sil_dialog.dart';

enum _OperatorSection {
  dashboard,
  orders,
  request,
  reviewQueue,
  patient,
  manualOrder,
  samples,
  results,
  report,
}

/// Estación de trabajo del operador. Publica SOLO PDFs ya autorizados fuera de Vitalia.
class OperadorLaboratorioPage extends StatefulWidget {
  const OperadorLaboratorioPage({
    super.key,
    required this.api,
    required this.onExpired,
    this.onLogout,
  });

  final AuthApi api;
  final VoidCallback onExpired;
  final VoidCallback? onLogout;

  @override
  State<OperadorLaboratorioPage> createState() => _OperadorLaboratorioPageState();
}

class _OperadorLaboratorioPageState extends State<OperadorLaboratorioPage> {
  static const _pageSize = 20;
  static const _navy = ColoresVitalia.texto;
  static const _teal = ColoresVitalia.verde;
  static const _workspace = ColoresVitalia.fondoAzul;
  static const _line = ColoresVitalia.borde;
  static const _nav = <(_OperatorSection, IconData, String)>[
    (_OperatorSection.dashboard, Icons.dashboard_outlined, 'Resumen'),
    (_OperatorSection.orders, Icons.assignment_outlined, 'Órdenes'),
    (_OperatorSection.request, Icons.note_add_outlined, 'Recibir solicitud'),
    (_OperatorSection.reviewQueue, Icons.fact_check_outlined, 'Revisión interna'),
    (_OperatorSection.patient, Icons.badge_outlined, 'Pacientes'),
  ];

  // La búsqueda de fichas es distinta al correo usado al crear una orden.
  final _patientController = TextEditingController();
  final _patientLookup = TextEditingController();
  final _patientFormKey = GlobalKey<FormState>();
  final _directoryKey = GlobalKey<DirectorioPacientesSilState>();
  bool _mobilePatientDetail = false;
  final _requestPatientEmail = TextEditingController(
    text:'paciente.sil@example.invalid');
  final _requestDocumentReference = TextEditingController();
  final _requestPrescriberName = TextEditingController();
  XFile? _requestPdf;
  Map<String,dynamic>? _requestPreview;
  String? _requestBranchCode;
  DateTime? _requestDate;
  final _requestExamCodes=<String>{};
  bool _requestHumanConfirmed=false;
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _receiptNoteController = TextEditingController();
  final _reviewNoteController = TextEditingController();
  final _reviewPanelKey = GlobalKey();
  final _reportProfessional = TextEditingController();
  final _reportPatientIdentifier = TextEditingController();
  final _patientDemoGiven = TextEditingController();
  final _patientDemoFamily = TextEditingController();
  final _patientDemoBirth = TextEditingController();
  final _patientDemoPhone = TextEditingController();
  String _patientDemoSex = 'not_specified';
  bool _syntheticPatientConfirmed = false;
  Map<String, dynamic>? _patientDemoLoaded;
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranch;
  final _reportReference = TextEditingController();
  XFile? _reportFile;
  DateTime? _reportAuthorizedAt;
  bool _confirmExternal = false;
  bool _confirmPatient = false;
  final Map<String, TextEditingController> _manualControllers = {};
  XFile? _resultsPdf;
  String? _resultsPreviewToken;
  String? _resultsPreviewStatus;
  List<String> _resultsPreviewWarnings = [];
  final Map<String, String> _resultsRowWarnings = {};
  final Map<String, String> _aiPrefilledValues = {};
  bool _resultsReviewed = false;
  String? _containerCode;
  final _selectedExams = <String>{'hemograma'};

  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _recentOrders = [];
  int _listRequestId = 0;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _selected;
  String? _error;
  String? _message;
  String? _filterStatus;
  bool _busy = false;
  bool _loading = true;
  bool _ordersLoading = false;
  bool _canReview = false;
  int _page = 0;
  int _total = 0;
  _OperatorSection _section = _OperatorSection.dashboard;

  int get _pendingReviews => (_summary?['pendingReview'] as num?)?.toInt() ?? 0;

  int get _navigationIndex {
    final index = _nav.indexWhere((item) => item.$1 == _section);
    return index == -1 ? 1 : index;
  }

  void _goTo(_OperatorSection section) {
    if (section == _OperatorSection.reviewQueue) {
      _openQueue('results_recorded');
      return;
    }
    if (_busy || section == _section) return;
    setState(() {
      _section = section;
      if (section == _OperatorSection.patient) _mobilePatientDetail = false;
      _error = null;
      _message = null;
    });
    if (section == _OperatorSection.orders) _refreshOrders();
  }

  void _openQueue(String? status) {
    if (_busy) return;
    _searchController.clear();
    setState(() {
      _section = status == 'results_recorded'
          ? _OperatorSection.reviewQueue
          : _OperatorSection.orders;
      _filterStatus = status;
      _page = 0;
      _error = null;
      _message = null;
    });
    _refreshOrders();
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _patientController.dispose();
    _patientLookup.dispose();
    _requestPatientEmail.dispose();
    _requestDocumentReference.dispose();
    _requestPrescriberName.dispose();
    _searchController.dispose();
    _barcodeController.dispose();
    _receiptNoteController.dispose();
    _reviewNoteController.dispose();
    _reportProfessional.dispose();
    _reportPatientIdentifier.dispose();
    for (final controller in [
      _patientDemoGiven, _patientDemoFamily,
      _patientDemoBirth, _patientDemoPhone,
    ]) { controller.dispose(); }
    _reportReference.dispose();
    for (final controller in _manualControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final orders = _refreshOrders();
    try {
      final catalog = await widget.api.silRequest('/catalog');
      final branches = await widget.api.silRequest('/branches');
      final summary = await widget.api.silRequest('/summary');
      final recent = await widget.api.silRequest('/orders?limit=5&offset=0');
      if (!mounted) return;
      setState(() {
        _branches = (branches['branches'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _catalog = (catalog['exams'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _summary = Map<String, dynamic>.from(summary['summary'] as Map);
        _canReview = (summary['permissions'] as Map?)?['reviewResults'] == true;
        _recentOrders = (recent['orders'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
    } on AuthFailure catch (error) {
      _showFailure(error);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar los datos del laboratorio.');
    } finally {
      await orders;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshOrders() async {
    final requestId = ++_listRequestId;
    setState(() {
      _ordersLoading = true;
      _orders = [];
      _total = 0;
    });
    try {
      final params = <String, String>{
        'limit': '$_pageSize',
        'offset': '${_page * _pageSize}',
        if (_filterStatus != null) 'status': _filterStatus!,
        if (_searchController.text.trim().isNotEmpty)
          'search': _searchController.text.trim(),
      };
      final query = Uri(queryParameters: params).query;
      final response = await widget.api.silRequest('/orders?$query');
      if (!mounted || requestId != _listRequestId) return;
      setState(() {
        _orders = (response['orders'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _total = (response['total'] as num?)?.toInt() ?? _orders.length;
      });
    } on AuthFailure catch (error) {
      if (requestId == _listRequestId) _showFailure(error);
    } catch (_) {
      if (mounted && requestId == _listRequestId) {
        setState(() => _error = 'No se pudo actualizar la lista de órdenes.');
      }
    } finally {
      if (mounted && requestId == _listRequestId) {
        setState(() => _ordersLoading = false);
      }
    }
  }

  void _showFailure(AuthFailure error) {
    if (!mounted) return;
    if (error.status == 401) {
      widget.onExpired();
    } else {
      setState(() => _error = error.message);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on AuthFailure catch (error) {
      _showFailure(error);
    } catch (_) {
      if (mounted) setState(() => _error = 'No fue posible completar la operación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOrder(String id) async {
    final response = await widget.api.silRequest('/orders/$id');
    if (!mounted) return;
    final selected = Map<String, dynamic>.from(response);
    final order = Map<String, dynamic>.from(selected['order'] as Map);
    final required = (selected['requiredContainers'] as List? ?? []);
    final samples = (selected['samples'] as List? ?? []);
    final received = samples.map((item) => (item as Map)['containerCode']).toSet();
    final pending = required
        .where((item) => !received.contains((item as Map)['code']))
        .toList();
    for (final controller in _manualControllers.values) {
      controller.dispose();
    }
    _manualControllers.clear();
    _resultsPdf = null;
    _resultsPreviewToken = null;
    _resultsPreviewStatus = null;
    _resultsPreviewWarnings = [];
    _resultsRowWarnings.clear();
    _aiPrefilledValues.clear();
    _resultsReviewed = false;
    final codes = (selected['exams'] as List? ?? [])
        .map((item) => (item as Map)['code'])
        .toSet();
    final prior = <String, String>{};
    if (order['status'] == 'review_rejected') {
      for (final item in (selected['results'] as List? ?? [])) {
        final value = item as Map;
        prior['${value['examCode']}::${value['analyte']}'] =
            '${value['numericValue']}';
      }
    }
    for (final exam in _catalog) {
      if (!codes.contains(exam['code'])) continue;
      for (final analyte in (exam['analytes'] as List? ?? [])) {
        final name = (analyte as Map)['analyte'] as String;
        final code = exam['code'] as String;
        _manualControllers['$code::$name'] =
            TextEditingController(text: prior['$code::$name'] ?? '');
      }
    }
    setState(() {
      _selected = selected;
      _barcodeController.clear();
      _receiptNoteController.clear();
      _reviewNoteController.clear();
      // Nunca conservar un PDF o una confirmación al cambiar de paciente/orden.
      _reportFile = null;
      _reportProfessional.clear();
      _reportPatientIdentifier.clear();
      _selectedBranch = null;
      _reportReference.clear();
      _reportAuthorizedAt = null;
      _confirmExternal = false;
      _confirmPatient = false;
      _containerCode = pending.isEmpty ? null : (pending.first as Map)['code'] as String;
      _section = switch (order['status']) {
        'report_attached' || 'report_published' => _OperatorSection.report,
        'sampled' || 'results_recorded' || 'review_rejected' ||
          'review_approved' => _OperatorSection.results,
        _ => _OperatorSection.samples,
      };
    });
  }

  Future<void> _downloadMedicalRequest() => _run(() async {
    final order=_selected?['order'] as Map?;
    final request=_selected?['medicalRequest'] as Map?;
    if (order == null || request == null) {
      throw const AuthFailure('La orden no tiene solicitud PDF vinculada.');
    }
    final name=request['fileName'] as String;
    final bytes=await widget.api.silDownloadMedicalRequest(order['id'] as String);
    if(!mounted||!widget.api.hasSession)return;
    final pdf=XFile.fromData(bytes,name:name,mimeType:'application/pdf');
    if(kIsWeb){
      await pdf.saveTo(name);
    }else{
      final target=await getSaveLocation(suggestedName:name);
      if(target==null)return;
      await pdf.saveTo(target.path);
    }
    if (mounted) {
      setState(() =>
        _message='Descarga de solicitud registrada en auditoría.');
    }
  });

  Future<void> _selectMedicalRequestPdf() async {
    try{
      final file=await openFile(acceptedTypeGroups:const [
        XTypeGroup(label:'Solicitud médica ficticia PDF',
          extensions:['pdf'],mimeTypes:['application/pdf']),
      ]);
      if(file==null||!mounted)return;
      final length=await file.length();
      if(!mounted)return;
      if(length<8||length>2*1024*1024){
        setState(()=>_error='La solicitud debe ser un PDF ficticio de hasta 2 MiB.');
        return;
      }
      setState((){
        _requestPdf=file;
        _requestPreview=null;
        _requestHumanConfirmed=false;
        _requestExamCodes.clear();
        _requestDocumentReference.clear();
        _requestPrescriberName.clear();
        _requestDate=null;
        _error=null;
      });
    }catch(_){
      if(mounted)setState(()=>_error='No se pudo abrir la solicitud PDF.');
    }
  }

  List<String> _requestIdentityFailures(Map<String,dynamic> preview) {
    final identity=preview['identity'] as Map? ?? {};
    return [
      if(identity['identifierMatches']!=true)'identificador ficticio',
      if(identity['givenNamesMatch']!=true)'nombres',
      if(identity['familyNamesMatch']!=true)'apellidos',
      if(identity['birthDateMatches']!=true)'fecha de nacimiento',
    ];
  }

  Future<void> _previewMedicalRequest() => _run(() async {
    final file=_requestPdf;
    if(file==null)throw const AuthFailure('Selecciona una solicitud PDF de prueba.');
    final result=await widget.api.silPreviewMedicalRequest(
      email:_requestPatientEmail.text.trim().toLowerCase(),
      fileName:file.name,bytes:await file.readAsBytes(),
    );
    if(!mounted)return;
    final preview=Map<String,dynamic>.from(result['preview'] as Map);
    final suggestions=(preview['suggestedExams'] as List? ?? []);
    setState((){
      _requestPreview=preview;
      if (_requestDocumentReference.text.trim().isEmpty) {
        _requestDocumentReference.text=preview['suggestedDocumentReference'] as String? ?? '';
      }
      _requestExamCodes..clear()..addAll(suggestions.map(
        (item)=>(item as Map)['code'] as String));
      _requestHumanConfirmed=false;
      final failures=_requestIdentityFailures(preview);
      _message=preview['previewToken']!=null
        ? 'Identidad DEMO cotejada con el documento. Revisa las prestaciones '
          'y los datos del solicitante antes de crear la orden.'
        : null;
      _error=preview['previewToken']==null
        ? failures.isEmpty
          ? 'Solicitud no comprobable: revisa las observaciones del archivo. '
            'No se creó ninguna orden.'
          : 'Identidad no comprobada. Debes revisar: '
            '${failures.join(', ')}. No se creó ninguna orden.'
        : null;
    });
  });

  Future<void> _registerFromMedicalRequest() => _run(() async {
    final preview=_requestPreview;
    if(preview==null||preview['previewToken'] is! String){
      throw const AuthFailure('Primero analiza una solicitud con identidad comprobada.');
    }
    if(!_requestHumanConfirmed){
      throw const AuthFailure('El operador debe confirmar todas las comprobaciones.');
    }
    if(_requestBranchCode==null||_requestDate==null||
       _requestExamCodes.isEmpty){
      throw const AuthFailure('Selecciona sucursal, fecha y prestaciones solicitadas.');
    }
    final identity=preview['patient'] as Map;
    final result=await widget.api.silRequest('/medical-requests/confirm',body:{
      'previewToken':preview['previewToken'],
      'patientId':identity['id'],
      'branchCode':_requestBranchCode,
      'examCodes':_requestExamCodes.toList()..sort(),
      'documentReference':_requestDocumentReference.text.trim(),
      'prescriberName':_requestPrescriberName.text.trim(),
      'requestDate':_requestDate!.toIso8601String().substring(0,10),
      'verified':true,
    });
    if(!mounted)return;
    final order=Map<String,dynamic>.from(result['order'] as Map);
    final id=order['id'] as String;
    _requestPreview=null;
    _requestPdf=null;
    _requestHumanConfirmed=false;
    _requestExamCodes.clear();
    _requestDocumentReference.clear();
    _requestPrescriberName.clear();
    _requestDate=null;
    await _openOrder(id);
    await _refreshAll();
    if (mounted) {
      setState(() => _message =
        'Solicitud ficticia asociada a ${order['orderNumber']}. '
        'Continúa con las muestras requeridas.');
    }
  });

  Future<void> _createOrder() => _run(() async {
    final email = _patientController.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const AuthFailure('Ingresa el correo de un paciente registrado.');
    }
    if (_selectedExams.isEmpty) {
      throw const AuthFailure('Selecciona al menos un examen.');
    }
    final patient = await widget.api.silRequest(
      '/patients?email=${Uri.encodeQueryComponent(email)}',
    );
    final id = (patient['patient'] as Map)['id'] as String;
    final created = await widget.api.silRequest('/orders', body: {
      'patientId': id,
      'examCodes': _selectedExams.toList()..sort(),
    });
    await _openOrder((created['order'] as Map)['id'] as String);
    _page = 0;
    _filterStatus = null;
    _searchController.clear();
    await _refreshAll();
    if (mounted) {
      setState(() => _message = 'Orden registrada. Continúa con la recepción de la muestra.');
    }
  });

  Future<void> _receiveSample() => _run(() async {
    final order = _selected?['order'] as Map?;
    if (order == null) throw const AuthFailure('Selecciona una orden.');
    final barcode = _barcodeController.text.trim().toUpperCase();
    if (barcode.isNotEmpty && !RegExp(r'^[A-Z0-9-]{3,40}$').hasMatch(barcode)) {
      throw const AuthFailure('Código de muestra inválido: usa letras, números o guiones.');
    }
    final container = _containerCode;
    if (container == null) {
      throw const AuthFailure('No hay tubos pendientes de recepción.');
    }
    final id = order['id'] as String;
    final response = await widget.api.silRequest('/orders/$id/sample', body: {
      if (barcode.isNotEmpty) 'barcode': barcode,
      'containerCode': container,
      if (_receiptNoteController.text.trim().isNotEmpty)
        'receiptNote': _receiptNoteController.text.trim(),
    });
    await _openOrder(id);
    await _refreshAll();
    final code = (response['sample'] as Map?)?['barcode'] as String? ?? barcode;
    if (mounted) {
      setState(() => _message = code.isEmpty
          ? 'Recepción de muestra registrada.'
          : 'Recepción de muestra registrada. Código $code.');
    }
  });

  Future<void> _selectReportPdf() async {
    try {
      final file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Informe PDF',
          extensions: ['pdf'],
          mimeTypes: ['application/pdf'],
        ),
      ]);
      if (file == null || !mounted) return;
      final size = await file.length();
      if (!mounted) return;
      if (size < 8 || size > 2 * 1024 * 1024) {
        setState(() => _error = 'Selecciona un PDF de prueba de hasta 2 MiB.');
        return;
      }
      setState(() {
        _reportFile = file;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo seleccionar el PDF.');
    }
  }

  Future<void> _selectAuthorizationDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reportAuthorizedAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Fecha de autorización externa',
    );
    if (mounted && date != null) setState(() => _reportAuthorizedAt = date);
  }

  Future<void> _attachExternalReport() => _run(() async {
    final order = _selected?['order'] as Map?;
    if (order == null || order['status'] != 'registered') {
      throw const AuthFailure('Selecciona una orden nueva para adjuntar el PDF.');
    }
    final file = _reportFile;
    if (file == null || _reportAuthorizedAt == null ||
        !_confirmExternal || !_confirmPatient) {
      throw const AuthFailure('Selecciona el PDF, la fecha y confirma sus verificaciones.');
    }
    if (_selectedBranch == null ||
        _reportProfessional.text.trim().length < 3 ||
        _reportPatientIdentifier.text.trim().isEmpty ||
        _reportReference.text.trim().length < 3) {
      throw const AuthFailure('Selecciona sucursal e indica profesional, identificador del PDF y referencia.');
    }
    final bytes = await file.readAsBytes();
    await widget.api.silUploadReport(
      orderId: order['id'] as String,
      fileName: file.name,
      branchCode: _selectedBranch!,
      authorizedProfessionalName: _reportProfessional.text.trim(),
      patientIdentifierFromPdf: _reportPatientIdentifier.text.trim().toUpperCase(),
      authorizationReference: _reportReference.text.trim(),
      authorizedAt: _reportAuthorizedAt!,
      bytes: bytes,
    );
    _reportFile = null;
    await _openOrder(order['id'] as String);
    await _refreshAll();
    if (mounted) {
      setState(() => _message =
          'Informe incorporado. Comprueba la asociación antes de publicarlo.');
    }
  });

  Future<void> _publishExternalReport() async {
    final order = _selected?['order'] as Map?;
    if (order == null || order['status'] != 'report_attached' || _busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar publicación al paciente'),
        content: const Text(
          'Confirma que comprobaste la autorización externa del PDF y '
          'su correspondencia con el paciente. La publicación no equivale '
          'a validar resultados clínicos dentro de Vitalia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Publicar informe')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      await widget.api.silRequest(
        '/orders/${order['id']}/report/publish', body: {});
      await _openOrder(order['id'] as String);
      await _refreshAll();
      if (mounted) {
        setState(() => _message =
            'Informe publicado en el portal de ese paciente. '
            'Aún no se envían notificaciones externas.');
      }
    });
  }

  Future<void> _loadDemoPatient({String? email}) => _run(() async {
    final address = (email ?? _patientLookup.text).trim().toLowerCase();
    if (!address.endsWith('@example.invalid')) {
      throw const AuthFailure('Solo se permiten cuentas ficticias @example.invalid.');
    }
    final response = await widget.api.silRequest(
      '/patients/profile?email=${Uri.encodeQueryComponent(address)}',
    );
    final patient = Map<String, dynamic>.from(response['patient'] as Map);
    if (!mounted) return;
    setState(() {
      _patientLookup.text = address;
      _patientDemoLoaded = patient;
      _patientDemoGiven.text = patient['givenNames'] as String? ?? '';
      _patientDemoFamily.text = patient['familyNames'] as String? ?? '';
      _patientDemoBirth.text = patient['birthDate'] as String? ?? '';
      _patientDemoPhone.text = patient['contactPhoneDemo'] as String? ?? '';
      _patientDemoSex = patient['sexForReference'] as String? ?? 'not_specified';
      _syntheticPatientConfirmed = false;
      _mobilePatientDetail = true;
    });
  });

  void _prepareRequestForPatient(String email) {
    if (_busy) return;
    setState(() {
      // El cambio de paciente invalida el PDF, la prelectura y las
      // confirmaciones: nunca reutilizar comprobaciones entre pacientes.
      _requestPatientEmail.text = email;
      _requestPdf = null;
      _requestPreview = null;
      _requestBranchCode = null;
      _requestDate = null;
      _requestExamCodes.clear();
      _requestDocumentReference.clear();
      _requestPrescriberName.clear();
      _requestHumanConfirmed = false;
      _section = _OperatorSection.request;
      _error = null;
      _message = 'Paciente de prueba seleccionado. Adjunta su solicitud PDF y coteja la identidad.';
    });
  }

  void _openPatientOrders(String email) {
    if (_busy) return;
    _searchController.text = email;
    setState(() {
      _section = _OperatorSection.orders;
      _filterStatus = null;
      _page = 0;
      _error = null;
      _message = null;
    });
    _refreshOrders();
  }

  Future<void> _createNewDemoPatient() async {
    if (_busy) return;
    final response=await showDialog<Map<String,dynamic>>(
      context:context,
      builder:(_)=>NuevoPacienteSilDialog(api:widget.api),
    );
    if(!mounted||response==null)return;
    final patient=Map<String,dynamic>.from(response['patient'] as Map);
    _directoryKey.currentState?.refresh();
    await _loadDemoPatient(email:patient['email'] as String);
    if(mounted)setState(() => _message =
      'Ficha ficticia creada. Corrobora identidad y correo antes de activar el acceso.');
  }

  Widget _patientDirectory() => DirectorioPacientesSil(
    key: _directoryKey,
    api: widget.api,
    onExpired: widget.onExpired,
    selectedEmail: _patientDemoLoaded?['email'] as String?,
    onOpenProfile: (email) => _loadDemoPatient(email: email),
    onPrepareRequest: _prepareRequestForPatient,
    onViewOrders: _openPatientOrders,
    onCreatePatient: _createNewDemoPatient,
  );


  Future<void> _saveDemoPatient() => _run(() async {
    if (_patientDemoLoaded == null || !_syntheticPatientConfirmed ||
        !(_patientFormKey.currentState?.validate() ?? false)) {
      throw const AuthFailure('Consulta el paciente y confirma que todos los datos son ficticios.');
    }
    final email = _patientDemoLoaded!['email'] as String;
    final result = await widget.api.silRequest('/patients/profile', body: {
      'email': email,
      'givenNames': _patientDemoGiven.text.trim(),
      'familyNames': _patientDemoFamily.text.trim(),
      'birthDate': _patientDemoBirth.text.trim(),
      'sexForReference': _patientDemoSex,
      if (_patientDemoPhone.text.trim().isNotEmpty)
        'contactPhoneDemo': _patientDemoPhone.text.trim(),
      'syntheticConfirmed': true,
    });
    if (!mounted) return;
    setState(() {
      _patientDemoLoaded = Map<String, dynamic>.from(result['patient'] as Map);
      _syntheticPatientConfirmed = false;
      _message = 'Ficha DEMO guardada. Coteja su identidad con el PDF antes de crear una solicitud.';
    });
    _directoryKey.currentState?.refresh();
  });

  void _clearAiSuggestedFields() {
    for(final entry in _aiPrefilledValues.entries) {
      final controller=_manualControllers[entry.key];
      if(controller!=null && controller.text==entry.value)controller.clear();
    }
    _aiPrefilledValues.clear();
  }

  void _discardResultsPdf() {
    if(_busy)return;
    setState((){
      _clearAiSuggestedFields();
      _resultsPdf=null;
      _resultsPreviewToken=null;
      _resultsPreviewStatus=null;
      _resultsPreviewWarnings=[];
      _resultsRowWarnings.clear();
      _resultsReviewed=false;
    });
  }

  Future<void> _selectResultsPdf() async {
    try {
      final file=await openFile(acceptedTypeGroups:const [
        XTypeGroup(label:'Informe PDF ficticio',extensions:['pdf'],
          mimeTypes:['application/pdf']),
      ]);
      if(file==null||!mounted)return;
      final length=await file.length();
      if(!mounted)return;
      if(length<8||length>2*1024*1024) {
        setState(()=>_error='Selecciona un PDF ficticio de hasta 2 MiB.');
        return;
      }
      setState((){
        _clearAiSuggestedFields();
        _resultsPdf=file;
        _resultsPreviewToken=null;
        _resultsPreviewStatus=null;
        _resultsPreviewWarnings=[];
        _resultsRowWarnings.clear();
        _resultsReviewed=false;
        _error=null;
      });
    } catch (_) {
      if(mounted)setState(()=>_error='No se pudo seleccionar el PDF.');
    }
  }

  Future<void> _previewResultsPdf() => _run(() async {
    final order=_selected?['order'] as Map?;
    if(order==null||order['status']!='sampled') {
      throw const AuthFailure('Primero registra la recepción de muestras.');
    }
    final file=_resultsPdf;
    if(file==null)throw const AuthFailure('Selecciona el PDF ficticio.');
    final response=await widget.api.silPreviewResultsFile(
      orderId:order['id'] as String,
      bytes:await file.readAsBytes(),
    );
    if(!mounted || (_selected?['order'] as Map?)?['id']!=order['id'])return;
    final preview=Map<String,dynamic>.from(response['preview'] as Map);
    final token=preview['previewToken'] as String?;
    final warnings=<String,String>{};
    _clearAiSuggestedFields();
    var filled=0;
    for(final raw in (preview['items'] as List? ?? [])){
      final item=raw as Map;
      final key="${item['examCode']}::${item['analyte']}";
      final controller=_manualControllers[key];
      if(controller==null)continue;
      final warning=item['warning'] as String?;
      if(warning!=null)warnings[key]=warning;
      final value=item['suggestedValue'];
      if(value is num && controller.text.trim().isEmpty){
        controller.text=value.toString();
        _aiPrefilledValues[key]=controller.text;
        filled++;
      }
    }
    setState((){
      _resultsPreviewToken=token;
      _resultsPreviewStatus=preview['state'] as String?;
      _resultsPreviewWarnings=(preview['warnings'] as List? ?? [])
          .map((x)=>x.toString()).toList();
      _resultsRowWarnings..clear()..addAll(warnings);
      _resultsReviewed=false;
      _message='Extracción revisable: $filled valores precargados. '
          'Comprueba el PDF y corrige los campos faltantes antes de registrar.';
    });
  });

  Future<void> _recordManual() => _run(() async {
    final order = _selected?['order'] as Map?;
    if (order == null || !['sampled', 'review_rejected'].contains(order['status'])) {
      throw const AuthFailure('La orden no está habilitada para ingresar o corregir resultados.');
    }
    if(_resultsPreviewStatus=='identity_mismatch') {
      throw const AuthFailure(
        'No se puede usar un PDF de otro paciente. Descarta el archivo '
        'y continúa con un registro manual desde una fuente correcta.');
    }
    if(_resultsPreviewToken!=null && !_resultsReviewed) {
      throw const AuthFailure(
        'Confirma que revisaste cada valor con el PDF original.');
    }
    final values = <Map<String, dynamic>>[];
    for (final entry in _manualControllers.entries) {
      final input = entry.value.text.trim().replaceAll(',', '.');
      final numeric = double.tryParse(input);
      if (numeric == null || !numeric.isFinite ||
          numeric < -1000000000 || numeric > 1000000000) {
        throw AuthFailure('Ingresa un valor numérico válido para ${entry.key.split('::').last}.');
      }
      final parts = entry.key.split('::');
      values.add({
        'examCode': parts.first,
        'analyte': parts.last,
        'numericValue': numeric,
      });
    }
    if (values.isEmpty) {
      throw const AuthFailure('Esta orden no tiene parámetros definidos.');
    }
    final id = order['id'] as String;
    await widget.api.silRequest('/orders/$id/results', body: {
      'results': values,
      if (_resultsPreviewToken != null) 'previewToken': _resultsPreviewToken,
    });
    if (!mounted) return;
    _searchController.clear();
    setState(() {
      _selected = null;
      _page = 0;
      _filterStatus = _canReview ? 'results_recorded' : null;
      _section = _OperatorSection.orders;
      _message = 'Resultados registrados para ${_orderCode(order)}. '
          'Orden pendiente de revisión profesional.';
    });
    await _refreshAll();
  });

  Future<void> _reviewSelected({required bool approve}) async {
    final order = _selected?['order'] as Map?;
    if (order == null || !_canReview || _busy || order['status'] != 'results_recorded') return;
    final note = _reviewNoteController.text.trim();
    if (!approve && note.length < 10) {
      setState(() => _error = 'Indica un motivo de devolución de al menos 10 caracteres.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Aprobar revisión' : 'Devolver orden'),
        content: Text(approve
            ? 'La revisión interna quedará aprobada. La publicación del informe es un paso separado.'
            : 'La orden volverá a corrección. Los valores y el motivo quedarán registrados en auditoría.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run(() async {
      await widget.api.silRequest('/orders/${order['id']}/review', body: {
        'decision': approve ? 'approve' : 'return',
        'note': note,
      });
      if (!mounted) return;
      setState(() {
        _selected = null;
        _page = 0;
        _section = _OperatorSection.reviewQueue;
        _filterStatus = 'results_recorded';
        _searchController.clear();
        _message = approve
            ? 'Revisión interna aprobada para ${_orderCode(order)}.'
            : 'Orden ${_orderCode(order)} devuelta para corrección.';
      });
      await _refreshAll();
    });
  }

  void _search() {
    if (_busy) return;
    if (_searchController.text.trim().length > 100) {
      setState(() => _error = 'El término de búsqueda es demasiado largo.');
      return;
    }
    setState(() {
      _page = 0;
      _error = null;
    });
    _refreshOrders();
  }

  String _examName(String code) {
    for (final exam in _catalog) {
      if (exam['code'] == code) return exam['name'] as String;
    }
    return code.replaceAll('_', ' ');
  }

  String _orderCode(Map order) => '${order['orderNumber'] ?? 'Orden'}';

  String _orderAction(Object? status) => switch (status) {
    'registered' => 'Recibir muestra',
    'sampled' => 'Ingresar resultados',
    'review_rejected' => 'Corregir resultados',
    'results_recorded' when _canReview => 'Revisar resultados',
    'results_recorded' || 'review_approved' => 'Ver resultados',
    'report_attached' || 'report_published' => 'Ver informe',
    _ => 'Abrir orden',
  };

  String _statusLabel(String? status) => switch (status) {
    'registered' => 'Pendiente de muestra',
    'sampled' => 'Pendiente de resultados',
    'results_recorded' => 'Pendiente de revisión',
    'review_rejected' => 'Devuelta para corrección',
    'review_approved' => 'Revisión interna aprobada',
    'report_attached' => 'Informe externo recibido',
    'report_published' => 'Informe disponible al paciente',
    _ => 'Sin estado',
  };

  Widget _statusBadge(String? status) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, background, foreground) = switch (status) {
      'review_rejected' => (
          Icons.undo_outlined,
          colors.errorContainer,
          colors.onErrorContainer
        ),
      'registered' || 'sampled' || 'report_attached' => (
          Icons.pending_actions,
          colors.primaryContainer,
          colors.onPrimaryContainer
        ),
      'review_approved' || 'report_published' => (
          Icons.check_circle_outline,
          colors.tertiaryContainer,
          colors.onTertiaryContainer
        ),
      _ => (
          Icons.schedule,
          colors.secondaryContainer,
          colors.onSecondaryContainer
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: foreground),
        const SizedBox(width: 6),
        Flexible(
            child: Text(_statusLabel(status),
                style:
                    theme.textTheme.labelMedium?.copyWith(color: foreground))),
      ]),
    );
  }

  String _date(Object? input) {
    final date = DateTime.tryParse('$input')?.toLocal();
    if (date == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Widget _panel(String title, String subtitle, Widget child,
      {IconData? icon}) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            ]),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _queueCard(IconData icon, String title, int count, String status) {
    final theme = Theme.of(context);
    final (ink, tint) = switch (status) {
      'review_rejected' => (const Color(0xFFA14957), ColoresVitalia.errorSuave),
      'registered' => (const Color(0xFF876027), ColoresVitalia.advertenciaSuave),
      'sampled' => (const Color(0xFF315F80), ColoresVitalia.azulSuave),
      _ => (_teal, ColoresVitalia.verdeSuave),
    };
    return Material(
      color: count > 0 ? tint : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : () => _openQueue(status),
        hoverColor: ink.withValues(alpha: .08),
        focusColor: ink.withValues(alpha: .13),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: count > 0 ? Colors.white.withValues(alpha: 0.75) : tint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 20, color: ink),
              ),
              const Spacer(),
              Icon(Icons.arrow_outward, size: 18, color: ink),
            ]),
            const SizedBox(height: 10),
            Text('$count',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: _navy,
                  fontWeight: FontWeight.w700,
                )),
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(color: _navy)),
          ]),
        ),
      ),
    );
  }

  Widget _orderButton(Map<String, dynamic> order) => TextButton(
        onPressed:
            _busy ? null : () => _run(() => _openOrder(order['id'] as String)),
        child: Text(_orderAction(order['status'])),
      );

  String _orderExams(Map<String, dynamic> order) =>
      (order['examCodes'] as List? ?? [])
          .map((code) => _examName('$code'))
          .join(', ');

  Widget _orderList({bool recent = false}) {
    final rows = recent ? _recentOrders : _orders;
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No hay órdenes en esta vista.'),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 920) {
        final theme = Theme.of(context);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final order in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(_orderCode(order),
                                      style: theme.textTheme.titleMedium),
                                  _statusBadge(order['status'] as String?),
                                ]),
                            const SizedBox(height: 6),
                            Text('${order['patientEmail'] ?? '—'}'),
                            Text(_orderExams(order),
                                style: theme.textTheme.bodySmall),
                            Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _orderButton(order),
                                  Text(_date(order['createdAt']),
                                      style: theme.textTheme.bodySmall),
                                ]),
                          ]),
                    ),
                  ),
                ),
            ]);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowColor: const WidgetStatePropertyAll(Color(0xFFF0F5FA)),
          columns: const [
            DataColumn(label: Text('N.º de orden')),
            DataColumn(label: Text('Acción')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Paciente')),
            DataColumn(label: Text('Exámenes')),
            DataColumn(label: Text('Fecha')),
          ],
          rows: rows
              .map((order) => DataRow(cells: [
                    DataCell(Text(_orderCode(order))),
                    DataCell(_orderButton(order)),
                    DataCell(_statusBadge(order['status'] as String?)),
                    DataCell(Text('${order['patientEmail'] ?? '—'}')),
                    DataCell(SizedBox(
                      width: 250,
                      child: Text(_orderExams(order),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(_date(order['createdAt']))),
                  ]))
              .toList(),
        ),
      );
    });
  }

  Widget _dashboardHeader() {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E6EA)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ESTACIÓN DEL OPERADOR',
          style: text.labelMedium?.copyWith(
            color: ColoresVitalia.verde,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          )),
        const SizedBox(height: 7),
        Text('Panel del laboratorio',
          style: text.headlineMedium?.copyWith(
            color: _navy, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Recepción, órdenes y revisión interna en un mismo espacio de trabajo.',
          style: text.bodyMedium?.copyWith(
            color: ColoresVitalia.textoSecundario)),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _goTo(_OperatorSection.request),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Recibir solicitud de exámenes'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openQueue('results_recorded'),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(_canReview
                ? 'Por revisar · $_pendingReviews'
                : 'Pendientes de revisión · $_pendingReviews'),
          ),
        ]),
      ]),
    );
  }

  /// Una ruta visual que hace reconocible la secuencia de trabajo.
  /// Ningún estado posterior se habilita automáticamente por extracción IA.
  Widget _workflowMap(Map<String,dynamic> summary){
    int amount(String key)=>(summary[key] as num?)?.toInt()??0;
    final stages=<({IconData icon,String title,String sub,String count,String? status})>[
      (icon:Icons.note_add_outlined,title:'Solicitud',
        sub:'Cotejar identidad y documento',count:'Iniciar',status:null),
      (icon:Icons.inventory_2_outlined,title:'Muestras',
        sub:'Recepción declarada de tubos',
        count:'${amount('pendingSample')}',status:'registered'),
      (icon:Icons.biotech_outlined,title:'Resultados',
        sub:'Ingreso o prelectura asistida',
        count:'${amount('pendingResults')}',status:'sampled'),
      (icon:Icons.fact_check_outlined,title:'Revisión',
        sub:'Decisión del operador autorizado',
        count:'${amount('pendingReview')}',status:'results_recorded'),
      (icon:Icons.file_present_outlined,title:'Publicación',
        sub:'Informe externo autorizado',
        count:'${amount('attached')}',status:'report_attached'),
    ];
    return _panel(
      'Ruta de trabajo postanalítica',
      'Cada etapa tiene requisitos explícitos. La extracción asistida no sustituye la revisión humana.',
      LayoutBuilder(builder:(context,constraints){
        final columns=constraints.maxWidth>=1080?5:
          constraints.maxWidth>=670?3:
          constraints.maxWidth>=360?2:1;
        final width=(constraints.maxWidth-(columns-1)*9)/columns;
        return Wrap(spacing:9,runSpacing:9,children:[
          for(final (index,stage) in stages.indexed)
            SizedBox(width:width,child:Material(
              color: index==2?ColoresVitalia.azulSuave:
                ColoresVitalia.fondoAzul,
              shape:RoundedRectangleBorder(
                borderRadius:BorderRadius.circular(13),
                side:const BorderSide(color:ColoresVitalia.bordeTenue)),
              clipBehavior:Clip.antiAlias,
              child:InkWell(
                onTap:_busy?null:()=>stage.status==null
                  ?_goTo(_OperatorSection.request)
                  :_openQueue(stage.status),
                child:Padding(padding:const EdgeInsets.all(13),
                  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Row(children:[
                      CircleAvatar(radius:16,
                        backgroundColor:Colors.white,
                        child:Icon(stage.icon,color:ColoresVitalia.azul,size:18)),
                      const Spacer(),
                      Text('${index+1}/5',
                        style:const TextStyle(
                          color:ColoresVitalia.textoSecundario,fontSize:10)),
                    ]),
                    const SizedBox(height:10),
                    Text(stage.title,style:const TextStyle(
                      color:ColoresVitalia.texto,fontWeight:FontWeight.w700)),
                    const SizedBox(height:3),
                    Text(stage.sub,maxLines:2,overflow:TextOverflow.ellipsis,
                      style:const TextStyle(
                        color:ColoresVitalia.textoSecundario,fontSize:11)),
                    const SizedBox(height:10),
                    Row(children:[
                      Text(stage.count,style:const TextStyle(
                        fontWeight:FontWeight.w700,color:ColoresVitalia.azul,
                        fontSize:13)),
                      const Spacer(),
                      const Icon(Icons.arrow_forward,
                        color:ColoresVitalia.azul,size:17),
                    ]),
                  ]),
                ),
              ),
            )),
        ]);
      }),
      icon:Icons.account_tree_outlined,
    );
  }

  Widget _dashboard() {
    final summary = _summary;
    if (summary == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _dashboardHeader(),
        const SizedBox(height: 16),
        Text(_loading
            ? 'Cargando indicadores del laboratorio…'
            : 'Actualiza los datos para consultar la bandeja del laboratorio.'),
      ]);
    }
    int count(String key) => (summary[key] as num?)?.toInt() ?? 0;
    final queues = [
      (
        Icons.undo_outlined,
        'Devueltas para corregir',
        'returned',
        'review_rejected'
      ),
      (
        Icons.inventory_2_outlined,
        'Pendientes de muestra',
        'pendingSample',
        'registered'
      ),
      (
        Icons.science_outlined,
        'Pendientes de resultados',
        'pendingResults',
        'sampled'
      ),
      (
        Icons.picture_as_pdf_outlined,
        'Informes por publicar',
        'attached',
        'report_attached'
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dashboardHeader(),
        const SizedBox(height: 16),
        _workflowMap(summary),
        const SizedBox(height: 16),
        _panel(
          'Trabajo del operador',
          'Abre una bandeja para ver las órdenes que requieren esa acción.',
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 860
                ? 4
                : constraints.maxWidth >= 300
                    ? 2
                    : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final (icon, title, key, status) in queues)
                SizedBox(
                    width: width,
                    child: _queueCard(icon, title, count(key), status)),
            ]);
          }),
          icon: Icons.pending_actions,
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          ActionChip(
            label: Text('Informes disponibles · ${count('published')}'),
            avatar: const Icon(Icons.check_circle_outline, size: 17),
            onPressed: _busy ? null : () => _openQueue('report_published'),
          ),
          ActionChip(
            label: Text('Total de órdenes · ${count('total')}'),
            avatar: const Icon(Icons.assignment_outlined, size: 17),
            onPressed: _busy ? null : () => _openQueue(null),
          ),
        ]),
        const SizedBox(height: 16),
        _panel(
          'Actividad reciente',
          'Últimas órdenes ingresadas al laboratorio.',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _orderList(recent: true),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _openQueue(null),
                icon: const Icon(Icons.arrow_forward_outlined),
                label: const Text('Ver todas las órdenes'),
              ),
            ),
          ]),
          icon: Icons.history,
        ),
      ],
    );
  }

  Widget _ordersView() {
    final reviewing = _section == _OperatorSection.reviewQueue;
    return _panel(
    reviewing ? 'Bandeja de revisión de resultados' : 'Buscar y gestionar órdenes',
    reviewing
        ? 'Órdenes pendientes de cotejo interno. La revisión no publica informes al paciente.'
        : 'Busca por folio o correo del paciente y filtra por estado.',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (reviewing) ...[
        const Text('Selecciona «Revisar resultados» para cotejar los valores con el documento original y registrar una aprobación o devolución. La publicación es independiente.'),
        const SizedBox(height: 12),
      ],
      if (!reviewing) ...[
      const Text('Accesos: recibe una solicitud médica PDF para vincularla con una orden o crea una orden manual para un paciente registrado.'),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _goTo(_OperatorSection.request),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Recibir solicitud de exámenes'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _goTo(_OperatorSection.manualOrder),
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('Crear orden manual'),
        ),
      ]),
      const SizedBox(height: 13),
      Wrap(
        spacing: 8,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final filter in <(String, String?)>[
            ('Todas', null),
            ('Por recibir muestra', 'registered'),
            ('Por ingresar resultados', 'sampled'),
            ('Devueltas', 'review_rejected'),
            ('Informes publicados', 'report_published'),
          ])
            FilterChip(
              label: Text(filter.$1),
              selected: _filterStatus == filter.$2,
              onSelected: _busy ? null : (_) => _openQueue(filter.$2),
            ),
        ],
      ),
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 340,
          child: TextField(
            controller: _searchController,
            enabled: !_busy,
            maxLength: 100,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Buscar orden o correo',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        if (reviewing)
          const Chip(
            avatar: Icon(Icons.fact_check_outlined, size: 17),
            label: Text('Pendientes de revisión'),
          )
        else SizedBox(width: 290, child: DropdownButton<String>(
          isExpanded: true,
          value: _filterStatus ?? '',
          items: const [
            DropdownMenuItem(value: '', child: Text('Todos los estados')),
            DropdownMenuItem(value: 'registered', child: Text('Pendiente de muestra')),
            DropdownMenuItem(value: 'sampled', child: Text('Pendiente de resultados')),
            DropdownMenuItem(value: 'results_recorded', child: Text('Pendiente de revisión')),
            DropdownMenuItem(value: 'review_rejected', child: Text('Devueltas para corrección')),
            DropdownMenuItem(value: 'review_approved', child: Text('Revisión aprobada')),
            DropdownMenuItem(value: 'report_attached', child: Text('Informe externo recibido')),
            DropdownMenuItem(value: 'report_published', child: Text('Informe publicado')),
          ],
          onChanged: _busy ? null : (value) {
            setState(() {
              _filterStatus = value == '' ? null : value;
              _page = 0;
            });
            _refreshOrders();
          },
        )),
        FilledButton.icon(
          onPressed: _busy ? null : _search,
          icon: const Icon(Icons.search),
          label: const Text('Buscar'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => _openQueue(reviewing ? 'results_recorded' : null),
          icon: const Icon(Icons.clear),
          label: Text(reviewing ? 'Limpiar búsqueda' : 'Limpiar filtros'),
        ),
      ]),
      const SizedBox(height: 12),
      if (_ordersLoading)
        const LinearProgressIndicator(semanticsLabel: 'Actualizando órdenes')
      else ...[
        Text(reviewing
            ? '$_total órdenes pendientes de revisión'
            : '$_total órdenes encontradas'),
        const SizedBox(height: 10),
        _orderList(),
      ],
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('Página ${_page + 1}'),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: _busy || _ordersLoading || _page == 0
              ? null
              : () {
                  setState(() => _page--);
                  _refreshOrders();
                },
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: _busy || _ordersLoading || (_page + 1) * _pageSize >= _total
              ? null
              : () {
                  setState(() => _page++);
                  _refreshOrders();
                },
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
    ]),
    icon: reviewing ? Icons.fact_check_outlined : Icons.assignment_outlined,
  );
  }

  Widget _prerequisiteHint(IconData icon, String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: ColoresVitalia.fondoAzul,
      border: Border.all(color: ColoresVitalia.bordeTenue),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: ColoresVitalia.azul),
      const SizedBox(width: 10),
      Expanded(child: Text(message,
        style: const TextStyle(fontSize: 12, color: ColoresVitalia.textoSecundario))),
    ]),
  );

  Widget _medicalRequestView() => _panel(
    'Recepción de solicitud de exámenes',
    'Vincula un documento médico ficticio con un paciente registrado, sin crear la orden hasta comprobar su identidad.',
    Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final step = _requestPreview == null ? 0
            : _requestPreview!['previewToken'] == null ? 1 : 2;
        final steps = <(IconData, String, String)>[
          (Icons.person_search_outlined, 'Identificar', 'Buscar la cuenta y cargar el PDF'),
          (Icons.verified_user_outlined, 'Cotejar identidad', 'Comparar ficha y solicitud original'),
          (Icons.fact_check_outlined, 'Completar orden', 'Verificar prestaciones y confirmar'),
        ];
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i=0; i<steps.length; i++)
            SizedBox(
              width: wide ? (constraints.maxWidth-20)/3 : constraints.maxWidth,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: i==step ? const Color(0xFFE5F5F3) : _workspace,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: i==step ? _teal : _line),
                ),
                child: Row(children: [
                  Icon(steps[i].$1, color: i==step ? _teal : _navy),
                  const SizedBox(width: 9),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i+1}. ${steps[i].$2}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(steps[i].$3,
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )),
                ]),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 20),
      Text('1. Identificar paciente y cargar solicitud',
        style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      TextField(
        controller:_requestPatientEmail,
        enabled:!_busy && _requestPreview==null,
        decoration:const InputDecoration(
          labelText:'Correo de la cuenta ficticia del paciente',
          border:OutlineInputBorder(),
          helperText:'El correo localiza la ficha; no confirma por sí solo la identidad.',
        ),
      ),
      const SizedBox(height:12),
      Wrap(spacing:10,runSpacing:8,children:[
        OutlinedButton.icon(
          onPressed:_busy?null:_selectMedicalRequestPdf,
          icon:const Icon(Icons.attach_file),
          label:Text(_requestPdf?.name??'Seleccionar solicitud PDF'),
        ),
        FilledButton.tonalIcon(
          onPressed:_busy||_requestPdf==null?null:_previewMedicalRequest,
          icon:const Icon(Icons.document_scanner_outlined),
          label:const Text('Revisar texto de la solicitud'),
        ),
      ]),
      const SizedBox(height:10),
      if (_requestPdf == null)
        _prerequisiteHint(Icons.attach_file_outlined,
          'Para habilitar la revisión, adjunta primero una solicitud médica PDF ficticia.')
      else if (_requestPreview == null)
        _prerequisiteHint(Icons.fact_check_outlined,
          'Archivo seleccionado. El siguiente paso es cotejar su texto y la identidad DEMO.')
      else if (_requestPreview!['previewToken'] == null)
        _prerequisiteHint(Icons.info_outline,
          'No puedes crear una orden hasta corregir la discrepancia en la solicitud original.')
      else
        _prerequisiteHint(Icons.check_circle_outline,
          'Identidad cotejada. Revisa sucursal, fecha, profesional y prestaciones antes de confirmar.'),
      const SizedBox(height:10),
      const Text('Formato admitido: PDF ficticio con texto seleccionable, máximo 2 MiB. '
        'Se cotejan identificador DEMO, nombres, apellidos y fecha de nacimiento. '
        'La detección de prestaciones es preliminar: el operador debe revisar el original. '
        'No se validan firmas ni habilitación profesional. Los PDF escaneados sin texto no están soportados.'),
      if(_requestPreview!=null)...[
        const Divider(height:28),
        Text('2. Comprobación de identidad',
          style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:8),
        Container(
          width:double.infinity,
          padding:const EdgeInsets.all(14),
          decoration:BoxDecoration(
            color:_requestPreview!['previewToken']!=null
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.errorContainer,
            borderRadius:BorderRadius.circular(10),
          ),
          child:Row(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Icon(
                _requestPreview!['previewToken']!=null
                  ? Icons.verified_outlined : Icons.gpp_bad_outlined,
                color:_requestPreview!['previewToken']!=null
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width:10),
              Expanded(child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Text(_requestPreview!['previewToken']!=null
                      ? 'Identidad cotejada; falta revisión del operador'
                      : 'IDENTIDAD NO COMPROBADA — ORDEN BLOQUEADA',
                    style:Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight:FontWeight.bold,
                      color:_requestPreview!['previewToken']!=null
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height:5),
                  Text(_requestPreview!['previewToken']!=null
                    ? 'Comprueba el documento original y las prestaciones antes '
                      'de registrar la orden.'
                    : 'Campos por revisar: '
                      '${_requestIdentityFailures(_requestPreview!).join(', ')}. '
                      'La solicitud permanece sin vincular hasta corregir '
                      'la discrepancia en el documento de origen.',
                    style:TextStyle(color:_requestPreview!['previewToken']!=null
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ],
              )),
            ],
          ),
        ),
        const SizedBox(height:12),
        Text('Ficha consultada: ${(_requestPreview!['patient'] as Map)['givenNames']} '
          '${(_requestPreview!['patient'] as Map)['familyNames']} '
          '(${(_requestPreview!['patient'] as Map)['identifier']})'),
        const SizedBox(height:6),
        for(final check in <(String,bool)>[
          ('Identificador ficticio',(_requestPreview!['identity'] as Map)['identifierMatches']==true),
          ('Nombres',(_requestPreview!['identity'] as Map)['givenNamesMatch']==true),
          ('Apellidos',(_requestPreview!['identity'] as Map)['familyNamesMatch']==true),
          ('Fecha de nacimiento',(_requestPreview!['identity'] as Map)['birthDateMatches']==true),
        ])
          Padding(padding:const EdgeInsets.only(bottom:5),
            child:Row(children:[
              Icon(check.$2?Icons.check_circle:Icons.error_outline,
                color:check.$2?Colors.green:Theme.of(context).colorScheme.error,
                size:20),
              const SizedBox(width:8),
              Expanded(child:Text(check.$1)),
              Text(check.$2?'Coincide':'REVISAR',
                style:TextStyle(
                  color:check.$2?Theme.of(context).colorScheme.primary
                    :Theme.of(context).colorScheme.error,
                  fontWeight:check.$2?FontWeight.normal:FontWeight.bold,
                )),
            ])),
        for(final warning in (_requestPreview!['warnings'] as List? ?? []))
          Padding(padding:const EdgeInsets.symmetric(vertical:3),
            child:Text(warning.toString(),style:TextStyle(
              color:Theme.of(context).colorScheme.error))),
        if(_requestPreview!['previewToken']!=null)...[
          const Divider(height:30),
          Text('3. Revisar solicitud y prestaciones',
            style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(
            initialValue:_requestBranchCode,
            isExpanded:true,
            decoration:const InputDecoration(
              labelText:'Sucursal que recibe la solicitud',
              border:OutlineInputBorder()),
            items:[
              for(final branch in _branches)
                DropdownMenuItem<String>(
                  value:branch['code'] as String,
                  child:Text('${branch['laboratoryName']} · ${branch['branchName']}',
                    overflow:TextOverflow.ellipsis),
                ),
            ],
            onChanged:_busy?null:(value)=>
              setState(()=>_requestBranchCode=value),
          ),
          const SizedBox(height:12),
          TextField(
            controller:_requestPrescriberName,
            maxLength:120,
            decoration:const InputDecoration(
              labelText:'Profesional solicitante según documento',
              helperText:'Transcribir del original. No comprueba matrícula ni firma.',
              border:OutlineInputBorder()),
          ),
          const SizedBox(height:12),
          TextField(
            controller:_requestDocumentReference,
            maxLength:100,
            decoration:const InputDecoration(
              labelText:'Número o referencia de solicitud',
              helperText:'Comprueba la referencia con el PDF original.',
              border:OutlineInputBorder()),
          ),
          const SizedBox(height:12),
          OutlinedButton.icon(
            onPressed:_busy?null:() async {
              final date=await showDatePicker(
                context:context,firstDate:DateTime(2000),
                lastDate:DateTime.now(),
                initialDate:_requestDate??DateTime.now(),
                helpText:'Fecha indicada en la solicitud médica',
              );
              if(mounted&&date!=null)setState(()=>_requestDate=date);
            },
            icon:const Icon(Icons.event),
            label:Text(_requestDate==null?'Elegir fecha de solicitud':
              '${_requestDate!.day.toString().padLeft(2,'0')}/'
              '${_requestDate!.month.toString().padLeft(2,'0')}/'
              '${_requestDate!.year}'),
          ),
          const SizedBox(height:14),
          Text('Prestaciones solicitadas (revisar en el PDF)',
            style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:8),
          Wrap(spacing:8,runSpacing:7,children:[
            for(final exam in _catalog)
              FilterChip(
                label:Text(exam['name'] as String),
                selected:_requestExamCodes.contains(exam['code']),
                onSelected:_busy?null:(value)=>setState((){
                  final code=exam['code'] as String;
                  if (value && _requestExamCodes.length < 6) {
                    _requestExamCodes.add(code);
                  }
                  if (!value) {
                    _requestExamCodes.remove(code);
                  }
                  _requestHumanConfirmed=false;
                }),
              ),
          ]),
          const SizedBox(height:12),
          CheckboxListTile(
            value:_requestHumanConfirmed,
            onChanged:_busy?null:(value)=>
              setState(()=>_requestHumanConfirmed=value??false),
            controlAffinity:ListTileControlAffinity.leading,
            title:const Text(
              'Confirmo que cotejé el PDF original, los datos de identidad, '
              'el profesional solicitante, la fecha y las prestaciones '
              'seleccionadas. Todos los datos son ficticios.'),
          ),
          const SizedBox(height:12),
          Align(alignment:Alignment.centerLeft,
            child:FilledButton.icon(
              onPressed:_busy||!_requestHumanConfirmed||
                  _requestExamCodes.isEmpty?null:_registerFromMedicalRequest,
              icon:const Icon(Icons.assignment_turned_in_outlined),
              label:const Text('Crear orden interna desde la solicitud'),
            )),
        ] else
          const Text('No es posible crear una orden mientras existan discrepancias '
            'de identidad. Revisa la ficha y el documento original.'),
      ],
    ]),
    icon:Icons.assignment_outlined,
  );

  Widget _newOrderView() => _panel(
    'Nueva orden de exámenes',
    'Selecciona un paciente existente y las prestaciones que se realizarán.',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _patientController,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: 'Correo del paciente',
          hintText: 'paciente.sil@example.invalid',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_search_outlined),
        ),
      ),
      const SizedBox(height: 20),
      Text('Catálogo de exámenes', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      if (_catalog.isEmpty)
        const Text('Cargando catálogo de exámenes…')
      else
        Wrap(
          spacing: 9,
          runSpacing: 6,
          children: _catalog.map((exam) {
            final code = exam['code'] as String;
            return FilterChip(
              label: Text(exam['name'] as String),
              selected: _selectedExams.contains(code),
              onSelected: _busy
                  ? null
                  : (selected) => setState(() {
                      if (selected) {
                        _selectedExams.add(code);
                      } else {
                        _selectedExams.remove(code);
                      }
                    }),
            );
          }).toList(),
        ),
      const SizedBox(height: 20),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy || _catalog.isEmpty ? null : _createOrder,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Registrar orden'),
        ),
      ),
    ]),
    icon: Icons.note_add_outlined,
  );

  Widget _withoutOrder(String title) => _panel(
    title,
    'Selecciona una orden para continuar.',
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : () => _goTo(_OperatorSection.orders),
        icon: const Icon(Icons.assignment_outlined),
        label: const Text('Consultar órdenes'),
      ),
    ),
  );

  Widget _orderNavigation(Map order) {
    final status = order['status'];
    final steps = [
      (_OperatorSection.samples, 'Muestras'),
      (_OperatorSection.results, 'Resultados'),
      if (status == 'registered' || status == 'report_attached' ||
          status == 'report_published')
        (_OperatorSection.report, 'Informe externo'),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _goTo(_OperatorSection.orders),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Volver a órdenes'),
      ),
      for (final (section, label) in steps)
        ChoiceChip(
          label: Text(label),
          selected: _section == section,
          onSelected: _busy ? null : (_) => _goTo(section),
        ),
    ]);
  }

  Widget _orderHeader(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    final status = order['status'] as String?;
    final nextStep = switch (status) {
      'registered' when _section == _OperatorSection.report =>
        'Incorpora el PDF autorizado por el laboratorio de origen.',
      'registered' => 'Registra la recepción de los tubos requeridos.',
      'sampled' => 'Ingresa los resultados de las prestaciones solicitadas.',
      'review_rejected' =>
        'Revisa la observación, corrige y reenvía los resultados.',
      'results_recorded' when _canReview => 'Coteja los resultados y registra tu decisión.',
      'results_recorded' => 'La orden está en la bandeja de revisión.',
      'review_approved' => 'La revisión interna está completa.',
      'report_attached' => 'Comprueba el PDF incorporado antes de publicarlo.',
      'report_published' =>
        'El PDF ya está disponible en el portal del paciente.',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Orden ${_orderCode(order)}',
                  style: theme.textTheme.titleLarge),
              _statusBadge(status),
            ]),
        if (nextStep != null) ...[
          const SizedBox(height: 8),
          Text(nextStep,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              )),
        ],
        const SizedBox(height: 6),
        Text('Paciente: ${order['patientEmail'] ?? '—'}'),
        if (_selected?['medicalRequest'] is Map) ...[
          Text('Solicitud recibida: '
              '${(_selected!['medicalRequest'] as Map)['documentReference']}'),
          Text('Procedencia: '
              '${(_selected!['medicalRequest'] as Map)['branchName']}'),
          Text('Profesional solicitante indicado: '
              '${(_selected!['medicalRequest'] as Map)['prescriberName']}'),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _downloadMedicalRequest,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Descargar solicitud original'),
              )),
        ],
        Text('Creación: ${_date(order['createdAt'])}'),
        const SizedBox(height: 8),
        Text(
            'Prestaciones: ${(_selected?['exams'] as List? ?? []).map((item) => (item as Map)['name']).join(', ')}'),
      ],
    );
  }

  String _auditAction(String code) => switch (code) {
    'order_created' => 'Orden registrada',
    'medical_request_received' => 'Solicitud médica ficticia recibida',
    'sample_received' => 'Muestra recibida',
    'results_simulated' => 'Resultados de prueba generados',
    'results_manual' => 'Resultados registrados por operador',
    'results_corrected' => 'Resultados corregidos y reenviados',
    'review_approved' => 'Revisión interna aprobada',
    'review_rejected' => 'Orden devuelta con observaciones',
    'external_report_attached' => 'PDF externo incorporado',
    'external_report_published' => 'PDF disponible al paciente',
    'external_report_downloaded' => 'Paciente descargó el PDF',
    _ => code,
  };

  Widget _auditTrail(Map<String, dynamic> data) {
    final audit = data['audit'] as List? ?? [];
    return _panel(
      'Historial de actividad',
      'Registro de acciones, fecha y cuenta responsable.',
      audit.isEmpty
          ? const Text('Sin eventos de auditoría para esta orden.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in audit)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(_auditAction((item as Map)['action'] as String)),
                    subtitle: Text(
                      '${item['actorEmail']} · ${_date(item['createdAt'])}'
                      '${(item['details'] as Map?)?['assistedImport'] == true
                          ? ' · Extracción IA revisada por operador' : ''}'
                      '${(item['details'] as Map?)?['note'] == null
                          ? '' : ' · ${(item['details'] as Map)['note']}'}',
                    ),
                  ),
              ],
            ),
      icon: Icons.history_outlined,
    );
  }

  String _tubeDescription(Map tube) {
    final cap = switch (tube['code']) {
      'edta' => 'lila',
      'serum' => 'rojo o dorado',
      'fluoride' => 'gris',
      _ => null,
    };
    return cap == null ? '${tube['label']}' : '${tube['label']} ($cap)';
  }

  Widget _samplesView() {
    final data = _selected;
    if (data == null) return _withoutOrder('Recepción de muestras');
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final status = order['status'] as String?;
    final samples = data['samples'] as List? ?? [];
    final required = data['requiredContainers'] as List? ?? [];
    final received = samples
        .map((entry) => (entry as Map)['containerCode'])
        .toSet();
    final pending = required
        .where((entry) => !received.contains((entry as Map)['code']))
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panel(
        'Recepción y seguimiento de muestras',
        'Cada orden debe contar con los tubos requeridos antes de registrar resultados.',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _orderHeader(order),
          const Divider(height: 30),
          Text('Tubos requeridos', style: Theme.of(context).textTheme.titleMedium),
          const Text('Colores orientativos para la demo. Coteja el tipo y la etiqueta del tubo recibido.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final container in required)
              Chip(
                avatar: Icon(
                  received.contains((container as Map)['code'])
                      ? Icons.check_circle_outline
                      : Icons.hourglass_empty,
                  size: 17,
                ),
                label: Text('${_tubeDescription(container)} · '
                    '${received.contains(container['code']) ? 'Recibido' : 'Pendiente'}'),
              ),
          ]),
          if (samples.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Recepciones registradas',
                style: Theme.of(context).textTheme.titleMedium),
            for (final entry in samples)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('${(entry as Map)['barcode']} · ${entry['containerLabel']}'),
                subtitle: Text('${_date(entry['registeredAt'])} · '
                    '${entry['receivedBy'] ?? 'Registro anterior'}'
                    '${entry['receiptNote'] == null ? '' : ' · ${entry['receiptNote']}'}'),
              ),
          ],
          if (status == 'registered' && pending.isNotEmpty) ...[
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _containerCode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tipo de tubo pendiente',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final container in pending)
                  DropdownMenuItem(
                    value: (container as Map)['code'] as String,
                    child: Text(_tubeDescription(container), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy ? null : (value) => setState(() => _containerCode = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _barcodeController,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código de etiqueta existente (opcional)',
                helperText: 'Si el tubo no tiene etiqueta, Vitalia asigna un código.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _receiptNoteController,
              maxLength: 300,
              maxLines: 2,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Observación de recepción (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _receiveSample,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Registrar recepción del tubo'),
              ),
            ),
          ],
          if (status == 'sampled') ...[
            const SizedBox(height: 18),
            const Text('Los tubos requeridos están registrados. Puedes ingresar '
                'los resultados manualmente o analizar un PDF con IA.'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _goTo(_OperatorSection.results),
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Ir a resultados'),
              ),
            ),
          ],
          if (['results_recorded','review_rejected','review_approved'].contains(status)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _goTo(_OperatorSection.results),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Ver resultados registrados'),
            ),
          ],
        ]),
        icon: Icons.science_outlined,
      ),
      const SizedBox(height: 14),
      _auditTrail(data),
    ]);
  }

  Widget _manualFields(Map<String, dynamic> data) {
    final selectedCodes = (data['exams'] as List? ?? [])
        .map((item) => (item as Map)['code']).toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Ingreso de resultados: PDF con IA o manual',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Modo asistido: carga un PDF ficticio. La IA propone valores, '
          'marca incidencias y deja los datos dudosos para corrección manual. '
          'No registra resultados sin tu confirmación.'),
      const SizedBox(height: 12),
      Wrap(spacing: 10,runSpacing: 8,children: [
        OutlinedButton.icon(
          onPressed:_busy?null:_selectResultsPdf,
          icon:const Icon(Icons.attach_file),
          label:Text(_resultsPdf?.name ?? 'Seleccionar PDF de resultados'),
        ),
        FilledButton.tonalIcon(
          onPressed:_busy||_resultsPdf==null?null:_previewResultsPdf,
          icon:const Icon(Icons.document_scanner_outlined),
          label:const Text('Analizar archivo con IA'),
        ),
        if(_resultsPdf!=null)
          TextButton.icon(
            onPressed:_busy?null:_discardResultsPdf,
            icon:const Icon(Icons.close),
            label:const Text('Descartar PDF / seguir manual'),
          ),
      ]),
      if(_resultsPreviewStatus!=null) ...[
        const SizedBox(height: 12),
        Text('Estado de extracción: ${_resultsPreviewStatus == 'ready'
          ? 'Propuesta completa, pendiente de revisión'
          : _resultsPreviewStatus == 'identity_mismatch'
          ? 'Identidad no coincide: NO usar el PDF'
          : 'Requiere corrección manual'}'),
        for(final warning in _resultsPreviewWarnings)
          Padding(
            padding:const EdgeInsets.only(top:4),
            child:Text(warning,
              style:TextStyle(color:Theme.of(context).colorScheme.error)),
          ),
      ],
      const Divider(height: 30),
      Text('Valores revisables',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      const Text('Ingresa todos los valores del catálogo. '
          'La unidad y la referencia se toman del sistema y no se editan.'),
      const SizedBox(height: 16),
      for (final exam in _catalog)
        if (selectedCodes.contains(exam['code'])) ...[
          Text(exam['name'] as String,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final analyte in (exam['analytes'] as List? ?? []))
              SizedBox(
                width: 245,
                child: TextField(
                  controller: _manualControllers[
                      '${exam['code']}::${(analyte as Map)['analyte']}'],
                  enabled: !_busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: '${analyte['analyte']}',
                    helperText: _resultsRowWarnings[
                      '${exam['code']}::${analyte['analyte']}'
                    ] ?? 'Unidad: ${analyte['unit']}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 18),
        ],
      if(_resultsPreviewToken!=null)
        CheckboxListTile(
          contentPadding:EdgeInsets.zero,
          controlAffinity:ListTileControlAffinity.leading,
          value:_resultsReviewed,
          onChanged:_busy?null:(value)=>
            setState(()=>_resultsReviewed=value??false),
          title:const Text('Revisé cada cifra con el PDF original '
            'y corregí manualmente los errores de extracción.'),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy || _manualControllers.isEmpty ? null : _recordManual,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Registrar resultados'),
        ),
      ),
    ]);
  }

  Widget _resultReadings(List<dynamic> results) {
    String source(Map row) => switch (row['entryMethod']) {
          'manual' => 'Manual',
          'simulated' => 'Prueba automática',
          _ => 'Registro anterior',
        };
    String reference(Map row) =>
        '${row['referenceMin'] ?? '—'} – ${row['referenceMax'] ?? '—'}';
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 860) {
        final text = Theme.of(context).textTheme;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in results.cast<Map>())
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _workspace,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_examName('${row['examCode'] ?? ''}'),
                            style: text.labelMedium),
                        const SizedBox(height: 4),
                        Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('${row['analyte']}', style: text.titleSmall),
                              Text('${row['numericValue']} ${row['unit']}',
                                  style: text.titleMedium?.copyWith(
                                      color: _teal,
                                      fontWeight: FontWeight.w700)),
                            ]),
                        const SizedBox(height: 4),
                        Text(
                            'Referencia de prueba ${reference(row)} · ${source(row)}',
                            style: text.bodySmall),
                      ]),
                ),
            ]);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Examen')),
            DataColumn(label: Text('Analito')),
            DataColumn(label: Text('Valor')),
            DataColumn(label: Text('Unidad')),
            DataColumn(label: Text('Origen')),
            DataColumn(label: Text('Referencia de prueba')),
          ],
          rows: results.map((item) {
            final row = item as Map;
            return DataRow(cells: [
              DataCell(Text(_examName('${row['examCode'] ?? ''}'))),
              DataCell(Text('${row['analyte']}')),
              DataCell(Text('${row['numericValue']}')),
              DataCell(Text('${row['unit']}')),
              DataCell(Text(source(row))),
              DataCell(Text(reference(row))),
            ]);
          }).toList(),
        ),
      );
    });
  }

  Widget _reviewPanel() => KeyedSubtree(
        key: _reviewPanelKey,
        child: _panel(
          'Revisión interna',
          'El operador autorizado coteja los valores con su documento de origen. Aprobar no equivale a publicar un informe.',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _reviewNoteController,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observación de revisión',
                helperText: 'Para devolver, escribe al menos 10 caracteres.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _reviewSelected(approve: true),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Aprobar revisión'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _reviewSelected(approve: false),
                icon: const Icon(Icons.undo),
                label: const Text('Devolver orden'),
              ),
            ]),
          ]),
          icon: Icons.fact_check_outlined,
        ),
      );

  Widget _resultsView() {
    final data = _selected;
    if (data == null) return _withoutOrder('Resultados');
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final status = order['status'] as String?;
    final results = data['results'] as List? ?? [];
    final canReview =
        _canReview && status == 'results_recorded' && results.isNotEmpty;

    return LayoutBuilder(builder: (context, constraints) {
      final wide = canReview && constraints.maxWidth >= 1020;
      final readings = _panel(
        'Resultados de la orden',
        'Registro y revisión interna de resultados ficticios.',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _orderHeader(order),
          if (canReview && !wide) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  final target = _reviewPanelKey.currentContext;
                  if (target != null) {
                    Scrollable.ensureVisible(target,
                        alignment: .05,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 250));
                  }
                },
                icon: const Icon(Icons.south),
                label: const Text('Ir a revisión interna'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (status == 'registered')
            const Text('Primero se deben registrar todos los tubos requeridos '
                'en la sección Muestras.'),
          if (status == 'sampled' || status == 'review_rejected') ...[
            if (status == 'review_rejected') ...[
              Text(
                'Devuelta por el responsable de revisión. Corrige los valores '
                'y registra nuevamente la orden.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (data['latestReview'] is Map)
                Text(
                    'Motivo: ${(data['latestReview'] as Map)['details']?['note'] ?? 'Sin motivo disponible'}'),
              const SizedBox(height: 15),
            ],
            _manualFields(data),
          ],
          if (results.isNotEmpty) _resultReadings(results),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
                'Resultados de uso interno. El portal muestra los informes publicados.'),
          ],
        ]),
        icon: Icons.fact_check_outlined,
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: readings),
            const SizedBox(width: 16),
            SizedBox(width: 320, child: _reviewPanel()),
          ])
        else ...[
          readings,
          if (canReview) ...[
            const SizedBox(height: 14),
            _reviewPanel(),
          ],
        ],
        const SizedBox(height: 14),
        _auditTrail(data),
      ]);
    });
  }

  Widget _reportsView() {
    final data = _selected;
    if (data == null) return _withoutOrder('Informes PDF');
    final order = data['order'] as Map;
    final status = order['status'] as String?;
    final report = data['externalReport'] as Map?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panel(
        'Informes autorizados por el laboratorio de origen',
        'Este flujo incorpora PDF de prueba ya autorizado externamente; '
        'no valida clínicamente resultados ni notifica por correo o WhatsApp.',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _orderHeader(Map<String, dynamic>.from(order)),
          const SizedBox(height: 14),
          if (status == 'registered') ...[
            const Text('Para recibir el PDF debes comprobar por separado '
                'la autorización emitida por el laboratorio y la identidad del paciente.'),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              initialValue: _selectedBranch,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sucursal de origen del informe',
                border: OutlineInputBorder(),
              ),
              hint: const Text('Selecciona una sucursal de la empresa'),
              items: [
                for (final branch in _branches)
                  DropdownMenuItem<String>(
                    value: branch['code'] as String,
                    child: Text('${branch['laboratoryName']} · '
                        '${branch['branchName']}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy ? null : (code) =>
                  setState(() => _selectedBranch = code),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reportProfessional,
              enabled: !_busy,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Profesional que figura como responsable en el informe',
                helperText: 'Transcribir del PDF. No comprueba firmas ni credenciales.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reportPatientIdentifier,
              enabled: !_busy,
              maxLength: 21,
              decoration: const InputDecoration(
                labelText: 'Identificador del paciente leído del PDF de prueba',
                hintText: 'DEMO-0001',
                helperText: 'Debe coincidir con la ficha sintética del paciente.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reportReference,
              enabled: !_busy,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'N.º de informe o referencia de autorización',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _selectAuthorizationDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_reportAuthorizedAt == null
                  ? 'Fecha de autorización externa'
                  : '${_reportAuthorizedAt!.day}/${_reportAuthorizedAt!.month}/${_reportAuthorizedAt!.year}'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _selectReportPdf,
              icon: const Icon(Icons.attach_file),
              label: Text(_reportFile == null
                  ? 'Seleccionar PDF autorizado (máximo 2 MiB)'
                  : _reportFile!.name),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _confirmExternal,
              onChanged: _busy ? null : (value) =>
                  setState(() => _confirmExternal = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Confirmé fuera de Vitalia que el PDF ya '
                  'fue autorizado por el laboratorio emisor.'),
            ),
            CheckboxListTile(
              value: _confirmPatient,
              onChanged: _busy ? null : (value) =>
                  setState(() => _confirmPatient = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('Revisé manualmente el identificador ficticio del PDF y ' 
                  'verifiqué que corresponde al paciente '
                  '${order['patientEmail']}.'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _attachExternalReport,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Incorporar PDF autorizado'),
              ),
            ),
          ] else if (report != null) ...[
            Text('Documento: ${report['fileName']}'),
            Text('Emisor: ${report['issuingLaboratory']}'),
            Text('Sucursal: ${report['originBranchName'] ?? report['originBranchCode'] ?? 'No registrada'}'),
            Text('Profesional en informe: ${report['authorizedProfessionalName'] ?? 'No registrado'}'),
            Text('Identificación del paciente comprobada: '
                '${report['patientIdentifierChecked'] == true ? 'Sí' : 'Pendiente'}'),
            Text('Autorización externa: ${report['authorizationReference']}'),
            Text('Fecha de autorización: ${_date(report['externallyAuthorizedAt'])}'),
            Text('Integridad SHA-256: ${report['sha256']}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            if (status == 'report_attached')
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _publishExternalReport,
                  icon: const Icon(Icons.publish_outlined),
                  label: const Text('Publicar PDF para este paciente'),
                ),
              )
            else if (status == 'report_published')
              const Text('El informe está disponible exclusivamente en '
                  'el portal de este paciente.')
            else
              const Text('El documento no está habilitado para publicación.'),
          ] else
            const Text('Esta orden tiene un flujo de resultados internos. '
                'Para adjuntar un PDF externo, registra una nueva orden.'),
        ]),
        icon: Icons.picture_as_pdf_outlined,
      ),
      const SizedBox(height: 14),
      _auditTrail(data),
    ]);
  }

  bool get _demoProfileComplete {
    final p = _patientDemoLoaded;
    return p != null &&
        p['syntheticIdentifier'] is String &&
        (p['givenNames'] as String? ?? '').trim().isNotEmpty &&
        (p['familyNames'] as String? ?? '').trim().isNotEmpty &&
        p['birthDate'] is String;
  }

  Widget _demoPatientForm({bool compact = false}) => _panel(
    'Ficha de identificación DEMO',
    'Comprueba la identidad sintética antes de asociar un documento.',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (compact && _mobilePatientDetail) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => setState(() => _mobilePatientDetail = false),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Volver al directorio'),
          ),
        ),
        const SizedBox(height: 8),
      ],
      TextField(
        controller: _patientLookup,
        enabled: !_busy,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadDemoPatient(),
        decoration: const InputDecoration(
          labelText: 'Correo de la cuenta ficticia',
          hintText: 'paciente.sil@example.invalid',
          prefixIcon: Icon(Icons.alternate_email),
        ),
      ),
      const SizedBox(height: 9),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _loadDemoPatient(),
          icon: const Icon(Icons.person_search_outlined),
          label: const Text('Consultar ficha'),
        ),
      ),
      if (_patientDemoLoaded == null) ...[
        const SizedBox(height: 18),
        const Text('Selecciona «Ficha» junto a un paciente del directorio '
          'o consulta una cuenta DEMO por su correo. No se crean cuentas '
          'desde documentos médicos ni desde esta pantalla.'),
      ] else ...[
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ColoresVitalia.azulSuave,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(children: [
            const Icon(Icons.account_circle_outlined,
                color: ColoresVitalia.azul),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_patientDemoLoaded!['email']}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  _demoProfileComplete
                      ? 'Ficha con datos para cotejo documental'
                      : 'Ficha incompleta: completa y guarda los datos sintéticos',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )),
          ]),
        ),
        const SizedBox(height: 12),
        SelectableText('Identificador: '
          '${_patientDemoLoaded!['syntheticIdentifier'] ?? 'Se asignará al guardar'}'),
        const SizedBox(height: 8),
        Form(
          key: _patientFormKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _patientDemoGiven,
              maxLength: 100,
              enabled: !_busy,
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Ingresa al menos dos caracteres ficticios.' : null,
              decoration: const InputDecoration(
                labelText: 'Nombres ficticios',
                hintText: 'Paciente',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _patientDemoFamily,
              maxLength: 100,
              enabled: !_busy,
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Ingresa al menos dos caracteres ficticios.' : null,
              decoration: const InputDecoration(
                labelText: 'Apellidos ficticios',
                hintText: 'De prueba',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _patientDemoBirth,
              enabled: !_busy,
              validator: (value) {
                final date = (value ?? '').trim();
                final parsed = DateTime.tryParse(date);
                if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
                    parsed == null ||
                    parsed.toIso8601String().substring(0, 10) != date ||
                    date.compareTo('1900-01-01') < 0 ||
                    date.compareTo(DateTime.now().toIso8601String().substring(0, 10)) > 0) {
                  return 'Utiliza una fecha ficticia válida: AAAA-MM-DD.';
                }
                return null;
              },
              decoration: const InputDecoration(
                labelText: 'Fecha de nacimiento ficticia',
                hintText: '1990-01-01',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(_patientDemoLoaded!['id']),
              initialValue: _patientDemoSex,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sexo para referencias DEMO',
              ),
              items: const [
                DropdownMenuItem(value: 'not_specified', child: Text('No especificado')),
                DropdownMenuItem(value: 'female', child: Text('Femenino')),
                DropdownMenuItem(value: 'male', child: Text('Masculino')),
              ],
              onChanged: _busy ? null : (value) =>
                  setState(() => _patientDemoSex = value ?? 'not_specified'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _patientDemoPhone,
              maxLength: 20,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Teléfono inventado (opcional)',
                counterText: '',
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        const Text(
          'La edición queda bloqueada por el servidor cuando existen '
          'solicitudes médicas o informes externos asociados.',
          style: TextStyle(fontSize: 12, color: ColoresVitalia.textoSecundario),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _syntheticPatientConfirmed,
          onChanged: _busy ? null : (value) =>
              setState(() => _syntheticPatientConfirmed = value ?? false),
          title: const Text('Confirmo que todos los datos son ficticios.'),
        ),
        FilledButton.icon(
          onPressed: _busy || !_syntheticPatientConfirmed
              ? null : _saveDemoPatient,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar ficha de prueba'),
        ),
        if (!_syntheticPatientConfirmed)
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text('Para guardar, confirma primero el uso exclusivo de datos ficticios.',
              style: TextStyle(fontSize: 12, color: ColoresVitalia.textoSecundario)),
          ),
        const Divider(height: 25),
        const Text('Continuar con el paciente',
          style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
            onPressed: !_busy && _demoProfileComplete
                ? () => _prepareRequestForPatient(_patientDemoLoaded!['email'] as String)
                : null,
            icon: const Icon(Icons.note_add_outlined, size: 18),
            label: const Text('Recibir solicitud'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null
                : () => _openPatientOrders(_patientDemoLoaded!['email'] as String),
            icon: const Icon(Icons.assignment_outlined, size: 18),
            label: const Text('Ver órdenes'),
          ),
        ]),
        if (!_demoProfileComplete)
          const Text('Completa y guarda la ficha antes de recibir una solicitud.',
            style: TextStyle(fontSize: 12, color: ColoresVitalia.textoSecundario)),
        const SizedBox(height: 18),
        AccesoPortalPacienteDemo(
          key: ValueKey('portal-${_patientDemoLoaded!['id']}'),
          api: widget.api,
          patientId: _patientDemoLoaded!['id'] as String,
          onExpired: widget.onExpired,
        ),
      ],
    ]),
    icon: Icons.badge_outlined,
  );

  Widget _demoPatientView() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1100;
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // El mismo directorio conserva filtros y página al abrir una ficha.
          Expanded(child: _patientDirectory()),
          if (_patientDemoLoaded != null) ...[
            const SizedBox(width: 16),
            SizedBox(width: 430, child: _demoPatientForm()),
          ],
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Visibility(
          visible: !_mobilePatientDetail,
          maintainState: true,
          child: _patientDirectory(),
        ),
        if (_mobilePatientDetail) _demoPatientForm(compact: true),
      ]);
    },
  );

  Widget _bodyForSection() => switch (_section) {
    _OperatorSection.dashboard => _dashboard(),
    _OperatorSection.orders => _ordersView(),
    _OperatorSection.reviewQueue => _ordersView(),
    _OperatorSection.request => _medicalRequestView(),
    _OperatorSection.patient => _demoPatientView(),
    _OperatorSection.manualOrder => _newOrderView(),
    _OperatorSection.samples => _samplesView(),
    _OperatorSection.results => _resultsView(),
    _OperatorSection.report => _reportsView(),
  };

  Widget _notice(String message, {required bool error}) {
    final colors = Theme.of(context).colorScheme;
    final ink = error ? colors.onErrorContainer : _navy;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? colors.errorContainer : const Color(0xFFE5F5F3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: ink),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: ink))),
        ]),
      ),
    );
  }

  Widget _content() {
    final theme = Theme.of(context);
    final title = switch (_section) {
      _OperatorSection.dashboard => 'Panel del laboratorio',
      _OperatorSection.manualOrder => 'Crear orden manual',
      _OperatorSection.reviewQueue => 'Revisión de resultados',
      _OperatorSection.samples => 'Recepción de muestras',
      _OperatorSection.results => 'Resultados',
      _OperatorSection.report => 'Informe externo',
      _ => _nav[_navigationIndex].$3,
    };
    final subtitle = switch (_section) {
      _OperatorSection.orders =>
        'Encuentra una orden y continúa desde su estado actual.',
      _OperatorSection.reviewQueue =>
        'Revisa las órdenes pendientes, registra tu decisión y conserva su trazabilidad.',
      _OperatorSection.request =>
        'Coteja la solicitud con la ficha del paciente y registra la orden.',
      _OperatorSection.patient =>
        'Busca cuentas ficticias, consulta sus fichas y continúa con órdenes o solicitudes.',
      _OperatorSection.manualOrder =>
        'Vincula un paciente con las prestaciones solicitadas.',
      _OperatorSection.samples =>
        'Registra los tubos requeridos para esta orden.',
      _OperatorSection.results =>
        'Consulta los valores y sigue el estado de la revisión.',
      _OperatorSection.report => 'Gestiona el PDF autorizado de esta orden.',
      _OperatorSection.dashboard => '',
    };
    final order = _selected?['order'] as Map?;
    final isOrderDetail = _section == _OperatorSection.samples ||
        _section == _OperatorSection.results ||
        _section == _OperatorSection.report;
    return SingleChildScrollView(
      key: ValueKey(_section),
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_section != _OperatorSection.dashboard) ...[
                Text(title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    )),
                const SizedBox(height: 5),
                Text(subtitle, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 18),
              ],
              if (_loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                _notice(_error!, error: true),
                const SizedBox(height: 12),
              ],
              if (_message != null) ...[
                _notice(_message!, error: false),
                const SizedBox(height: 12),
              ],
              if (isOrderDetail && order != null) ...[
                _orderNavigation(order),
                const SizedBox(height: 14),
              ],
              if (_section == _OperatorSection.manualOrder) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        _busy ? null : () => _goTo(_OperatorSection.orders),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Volver a órdenes'),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _bodyForSection(),
              const SizedBox(height: 28),
              Text(
                'Vitalia Health · Gestión postanalítica de órdenes, muestras y resultados.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Navegación horizontal: permite dedicar el ancho útil a las órdenes.
  Widget _topNavigation({required bool compact}) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    primary: false,
    child: Row(children: [
      for (final (section, icon, label) in _nav)
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () => section == _OperatorSection.orders
                    ? _openQueue(null)
                    : _goTo(section),
            style: TextButton.styleFrom(
              foregroundColor: section == _section ? _navy : const Color(0xFF415367),
              backgroundColor: section == _section
                  ? const Color(0xFFE5F5F3)
                  : Colors.transparent,
              padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: compact
                ? const SizedBox.shrink()
                : section == _OperatorSection.reviewQueue
                    ? Badge.count(
                        count: _pendingReviews,
                        isLabelVisible: _pendingReviews > 0,
                        backgroundColor: ColoresVitalia.azul,
                        textColor: Colors.white,
                        child: Icon(icon, size: 18),
                      )
                    : Icon(icon, size: 18),
            label: Text(section == _OperatorSection.reviewQueue
                ? 'Revisión interna ($_pendingReviews)'
                : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          ),
        ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final phoneNavigation = width < 900;
    return Scaffold(
      backgroundColor: _workspace,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/branding/vitalia-simbolo.png',
                width: 31, height: 31, excludeFromSemantics: true),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Vitalia Health',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar datos del laboratorio',
            onPressed: _busy || _loading ? null : () => _run(_refreshAll),
            icon: const Icon(Icons.refresh),
          ),
          if (width >= 1550)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Center(child: Text('Operador de laboratorio')),
            ),
          if (widget.onLogout != null)
            if (width < 1250)
              IconButton(
                tooltip: 'Cerrar sesión',
                onPressed: _busy ? null : widget.onLogout,
                icon: const Icon(Icons.logout_outlined),
              )
            else
              TextButton.icon(
                onPressed: _busy ? null : widget.onLogout,
                icon: const Icon(Icons.logout_outlined),
                label: const Text('Cerrar sesión'),
              ),
        ],
        bottom: phoneNavigation
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  height: 48,
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _line)),
                  ),
                  child: _topNavigation(compact: width < 1250),
                ),
              ),
      ),
      body: _content(),
      bottomNavigationBar: phoneNavigation
          ? NavigationBar(
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFFD6EEEC),
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              selectedIndex: _navigationIndex,
              onDestinationSelected: _busy
                  ? null
                  : (index) {
                      final section = _nav[index].$1;
                      section == _OperatorSection.orders
                          ? _openQueue(null)
                          : _goTo(section);
                    },
              destinations: _nav.map((item) {
                final icon = item.$1 == _OperatorSection.reviewQueue
                    ? Badge.count(
                        count: _pendingReviews,
                        isLabelVisible: _pendingReviews > 0,
                        backgroundColor: ColoresVitalia.azul,
                        textColor: Colors.white,
                        child: Icon(item.$2),
                      )
                    : Icon(item.$2);
                final mobileLabel = switch (item.$1) {
                  _OperatorSection.dashboard => 'Inicio',
                  _OperatorSection.request => 'Recibir',
                  _OperatorSection.reviewQueue => 'Revisión',
                  _ => item.$3,
                };
                return NavigationDestination(
                    icon: icon, label: mobileLabel);
              }).toList(),
            )
          : null,
    );
  }
}
