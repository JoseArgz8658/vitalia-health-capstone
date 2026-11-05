import '../features/incorporacion/activar_invitacion_page.dart';
import '../features/asignaciones/asignaciones_page.dart';
import '../features/perfil/perfil_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/tema_vitalia.dart';
import '../core/auth_api.dart';
import '../features/acceso/acceso_page.dart';
import '../features/documentos_reales/paciente_documentos_page.dart';

class VitaliaMvpApp extends StatefulWidget {
  const VitaliaMvpApp({super.key, this.api, this.initialRoute});
  final AuthApi? api;
  final String? initialRoute;
  @override
  State<VitaliaMvpApp> createState() => _VitaliaMvpAppState();
}

class _VitaliaMvpAppState extends State<VitaliaMvpApp>
    with WidgetsBindingObserver {
  late final AuthApi _api;
  Map<String, dynamic>? _user;
  Timer? _expiration;
  String? _message;
  bool _busy = false;
  final _navigator = GlobalKey<NavigatorState>();
  String? _accessNotice;
  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AuthApi();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiration?.cancel();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  void _signedIn(Map<String, dynamic> user) {
    _expiration?.cancel();
    final remaining = _api.expiresAt!.difference(DateTime.now());
    _expiration = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _expired,
    );
    setState(() {
      _user = user;
      _message = null;
      _accessNotice = null;
    });
  }

  void _expired() {
    _expiration?.cancel();
    _api.clear();
    _navigator.currentState?.popUntil((route) => route.isFirst);
    if (mounted)
      setState(() {
        _user = null;
        _message = null;
      });
  }

  void _openProfile() {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => PerfilPage(
          api: _api,
          onExpired: _expired,
          isPatient: _user?['role'] == 'paciente',
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _user != null) _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = await _api.me();
      if (mounted)
        setState(() {
          _user = user;
          _message = null;
        });
    } on AuthFailure catch (e) {
      if (e.status == 401 || !_api.hasSession) {
        _expired();
      } else if (mounted) {
        setState(() => _message = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? notice;
    try {
      await _api.logout();
    } on AuthFailure {
      notice =
          'Sesión cerrada en este dispositivo. No se pudo confirmar el cierre '
          'en el servidor; el token vencerá automáticamente.';
    } finally {
      _expired();
      if (mounted)
        setState(() {
          _busy = false;
          _accessNotice = notice;
        });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'Vitalia Health',
    debugShowCheckedModeBanner: false,
    theme: temaVitalia(),
    initialRoute: widget.initialRoute,
    onGenerateRoute: (settings) {
      if (settings.name == '/activar-invitacion')
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ActivarInvitacionPage(api: AuthApi(), ownsApi: true),
        );
      if (settings.name == '/administracion')
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => AccesoPage(
            api: _api,
            adminMode: true,
            onAuthenticated: (user) {
              _signedIn(user);
              _navigator.currentState?.popUntil((r) => r.isFirst);
            },
          ),
        );
      return null;
    },
    home: _user == null
        ? AccesoPage(
            api: _api,
            onAuthenticated: _signedIn,
            notice: _accessNotice,
          )
        : _user!['role'] == 'paciente'
        ? PacienteDocumentosPage(
            key: ValueKey(_user!['id']),
            api: _api,
            email: _user!['email'] as String,
            onExpired: _expired,
            onLogout: _logout,
            sessionBusy: _busy,
            onProfile: _openProfile,
          )
        : AsignacionesPage(
            key: ValueKey(_user!['id']),
            auth: _api,
            email: _user!['email'] as String,
            role: _user!['role'] as String,
            onExpired: _expired,
            onLogout: _logout,
            sessionBusy: _busy,
            notice: _message,
            onProfile: _user!['role'] == 'profesional' ? _openProfile : null,
          ),
  );
}
