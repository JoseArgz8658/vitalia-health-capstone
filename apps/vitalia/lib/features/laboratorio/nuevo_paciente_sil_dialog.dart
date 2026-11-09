import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';

/// Alta separada de la habilitación del portal. La contraseña privada sólo
/// podrá configurarla el paciente al completar su invitación DEMO.
class NuevoPacienteSilDialog extends StatefulWidget {
  const NuevoPacienteSilDialog({super.key,required this.api});
  final AuthApi api;
  @override State<NuevoPacienteSilDialog> createState()=>
      _NuevoPacienteSilDialogState();
}
class _NuevoPacienteSilDialogState extends State<NuevoPacienteSilDialog>{
  final _key=GlobalKey<FormState>();
  final _email=TextEditingController();
  final _names=TextEditingController();
  final _family=TextEditingController();
  final _birth=TextEditingController();
  String _sex='not_specified';
  bool _syntheticConfirmed=false;
  bool _busy=false;
  String? _error;
  @override void dispose(){
    for(final c in [_email,_names,_family,_birth]){c.dispose();}
    super.dispose();
  }
  String? _validBirth(String? value){
    final text=(value??'').trim();
    final date=DateTime.tryParse(text);
    if(!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)||
      date==null||date.toIso8601String().substring(0,10)!=text||
      text.compareTo('1900-01-01')<0||
      text.compareTo(DateTime.now().toIso8601String().substring(0,10))>0){
      return 'Utiliza una fecha ficticia válida: AAAA-MM-DD.';
    }
    return null;
  }
  Future<void> _save()async{
    if(_busy||!(_key.currentState?.validate()??false)||
       !_syntheticConfirmed)return;
    setState((){_busy=true;_error=null;});
    try{
      final result=await widget.api.silPortalRequest(
        '/portal/patients',body:{
          'email':_email.text.trim().toLowerCase(),
          'givenNames':_names.text.trim(),
          'familyNames':_family.text.trim(),
          'birthDate':_birth.text.trim(),
          'sexForReference':_sex,
          'syntheticConfirmed':true,
        });
      if(mounted)Navigator.of(context).pop(result);
    }on AuthFailure catch(e){
      if(mounted)setState(()=>_error=e.message);
    }catch(_){
      if(mounted)setState(()=>_error='No fue posible registrar la ficha DEMO.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Dialog(
    insetPadding:const EdgeInsets.all(16),
    child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:570),
      child:SingleChildScrollView(
        padding:const EdgeInsets.all(22),
        child:Form(key:_key,child:Column(
          mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Row(children:[
              Container(padding:const EdgeInsets.all(12),
                decoration:BoxDecoration(color:ColoresVitalia.azulSuave,
                  borderRadius:BorderRadius.circular(13)),
                child:const Icon(Icons.person_add_alt_1_outlined,
                  color:ColoresVitalia.azul,size:26)),
              const SizedBox(width:12),
              const Expanded(child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('Nuevo paciente DEMO',style:TextStyle(
                    fontSize:20,fontWeight:FontWeight.bold,
                    color:ColoresVitalia.texto)),
                  Text('Ficha primero · Activación después',
                    style:TextStyle(fontSize:12,
                      color:ColoresVitalia.textoSecundario)),
                ])),
              IconButton(onPressed:_busy?null:()=>Navigator.pop(context),
                icon:const Icon(Icons.close),tooltip:'Cerrar'),
            ]),
            const SizedBox(height:15),
            Container(padding:const EdgeInsets.all(12),
              decoration:BoxDecoration(color:ColoresVitalia.fondoAzul,
                borderRadius:BorderRadius.circular(11)),
              child:const Row(children:[
                Icon(Icons.info_outline,color:ColoresVitalia.azul),
                SizedBox(width:9),
                Expanded(child:Text('Solo identidades inventadas y correos '
                  '@example.invalid. La nueva cuenta no puede iniciar sesión '
                  'hasta completar la activación de dos canales.',
                  style:TextStyle(fontSize:12))),
              ]),
            ),
            const SizedBox(height:16),
            TextFormField(controller:_names,maxLength:100,
              decoration:const InputDecoration(labelText:'Nombres ficticios',
                prefixIcon:Icon(Icons.person_outline),counterText:''),
              validator:(v)=>(v??'').trim().length<2?
                'Ingresa al menos 2 caracteres.':null),
            const SizedBox(height:9),
            TextFormField(controller:_family,maxLength:100,
              decoration:const InputDecoration(labelText:'Apellidos ficticios',
                prefixIcon:Icon(Icons.badge_outlined),counterText:''),
              validator:(v)=>(v??'').trim().length<2?
                'Ingresa al menos 2 caracteres.':null),
            const SizedBox(height:9),
            TextFormField(controller:_birth,validator:_validBirth,
              decoration:const InputDecoration(
                labelText:'Nacimiento ficticio (AAAA-MM-DD)',
                prefixIcon:Icon(Icons.calendar_today_outlined),
                hintText:'1990-01-01')),
            const SizedBox(height:9),
            DropdownButtonFormField<String>(
              initialValue:_sex,
              decoration:const InputDecoration(
                labelText:'Sexo para referencias DEMO',
                prefixIcon:Icon(Icons.assignment_ind_outlined)),
              items:const [
                DropdownMenuItem(value:'not_specified',
                  child:Text('No especificado')),
                DropdownMenuItem(value:'female',child:Text('Femenino')),
                DropdownMenuItem(value:'male',child:Text('Masculino')),
              ],
              onChanged:_busy?null:(v)=>setState(()=>_sex=v??'not_specified'),
            ),
            const SizedBox(height:9),
            TextFormField(controller:_email,
              keyboardType:TextInputType.emailAddress,
              decoration:const InputDecoration(labelText:'Correo ficticio',
                prefixIcon:Icon(Icons.alternate_email),
                hintText:'paciente-nuevo@example.invalid'),
              validator:(v)=>RegExp(r'^[^\s@]+@example\.invalid$')
                .hasMatch((v??'').trim().toLowerCase())?null:
                'Se requiere un correo ficticio @example.invalid.'),
            const SizedBox(height:12),
            CheckboxListTile(
              contentPadding:EdgeInsets.zero,
              controlAffinity:ListTileControlAffinity.leading,
              value:_syntheticConfirmed,
              onChanged:_busy?null:(v)=>setState(
                ()=>_syntheticConfirmed=v??false),
              title:const Text('Confirmo que esta ficha contiene '
                'únicamente datos inventados para demostración.'),
            ),
            if(_error!=null)Padding(
              padding:const EdgeInsets.only(bottom:10),
              child:Text(_error!,style:const TextStyle(
                color:ColoresVitalia.error))),
            const SizedBox(height:10),
            Wrap(alignment:WrapAlignment.end,spacing:10,runSpacing:6,
              children:[
                TextButton(onPressed:_busy?null:()=>Navigator.pop(context),
                  child:const Text('Cancelar')),
                FilledButton.icon(
                  onPressed:_busy||!_syntheticConfirmed?null:_save,
                  icon:_busy?const SizedBox(width:18,height:18,
                    child:CircularProgressIndicator(strokeWidth:2)):
                    const Icon(Icons.save_outlined),
                  label:Text(_busy?'Creando ficha…':'Crear ficha sin activar'),
                ),
              ]),
          ],
        )),
      )),
  );
}
