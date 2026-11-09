import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';

/// Proceso de activación con dos códigos independientes y contraseña privada.
/// El buzón visible sólo existe con VITALIA_SIL_DEMO_MODE=true.
class ActivarPortalSilPage extends StatefulWidget {
  const ActivarPortalSilPage({super.key, required this.api});
  final AuthApi api;
  @override
  State<ActivarPortalSilPage> createState() => _ActivarPortalSilPageState();
}

class _ActivarPortalSilPageState extends State<ActivarPortalSilPage> {
  static const _demo =
      bool.fromEnvironment('VITALIA_SIL_DEMO_MODE', defaultValue: false);
  final _email = TextEditingController();
  final _emailCode = TextEditingController();
  final _handoffCode = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  int _step = 0;
  bool _busy = false;
  bool _obscure = true;
  bool _confirm = false;
  bool _completed = false;
  String? _error;
  String? _verifiedEmail;
  @override
  void dispose() {
    for (final c in [_email, _emailCode, _handoffCode, _password, _repeat]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  String get _address => _email.text.trim().toLowerCase();
  bool get _hasEmail =>
      _address.length <= 254 &&
      RegExp(r'^[^\s@]+@example\.invalid$').hasMatch(_address);
  void _showStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step = step;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _nextEmail() {
    if (_busy || _step != 0) return;
    if (!_hasEmail) {
      setState(() => _error = 'Ingresa el correo ficticio indicado '
          'en la invitación del laboratorio.');
      return;
    }
    if (_verifiedEmail != _address) {
      _verifiedEmail = _address;
      _emailCode.clear();
      _handoffCode.clear();
      _password.clear();
      _repeat.clear();
      _confirm = false;
      _obscure = true;
    }
    _showStep(1);
  }

  Future<void> _readDemoInbox() async {
    if (_busy || _step != 1 || !_hasEmail) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.api.silPortalPublic(
          '/portal/demo-mailbox?email=${Uri.encodeQueryComponent(_address)}');
      if (!mounted) return;
      final code = response['emailCode'] as String?;
      if (code == null) {
        setState(() => _error = 'No hay un mensaje de invitación DEMO vigente. '
            'Solicita uno al operador.');
      } else {
        setState(() => _busy = false);
        final useCode = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            scrollable: true,
            title: const Row(children: [
              Icon(Icons.mark_email_read_outlined, color: ColoresVitalia.azul),
              SizedBox(width: 9),
              Expanded(child: Text('Correo de activación DEMO')),
            ]),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${response['subject'] ?? 'Invitación de Vitalia'}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(height: 20),
                    Text('${response['guidance'] ?? ''}'),
                    const SizedBox(height: 14),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: ColoresVitalia.azulSuave,
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(children: [
                          const Text('TU CÓDIGO DE CORREO',
                              style: TextStyle(fontSize: 11, letterSpacing: 1)),
                          const SizedBox(height: 6),
                          SelectableText(code,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 19)),
                        ])),
                    const SizedBox(height: 10),
                    const Text(
                        'Buzón local simulado: no se envió ningún email real.',
                        style: TextStyle(
                            fontSize: 12,
                            color: ColoresVitalia.textoSecundario)),
                  ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cerrar')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Usar código de correo')),
            ],
          ),
        );
        if (mounted && _step == 1 && useCode == true) _emailCode.text = code;
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _nextCodes() {
    if (_busy || _step != 1) return;
    final valid = RegExp(r'^[A-Za-z0-9_-]{12}$');
    if (!valid.hasMatch(_emailCode.text.trim()) ||
        !valid.hasMatch(_handoffCode.text.trim())) {
      setState(() => _error = 'Debes ingresar ambos códigos '
          'de 12 caracteres de sus respectivos canales.');
      return;
    }
    _showStep(2);
  }

  Future<void> _activate() async {
    if (_busy ||
        _step != 2 ||
        !(_formKey.currentState?.validate() ?? false) ||
        !_confirm) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response =
          await widget.api.silPortalPublic('/portal/activate', body: {
        'email': _address,
        'emailCode': _emailCode.text.trim(),
        'handoffCode': _handoffCode.text.trim(),
        'password': _password.text,
        'confirmedDetails': true,
      });
      if (!mounted) return;
      if (response['activated'] == true) {
        _password.clear();
        _repeat.clear();
        _emailCode.clear();
        _handoffCode.clear();
        _completed = true;
        _showStep(3);
      } else {
        setState(() =>
            _error = 'No se pudo confirmar la activación. Intenta nuevamente.');
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _progress() {
    const labels = ['Cuenta', 'Verificación', 'Contraseña'];
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0)
          Container(
              width: 12,
              height: 2,
              color: _step >= i ? ColoresVitalia.verde : ColoresVitalia.borde),
        Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
              radius: 16,
              backgroundColor: _step > i
                  ? ColoresVitalia.verdeSuave
                  : _step == i
                      ? ColoresVitalia.azul
                      : ColoresVitalia.fondoAzul,
              child: _step > i
                  ? const Icon(Icons.check,
                      size: 18, color: ColoresVitalia.verde)
                  : Text('${i + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _step == i
                              ? Colors.white
                              : ColoresVitalia.textoSecundario))),
          const SizedBox(height: 7),
          Semantics(
              selected: _step == i,
              child: Text(labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          _step == i ? FontWeight.bold : FontWeight.w500,
                      color: ColoresVitalia.textoSecundario))),
        ])),
      ],
    ]);
  }

  Widget _helper(IconData icon, String title, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: ColoresVitalia.azulSuave,
          borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: ColoresVitalia.azul, size: 22),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: ColoresVitalia.azulActivo,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 3),
          Text(text,
              style: const TextStyle(
                  color: ColoresVitalia.textoSecundario, fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _emailStep() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Activa tu acceso privado',
            style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: ColoresVitalia.texto)),
        const SizedBox(height: 8),
        const Text(
            'Tu ficha del laboratorio ya existe. '
            'Comprueba el correo al que recibiste la invitación. '
            'La cuenta web se activará cuando completes la verificación.',
            style: TextStyle(color: ColoresVitalia.textoSecundario)),
        const SizedBox(height: 22),
        TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _nextEmail(),
            decoration: const InputDecoration(
                labelText: 'Correo de contacto',
                prefixIcon: Icon(Icons.alternate_email),
                hintText: 'paciente-demo@example.invalid')),
        const SizedBox(height: 14),
        _helper(
            Icons.lock_person_outlined,
            'Tu información permanece protegida',
            'Este proceso no envía ni muestra resultados clínicos. '
                'Un correo conocido no concede acceso por sí solo.'),
        _feedback(),
        const SizedBox(height: 20),
        FilledButton.icon(
            onPressed: _busy ? null : _nextEmail,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continuar')),
      ]);

  Widget _codesStep() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Comprueba los dos canales',
            style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: ColoresVitalia.texto)),
        const SizedBox(height: 8),
        Text('Cuenta: $_address',
            style: const TextStyle(color: ColoresVitalia.textoSecundario)),
        const SizedBox(height: 18),
        _helper(
            Icons.mark_email_read_outlined,
            'Paso A · Código de correo',
            'Introduce el código temporal recibido por email. '
                'En este prototipo el correo se simula de manera local.'),
        const SizedBox(height: 11),
        TextField(
            controller: _emailCode,
            enabled: !_busy,
            maxLength: 12,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
                labelText: 'Código recibido por correo',
                counterText: '',
                prefixIcon: Icon(Icons.mail_outline))),
        if (_demo) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
              onPressed: _busy ? null : _readDemoInbox,
              icon: const Icon(Icons.markunread_mailbox_outlined),
              label: const Text('Abrir buzón ficticio de prueba')),
          if (_busy) const LinearProgressIndicator(),
        ],
        const SizedBox(height: 13),
        _helper(
            Icons.badge_outlined,
            'Paso B · Clave entregada en el laboratorio',
            'Introduce la clave que recibiste por un canal distinto, '
                'tras la comprobación presencial de identidad.'),
        const SizedBox(height: 11),
        TextField(
            controller: _handoffCode,
            enabled: !_busy,
            maxLength: 12,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
                labelText: 'Clave de entrega presencial',
                counterText: '',
                prefixIcon: Icon(Icons.verified_user_outlined))),
        _feedback(),
        const SizedBox(height: 18),
        _stepActions(
          previous: 0,
          primary: FilledButton.icon(
              onPressed: _busy ? null : _nextCodes,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continuar')),
        ),
      ]);

  Widget _passwordStep() => Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tu acceso, tu contraseña',
              style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: ColoresVitalia.texto)),
          const SizedBox(height: 8),
          const Text(
              'El laboratorio no puede conocer ni recuperar tu nueva '
              'contraseña. Crea una que no utilices en otros servicios.',
              style: TextStyle(color: ColoresVitalia.textoSecundario)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _password,
            enabled: !_busy,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
                labelText: 'Nueva contraseña',
                prefixIcon: const Icon(Icons.password_outlined),
                suffixIcon: IconButton(
                    tooltip:
                        _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined)),
                helperText:
                    'Al menos 12 caracteres. Utiliza una contraseña única.',
                helperMaxLines: 2),
            validator: (value) {
              final password = value ?? '';
              if (password.runes.length < 12)
                return 'Utiliza al menos 12 caracteres.';
              if (utf8.encode(password).length > 1024)
                return 'La contraseña es demasiado larga.';
              return null;
            },
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: _repeat,
            enabled: !_busy,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
                labelText: 'Repetir contraseña',
                prefixIcon: Icon(Icons.verified_outlined)),
            validator: (v) =>
                v == _password.text ? null : 'Las contraseñas no coinciden.',
          ),
          const SizedBox(height: 13),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirm,
            onChanged:
                _busy ? null : (v) => setState(() => _confirm = v ?? false),
            title: const Text('Confirmo que este acceso es para mi cuenta '
                'y que los datos proporcionados para la invitación me corresponden.'),
            subtitle: const Text('Si los datos son incorrectos, contacta al '
                'laboratorio. No actives una cuenta ajena.'),
          ),
          const SizedBox(height: 14),
          _helper(
              Icons.privacy_tip_outlined,
              'Privacidad por diseño',
              'Solo verás los informes publicados para tu cuenta. '
                  'Las solicitudes internas no aparecen en el portal.'),
          _feedback(),
          const SizedBox(height: 18),
          _stepActions(
            previous: 1,
            primary: FilledButton.icon(
                onPressed: _busy || !_confirm ? null : _activate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_user_outlined),
                label: Text(_busy ? 'Activando…' : 'Activar mi cuenta')),
          ),
        ],
      ));
  Widget _stepActions({required int previous, required Widget primary}) =>
      OverflowBar(
        spacing: 12,
        overflowSpacing: 8,
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        children: [
          TextButton.icon(
              onPressed: _busy ? null : () => _showStep(previous),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver')),
          primary,
        ],
      );
  Widget _feedback() {
    final error = _error;
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: ColoresVitalia.errorSuave,
                borderRadius: BorderRadius.circular(10)),
            child: Text(error,
                style: const TextStyle(color: ColoresVitalia.error)),
          )),
    );
  }

  Widget _success() => Column(children: [
        Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: ColoresVitalia.verdeSuave),
            child: const Icon(Icons.check_circle_outline,
                size: 54, color: ColoresVitalia.verde)),
        const SizedBox(height: 18),
        const Text('Cuenta activada',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: ColoresVitalia.texto)),
        const SizedBox(height: 10),
        const Text(
            'La contraseña ya fue creada. '
            'Vuelve al inicio de sesión para consultar los informes '
            'que el laboratorio haya publicado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ColoresVitalia.textoSecundario)),
        const SizedBox(height: 22),
        FilledButton.icon(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            icon: const Icon(Icons.login_outlined),
            label: const Text('Ir a iniciar sesión')),
      ]);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColoresVitalia.fondoAzul,
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.favorite_border, color: ColoresVitalia.azul),
          SizedBox(width: 9),
          Flexible(child: Text('Vitalia Health')),
        ]),
      ),
      body: SafeArea(
          child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
        child: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF214B62), Color(0xFF2C777B)]),
                  borderRadius: BorderRadius.circular(15)),
              child: const Row(children: [
                Icon(Icons.shield_outlined, color: Colors.white, size: 29),
                SizedBox(width: 12),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PORTAL PRIVADO DEL PACIENTE',
                        style: TextStyle(
                            color: Color(0xFFC9E9E9),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                    SizedBox(height: 4),
                    Text('Activación de acceso',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              color: Colors.white,
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_completed) ...[
                          _progress(),
                          const Divider(height: 31),
                        ],
                        AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: KeyedSubtree(
                              key: ValueKey(_step),
                              child: switch (_step) {
                                0 => _emailStep(),
                                1 => _codesStep(),
                                2 => _passwordStep(),
                                _ => _success(),
                              }),
                        ),
                      ])),
            ),
            const SizedBox(height: 14),
            Text(
                _demo
                    ? 'ENTORNO DEMO · Solo cuentas ficticias. El buzón es simulado y no envía correos reales.'
                    : 'La activación debe iniciarse desde una invitación emitida por el laboratorio.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ColoresVitalia.textoSecundario, fontSize: 12)),
          ]),
        )),
      )),
    );
  }
}
