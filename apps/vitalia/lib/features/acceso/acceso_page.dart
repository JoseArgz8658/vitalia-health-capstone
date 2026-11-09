import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import 'credenciales_paciente.dart';
import 'recuperar_portal_sil_page.dart';
import 'registro_page.dart';
import '../perfil/contrasena_profesional_page.dart';

const _silMainMode = bool.fromEnvironment('VITALIA_SIL_MAIN_MODE');

class AccesoPage extends StatefulWidget {
  const AccesoPage({
    super.key,
    this.api,
    this.onAuthenticated,
    this.notice,
    this.adminMode = false,
    this.laboratoryMode = false,
  });
  final AuthApi? api;
  final bool adminMode;
  final bool laboratoryMode;
  final String? notice;
  final ValueChanged<Map<String, dynamic>>? onAuthenticated;
  @override
  State<AccesoPage> createState() => _AccesoPageState();
}

class _AccesoPageState extends State<AccesoPage> {
  final _form = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _busy = false;
  bool _professionalMode = false;
  bool _ocultar = true;
  String? _error;
  bool get _patientMode =>
      !widget.adminMode && !widget.laboratoryMode && !_professionalMode;

  Future<void> _openPatientAccess(Widget page) async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted && email != null) {
      setState(() {
        _correo.text = email;
        _clave.clear();
        _ocultar = true;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.api == null) {
      setState(() => _error = 'El servicio de acceso no está configurado.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.api!.login(
        _correo.text,
        _clave.text,
        mode: widget.laboratoryMode
            ? 'operador_laboratorio'
            : widget.adminMode
                ? 'administrador'
                : _professionalMode
                    ? 'profesional'
                    : 'paciente',
      );
      if (mounted) widget.onAuthenticated?.call(user);
    } on ProfessionalPasswordSetupRequired catch (e) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ContrasenaProfesionalPage(api: widget.api!, setupToken: e.token),
        ),
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        _clave.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/branding/vitalia-fondo-acceso.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const Positioned.fill(child: ColoredBox(color: Color(0x33FFFFFF))),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: 500,
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(
                          MediaQuery.sizeOf(context).width < 420 ? 20 : 32,
                        ),
                        child: Form(
                          key: _form,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Image.asset(
                                'assets/branding/vitalia-simbolo.png',
                                height: 112,
                                semanticLabel: 'Símbolo de Vitalia Health',
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Vitalia Health',
                                textAlign: TextAlign.center,
                                style:
                                    Theme.of(context).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Tus exámenes, en un solo lugar',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                silPatientDemo && _patientMode
                                    ? 'Accede a los informes que el laboratorio publicó para ti.'
                                    : 'Inicia sesión para consultar tus documentos y su revisión profesional.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.laboratoryMode
                                    ? 'Acceso del laboratorio'
                                    : widget.adminMode
                                        ? 'Acceso de administración'
                                        : _professionalMode
                                            ? 'Acceso de profesionales'
                                            : 'Acceso de pacientes',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (!silPatientDemo &&
                                  !widget.adminMode &&
                                  !widget.laboratoryMode)
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                            _professionalMode =
                                                !_professionalMode;
                                            _clave.clear();
                                            _error = null;
                                          }),
                                  icon: const Icon(Icons.swap_horiz),
                                  label: Text(
                                    _professionalMode
                                        ? 'Cambiar a modo paciente'
                                        : 'Cambiar a modo profesional',
                                  ),
                                ),
                              const SizedBox(height: 24),
                              if (widget.notice != null) Text(widget.notice!),
                              TextFormField(
                                controller: _correo,
                                enabled: !_busy,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Correo electrónico',
                                  prefixIcon: Icon(Icons.mail_outline),
                                ),
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                validator: (value) => validatePatientEmail(
                                    value,
                                    demo: silPatientDemo && _patientMode),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _clave,
                                enabled: !_busy,
                                obscureText: _ocultar,
                                autofillHints: const [AutofillHints.password],
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => _ocultar = !_ocultar),
                                    tooltip: _ocultar
                                        ? 'Mostrar contraseña'
                                        : 'Ocultar contraseña',
                                    icon: Icon(
                                      _ocultar
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (v) => (v ?? '').isEmpty
                                    ? 'Escribe tu contraseña.'
                                    : null,
                                onFieldSubmitted: (_) => _login(),
                              ),
                              const SizedBox(height: 16),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(_error!,
                                        style: roleStyle(context)),
                                  ),
                                ),
                              FilledButton(
                                onPressed: _busy ? null : _login,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_busy)
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    else
                                      const Icon(Icons.login),
                                    const SizedBox(width: 10),
                                    Flexible(
                                        child: Text(_busy
                                            ? 'Ingresando…'
                                            : 'Iniciar sesión')),
                                  ],
                                ),
                              ),
                              if (widget.laboratoryMode &&
                                  const bool.fromEnvironment(
                                    'VITALIA_SIL_MAIN_MODE',
                                    defaultValue:false,
                                  ))
                                Padding(
                                  padding:const EdgeInsets.only(top:10),
                                  child:TextButton.icon(
                                    onPressed:_busy
                                        ?null
                                        :()=>Navigator.of(context)
                                          .pushNamed('/activar-operador'),
                                    icon:const Icon(Icons.verified_user_outlined),
                                    label:const Text(
                                      'Activar cuenta de operador invitado',
                                    ),
                                  ),
                                ),
                              if (_patientMode) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  children: [
                                    TextButton(
                                      onPressed: _busy || widget.api == null
                                          ? null
                                          : () => _openPatientAccess(
                                              RegistroPage(api: widget.api!)),
                                      child: const Text(
                                          'Crear cuenta de paciente'),
                                    ),
                                    if (silPatientDemo || _silMainMode)
                                      TextButton(
                                        onPressed: _busy || widget.api == null
                                            ? null
                                            : () => _openPatientAccess(
                                                RecuperarPortalSilPage(
                                                    api: widget.api!,
                                                    email:
                                                        _correo.text.trim())),
                                        child:
                                            const Text('Olvidé mi contraseña'),
                                      ),
                                  ],
                                ),
                                if (silPatientDemo || _silMainMode)
                                  OutlinedButton.icon(
                                    onPressed: _busy || widget.api == null
                                        ? null
                                        : () => Navigator.of(context)
                                            .pushNamed('/activar-portal'),
                                    icon: const Icon(
                                        Icons.verified_user_outlined),
                                    label: const Text(
                                        'Activar acceso con invitación'),
                                  ),
                              ],
                              if (!widget.adminMode && !widget.laboratoryMode)
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.of(context)
                                          .pushNamed('/laboratorio'),
                                  icon: const Icon(Icons.science_outlined),
                                  label: const Text(
                                      'Acceso del personal de laboratorio'),
                                ),
                              if (!silPatientDemo && !_silMainMode)
                                TextButton(
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Recuperar acceso'),
                                      content: const Text(
                                        'La recuperación de contraseña aún no está disponible.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c),
                                          child: const Text('Entendido'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: const Text('Olvidé mi contraseña'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  TextStyle roleStyle(BuildContext context) =>
      TextStyle(color: Theme.of(context).colorScheme.error);
}
