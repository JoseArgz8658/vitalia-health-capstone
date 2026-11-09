import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';

/// Activación del operador principal por código externo de un solo uso.
class ActivarOperadorSilPage extends StatefulWidget {
  const ActivarOperadorSilPage({super.key,required this.api,this.patient=false});
  final AuthApi api;
  final bool patient;

  @override
  State<ActivarOperadorSilPage> createState()=>_ActivarOperadorSilPageState();
}

class _ActivarOperadorSilPageState extends State<ActivarOperadorSilPage>{
  final _email=TextEditingController();
  final _code=TextEditingController();
  final _password=TextEditingController();
  final _confirm=TextEditingController();
  bool _busy=false;
  bool _activated=false;
  String? _error;

  @override
  void dispose(){
    for(final item in [_email,_code,_password,_confirm]){item.dispose();}
    super.dispose();
  }

  Future<void> _activate()async{
    if(_busy||_activated)return;
    if(_password.text!=_confirm.text){
      setState(()=>_error='Las contraseñas no coinciden.');
      return;
    }
    if(_password.text.runes.length<12){
      setState(()=>_error='Utiliza una contraseña de al menos 12 caracteres.');
      return;
    }
    setState((){_busy=true;_error=null;});
    try{
      await widget.api.silMainActivateOperator(
        email:_email.text.trim(),code:_code.text.trim(),
        password:_password.text,patient:widget.patient,
      );
      if(mounted)setState(()=>_activated=true);
    }on AuthFailure catch(error){
      if(mounted)setState(()=>_error=error.message);
    }catch(_){
      if(mounted)setState(()=>_error='No fue posible completar la activación.');
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(
        title:Text(widget.patient ? 'Vitalia Health · Pacientes' : 'Vitalia Health · Acceso al laboratorio'),
        leading:IconButton(
          tooltip:'Volver',
          icon:const Icon(Icons.arrow_back),
          onPressed:()=>Navigator.of(context).pop(),
        ),
      ),
      body:SafeArea(
        child:SingleChildScrollView(
          padding:const EdgeInsets.all(20),
          child:Center(
            child:ConstrainedBox(
              constraints:const BoxConstraints(maxWidth:510),
              child:Card(
                child:Padding(
                  padding:const EdgeInsets.all(24),
                  child:Column(
                    crossAxisAlignment:CrossAxisAlignment.stretch,
                    children:[
                      const Icon(Icons.verified_user_outlined,
                        color:ColoresVitalia.azul,size:46),
                      const SizedBox(height:15),
                      Text(
                        _activated ? 'Acceso activado' : widget.patient ? 'Activar acceso de paciente' : 'Activar acceso de operador',
                        textAlign:TextAlign.center,
                        style:Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight:FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height:9),
                      Text(
                        _activated
                          ?'Ya puedes iniciar sesión '
                           'con tu correo y la contraseña configurada.'
                          :'Ingresa el correo y el código personal que '
                           'recibiste por un canal oficial del laboratorio. '
                           'El código solo puede utilizarse una vez.',
                        textAlign:TextAlign.center,
                        style:const TextStyle(
                          color:ColoresVitalia.textoSecundario,height:1.5,
                        ),
                      ),
                      const SizedBox(height:20),
                      if(!_activated)...[
                        TextField(
                          controller:_email,
                          enabled:!_busy,
                          keyboardType:TextInputType.emailAddress,
                          decoration:const InputDecoration(
                            labelText:'Correo institucional',
                            border:OutlineInputBorder(),
                            prefixIcon:Icon(Icons.alternate_email),
                          ),
                        ),
                        const SizedBox(height:12),
                        TextField(
                          controller:_code,
                          enabled:!_busy,
                          decoration:const InputDecoration(
                            labelText:'Código de invitación',
                            border:OutlineInputBorder(),
                            prefixIcon:Icon(Icons.key_outlined),
                          ),
                        ),
                        const SizedBox(height:12),
                        TextField(
                          controller:_password,
                          enabled:!_busy,
                          obscureText:true,
                          decoration:const InputDecoration(
                            labelText:'Contraseña nueva (mín. 12 caracteres)',
                            border:OutlineInputBorder(),
                            prefixIcon:Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height:12),
                        TextField(
                          controller:_confirm,
                          enabled:!_busy,
                          obscureText:true,
                          decoration:const InputDecoration(
                            labelText:'Confirmar contraseña',
                            border:OutlineInputBorder(),
                            prefixIcon:Icon(Icons.lock_outline),
                          ),
                        ),
                      ],
                      if(_error!=null)...[
                        const SizedBox(height:12),
                        Text(_error!,textAlign:TextAlign.center,
                          style:TextStyle(color:Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height:20),
                      if(_busy)const LinearProgressIndicator(),
                      FilledButton.icon(
                        onPressed:_busy?null:_activated
                            ?()=>Navigator.of(context).pop()
                            :_activate,
                        icon:Icon(_activated?Icons.login:Icons.verified_outlined),
                        label:Text(_activated?'Ir al inicio de sesión':'Activar acceso'),
                      ),
                      const SizedBox(height:12),
                      const Text(
                        'Por seguridad, no compartas el código ni tu contraseña. '
                        'Si la invitación expira, solicita otra al administrador.',
                        textAlign:TextAlign.center,
                        style:TextStyle(fontSize:12,
                          color:ColoresVitalia.textoSecundario),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
