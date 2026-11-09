import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';
import 'portal_visual_sil.dart';
import 'sil_main_clinical_panel.dart';

/// Estación de trabajo integrada a Vitalia original.
/// Sin simuladores ni entidades ficticias de laboratorio.
class SilPrincipalPage extends StatefulWidget {
  const SilPrincipalPage({
    super.key,
    required this.api,
    required this.role,
    required this.onExpired,
    required this.onLogout,
    this.onOpenOriginal,
  });

  final AuthApi api;
  final String role;
  final VoidCallback onExpired;
  final VoidCallback onLogout;
  final VoidCallback? onOpenOriginal;

  @override
  State<SilPrincipalPage> createState() => _SilPrincipalPageState();
}

enum _StationSection { dashboard, orders, requests, patients, clinical, review }

class _SilPrincipalPageState extends State<SilPrincipalPage> {
  final _name = TextEditingController();
  final _inviteEmail = TextEditingController();
  final _staffAccount = TextEditingController();
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
      _name,_inviteEmail,_staffAccount,_invitedPatientEmail,_patientSearch,_patientAccount,_evidence,_orderPatient,
      _requestPatient,_requestPrescriber,_requestReference,_requestDate,
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
    setState((){
      _orders=orders;
      if(!orders.any((v)=>v['id']==_uploadOrderId))_uploadOrderId=null;
      if(!orders.any((v)=>v['id']==_reviewOrderId && _isReviewable(v))){
        _reviewOrderId=null;
        _reviewPdfDownloaded=false;
        _reviewConfirmed=false;
      }
    });
  }

  void _resetLab(String? value) {
    _labId = value;
    _activeSection = _StationSection.dashboard;
    _patients = [];
    _patientSearch.clear();
    _activePatientSearch = '';
    _patientOffset = 0;
    _morePatients = false;
    _orders = [];
    for (final controller in [
      _patientAccount, _invitedPatientEmail, _evidence, _orderPatient, _requestPatient, _requestPrescriber,
      _requestReference, _requestDate, _reportProfessional, _reportReference, _reportDate,
    ]) {
      controller.clear();
    }
    _verifiedPatient = false;
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
    _execute(_loadOrders, showNotice: false);
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
  }

  Future<void> _setReviewPermission(bool enabled) async {
    final lab=_labId,accountId=_requireUuid(_staffAccount.text);
    if(lab==null||accountId==null){
      throw const AuthFailure('Selecciona laboratorio y escribe el UUID del operador.');
    }
    await widget.api.silMainRequest('/labs/$lab/staff/review-permission',body:{
      'accountId':accountId,'enabled':enabled,
    });
  }

  Future<void> _invitePatient() async {
    final lab = _labId;
    final email = _invitedPatientEmail.text.trim().toLowerCase();
    final reference = _evidence.text.trim();
    if (lab == null || !email.contains('@') || reference.length < 6 || !_verifiedPatient) {
      throw const AuthFailure('Verifica la identidad e ingresa el correo y la referencia.');
    }
    final invite = await widget.api.silMainRequest('/labs/$lab/patient-invitations', body: {
      'email': email, 'identityReference': reference, 'identityConfirmed': true,
    });
    if (!mounted) return;
    setState(() {
      _verifiedPatient = false;
      _evidence.clear();
      _invitedPatientEmail.clear();
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invitación de paciente'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Entrega el código a $email por un canal verificado. Vence en 24 horas.'),
          const SizedBox(height: 12),
          SelectableText(invite['code'] as String),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
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
      _requestReference.clear();
      _requestPrescriber.clear();
      _requestDate.clear();
      _requestExams.clear();
      _requestPreviewNotice = null;
      _requestIdentityChecked = false;
      _requestHumanChecked = false;
    });
  }

  Future<void> _previewMedicalRequest() async {
    final lab = _labId;
    final file = _medicalRequestFile;
    if (lab == null || file == null) throw const AuthFailure('Selecciona el PDF de la solicitud.');
    final preview = await widget.api.silMainPreviewMedicalRequest(
      labId: lab, fileName: file.name, bytes: await file.readAsBytes(),
    );
    if (!mounted) return;
    setState(() {
      _requestReference.text = preview['suggestedDocumentReference'] as String? ?? '';
      _requestPrescriber.text = preview['suggestedPrescriberName'] as String? ?? '';
      _requestDate.text = preview['suggestedRequestDate'] as String? ?? '';
      _requestExams
        ..clear()
        ..addAll((preview['suggestedExams'] as List? ?? [])
            .map((entry) => entry['code'] as String)
            .where((code) => _catalog.any((entry) => entry.$1 == code)).take(6));
      _requestPreviewNotice = preview['state'] == 'text_ready'
          ? 'Revisa las sugerencias con el PDF original y confirma la identidad.'
          : 'No se pudo leer texto del PDF. Contrasta el original e ingresa los datos manualmente.';
      _requestIdentityChecked = false;
      _requestHumanChecked = false;
    });
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

  String _orderLabel(Map<String,dynamic> order){
    final num=order['orderNumber'];
    return 'VH-${num.toString().padLeft(6,'0')} · ${_status(order['status'])}';
  }

  String _status(dynamic value)=>switch(value){
    'registered'=>'Orden registrada',
    'report_attached'=>'PDF en revisión',
    'report_published'=>'Informe publicado',
    _=>'Estado pendiente',
  };

  Widget _ordersPanel({bool recent = false}){
    final list=recent ? _orders.take(5) : _orders;
    return _section(
      recent ? 'Actividad reciente' : 'Órdenes del laboratorio',
      'Consulta postanalítica del laboratorio seleccionado.',
      Icons.assignment_outlined,
      [
        if(list.isEmpty)
          const Padding(
            padding:EdgeInsets.only(bottom:12),
            child:Text('Aún no existen órdenes en este laboratorio.'),
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
                      Text(_orderLabel(order),style:
                        const TextStyle(fontWeight:FontWeight.w700)),
                      const SizedBox(height:4),
                      Text((order['examCodes'] as List? ?? []).join(' · '),
                        style:const TextStyle(
                          fontSize:12,color:ColoresVitalia.textoSecundario)),
                    ],
                  )),
                ],
              ),
            ),
        OutlinedButton.icon(
          onPressed:_busy?null:()=>_execute(_loadLabs,showNotice:false),
          icon:const Icon(Icons.refresh),
          label:const Text('Actualizar estación'),
        ),
      ],
    );
  }

  Widget _adminPanel(){
    return Column(children:[
      _section('Registrar laboratorio',
        'Crea una organización real del sistema, sin generar datos clínicos.',
        Icons.add_business_outlined,[
        _field(_name,'Nombre del laboratorio'),
        _action('Registrar laboratorio',Icons.add,_createLab),
      ]),
      if(_labId!=null)
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
      if(_labId!=null)
        _section('Acceso y permiso de revisión',
          'Asigna un operador existente al laboratorio. Concede el permiso de '
          'revisión solo tras verificar su capacitación para este flujo.',
          Icons.admin_panel_settings_outlined,[
          _field(_staffAccount,'UUID de la cuenta del operador'),
          Wrap(spacing:8,runSpacing:8,children:[
            _action('Asignar operador',Icons.person_add_alt_1,_grantStaff),
            OutlinedButton(
              onPressed:_busy?null:()=>_execute(()=>_setReviewPermission(true)),
              child:const Text('Autorizar revisión'),
            ),
            OutlinedButton(
              onPressed:_busy?null:()=>_execute(()=>_setReviewPermission(false)),
              child:const Text('Retirar permiso'),
            ),
          ]),
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
        _action('Emitir código de activación', Icons.person_add_alt_1_outlined, _invitePatient),
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

  Widget _requestIntake() => _section('Recibir solicitud médica',
        'Lee la solicitud para preparar una orden nueva o adjúntala a una orden existente.',
        Icons.note_add_outlined,[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vincular a una orden existente'),
          value: _attachToExistingOrder,
          onChanged: _busy ? null : (value) => setState(() {
            _attachToExistingOrder = value;
            _requestIdentityChecked = false;
            _requestHumanChecked = false;
          }),
        ),
        if (_attachToExistingOrder)
          DropdownButtonFormField<String>(
            value:_requestOrderId,
            isExpanded:true,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Orden del paciente',
            ),
            items:[
              for(final order in _orders.where((v)=>v['status']=='registered'))
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
        else
          _field(_requestPatient, 'UUID del paciente vinculado', onChanged: (_) => setState(() {
            _requestIdentityChecked = false;
            _requestHumanChecked = false;
          })),
        const SizedBox(height:10),
        OutlinedButton.icon(
          onPressed:_busy?null:_pickMedicalRequest,
          icon:const Icon(Icons.picture_as_pdf_outlined),
          label:Text(_medicalRequestFile?.name??'Seleccionar solicitud PDF'),
        ),
        const SizedBox(height:10),
        OutlinedButton.icon(
          onPressed: _busy || _medicalRequestFile == null ? null :
            () => _execute(_previewMedicalRequest, showNotice: false),
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Leer PDF y sugerir datos'),
        ),
        if (_requestPreviewNotice != null) Text(_requestPreviewNotice!),
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
        _action(_attachToExistingOrder ? 'Registrar solicitud' : 'Crear orden con solicitud',
          Icons.post_add_outlined,_attachMedicalRequest),
      ]);

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
              for(final order in _orders.where((v)=>v['status']=='registered'))
                DropdownMenuItem<String>(
                  value:order['id'] as String,
                  child:Text(_orderLabel(order),overflow:TextOverflow.ellipsis),
                ),
            ],
            onChanged:_busy?null:(v)=>setState(()=>_uploadOrderId=v),
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
            for(final order in _orders.where(_isReviewable))
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

  Widget _navigation(bool compact) {
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
    return SingleChildScrollView(
      primary: false,
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (section, icon, label) in destinations)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: TextButton.icon(
              onPressed: _busy ? null : () => _openSection(section),
              style: TextButton.styleFrom(
                foregroundColor: section == _activeSection
                    ? const Color(0xFF11263C) : const Color(0xFF415367),
                backgroundColor: section == _activeSection
                    ? const Color(0xFFE5F5F3) : Colors.transparent,
                padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: compact ? const SizedBox.shrink() : Icon(icon, size: 18),
              label: Text(label, maxLines: 1),
            ),
          ),
      ]),
    );
  }

  Widget _dashboard() {
    final pending = _orders.where(_isReviewable).length;
    final published = _orders.where((order) => order['status'] == 'report_published').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('Trabajo del operador', 'Accesos del laboratorio seleccionado. '
          'Los recuentos corresponden a las órdenes cargadas.', Icons.space_dashboard_outlined, [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openSection(_StationSection.requests),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Recibir solicitud de exámenes'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openSection(_StationSection.orders),
            icon: const Icon(Icons.assignment_outlined),
            label: Text('Órdenes visibles · ${_orders.length}'),
          ),
          if (_canReview)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _openSection(_StationSection.review),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text('Informes por revisar · $pending'),
            ),
          Chip(label: Text('Informes publicados · $published')),
        ]),
      ]),
      _ordersPanel(recent: true),
    ]);
  }

  Widget _station() {
    if (_labId == null) return const SizedBox.shrink();
    return switch (_activeSection) {
      _StationSection.dashboard => _dashboard(),
      _StationSection.orders => LayoutBuilder(builder: (context, constraints) {
          final forms = Column(children: [_newOrder(), _reportUpload()]);
          final list = _ordersPanel();
          if (constraints.maxWidth < 860) return Column(children: [forms, list]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 6, child: forms),
            const SizedBox(width: 14),
            Expanded(flex: 4, child: list),
          ]);
        }),
      _StationSection.requests => _requestIntake(),
      _StationSection.patients => Column(children: [_patientDirectory(), _patientLink()]),
      _StationSection.clinical => _section(
        'Muestras y resultados', 'Registra la recepción y revisa los analitos de la orden.',
        Icons.science_outlined, [
          SilMainClinicalPanel(
            key: ValueKey(_labId), api: widget.api, labId: _labId!, orders: _orders,
            canReview: _canReview, onExpired: widget.onExpired,
          ),
        ],
      ),
      _StationSection.review => _canReview ? _reviewPanel() : _dashboard(),
    };
  }

  @override
  Widget build(BuildContext context){
    final roleName=_admin?'Administración':'Panel del laboratorio';
    final compact = MediaQuery.sizeOf(context).width < 900;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FA),
      appBar:AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Image.asset('assets/branding/vitalia-simbolo.png',
            width: 31, height: 31, excludeFromSemantics: true),
          const SizedBox(width: 8),
          const Flexible(child: Text('Vitalia Health', overflow: TextOverflow.ellipsis)),
        ]),
        bottom: _operator ? PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _navigation(compact),
            ),
          ),
        ) : null,
        actions:[
          if(widget.onOpenOriginal!=null)
            IconButton(
              onPressed:widget.onOpenOriginal,
              tooltip:'Abrir módulo original de Vitalia',
              icon:const Icon(Icons.open_in_new),
            ),
          IconButton(
            onPressed:widget.onLogout,
            tooltip:'Cerrar sesión',
            icon:const Icon(Icons.logout),
          ),
        ],
      ),
      body:SafeArea(
        child:SingleChildScrollView(
          padding:const EdgeInsets.all(18),
          child:Center(
            child:ConstrainedBox(
              constraints:const BoxConstraints(maxWidth:1160),
              child:Column(
                crossAxisAlignment:CrossAxisAlignment.stretch,
                children:[
                  PortalHeroSil(
                    eyebrow:'Vitalia Health · Sistema postanalítico',
                    title:roleName,
                    subtitle:'Órdenes, informes autorizados y publicación '
                      'en un mismo espacio. La identidad y los permisos '
                      'se verifican desde el backend de Vitalia.',
                    compact:true,
                    showLaboratoryArt:false,
                  ),
                  const SizedBox(height:18),
                  if(_busy)const LinearProgressIndicator(),
                  if(_error!=null)
                    Padding(
                      padding:const EdgeInsets.only(bottom:10),
                      child:Text(_error!,
                        style:const TextStyle(color:Colors.red)),
                    ),
                  if(_notice!=null)
                    Padding(
                      padding:const EdgeInsets.only(bottom:10),
                      child:Text(_notice!,
                        style:const TextStyle(color:ColoresVitalia.verde)),
                    ),
                  _section('Laboratorio activo',
                    'Las operaciones solo afectan al laboratorio seleccionado.',
                    Icons.local_hospital_outlined,[
                    if(_labs.isEmpty)
                      const Text('No tienes laboratorios asociados. '
                        'Solicita autorización a la administración.')
                    else
                      DropdownButtonFormField<String>(
                        value:_labId,
                        isExpanded:true,
                        decoration:const InputDecoration(
                          border:OutlineInputBorder(),labelText:'Laboratorio',
                        ),
                        items:[
                          for(final lab in _labs)
                            DropdownMenuItem<String>(
                              value:lab['id'] as String,
                              child:Text(lab['displayName'] as String,
                                overflow:TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged:_busy?null:_selectLab,
                      ),
                  ]),
                  if (_operator) _station(),
                  if (_admin) ...[
                    _adminPanel(),
                    if (_labId != null) _ordersPanel(),
                  ],
                  const SizedBox(height:14),
                  const Text(
                    'Vitalia Health · Entorno de integración. '
                    'No utilizar datos clínicos reales antes de aprobar '
                    'seguridad, procedimientos y cumplimiento.',
                    textAlign:TextAlign.center,
                    style:TextStyle(
                      fontSize:12,color:ColoresVitalia.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
