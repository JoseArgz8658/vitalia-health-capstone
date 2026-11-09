import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_selector/file_selector.dart';

import '../../core/auth_api.dart';

enum _OperatorSection {
  dashboard,
  orders,
  request,
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
  static const _nav = <(_OperatorSection, IconData, String)>[
    (_OperatorSection.dashboard, Icons.dashboard_outlined, 'Resumen'),
    (_OperatorSection.orders, Icons.assignment_outlined, 'Órdenes'),
    (_OperatorSection.request, Icons.note_add_outlined, 'Recibir solicitud'),
    (_OperatorSection.patient, Icons.badge_outlined, 'Pacientes DEMO'),
  ];

  final _patientController = TextEditingController();
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
  final _reportProfessional = TextEditingController();
  final _reportPatientIdentifier = TextEditingController();
  final _patientDemoId = TextEditingController();
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
  int _page = 0;
  int _total = 0;
  _OperatorSection _section = _OperatorSection.dashboard;

  int get _navigationIndex {
    final index = _nav.indexWhere((item) => item.$1 == _section);
    return index == -1 ? 1 : index;
  }

  void _goTo(_OperatorSection section) {
    if (_busy || section == _section) return;
    setState(() {
      _section = section;
      _error = null;
      _message = null;
    });
    if (section == _OperatorSection.orders) _refreshOrders();
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _patientController.dispose();
    _requestPatientEmail.dispose();
    _requestDocumentReference.dispose();
    _requestPrescriberName.dispose();
    _searchController.dispose();
    _barcodeController.dispose();
    _receiptNoteController.dispose();
    _reportProfessional.dispose();
    _reportPatientIdentifier.dispose();
    for (final controller in [
      _patientDemoId, _patientDemoGiven, _patientDemoFamily,
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
    if(order==null||request==null)
      throw const AuthFailure('La orden no tiene solicitud PDF vinculada.');
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
    if(mounted)setState(()=>
      _message='Descarga de solicitud registrada en auditoría.');
  });

  Future<void> _selectMedicalRequestPdf() async {
    try{
      final file=await openFile(acceptedTypeGroups:const [
        XTypeGroup(label:'Solicitud médica ficticia PDF',
          extensions:['pdf'],mimeTypes:['application/pdf']),
      ]);
      if(file==null||!mounted)return;
      final length=await file.length();
      if(length<8||length>2*1024*1024){
        setState(()=>_error='La solicitud debe ser un PDF ficticio de hasta 2 MiB.');
        return;
      }
      setState((){
        _requestPdf=file;
        _requestPreview=null;
        _requestHumanConfirmed=false;
        _requestExamCodes.clear();
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
    if(mounted)setState(()=>_message=
      'Solicitud ficticia asociada a ${order['orderNumber']}. '
      'Continúa con las muestras requeridas.');
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
    if (!RegExp(r'^[A-Z0-9-]{3,40}$').hasMatch(barcode)) {
      throw const AuthFailure('Código de muestra inválido: usa letras, números o guiones.');
    }
    final container = _containerCode;
    if (container == null) {
      throw const AuthFailure('No hay tubos pendientes de recepción.');
    }
    final id = order['id'] as String;
    await widget.api.silRequest('/orders/$id/sample', body: {
      'barcode': barcode,
      'containerCode': container,
      if (_receiptNoteController.text.trim().isNotEmpty)
        'receiptNote': _receiptNoteController.text.trim(),
    });
    await _openOrder(id);
    await _refreshAll();
    if (mounted) setState(() => _message = 'Recepción de muestra registrada.');
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
      if (mounted) setState(() => _message =
          'Informe publicado en el portal de ese paciente. '
          'Aún no se envían notificaciones externas.');
    });
  }

  Future<void> _loadDemoPatient() => _run(() async {
    final email = _patientController.text.trim().toLowerCase();
    if (!email.endsWith('@example.invalid')) {
      throw const AuthFailure('Solo se permiten cuentas ficticias example.invalid.');
    }
    final response = await widget.api.silRequest(
      '/patients/profile?email=${Uri.encodeQueryComponent(email)}',
    );
    final patient = Map<String, dynamic>.from(response['patient'] as Map);
    if (!mounted) return;
    setState(() {
      _patientDemoLoaded = patient;
      _patientDemoId.text = patient['syntheticIdentifier'] as String? ?? '';
      _patientDemoGiven.text = patient['givenNames'] as String? ?? '';
      _patientDemoFamily.text = patient['familyNames'] as String? ?? '';
      _patientDemoBirth.text = patient['birthDate'] as String? ?? '';
      _patientDemoPhone.text = patient['contactPhoneDemo'] as String? ?? '';
      _patientDemoSex = patient['sexForReference'] as String? ?? 'not_specified';
      _syntheticPatientConfirmed = false;
    });
  });

  Future<void> _saveDemoPatient() => _run(() async {
    if (_patientDemoLoaded == null || !_syntheticPatientConfirmed) {
      throw const AuthFailure('Consulta el paciente y confirma que todos los datos son ficticios.');
    }
    final email = _patientDemoLoaded!['email'] as String;
    final result = await widget.api.silRequest('/patients/profile', body: {
      'email': email,
      'syntheticIdentifier': _patientDemoId.text.trim().toUpperCase(),
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
      _message = 'Ficha sintética guardada. Comprueba el identificador del PDF antes de publicarlo.';
    });
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
      _filterStatus = null;
      _section = _OperatorSection.orders;
      _message = 'Resultados registrados para ${_orderCode(order)}. '
          'Orden pendiente de revisión profesional.';
    });
    await _refreshAll();
  });

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
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
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

  Widget _metric(IconData icon, String title, int count) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: _panel(
        title,
        'Órdenes del laboratorio',
        Row(children: [
          Icon(icon, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 14),
          Text('$count', style: theme.textTheme.headlineMedium),
        ]),
      ),
    );
  }

  Widget _ordersTable({bool recent = false}) {
    final rows = recent ? _recentOrders : _orders;
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No hay órdenes que coincidan con la búsqueda.'),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('N.º de orden')),
          DataColumn(label: Text('Paciente')),
          DataColumn(label: Text('Exámenes')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Fecha')),
          DataColumn(label: Text('Acción')),
        ],
        rows: rows.map((order) {
          final exams = (order['examCodes'] as List? ?? [])
              .map((code) => _examName('$code'))
              .join(', ');
          return DataRow(cells: [
            DataCell(Text(_orderCode(order))),
            DataCell(Text('${order['patientEmail'] ?? '—'}')),
            DataCell(SizedBox(
              width: 250,
              child: Text(exams, maxLines: 2, overflow: TextOverflow.ellipsis),
            )),
            DataCell(Text(_statusLabel(order['status'] as String?))),
            DataCell(Text(_date(order['createdAt']))),
            DataCell(TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => _openOrder(order['id'] as String)),
              child: Text(_orderAction(order['status'])),
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _dashboard() {
    final summary = _summary;
    if (summary == null) {
      return const Text('Cargando indicadores del laboratorio…');
    }
    int count(String key) => (summary[key] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _metric(Icons.assignment_outlined, 'Órdenes totales', count('total')),
          _metric(Icons.inventory_2_outlined, 'Pendientes de muestra', count('pendingSample')),
          _metric(Icons.science_outlined, 'Pendientes de resultados', count('pendingResults')),
          _metric(Icons.verified_outlined, 'Pendientes de revisión', count('pendingReview')),
          _metric(Icons.undo_outlined, 'Devueltas para corregir', count('returned')),
          _metric(Icons.picture_as_pdf_outlined, 'Informes por publicar', count('attached')),
          _metric(Icons.file_download_done_outlined, 'Informes disponibles', count('published')),
        ]),
        const SizedBox(height: 20),
        _panel(
          'Actividad reciente',
          'Últimas órdenes obtenidas desde PostgreSQL.',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _ordersTable(recent: true),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _goTo(_OperatorSection.orders),
                icon: const Icon(Icons.arrow_forward_outlined),
                label: const Text('Ver todas las órdenes'),
              ),
            ),
          ]),
          icon: Icons.history,
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _goTo(_OperatorSection.request),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Recibir solicitud de exámenes'),
          ),
        ),
      ],
    );
  }

  Widget _ordersView() => _panel(
    'Buscar y gestionar órdenes',
    'Consulta por paciente, número de orden o identificador, y filtra por estado.',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 340,
          child: TextField(
            controller: _searchController,
            enabled: !_busy,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Buscar orden o correo',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        DropdownButton<String>(
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
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _search,
          icon: const Icon(Icons.search),
          label: const Text('Buscar'),
        ),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () {
                  _searchController.clear();
                  setState(() {
                    _page = 0;
                    _filterStatus = null;
                  });
                  _refreshOrders();
                },
          icon: const Icon(Icons.clear),
          label: const Text('Limpiar filtros'),
        ),
      ]),
      const SizedBox(height: 12),
      if (_ordersLoading)
        const LinearProgressIndicator(semanticsLabel: 'Actualizando órdenes')
      else ...[
        Text('$_total órdenes encontradas'),
        const SizedBox(height: 10),
        _ordersTable(),
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
    icon: Icons.assignment_outlined,
  );

  Widget _medicalRequestView() => _panel(
    'Recepción de solicitud de exámenes',
    'Vincula una solicitud médica ficticia a una orden interna. '
    'Los datos del paciente deben constar en una ficha previamente registrada.',
    Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
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
      const Text('El sistema detecta prestaciones del catálogo por texto '
        'y coteja identificador DEMO, nombres y fecha de nacimiento. '
        'No verifica firmas ni habilitación profesional. '
        'Un PDF escaneado sin texto deberá procesarse con OCR en una versión posterior.'),
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
            value:_requestBranchCode,
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
                  if(value && _requestExamCodes.length<6)
                    _requestExamCodes.add(code);
                  if(!value)_requestExamCodes.remove(code);
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

  Widget _orderHeader(Map<String, dynamic> order) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Orden: ${_orderCode(order)}',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text('Paciente: ${order['patientEmail'] ?? '—'}'),
      if(_selected?['medicalRequest'] is Map) ...[
        Text('Solicitud recibida: '
          '${(_selected!['medicalRequest'] as Map)['documentReference']}'),
        Text('Procedencia: '
          '${(_selected!['medicalRequest'] as Map)['branchName']}'),
        Text('Profesional solicitante indicado: '
          '${(_selected!['medicalRequest'] as Map)['prescriberName']}'),
        const SizedBox(height:8),
        Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(
          onPressed:_busy?null:_downloadMedicalRequest,
          icon:const Icon(Icons.download_outlined),
          label:const Text('Descargar solicitud original'),
        )),
      ],
      Text('Creación: ${_date(order['createdAt'])}'),
      Text('Estado: ${_statusLabel(order['status'] as String?)}'),
      const SizedBox(height: 8),
      Text('Prestaciones: ${(_selected?['exams'] as List? ?? [])
          .map((item) => (item as Map)['name']).join(', ')}'),
    ],
  );

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
                label: Text('${container['label']} · '
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
              value: _containerCode,
              decoration: const InputDecoration(
                labelText: 'Tipo de tubo pendiente',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final container in pending)
                  DropdownMenuItem(
                    value: (container as Map)['code'] as String,
                    child: Text(container['label'] as String),
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
                labelText: 'Código de muestra',
                hintText: 'LAB-2026-001',
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

  Widget _resultsView() {
    final data = _selected;
    if (data == null) return _withoutOrder('Resultados');
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final status = order['status'] as String?;
    final results = data['results'] as List? ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panel(
        'Resultados de la orden',
        'Consulta interna. La revisión y publicación clínica no están habilitadas.',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _orderHeader(order),
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
                Text('Motivo: ${(data['latestReview'] as Map)['details']?['note'] ?? 'Sin motivo disponible'}'),
              const SizedBox(height: 15),
            ],
            _manualFields(data),
          ],
          if (results.isNotEmpty)
            SingleChildScrollView(
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
                  final source = switch (row['entryMethod']) {
                    'manual' => 'Manual',
                    'simulated' => 'Prueba automática',
                    _ => 'Registro anterior',
                  };
                  return DataRow(cells: [
                    DataCell(Text(_examName('${row['examCode'] ?? ''}'))),
                    DataCell(Text('${row['analyte']}')),
                    DataCell(Text('${row['numericValue']}')),
                    DataCell(Text('${row['unit']}')),
                    DataCell(Text(source)),
                    DataCell(Text(
                      '${row['referenceMin'] ?? '—'} – ${row['referenceMax'] ?? '—'}',
                    )),
                  ]);
                }).toList(),
              ),
            ),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Los resultados registrados permanecen en el sistema '
                'interno y no se publican en el acceso del paciente.'),
          ],
        ]),
        icon: Icons.fact_check_outlined,
      ),
      const SizedBox(height: 14),
      _auditTrail(data),
    ]);
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
              value: _selectedBranch,
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

  Widget _demoPatientView() => _panel(
    'Ficha de identificación (solo datos ficticios)',
    'Los datos de esta pantalla solo sirven para probar la correspondencia '
    'del PDF con la cuenta del paciente. No ingreses RUT ni teléfonos reales.',
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _patientController,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: 'Correo de la cuenta de pruebas',
          hintText: 'paciente.sil@example.invalid',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _loadDemoPatient,
          icon: const Icon(Icons.search),
          label: const Text('Consultar paciente'),
        ),
      ),
      if (_patientDemoLoaded != null) ...[
        const SizedBox(height: 18),
        Text('Cuenta: ${_patientDemoLoaded!['email']}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _patientDemoId,
          maxLength: 21,
          decoration: const InputDecoration(
            labelText: 'Identificador ficticio (no utilizar RUN reales)',
            hintText: 'DEMO-0001',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _patientDemoGiven,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Nombres ficticios',
            hintText: 'Paciente',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _patientDemoFamily,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Apellidos ficticios',
            hintText: 'De Prueba',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _patientDemoBirth,
          decoration: const InputDecoration(
            labelText: 'Fecha de nacimiento ficticia (AAAA-MM-DD)',
            hintText: '1990-01-01',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _patientDemoSex,
          decoration: const InputDecoration(
            labelText: 'Sexo para referencias de laboratorio (demo)',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'not_specified',
                child: Text('No especificado')),
            DropdownMenuItem(value: 'female', child: Text('Femenino')),
            DropdownMenuItem(value: 'male', child: Text('Masculino')),
          ],
          onChanged: _busy ? null : (value) =>
              setState(() => _patientDemoSex = value ?? 'not_specified'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _patientDemoPhone,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: 'Teléfono ficticio (opcional)',
            hintText: '000000000',
            border: OutlineInputBorder(),
          ),
        ),
        CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: _syntheticPatientConfirmed,
          onChanged: _busy ? null : (value) =>
              setState(() => _syntheticPatientConfirmed = value ?? false),
          title: const Text('Confirmo que la ficha contiene únicamente datos '
              'inventados para la demostración.'),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : _saveDemoPatient,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar ficha de prueba'),
          ),
        ),
      ],
    ]),
    icon: Icons.badge_outlined,
  );

  Widget _bodyForSection() => switch (_section) {
    _OperatorSection.dashboard => _dashboard(),
    _OperatorSection.orders => _ordersView(),
    _OperatorSection.request => _medicalRequestView(),
    _OperatorSection.patient => _demoPatientView(),
    _OperatorSection.manualOrder => _newOrderView(),
    _OperatorSection.samples => _samplesView(),
    _OperatorSection.results => _resultsView(),
    _OperatorSection.report => _reportsView(),
  };

  Widget _content() {
    final theme = Theme.of(context);
    final title = switch (_section) {
      _OperatorSection.dashboard => 'Panel del laboratorio',
      _OperatorSection.manualOrder => 'Crear orden manual',
      _OperatorSection.samples => 'Recepción de muestras',
      _OperatorSection.results => 'Resultados',
      _OperatorSection.report => 'Informe externo',
      _ => _nav[_navigationIndex].$3,
    };
    final order = _selected?['order'] as Map?;
    final isOrderDetail = _section == _OperatorSection.samples ||
        _section == _OperatorSection.results || _section == _OperatorSection.report;
    return SingleChildScrollView(
      key: ValueKey(_section),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 5),
              Text(
                'Gestión de órdenes, muestras y resultados.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 10),
              ],
              if (_message != null) ...[
                Text(_message!, style: TextStyle(color: theme.colorScheme.primary)),
                const SizedBox(height: 10),
              ],
              if (isOrderDetail && order != null) ...[
                _orderNavigation(order),
                const SizedBox(height: 14),
              ],
              if (_section == _OperatorSection.manualOrder) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _goTo(_OperatorSection.orders),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitalia Health'),
        actions: [
          IconButton(
            tooltip: 'Actualizar datos del laboratorio',
            onPressed: _busy || _loading ? null : () => _run(_refreshAll),
            icon: const Icon(Icons.refresh),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Center(child: Text('Operador de laboratorio')),
          ),
          if (widget.onLogout != null)
            TextButton.icon(
              onPressed: _busy ? null : widget.onLogout,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('Cerrar sesión'),
            ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return _content();
        }
        return Row(children: [
          NavigationRail(
            extended: constraints.maxWidth >= 1250,
            selectedIndex: _navigationIndex,
            labelType: constraints.maxWidth >= 1250
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            onDestinationSelected: _busy ? null : (index) => _goTo(_nav[index].$1),
            destinations: _nav
                .map((item) => NavigationRailDestination(
                  icon: Icon(item.$2), label: Text(item.$3),
                ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _content()),
        ]);
      }),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
          ? NavigationBar(
              selectedIndex: _navigationIndex,
              onDestinationSelected: _busy ? null : (index) => _goTo(_nav[index].$1),
              destinations: _nav
                  .map((item) => NavigationDestination(
                    icon: Icon(item.$2), label: item.$3,
                  ))
                  .toList(),
            )
          : null,
    );
  }
}
