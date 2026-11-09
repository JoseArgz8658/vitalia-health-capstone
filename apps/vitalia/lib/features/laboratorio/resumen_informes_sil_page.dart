import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

class ResumenInformesSilPage extends StatefulWidget {
  const ResumenInformesSilPage({
    super.key,
    required this.api,
    required this.reports,
    required this.onExpired,
    this.initialReportId,
  });

  final AuthApi api;
  final List<Map<String, dynamic>> reports;
  final VoidCallback onExpired;
  final String? initialReportId;

  @override
  State<ResumenInformesSilPage> createState() => _ResumenInformesSilPageState();
}

enum _Section { results, comparison, referral }

class _ResumenInformesSilPageState extends State<ResumenInformesSilPage> {
  late final _selected = <String>{
    if (widget.initialReportId case final String id) id,
  };
  Map<String, dynamic>? _overview;
  _Section _section = _Section.results;
  bool _loading = false;
  String? _error;

  Future<void> _analyze() async {
    if (_loading || _selected.isEmpty) return;
    setState(() {
      _loading = true;
      _overview = null;
      _error = null;
    });
    try {
      final response = await widget.api.silRequest(
        '/patient/reports/overview',
        body: {'reportIds': _selected.toList()},
      );
      if (mounted) setState(() => _overview = response);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        Navigator.pop(context);
        widget.onExpired();
      } else {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _number(num value) => value
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'\.?0+$'), '')
      .replaceAll('.', ',');

  String _date(Object? raw) {
    final date = DateTime.tryParse('$raw')?.toLocal();
    return date == null
        ? 'Fecha sin registrar'
        : '${date.day}/${date.month}/${date.year}';
  }

  List<Map> _items(Map source, String key) =>
      (source[key] as List?)?.whereType<Map>().toList() ?? [];

  Widget _panel(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  List<Widget> _content(Map<String, dynamic> overview) {
    final reports = _items(overview, 'reports');
    if (_section == _Section.comparison) {
      final groups = _items(overview, 'statistics');
      return [
        const Text(
            'Comparación descriptiva del mismo examen, unidad y laboratorio. Verifica en los PDF si las condiciones y el método coinciden.'),
        const SizedBox(height: 10),
        if (groups.isEmpty)
          _panel('Aún no hay mediciones para comparar', [
            const Text(
                'Selecciona informes con dos o más valores legibles para el mismo examen.'),
          ]),
        for (final group in groups) ...[
          _panel('${group['analyte']} · ${group['unit']}', [
            Text('${group['laboratory']} · ${group['count']} mediciones'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final (key, label) in [
                ('minimum', 'Menor'),
                ('mean', 'Promedio'),
                ('maximum', 'Mayor'),
              ])
                Chip(label: Text('$label ${_number(group[key] as num)}')),
            ]),
            const SizedBox(height: 8),
            for (final measurement in _items(group, 'measurements'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                    '${_date(measurement['authorizedAt'])} · ${measurement['orderNumber']} · ${_number(measurement['value'] as num)} ${group['unit']}'),
              ),
          ]),
          const SizedBox(height: 10),
        ],
      ];
    }
    return [
      for (final report in reports) ...[
        _panel('Orden ${report['orderNumber']}', [
          Text(
              '${report['laboratory']} · Autorizado el ${_date(report['authorizedAt'])}'),
          const SizedBox(height: 10),
          if (_section == _Section.referral) ...[
            if (report['observation'] case final String observation) ...[
              Text(
                  'Texto detectado en la solicitud ${report['reference'] ?? ''}'
                      .trim()),
              const SizedBox(height: 6),
              SelectableText('«$observation»'),
              if (report['observationExplanation']
                  case final String explanation) ...[
                const SizedBox(height: 8),
                Text(explanation),
              ],
              const SizedBox(height: 8),
              const Text(
                  'Confirma la transcripción y su significado con el laboratorio.'),
            ] else
              const Text(
                  'No se detectó una observación claramente rotulada en la solicitud.'),
          ] else ...[
            if (_items(report, 'measurements').isEmpty)
              const Text(
                  'No se reconocieron cifras con su unidad. Consulta el PDF original.'),
            for (final item in _items(report, 'measurements'))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${item['analyte']} · ${_number(item['value'] as num)} ${item['unit']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (item['explanation'] case final String explanation)
                      Text(explanation),
                  ],
                ),
              ),
          ],
        ]),
        const SizedBox(height: 10),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen de informes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _panel('Elige hasta cuatro informes', [
                      const Text(
                          'Usa uno para entender sus cifras o varios para compararlos.'),
                      const SizedBox(height: 8),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        initiallyExpanded:
                            _selected.isEmpty && widget.reports.length <= 6,
                        title: Text('${_selected.length} seleccionados'),
                        children: [
                          for (final report in widget.reports)
                            CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                  '${report['orderNumber']} · ${report['issuingLaboratory']}'),
                              subtitle:
                                  Text(_date(report['externallyAuthorizedAt'])),
                              value: _selected.contains(report['id']),
                              onChanged: _loading ||
                                      (_selected.length == 4 &&
                                          !_selected.contains(report['id']))
                                  ? null
                                  : (checked) => setState(() {
                                        final id = report['id'] as String;
                                        if (checked == true) {
                                          _selected.add(id);
                                        } else {
                                          _selected.remove(id);
                                        }
                                        _overview = null;
                                        _error = null;
                                      }),
                            ),
                        ],
                      ),
                      FilledButton(
                        onPressed:
                            _loading || _selected.isEmpty ? null : _analyze,
                        child: Text(_loading
                            ? 'Leyendo los documentos…'
                            : 'Leer informes'),
                      ),
                    ]),
                    if (_loading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(
                          semanticsLabel: 'Leyendo informes seleccionados'),
                    ],
                    if (_error case final String error) ...[
                      const SizedBox(height: 12),
                      Semantics(liveRegion: true, child: Text(error)),
                    ],
                    if (overview != null) ...[
                      const SizedBox(height: 20),
                      Text('¿Qué quieres revisar?',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final (section, label) in [
                            (_Section.results, '¿Cuáles son mis resultados?'),
                            (_Section.comparison, '¿Cómo se comparan?'),
                            (_Section.referral, '¿Qué dice la derivación?'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _section == section,
                              onSelected: (_) =>
                                  setState(() => _section = section),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._content(overview),
                      const Text(
                          'Lectura de apoyo. Verifica las cifras y las observaciones en los documentos originales.'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
