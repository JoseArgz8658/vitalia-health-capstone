import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

class SilMainClinicalPanel extends StatefulWidget {
  const SilMainClinicalPanel({
    super.key,
    required this.api,
    required this.labId,
    required this.orders,
    required this.canReview,
    required this.onExpired,
    required this.onOrderChanged,
    this.initialOrderId,
  });

  final AuthApi api;
  final String labId;
  final List<Map<String, dynamic>> orders;
  final bool canReview;
  final VoidCallback onExpired;
  final ValueChanged<String> onOrderChanged;
  final String? initialOrderId;

  @override
  State<SilMainClinicalPanel> createState() => _SilMainClinicalPanelState();
}

class _SilMainClinicalPanelState extends State<SilMainClinicalPanel> {
  String? _orderId;
  Map<String, dynamic>? _details;
  final _values = <String, String>{};
  final _reason = TextEditingController();
  String? _error;
  String? _previewMessage;
  final _suggestions = <String, num>{};
  bool _busy = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _orderId = widget.initialOrderId;
    if (_orderId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(_load);
      });
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _key(Map row) => '${row['examCode']}|${row['analyte']}';
  String get _path => '/labs/${widget.labId}/orders/$_orderId/clinical';

  Future<void> _load() async {
    final details = await widget.api.silMainRequest(_path);
    if (!mounted) return;
    final result = details['results'] as Map?;
    setState(() {
      _details = details;
      _values.clear();
      _previewMessage = null;
      _suggestions.clear();
      for (final row in (result?['values'] as List? ?? []).cast<Map>()) {
        _values[_key(row)] = row['numericValue'].toString();
      }
      _reason.clear();
      _revision++;
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      if (failure.status == 401) {
        widget.onExpired();
      } else {
        setState(() => _error = failure.message);
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = 'No se pudo completar la operación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(String action, Map<String, dynamic> body) async {
    await widget.api.silMainRequest('$_path/$action', body: body);
    await _load();
  }

  Future<void> _previewPdf() async {
    final orderId = _orderId!;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Resultados PDF',
          extensions: ['pdf'],
          mimeTypes: ['application/pdf'],
        ),
      ],
    );
    if (!mounted || file == null) return;
    setState(() {
      _previewMessage = null;
      _suggestions.clear();
    });
    if (await file.length() > 2 * 1024 * 1024) {
      throw const AuthFailure('El PDF supera los 2 MiB.');
    }
    final preview = await widget.api.silMainPreviewResults(
      labId: widget.labId,
      orderId: orderId,
      fileName: file.name,
      bytes: await file.readAsBytes(),
    );
    if (!mounted) return;
    setState(() {
      for (final row in (preview['items'] as List).cast<Map>()) {
        final value = row['suggestedValue'];
        if (value is num) _suggestions[_key(row)] = value;
      }
      _previewMessage = switch (preview['state']) {
        'sample_mismatch' =>
          'Los códigos de muestra del PDF no coinciden con los de la orden.',
        'needs_ocr' =>
          'El PDF no tiene texto utilizable. Puedes transcribir los valores.',
        'unreadable' =>
          'No se pudo leer el PDF. Puedes transcribir los valores.',
        _ when _suggestions.isEmpty =>
          'No se encontraron valores con una unidad inequívoca. Completa los campos manualmente.',
        _ =>
          'Coteja cada sugerencia con el PDF original. Completa los campos sin sugerencia manualmente.',
      };
    });
  }

  void _applySuggestions() {
    setState(() {
      for (final entry in _suggestions.entries) {
        if ((_values[entry.key] ?? '').trim().isEmpty) {
          _values[entry.key] = entry.value.toString();
        }
      }
      _suggestions.clear();
      _previewMessage = 'Revisa los campos antes de guardar los resultados.';
      _revision++;
    });
  }

  String _folio(Map order) =>
      'VH-${order['orderNumber'].toString().padLeft(6, '0')}';

  Future<void> _downloadMedicalRequest() async {
    final order = widget.orders.firstWhere((order) => order['id'] == _orderId);
    final name = 'solicitud-${_folio(order)}.pdf';
    final target = kIsWeb ? null : await getSaveLocation(suggestedName: name);
    if (!mounted || (!kIsWeb && target == null)) return;
    final bytes = await widget.api.silMainDownloadMedicalRequest(
      labId: widget.labId,
      orderId: order['id'] as String,
    );
    if (!mounted || !widget.api.hasSession) return;
    final pdf = XFile.fromData(bytes, name: name, mimeType: 'application/pdf');
    await pdf.saveTo(target?.path ?? name);
  }

  Future<void> _showActivity() async {
    final activity = await widget.api.silMainRequest('$_path/audit');
    if (!mounted) return;
    final events = (activity['events'] as List).cast<Map>();
    await showDialog<void>(
      context: context,
      builder: (context) {
        final locale = MaterialLocalizations.of(context);
        return AlertDialog(
          title: const Text('Historial de actividad'),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (events.isEmpty)
                  const Text(
                    'Aún no hay actividad registrada para esta orden.',
                  ),
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _activityLabel(event['action'] as String),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(_activityDetail(event, locale)),
                      ],
                    ),
                  ),
                if (activity['hasOlder'] == true)
                  const Text('Se muestran los 30 eventos más recientes.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar historial'),
            ),
          ],
        );
      },
    );
  }

  String _activityDetail(Map event, MaterialLocalizations locale) {
    final time = DateTime.parse(event['createdAt'] as String).toLocal();
    final actor = event['staffEmail'] ?? 'Paciente';
    return '${locale.formatShortDate(time)} · '
        '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(time))}\n$actor';
  }

  String _activityLabel(String action) => switch (action) {
    'order_created' => 'Orden registrada',
    'medical_request_received' => 'Solicitud recibida',
    'medical_request_downloaded' => 'Solicitud descargada',
    'sample_received' => 'Muestra recibida',
    'results_recorded' => 'Resultados registrados',
    'results_returned' => 'Resultados devueltos para corrección',
    'results_approved' => 'Resultados aprobados',
    'report_attached' => 'Informe adjuntado',
    'report_review_accessed' => 'Informe descargado para revisión',
    'report_published' => 'Informe publicado',
    'report_downloaded' => 'Informe descargado por el paciente',
    _ => 'Actividad registrada',
  };

  Future<void> _save(List<Map> analytes) async {
    final results = <Map<String, dynamic>>[];
    for (final row in analytes) {
      final number = double.tryParse(
        (_values[_key(row)] ?? '').trim().replaceAll(',', '.'),
      );
      if (number == null || !number.isFinite) {
        throw const AuthFailure('Ingresa un valor numérico para cada analito.');
      }
      results.add({
        'examCode': row['examCode'],
        'analyte': row['analyte'],
        'numericValue': number,
      });
    }
    await _write('results', {'values': results});
  }

  @override
  Widget build(BuildContext context) {
    final hasMedicalRequest = _details?['hasMedicalRequest'] == true;
    final canSaveFile =
        kIsWeb ||
        switch (defaultTargetPlatform) {
          TargetPlatform.linux ||
          TargetPlatform.macOS ||
          TargetPlatform.windows => true,
          _ => false,
        };
    final containers = (_details?['containers'] as List? ?? []).cast<Map>();
    final analytes = (_details?['analytes'] as List? ?? []).cast<Map>();
    final result = _details?['results'] as Map?;
    final status = result?['status'];
    final open = _details?['status'] == 'registered';
    final sampled =
        containers.isNotEmpty &&
        containers.every((row) => row['barcode'] != null);
    final editable =
        open && sampled && (status == null || status == 'returned');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          identifier: 'sil-clinical-order',
          child: DropdownButtonFormField<String>(
            key: ValueKey(widget.labId),
            initialValue: _orderId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Orden para muestras y resultados',
            ),
            items: [
              for (final order in widget.orders)
                DropdownMenuItem(
                  value: order['id'] as String,
                  child: Text(_folio(order)),
                ),
            ],
            onChanged: _busy
                ? null
                : (orderId) {
                    if (orderId == null) return;
                    widget.onOrderChanged(orderId);
                    setState(() {
                      _orderId = orderId;
                      _details = null;
                      _previewMessage = null;
                      _suggestions.clear();
                    });
                    _run(_load);
                  },
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_details != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (hasMedicalRequest && canSaveFile)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_downloadMedicalRequest),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Descargar solicitud original'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_showActivity),
                icon: const Icon(Icons.history),
                label: const Text('Ver historial de la orden'),
              ),
            ],
          ),
          if (hasMedicalRequest && !canSaveFile)
            const Text(
              'Puedes descargar la solicitud desde Vitalia en el navegador.',
            ),
          const SizedBox(height: 12),
          const Text('Contenedores requeridos'),
          for (final row in containers)
            ListTile(
              title: Text(row['label'] as String),
              subtitle: Text(
                row['barcode'] as String? ?? 'Pendiente de recepción',
              ),
              trailing: row['barcode'] == null && open
                  ? TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => _write('samples', {
                                'containerCode': row['code'],
                              }),
                            ),
                      child: const Text('Recibir'),
                    )
                  : null,
            ),
          if (sampled || result != null) ...[
            Text(switch (status) {
              'pending' => 'Resultados pendientes de revisión',
              'approved' => 'Resultados aprobados',
              'returned' => 'Resultados devueltos para corrección',
              _ => 'Ingresar resultados por analito',
            }),
            if (editable && analytes.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_previewPdf),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Leer PDF de resultados'),
              ),
              if (_previewMessage != null)
                Semantics(liveRegion: true, child: Text(_previewMessage!)),
            ],
            for (final row in analytes)
              TextFormField(
                key: ValueKey('$_revision-${_key(row)}'),
                initialValue: _values[_key(row)],
                enabled: editable && !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: '${row['analyte']} (${row['unit']})',
                  helperText: _suggestions.containsKey(_key(row))
                      ? 'Sugerencia del PDF: ${_suggestions[_key(row)]}'
                      : null,
                ),
                onChanged: (value) => _values[_key(row)] = value,
              ),
            if (_suggestions.isNotEmpty)
              TextButton(
                onPressed: _busy ? null : _applySuggestions,
                child: const Text('Cotejé el PDF. Completar campos vacíos'),
              ),
            if (editable)
              FilledButton(
                onPressed: _busy || analytes.isEmpty
                    ? null
                    : () => _run(() => _save(analytes)),
                child: const Text('Guardar resultados para revisión'),
              ),
            if (open && status == 'pending' && widget.canReview) ...[
              TextField(
                controller: _reason,
                enabled: !_busy,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Motivo de devolución',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => _write('review', {'decision': 'approved'}),
                          ),
                    child: const Text('Aprobar resultados'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => _write('review', {
                              'decision': 'returned',
                              'reason': _reason.text.trim(),
                            }),
                          ),
                    child: const Text('Devolver para corregir'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ],
    );
  }
}
