import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../core/auth_api.dart';
import '../perfil/ubicacion_panel.dart';
import 'documentos_api.dart';

class SubirDocumentoForm extends StatefulWidget {
  const SubirDocumentoForm({
    super.key,
    required this.api,
    required this.onSaved,
    required this.onCancel,
    required this.onExpired,
  });
  final DocumentosApi api;
  final VoidCallback onSaved, onCancel, onExpired;
  @override
  State<SubirDocumentoForm> createState() => _SubirDocumentoFormState();
}

class _SubirDocumentoFormState extends State<SubirDocumentoForm> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController(), _street = TextEditingController();
  final _number = TextEditingController(), _phone = TextEditingController();
  late Future<Map<String, dynamic>> _territories;
  Map<String, dynamic>? _context, _catalog;
  final List<Map<String, dynamic>> _options = [];
  String? _residence, _zone, _clinic, _branch, _specialty, _membership, _tipo;
  DateTime? _fecha;
  XFile? _archivo;
  int? _archivoBytes, _nextOffset;
  int _step = 0, _searchVersion = 0;
  bool _busy = false, _loading = true, _searching = false;
  bool _sameZone = true,
      _saveProfile = true,
      _confirmed = false,
      _searched = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_nombre, _street, _number, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _territories = widget.api.auth.territories();
    try {
      final values = await Future.wait([
        widget.api.auth.careContext(),
        _territories,
      ]);
      if (!mounted) return;
      final data = values[0];
      setState(() {
        _context = data;
        _catalog = values[1];
        _clearChoice();
        _street.text = data['street'] as String? ?? '';
        _number.text = data['addressNumber'] as String? ?? '';
        _phone.text = data['phone'] as String? ?? '';
        _residence =
            (data['residenceCommuneCode'] ?? data['preferredCommuneCode'])
                as String?;
      });
    } on AuthFailure catch (e) {
      _failure(e);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar tus datos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _failure(AuthFailure e) {
    if (!mounted) return;
    if (e.status == 401) {
      widget.onExpired();
    } else {
      setState(() => _error = e.message);
    }
  }

  void _clearChoice() {
    _searchVersion++;
    _options.clear();
    _nextOffset = null;
    _clinic = _branch = _specialty = _membership = null;
    _searched = false;
    _searching = false;
    _confirmed = false;
  }

  String? get _consultation => _sameZone ? _residence : _zone;
  String _commune(String? code) {
    for (final item in (_catalog?['communes'] as List? ?? [])) {
      if (item['code'] == code) return item['name'] as String;
    }
    return code ?? 'Sin seleccionar';
  }

  Map<String, dynamic>? get _selected {
    for (final x in _options) {
      if (x['clinicId'] == _clinic &&
          x['branchId'] == _branch &&
          x['specialtyId'] == _specialty &&
          x['membershipId'] == _membership)
        return x;
    }
    return null;
  }

  Future<void> _search({bool more = false}) async {
    if (_searching || _consultation == null || (more && _nextOffset == null))
      return;
    final version = ++_searchVersion, commune = _consultation!;
    setState(() {
      _searching = true;
      _error = null;
      if (!more) {
        _options.clear();
        _clinic = _branch = _specialty = _membership = null;
        _nextOffset = null;
        _searched = false;
      }
    });
    try {
      final result = await widget.api.auth.careCatalog(
        commune,
        offset: more ? _nextOffset! : 0,
      );
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _options.addAll(
          (result['items'] as List).map(
            (x) => Map<String, dynamic>.from(x as Map),
          ),
        );
        _nextOffset = result['nextOffset'] as int?;
        _searched = true;
      });
    } on AuthFailure catch (e) {
      if (version == _searchVersion) _failure(e);
    } catch (_) {
      if (mounted && version == _searchVersion)
        setState(() => _error = 'No se pudo consultar la atención.');
    } finally {
      if (mounted && version == _searchVersion)
        setState(() => _searching = false);
    }
  }

  Future<void> _pick() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Exámenes',
            extensions: ['pdf', 'jpg', 'jpeg', 'png'],
            mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
            uniformTypeIdentifiers: [
              'com.adobe.pdf',
              'public.jpeg',
              'public.png',
            ],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final size = await file.length();
      if (!mounted) return;
      if (size < 1 || size > 10 * 1024 * 1024) {
        setState(() => _error = 'Elige un archivo no vacío de hasta 10 MiB.');
        return;
      }
      setState(() {
        _archivo = file;
        _archivoBytes = size;
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'No se pudo seleccionar el archivo.');
    }
  }

  Future<void> _date() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _fecha ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Fecha del examen',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (mounted && date != null) setState(() => _fecha = date);
  }

  void _next() {
    if (_busy || !_form.currentState!.validate()) return;
    String? error;
    if (_step == 0 && _residence == null)
      error = 'Selecciona la comuna de tu domicilio.';
    if (_step == 1 && _selected == null)
      error = 'Busca atención y selecciona un profesional.';
    if (_step == 2 && (_fecha == null || _archivo == null))
      error = 'Selecciona la fecha y el archivo del examen.';
    setState(() {
      _error = error;
      if (error == null) {
        _step++;
        _confirmed = false;
      }
    });
  }

  Future<void> _upload() async {
    if (_busy ||
        !_confirmed ||
        _selected == null ||
        _archivo == null ||
        _fecha == null)
      return;
    final file = _archivo!, date = _fecha!, lower = file.name.toLowerCase();
    final mime = lower.endsWith('.pdf')
        ? 'application/pdf'
        : lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.jpg') || lower.endsWith('.jpeg')
        ? 'image/jpeg'
        : null;
    if (mime == null) {
      setState(() => _error = 'Solo se permiten PDF, JPEG y PNG.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final fecha =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await widget.api.upload(
        nombre: _nombre.text,
        tipo: _tipo!,
        fecha: fecha,
        archivo: file.name,
        mime: mime,
        bytes: bytes,
        care: {
          'clinicId': _clinic,
          'branchId': _branch,
          'specialtyId': _specialty,
          'membershipId': _membership,
          'residenceCommuneCode': _residence,
          'consultationCommuneCode': _consultation,
          'street': _street.text.trim(),
          'addressNumber': _number.text.trim(),
          'phone': _phone.text.trim(),
          'profileRevision': _context!['revision'],
          'saveProfile': _saveProfile,
          'confirmed': true,
        },
      );
      if (mounted) widget.onSaved();
    } on AuthFailure catch (e) {
      _failure(e);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'No se pudo leer o subir el archivo. Actualiza el historial antes de repetir.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int max = 200,
    bool phone = false,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      maxLength: max,
      textInputAction: TextInputAction.next,
      keyboardType: phone ? TextInputType.phone : TextInputType.streetAddress,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
      ),
      validator: (v) => (v ?? '').trim().isEmpty
          ? 'Completa este dato.'
          : phone && !RegExp(r'^\+?[0-9]{8,15}$').hasMatch(v!.trim())
          ? 'Ingresa entre 8 y 15 dígitos; puedes iniciar con +.'
          : null,
    ),
  );
  Widget _location(
    String? value,
    ValueChanged<String?> changed,
    String description,
  ) => UbicacionPanel(
    api: widget.api.auth,
    value: value,
    editing: true,
    enabled: !_busy && !_searching,
    requiredLocation: true,
    locationDescription: description,
    loadCatalog: () => _territories,
    onChanged: changed,
    onExpired: widget.onExpired,
  );
  List<Widget> _contact() => [
    const Text(
      'Confirma tu domicilio y cómo contactarte. La zona para consultar se elige en el siguiente paso.',
    ),
    TextButton(
      onPressed: _busy ? null : _load,
      child: const Text('Volver a cargar mis datos del perfil'),
    ),
    const SizedBox(height: 16),
    _location(
      _residence,
      (v) => setState(() {
        _residence = v;
        _clearChoice();
      }),
      'Domicilio: selecciona región, provincia y comuna.',
    ),
    _field(
      _street,
      'Calle del domicilio',
      hint: 'Por ejemplo: Avenida Las Torres',
    ),
    _field(
      _number,
      'Número de la dirección',
      max: 40,
      hint: 'Por ejemplo: 1234',
      suffix: const Tooltip(
        message: 'Ingresa el número de tu dirección. Si no tiene, escribe S/N (sin número).',
        child: Icon(Icons.help_outline),
      ),
    ),
    _field(
      _phone,
      'Teléfono de contacto',
      phone: true,
      max: 16,
      hint: '+56912345678',
    ),
    InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Correo de tu cuenta',
        border: OutlineInputBorder(),
      ),
      child: Text(_context!['email'] as String),
    ),
    const SizedBox(height: 8),
    const Text(
      'Este correo proviene de tu cuenta. Aquí no se comprueba que reciba mensajes.',
    ),
    CheckboxListTile(
      value: _saveProfile,
      onChanged: _busy
          ? null
          : (v) => setState(() => _saveProfile = v ?? false),
      title: const Text('Guardar este domicilio y teléfono en mi perfil'),
      contentPadding: EdgeInsets.zero,
    ),
  ];
  Widget _choice(
    String label,
    String key,
    String name,
    String? value,
    List<Map<String, dynamic>> rows,
    ValueChanged<String?> changed,
  ) {
    final unique = <String, String>{
      for (final x in rows) x[key] as String: x[name] as String,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$key-$value-${unique.keys.join()}'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: unique.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: _busy || _searching || unique.isEmpty ? null : changed,
      ),
    );
  }

  List<Widget> _attention() => [
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _sameZone,
      onChanged: _searching
          ? null
          : (v) => setState(() {
              _sameZone = v;
              _clearChoice();
            }),
      title: const Text('Buscar en la comuna de mi domicilio'),
      subtitle: Text(_commune(_residence)),
    ),
    if (!_sameZone)
      _location(
        _zone,
        (v) => setState(() {
          _zone = v;
          _clearChoice();
        }),
        'Zona de atención: esta selección no cambia tu domicilio.',
      ),
    OutlinedButton.icon(
      onPressed: _searching || _consultation == null ? null : () => _search(),
      icon: const Icon(Icons.search),
      label: const Text('Buscar atención'),
    ),
    if (_searching) const LinearProgressIndicator(),
    if (_searched && _options.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No hay profesionales habilitados en esta comuna. Puedes elegir otra zona de atención.',
        ),
      ),
    if (_options.isNotEmpty) ...[
      const SizedBox(height: 16),
      const Text(
        'Elige dónde y con quién deseas atenderte. La lista no representa horas disponibles ni una reserva de consulta.',
      ),
      const SizedBox(height: 16),
      _choice(
        'Clínica',
        'clinicId',
        'clinicName',
        _clinic,
        _options,
        (v) => setState(() {
          _clinic = v;
          _branch = _specialty = _membership = null;
        }),
      ),
      _choice(
        'Sucursal',
        'branchId',
        'branchName',
        _branch,
        _options.where((x) => x['clinicId'] == _clinic).toList(),
        (v) => setState(() {
          _branch = v;
          _specialty = _membership = null;
        }),
      ),
      _choice(
        'Especialidad',
        'specialtyId',
        'specialtyName',
        _specialty,
        _options
            .where((x) => x['clinicId'] == _clinic && x['branchId'] == _branch)
            .toList(),
        (v) => setState(() {
          _specialty = v;
          _membership = null;
        }),
      ),
      const Text(
        'Si no sabes qué especialidad elegir, busca Medicina general cuando esté disponible. No se asigna una especialidad automáticamente.',
      ),
      const SizedBox(height: 16),
      _choice(
        'Profesional',
        'membershipId',
        'professionalName',
        _membership,
        _options
            .where(
              (x) =>
                  x['clinicId'] == _clinic &&
                  x['branchId'] == _branch &&
                  x['specialtyId'] == _specialty,
            )
            .toList(),
        (v) => setState(() => _membership = v),
      ),
      if (_selected != null)
        Text(
          'Sucursal: ${_selected!['street']} ${_selected!['addressNumber']}, ${_commune(_consultation)}',
        ),
    ],
    if (_nextOffset != null)
      TextButton(
        onPressed: _searching ? null : () => _search(more: true),
        child: const Text('Cargar más opciones de esta comuna'),
      ),
  ];
  List<Widget> _exam() => [
    _field(
      _nombre,
      'Nombre del examen',
      max: 100,
      hint: 'Por ejemplo: Hemograma de octubre',
    ),
    DropdownButtonFormField<String>(
      initialValue: _tipo,
      decoration: const InputDecoration(
        labelText: 'Tipo de examen',
        border: OutlineInputBorder(),
      ),
      items: [
        'Laboratorio',
        'Imagenología',
      ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
      onChanged: (v) => setState(() => _tipo = v),
      validator: (v) => v == null ? 'Selecciona un tipo.' : null,
    ),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: _date,
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(
        _fecha == null
            ? 'Seleccionar fecha'
            : '${_fecha!.day}/${_fecha!.month}/${_fecha!.year}',
      ),
    ),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: _pick,
      icon: const Icon(Icons.attach_file),
      label: const Text('Seleccionar PDF, JPEG o PNG'),
    ),
    if (_archivo != null)
      Text(
        '${_archivo!.name} · ${((_archivoBytes ?? 0) / 1024).toStringAsFixed(1)} KB',
      ),
    const Text(
      'Tamaño máximo: 10 MiB. Usa documentos ficticios o correctamente anonimizados durante las pruebas.',
    ),
  ];
  List<Widget> _review() => [
    _summary('Contacto', '${_phone.text}\n${_context!['email']}'),
    _summary(
      'Domicilio',
      '${_street.text} ${_number.text}, ${_commune(_residence)}',
    ),
    _summary(
      'Atención elegida',
      '${_selected?['clinicName']} · ${_selected?['branchName']}\n${_selected?['street']} ${_selected?['addressNumber']}, ${_commune(_consultation)}\n${_selected?['specialtyName']} · ${_selected?['professionalName']}',
    ),
    _summary(
      'Examen',
      '${_nombre.text} · $_tipo\n${_fecha!.day}/${_fecha!.month}/${_fecha!.year}\n${_archivo!.name}',
    ),
    Text(
      _saveProfile
          ? 'Actualizaré el domicilio y teléfono de mi perfil.'
          : 'Usaré estos datos solo para este envío.',
    ),
    const SizedBox(height: 12),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _confirmed,
      onChanged: _busy ? null : (v) => setState(() => _confirmed = v ?? false),
      title: const Text(
        'Confirmo mis datos de contacto, la zona y el profesional elegido',
      ),
    ),
  ];
  Widget _summary(String title, String text) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(text),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    const titles = [
      'Ubicación y contacto',
      'Elegir atención',
      'Adjuntar examen',
      'Revisar y enviar',
    ];
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Subir examen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            'Paso ${_step + 1} de 4 · ${titles[_step]}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (_step + 1) / 4),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_context == null)
            OutlinedButton(
              onPressed: _load,
              child: const Text('Reintentar datos de contacto'),
            )
          else ...[
            ...switch (_step) {
              0 => _contact(),
              1 => _attention(),
              2 => _exam(),
              _ => _review(),
            },
            const SizedBox(height: 20),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(),
              ),
            if (_step < 3)
              FilledButton(
                onPressed: _busy || _searching ? null : _next,
                child: const Text('Continuar'),
              )
            else
              FilledButton.icon(
                onPressed: _busy || !_confirmed ? null : _upload,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(_busy ? 'Enviando…' : 'Confirmar y enviar examen'),
              ),
            if (_step > 0)
              TextButton(
                onPressed: _busy || _searching
                    ? null
                    : () => setState(() {
                        _step--;
                        _error = null;
                        _confirmed = false;
                      }),
                child: const Text('Anterior'),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          TextButton(
            onPressed: _busy ? null : widget.onCancel,
            child: const Text('Volver al historial'),
          ),
        ],
      ),
    );
  }
}
