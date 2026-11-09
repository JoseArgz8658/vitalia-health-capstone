import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';

/// Activación guiada DEMO: nunca revela contraseñas ni códigos de correo
/// al operador. El comprobante de entrega presencial aparece una sola vez.
class AccesoPortalPacienteDemo extends StatefulWidget {
  const AccesoPortalPacienteDemo({
    super.key,required this.api,required this.patientId,required this.onExpired,
  });
  final AuthApi api;
  final String patientId;
  final VoidCallback onExpired;

  @override
  State<AccesoPortalPacienteDemo> createState() => _AccesoPortalPacienteDemoState();
}
class _AccesoPortalPacienteDemoState extends State<AccesoPortalPacienteDemo> {
  Map<String,dynamic>? _data;
  String? _error;
  bool _loading=true;
  bool _sending=false;
  int _request=0;
  static const _ink=ColoresVitalia.texto;
  static const _muted=ColoresVitalia.textoSecundario;
  static const _border=ColoresVitalia.bordeTenue;

  @override void initState(){
    super.initState();
    _load();
  }
  @override void didUpdateWidget(covariant AccesoPortalPacienteDemo old){
    super.didUpdateWidget(old);
    if(old.patientId!=widget.patientId)_load();
  }
  @override void dispose(){_request++;super.dispose();}

  Future<void> _load()async{
    final current=++_request;
    if(mounted)setState((){_loading=true;_error=null;_data=null;});
    try{
      final result=await widget.api.silPortalRequest(
        '/portal/patients/${widget.patientId}');
      if(!mounted||current!=_request)return;
      setState((){_data=result;_loading=false;});
    }on AuthFailure catch(e){
      if(!mounted||current!=_request)return;
      if(e.status==401){widget.onExpired();return;}
      setState((){_loading=false;_error=e.message;});
    }catch(_){
      if(mounted&&current==_request)setState((){
        _loading=false;_error='No se pudo consultar el acceso al portal.';
      });
    }
  }

  String _stateLabel(String? state)=>switch(state){
    'pending'=>'Sin activar',
    'invited'=>'Invitación pendiente',
    'active'=>'Cuenta activa',
    'suspended'=>'Acceso suspendido',
    _=>'Cuenta anterior',
  };
  Color _stateColor(String? state)=>switch(state){
    'active'=>const Color(0xFF23634F),
    'invited'=>const Color(0xFF906224),
    'suspended'=>ColoresVitalia.error,
    _=>ColoresVitalia.azul,
  };
  Color _stateFill(String? state)=>switch(state){
    'active'=>ColoresVitalia.verdeSuave,
    'invited'=>ColoresVitalia.advertenciaSuave,
    'suspended'=>ColoresVitalia.errorSuave,
    _=>ColoresVitalia.azulSuave,
  };
  String _date(Object? value){
    if(value==null)return '—';
    final v=DateTime.tryParse('$value')?.toLocal();
    if(v==null)return '—';
    String two(int n)=>n.toString().padLeft(2,'0');
    return '${two(v.day)}/${two(v.month)}/${v.year} · ${two(v.hour)}:${two(v.minute)}';
  }

  Widget _detail(String label,String value,{IconData? icon}){
    return Padding(padding:const EdgeInsets.only(bottom:10),
      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(icon!=null)...[
          Icon(icon,color:_muted,size:18),
          const SizedBox(width:9),
        ],
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(label,style:const TextStyle(color:_muted,fontSize:11,
            fontWeight:FontWeight.w600,letterSpacing:.2)),
          const SizedBox(height:2),
          SelectableText(value,style:const TextStyle(color:_ink,
            fontWeight:FontWeight.w600,fontSize:13)),
        ])),
      ]));
  }
  Widget _stage(int n,String label,bool completed,bool current){
    final color=completed?const Color(0xFF27775E):
      current?ColoresVitalia.azul:_muted;
    return Row(mainAxisSize:MainAxisSize.min,children:[
      CircleAvatar(radius:12,backgroundColor:completed
          ?ColoresVitalia.verdeSuave:current?ColoresVitalia.azulSuave:
          ColoresVitalia.fondoAzul,
        child:completed?const Icon(Icons.check,size:14,color:Color(0xFF27775E)):
          Text('$n',style:TextStyle(fontSize:11,color:color,fontWeight:FontWeight.w700))),
      const SizedBox(width:6),
      Text(label,style:TextStyle(color:color,fontSize:11,
        fontWeight:current?FontWeight.w700:FontWeight.w500)),
    ]);
  }

  Future<bool> _confirmRecipient(Map<String,dynamic> p)async{
    var identity=false;
    var contact=false;
    final approved=await showDialog<bool>(context:context,
      barrierDismissible:false,builder:(context)=>StatefulBuilder(
      builder:(context,change)=>AlertDialog(
        title:const Row(children:[
          Icon(Icons.verified_user_outlined,color:ColoresVitalia.azul),
          SizedBox(width:8),
          Expanded(child:Text('Confirmar destinatario')),
        ]),
        content:SizedBox(width:470,child:SingleChildScrollView(
          child:Column(mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('Antes de generar una invitación revisa a quién '
                'se entregará el acceso. Estos datos son ficticios.'),
              const SizedBox(height:14),
              Container(padding:const EdgeInsets.all(14),
                decoration:BoxDecoration(
                  color:ColoresVitalia.fondoAzul,borderRadius:BorderRadius.circular(12)),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('${p['givenNames']??''} ${p['familyNames']??''}',
                    style:const TextStyle(fontWeight:FontWeight.w700,fontSize:16)),
                  const SizedBox(height:8),
                  Text('ID: ${p['syntheticIdentifier']??'—'}'),
                  Text('Nacimiento: ${p['birthDate']??'—'}'),
                  Text('Correo destino: ${p['email']??'—'}'),
                ]),
              ),
              const SizedBox(height:12),
              CheckboxListTile(
                contentPadding:EdgeInsets.zero,
                controlAffinity:ListTileControlAffinity.leading,
                value:identity,
                title:const Text('Corroboré presencialmente la identidad DEMO.'),
                subtitle:const Text('Declaración del operador; no es verificación automatizada.'),
                onChanged:(v)=>change(()=>identity=v??false)),
              CheckboxListTile(
                contentPadding:EdgeInsets.zero,
                controlAffinity:ListTileControlAffinity.leading,
                value:contact,
                title:const Text('Corroboré con la persona este correo de contacto.'),
                subtitle:const Text('La entrega del correo se simula; no se envían emails reales.'),
                onChanged:(v)=>change(()=>contact=v??false)),
              const Text('La invitación caduca a los 20 minutos. Un reenvío '
                'invalida el anterior.',style:TextStyle(color:_muted,fontSize:12)),
            ]),
        )),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context,false),
            child:const Text('Cancelar')),
          FilledButton.icon(
            onPressed:identity&&contact
                ?()=>Navigator.pop(context,true):null,
            icon:const Icon(Icons.send_outlined),
            label:const Text('Generar invitación DEMO')),
        ],
      ),
    ));
    return approved==true;
  }

  Future<void> _invite()async{
    if(_sending||_data==null||_data!['canInvite']!=true)return;
    final recipient=Map<String,dynamic>.from(_data!['patient'] as Map);
    if(!await _confirmRecipient(recipient)||!mounted)return;
    setState((){_sending=true;_error=null;});
    try{
      final response=await widget.api.silPortalRequest(
        '/portal/patients/${widget.patientId}/invitations',
        body:{'contactConfirmed':true,'identityChecked':true});
      if(!mounted)return;
      await _showHandoff(response);
      if(mounted)_load();
    }on AuthFailure catch(e){
      if(e.status==401){widget.onExpired();return;}
      if(mounted)setState(()=>_error=e.message);
    }catch(_){
      if(mounted)setState(()=>_error='No fue posible generar la invitación.');
    }finally{if(mounted)setState(()=>_sending=false);}
  }

  Future<void> _showHandoff(Map<String,dynamic> response)async{
    final token=response['handoffCode'] as String;
    final recipient=Map<String,dynamic>.from(response['recipient'] as Map);
    await showDialog<void>(context:context,barrierDismissible:false,
      builder:(context)=>AlertDialog(
        title:const Text('Invitación generada para DEMO'),
        content:SizedBox(width:460,
          child:Column(mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('La entrega del correo se simula en este entorno. '
                'Entrega el siguiente comprobante por separado al paciente '
                'después de corroborar su identidad:'),
              const SizedBox(height:12),
              Text('${recipient['givenNames']} ${recipient['familyNames']}',
                style:const TextStyle(fontWeight:FontWeight.bold)),
              Text('ID ${recipient['syntheticIdentifier']} · '
                '${recipient['email']}',style:const TextStyle(fontSize:12)),
              const SizedBox(height:14),
              Container(
                width:double.infinity,padding:const EdgeInsets.all(16),
                decoration:BoxDecoration(color:ColoresVitalia.azulSuave,
                  borderRadius:BorderRadius.circular(12)),
                child:Column(children:[
                  const Text('CLAVE DE ENTREGA PRESENCIAL',
                    style:TextStyle(fontSize:11,letterSpacing:1)),
                  const SizedBox(height:8),
                  SelectableText(token,
                    style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700)),
                  const SizedBox(height:8),
                  TextButton.icon(
                    onPressed:()=>Clipboard.setData(ClipboardData(text:token)),
                    icon:const Icon(Icons.copy,size:17),
                    label:const Text('Copiar clave de entrega')),
                ]),
              ),
              const SizedBox(height:12),
              const Text('Visible una sola vez. No envíes ambas claves por '
                'el mismo canal ni guardes este código en observaciones. '
                'Se solicitará otra clave desde el buzón DEMO.',
                style:TextStyle(fontSize:12,color:_muted)),
            ]),
        )),
        actions:[
          FilledButton(onPressed:()=>Navigator.pop(context),
            child:const Text('Entendido y entregado')),
        ],
      ));
  }

  @override Widget build(BuildContext context){
    final colors=Theme.of(context).colorScheme;
    final p=(_data?['patient'] as Map?)?.cast<String,dynamic>();
    final status=p?['portalStatus'] as String?;
    final canInvite=_data?['canInvite']==true;
    return Container(
      decoration:BoxDecoration(
        color:Colors.white,borderRadius:BorderRadius.circular(16),
        border:Border.all(color:ColoresVitalia.borde)),
      child:Padding(padding:const EdgeInsets.all(17),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            Container(padding:const EdgeInsets.all(10),
              decoration:BoxDecoration(color:ColoresVitalia.azulSuave,
                borderRadius:BorderRadius.circular(11)),
              child:const Icon(Icons.shield_outlined,
                color:ColoresVitalia.azul,size:22)),
            const SizedBox(width:10),
            const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Text('Acceso al portal',
                  style:TextStyle(fontSize:17,fontWeight:FontWeight.w700,color:_ink)),
                Text('Identidad · Entrega · Activación',
                  style:TextStyle(fontSize:11,color:_muted)),
              ])),
            if(!_loading)IconButton(
              tooltip:'Actualizar estado de acceso',
              icon:const Icon(Icons.refresh,size:19),
              onPressed:_sending?null:_load),
          ]),
          const SizedBox(height:14),
          if(_loading)const LinearProgressIndicator()
          else if(_error!=null && p==null)
            Text(_error!,style:TextStyle(color:colors.error))
          else if(p!=null)...[
            Wrap(spacing:6,runSpacing:7,children:[
              Container(
                padding:const EdgeInsets.symmetric(horizontal:11,vertical:6),
                decoration:BoxDecoration(color:_stateFill(status),
                  borderRadius:BorderRadius.circular(20)),
                child:Text(_stateLabel(status),style:TextStyle(
                  color:_stateColor(status),fontWeight:FontWeight.w700,fontSize:12))),
              if(status==null)
                const Text('Cuenta anterior sin invitación pendiente',
                  style:TextStyle(fontSize:12,color:_muted)),
            ]),
            const SizedBox(height:12),
            Wrap(spacing:9,runSpacing:8,children:[
              _stage(1,'Ficha',true,false),
              _stage(2,'Invitación',
                status=='invited'||status=='active',status=='pending'),
              _stage(3,'Activación',status=='active',status=='invited'),
            ]),
            const Divider(height:23,color:_border),
            const Text('DESTINATARIO',
              style:TextStyle(color:_muted,fontWeight:FontWeight.bold,
                fontSize:10,letterSpacing:1.1)),
            const SizedBox(height:10),
            _detail('Nombre completo',
              '${p['givenNames']??''} ${p['familyNames']??''}',
              icon:Icons.person_outline),
            _detail('Identificador ficticio',
              '${p['syntheticIdentifier']??'—'}',icon:Icons.badge_outlined),
            _detail('Nacimiento ficticio',
              '${p['birthDate']??'—'}',icon:Icons.cake_outlined),
            _detail('Correo al que se enviaría',
              '${p['email']??'—'}',icon:Icons.alternate_email),
            const Divider(height:17,color:_border),
            _detail('Correo corroborado por operador',
              _date(p['contactConfirmedAt']),icon:Icons.mark_email_read_outlined),
            _detail('Identidad corroborada por operador',
              _date(p['identityCheckedAt']),icon:Icons.verified_user_outlined),
            if(status=='invited')...[
              _detail('Última invitación / vence',
                '${_date(p['invitedAt'])} / ${_date(p['expiresAt'])}',
                icon:Icons.schedule),
              const Padding(padding:EdgeInsets.only(bottom:8),
                child:Text('La activación requiere el código del correo '
                  'y la clave de entrega presencial.',
                  style:TextStyle(color:_muted,fontSize:12))),
            ],
            if(status=='active')
              const Padding(padding:EdgeInsets.only(bottom:8),
                child:Text('La cuenta está activada. No es necesario reenviar '
                  'credenciales ni compartir contraseñas.',
                  style:TextStyle(color:Color(0xFF23634F),fontSize:12))),
            if(status==null)
              const Padding(padding:EdgeInsets.only(bottom:8),
                child:Text('Cuenta preexistente: no se altera su contraseña. '
                  'Esta activación sólo aplica a pacientes dados de alta '
                  'con el flujo nuevo.',style:TextStyle(color:_muted,fontSize:12))),
            const SizedBox(height:8),
            FilledButton.icon(
              onPressed:canInvite&&!_sending?_invite:null,
              icon:_sending?const SizedBox(width:16,height:16,
                child:CircularProgressIndicator(strokeWidth:2)):
                const Icon(Icons.mark_email_unread_outlined),
              label:Text(status=='invited'
                ?'Renovar invitación DEMO':'Preparar invitación DEMO'),
            ),
            if(!canInvite)
              Padding(padding:const EdgeInsets.only(top:7),
                child:Text(status=='active'
                  ?'Acceso ya activado.'
                  :'Esta cuenta no puede recibir una invitación en el flujo DEMO.',
                  style:const TextStyle(fontSize:12,color:_muted))),
            if(_error!=null)
              Padding(padding:const EdgeInsets.only(top:10),
                child:Text(_error!,style:TextStyle(color:colors.error))),
            const SizedBox(height:8),
            const Text('Solo DEMO · No envía correos reales ni '
              'certifica identidad clínica automáticamente.',
              style:TextStyle(fontSize:11,color:_muted)),
          ],
        ]),
      )),
    );
  }
}
