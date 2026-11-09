import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';
import 'portal_visual_sil.dart';

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

class _SilPrincipalPageState extends State<SilPrincipalPage> {
  final _name = TextEditingController();
  final _inviteEmail = TextEditingController();
  final _staffAccount = TextEditingController();
  final _patientAccount = TextEditingController();
  final _evidence = TextEditingController();
  final _orderPatient = TextEditingController();
  final _requestPrescriber = TextEditingController();
  final _requestReference = TextEditingController();
  final _requestDate = TextEditingController();
  final _reportProfessional = TextEditingController();
  final _reportReference = TextEditingController();
  final _reportDate = TextEditingController();
  bool _verifiedPatient = false;
  bool _externallyAuthorized = false;
  bool _confirmedMatch = false;
  bool _reviewConfirmed = false;
  bool _reviewPdfDownloaded = false;
  String _staffKind = 'operator';
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
  bool get _validator => widget.role=='profesional';

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
      _name,_inviteEmail,_staffAccount,_patientAccount,_evidence,_orderPatient,
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
      _labId=selected;
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
      if(!orders.any((v)=>v['id']==_reviewOrderId))_reviewOrderId=null;
    });
  }

  void _selectLab(String? value){
    if(value==_labId||_busy)return;
    setState((){
      _labId=value;
      _orders=[];
      _requestOrderId=null;
      _uploadOrderId=null;
      _reviewOrderId=null;
      _reviewPdfDownloaded=false;
      _reviewConfirmed=false;
      _notice=null;
      _error=null;
    });
    _execute(_loadOrders,showNotice:false);
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
      'kind':_staffKind,
    });
    _staffAccount.clear();
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
    _patientAccount.clear();
    _evidence.clear();
    setState(()=>_verifiedPatient=false);
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
    if(file!=null&&mounted)setState(()=>_medicalRequestFile=file);
  }

  Future<void> _attachMedicalRequest() async {
    final lab=_labId,orderId=_requestOrderId,file=_medicalRequestFile;
    if(lab==null||orderId==null||file==null||
       !_requestIdentityChecked||!_requestHumanChecked){
      throw const AuthFailure('Selecciona orden, PDF y confirma la revisión e identidad.');
    }
    await widget.api.silMainAttachMedicalRequest(
      labId:lab,
      orderId:orderId,
      fileName:file.name,
      bytes:await file.readAsBytes(),
      prescriberName:_requestPrescriber.text,
      documentReference:_requestReference.text,
      requestDate:_requestDate.text.trim(),
    );
    if(mounted){
      setState((){
        _medicalRequestFile=null;
        _requestOrderId=null;
        _requestIdentityChecked=false;
        _requestHumanChecked=false;
        _requestPrescriber.clear();
        _requestReference.clear();
        _requestDate.clear();
      });
    }
    await _loadOrders();
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
      throw const AuthFailure('Selecciona el informe y confirma la revisión profesional.');
    }
    await widget.api.silMainRequest(
      '/labs/$lab/orders/$orderId/report/publish',
      body:{'professionalReviewConfirmed':true},
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
    String? hint,int lines=1
  })=>Padding(
    padding:const EdgeInsets.only(bottom:11),
    child:TextField(
      controller:ctrl,
      maxLines:lines,
      enabled:!_busy,
      decoration:InputDecoration(
        labelText:label,
        hintText:hint,
        border:const OutlineInputBorder(),
        isDense:true,
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

  Widget _ordersPanel(){
    final list=_orders;
    return _section(
      'Órdenes del laboratorio',
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
          onPressed:_busy?null:()=>_execute(_loadOrders,showNotice:false),
          icon:const Icon(Icons.refresh),
          label:const Text('Actualizar órdenes'),
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
        _section('Asignar personal autorizado',
          'La cuenta debe tener rol autorizado. Para validar resultados, '
          'el profesional necesita acreditación verificada.',
          Icons.admin_panel_settings_outlined,[
          _field(_staffAccount,'UUID de la cuenta de usuario'),
          DropdownButtonFormField<String>(
            value:_staffKind,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Tipo de acceso',
            ),
            items:const [
              DropdownMenuItem(value:'operator',child:Text('Operador de laboratorio')),
              DropdownMenuItem(value:'validator',child:Text('Profesional validador')),
            ],
            onChanged:_busy?null:(v){
              if(v!=null)setState(()=>_staffKind=v);
            },
          ),
          const SizedBox(height:12),
          _action('Asignar acceso',Icons.verified_user_outlined,_grantStaff),
        ]),
    ]);
  }

  Widget _operatorPanel(){
    return Column(children:[
      _section('Vincular paciente verificado',
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
      ]),
      _section('Crear orden postanalítica',
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
      ]),
      _section('Recibir solicitud médica',
        'Vincula una solicitud ya emitida a una orden existente. '
        'Los datos se registran tras revisar el PDF original.',
        Icons.note_add_outlined,[
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
          onChanged:_busy?null:(v)=>setState(()=>_requestOrderId=v),
        ),
        const SizedBox(height:10),
        OutlinedButton.icon(
          onPressed:_busy?null:_pickMedicalRequest,
          icon:const Icon(Icons.picture_as_pdf_outlined),
          label:Text(_medicalRequestFile?.name??'Seleccionar solicitud PDF'),
        ),
        const SizedBox(height:10),
        _field(_requestReference,'Referencia de solicitud'),
        _field(_requestPrescriber,'Profesional solicitante'),
        _field(_requestDate,'Fecha de solicitud (AAAA-MM-DD)'),
        CheckboxListTile(
          contentPadding:EdgeInsets.zero,
          controlAffinity:ListTileControlAffinity.leading,
          title:const Text('Identidad del paciente contrastada'),
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
        _action('Registrar solicitud',Icons.post_add_outlined,_attachMedicalRequest),
      ]),
      _section('Adjuntar informe autorizado',
        'Solo se reciben PDF ya validados externamente. '
        'Publicar requiere una segunda revisión profesional.',
        Icons.upload_file_outlined,[
        DropdownButtonFormField<String>(
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
        const SizedBox(height:10),
        OutlinedButton.icon(
          onPressed:_busy?null:_pickPdf,
          icon:const Icon(Icons.picture_as_pdf_outlined),
          label:Text(_pdf?.name??'Elegir archivo PDF (máx. 2 MiB)'),
        ),
        const SizedBox(height:8),
        _field(_reportProfessional,'Profesional que autorizó el PDF'),
        _field(_reportReference,'Referencia de autorización externa'),
        _field(_reportDate,'Fecha de autorización (AAAA-MM-DD)'),
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
      ]),
    ]);
  }

  Widget _validatorPanel(){
    return _section('Validación y publicación',
      'Solo un profesional acreditado puede publicar; no puede '
      'ser quien adjuntó el PDF.',
      Icons.fact_check_outlined,[
      DropdownButtonFormField<String>(
        value:_reviewOrderId,
        isExpanded:true,
        decoration:const InputDecoration(
          border:OutlineInputBorder(),labelText:'Informe pendiente de revisión',
        ),
        items:[
          for(final order in _orders.where((v)=>v['status']=='report_attached'))
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
        title:const Text('Confirmo revisión profesional y autorización externa'),
        value:_reviewConfirmed,
        onChanged:_busy||!_reviewPdfDownloaded
            ?null
            :(v)=>setState(()=>_reviewConfirmed=v??false),
      ),
      _action('Publicar informe',Icons.verified_outlined,_publishReport),
    ]);
  }

  @override
  Widget build(BuildContext context){
    final roleName=_admin?'Administración'
      :_operator?'Laboratorio':'Validación profesional';
    return Scaffold(
      appBar:AppBar(
        title:const Text('Vitalia Health · SIL principal'),
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
                  LayoutBuilder(builder:(context,constraints){
                    final oneColumn=constraints.maxWidth<860;
                    final controls=Column(children:[
                      if(_admin)_adminPanel(),
                      if(_operator&&_labId!=null)_operatorPanel(),
                      if(_validator&&_labId!=null)_validatorPanel(),
                    ]);
                    final orders=_labId==null
                      ?const SizedBox.shrink()
                      :_ordersPanel();
                    if(oneColumn) {
                      return Column(children:[controls,orders]);
                    }
                    return Row(
                      crossAxisAlignment:CrossAxisAlignment.start,
                      children:[
                        Expanded(flex:6,child:controls),
                        const SizedBox(width:14),
                        Expanded(flex:4,child:orders),
                      ],
                    );
                  }),
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
