import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

class UbicacionPanel extends StatefulWidget {
  const UbicacionPanel({
    super.key,
    required this.api,
    required this.value,
    required this.editing,
    required this.enabled,
    required this.onChanged,
    required this.onExpired,
    this.loadCatalog,
    this.requiredLocation = false,
    this.locationDescription,
  });
  final AuthApi api;
  final Future<Map<String, dynamic>> Function()? loadCatalog;
  final String? value;
  final bool editing, enabled;
  final bool requiredLocation;
  final String? locationDescription;
  final ValueChanged<String?> onChanged;
  final VoidCallback onExpired;
  @override
  State<UbicacionPanel> createState() => _UbicacionPanelState();
}

class _UbicacionPanelState extends State<UbicacionPanel> {
  Map<String, dynamic>? _catalog;
  String? _region, _province, _error;
  bool _loading = false;
  List<Map<String, dynamic>> _rows(String key) =>
      (_catalog?[key] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
  Map<String, dynamic>? _find(String key, String? code) {
    for (final row in _rows(key)) {
      if (row['code'] == code) return row;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UbicacionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing != widget.editing ||
        oldWidget.value != widget.value) {
      // Al cambiar de región se conserva la selección parcial hasta elegir comuna.
      if (!widget.editing ||
          oldWidget.editing != widget.editing ||
          widget.value != null)
        _restore();
    }
  }

  void _restore() {
    final commune = _find('communes', widget.value);
    _province = commune?['provinceCode'] as String?;
    _region = _find('provinces', _province)?['regionCode'] as String?;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog =
          await (widget.loadCatalog?.call() ?? widget.api.territories());
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _restore();
      });
    } on AuthFailure catch (error) {
      if (error.status == 401) {
        widget.onExpired();
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _selector(
    String name,
    String? value,
    List<Map<String, dynamic>> options,
    ValueChanged<String?> changed, {
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: DropdownButtonFormField<String>(
      key: ValueKey(
        '$name-${value ?? ''}-${options.map((x) => x['code']).join(',')}',
      ),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: name,
        border: const OutlineInputBorder(),
      ),
      items: options
          .map(
            (x) => DropdownMenuItem<String>(
              value: x['code'] as String,
              child: Text(x['name'] as String, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: widget.enabled && options.isNotEmpty ? changed : null,
      validator: (_) => required && value == null
          ? (widget.requiredLocation
                ? 'Selecciona la comuna.'
                : 'Selecciona la comuna o quita la ubicación.')
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final commune = _find('communes', widget.value);
    if (!widget.editing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ubicación (opcional)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              widget.value == null
                  ? 'Sin registrar'
                  : commune == null
                  ? 'Comuna registrada: ${widget.value}'
                  : '${commune['name']}, ${_find('provinces', commune['provinceCode'] as String?)?['name'] ?? ''}, ${_find('regions', _region)?['name'] ?? ''}',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Consultando ubicación…'),
              ),
            if (_error != null) ...[
              Text(_error!),
              TextButton(
                onPressed: widget.enabled ? _load : null,
                child: const Text('Reintentar catálogo'),
              ),
            ],
          ],
        ),
      );
    }
    if (_loading)
      return const Padding(
        padding: EdgeInsets.only(bottom: 18),
        child: Text('Cargando regiones, provincias y comunas…'),
      );
    if (_error != null)
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!),
            const Text(
              'La ubicación guardada se conserva. Puedes editar los demás datos.',
            ),
            TextButton(
              onPressed: widget.enabled ? _load : null,
              child: const Text('Reintentar catálogo'),
            ),
          ],
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            widget.locationDescription ??
                (widget.requiredLocation
                    ? 'Selecciona región, provincia y comuna de la sucursal.'
                    : 'Ubicación opcional. Elige región, provincia y comuna, o déjala sin registrar.'),
          ),
        ),
        _selector('Región', _region, _rows('regions'), (value) {
          setState(() {
            _region = value;
            _province = null;
          });
          widget.onChanged(null);
        }),
        _selector(
          'Provincia',
          _province,
          _rows('provinces').where((x) => x['regionCode'] == _region).toList(),
          (value) {
            setState(() => _province = value);
            widget.onChanged(null);
          },
        ),
        _selector(
          'Comuna',
          widget.value,
          _rows('communes')
              .where((x) => x['provinceCode'] == _province)
              .toList(),
          widget.onChanged,
          required: widget.requiredLocation || _region != null,
        ),
        if (!widget.requiredLocation)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.enabled
                  ? () {
                      setState(() {
                        _region = null;
                        _province = null;
                      });
                      widget.onChanged(null);
                    }
                  : null,
              icon: const Icon(Icons.location_off_outlined),
              label: const Text('Quitar ubicación'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(bottom: 18),
          child: Text(
            'Catálogo de códigos territoriales de SUBDERE, versión 2018. Esta selección no comprueba tu domicilio.',
          ),
        ),
      ],
    );
  }
}
