import 'package:flutter/material.dart';

import '../../core/auth_api.dart';
import '../../core/tema_vitalia.dart';
import 'portal_visual_sil.dart';

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
  final _detailsKey = GlobalKey();

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
      if (mounted) {
        setState(() => _overview = response);
        // En móvil, el resultado suele quedar bajo el selector. Lleva la
        // lectura a la vista sin mover el contenido en escritorio.
        if (MediaQuery.sizeOf(context).width < 900) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final destination = _detailsKey.currentContext;
            if (mounted && destination != null) {
              Scrollable.ensureVisible(
                destination,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }
      }
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

  Widget _selector() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ColoresVitalia.azulSuave,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.library_books_outlined,
                    color: ColoresVitalia.azul,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Elige hasta cuatro informes',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 4),
                      const Text(
                        'Usa uno para entender sus cifras o varios para compararlos.',
                        style: TextStyle(
                          fontSize: 12,
                          color: ColoresVitalia.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Material(
              color: ColoresVitalia.fondoAzul,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                initiallyExpanded:
                    _selected.isEmpty && widget.reports.length <= 6,
                title: Text('${_selected.length} seleccionados'),
                subtitle: const Text('Máximo cuatro documentos publicados'),
                children: [
                  if (widget.reports.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Todavía no hay informes publicados '
                          'disponibles para seleccionar.'),
                    ),
                  for (final report in widget.reports)
                    CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 7,
                      ),
                      title: Text(
                        '${report['orderNumber']} · '
                        '${report['issuingLaboratory']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        _date(report['externallyAuthorizedAt']),
                        style: const TextStyle(fontSize: 12),
                      ),
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
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading || _selected.isEmpty ? null : _analyze,
                icon: const Icon(Icons.analytics_outlined),
                label: Text(_loading
                    ? 'Leyendo los documentos…'
                    : 'Leer informes'),
              ),
            ),
            const SizedBox(height: 11),
            Text(
              _selected.length < 2
                  ? 'Para una comparación descriptiva necesitas al menos '
                      'dos informes con valores compatibles.'
                  : 'Los cálculos solo agrupan cifras del mismo examen, '
                      'analito, unidad y laboratorio.',
              style: const TextStyle(
                color: ColoresVitalia.textoSecundario,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentArea() {
    final overview = _overview;
    final theme = Theme.of(context);
    if (overview == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: ColoresVitalia.verdeSuave,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.auto_graph_outlined,
                    color: ColoresVitalia.verde, size: 27),
              ),
              const SizedBox(height: 15),
              Text(
                'Una lectura más clara de tus informes',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Selecciona los documentos publicados que quieras revisar '
                'y pulsa «Leer informes». Aquí aparecerán sus cifras '
                'detectadas y las observaciones de su derivación.',
                style: TextStyle(
                  height: 1.5,
                  color: ColoresVitalia.textoSecundario,
                ),
              ),
              const SizedBox(height: 16),
              for (final item in const [
                (
                  Icons.fact_check_outlined,
                  'Resultados del documento',
                  'Conservamos la referencia de la orden original.',
                ),
                (
                  Icons.compare_arrows_outlined,
                  'Comparación responsable',
                  'Solo se comparan cifras compatibles.',
                ),
                (
                  Icons.notes_outlined,
                  'Observación de derivación',
                  'Puedes leer el texto detectado en la solicitud.',
                ),
              ]) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.$1, color: ColoresVitalia.azul, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.$2,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(item.$3,
                              style: const TextStyle(
                                fontSize: 12,
                                color: ColoresVitalia.textoSecundario,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortalEncabezadoSeccionSil(
          title: 'Tu lectura guiada',
          subtitle:
              'Selecciona lo que necesitas comprender de los documentos.',
        ),
        const SizedBox(height: 13),
        Wrap(
          spacing: 8,
          runSpacing: 7,
          children: [
            for (final (section, label, icon) in [
              (
                _Section.results,
                '¿Cuáles son mis resultados?',
                Icons.biotech_outlined,
              ),
              (
                _Section.comparison,
                '¿Cómo se comparan?',
                Icons.insights_outlined,
              ),
              (
                _Section.referral,
                '¿Qué dice la derivación?',
                Icons.notes_outlined,
              ),
            ])
              ChoiceChip(
                avatar: Icon(icon, size: 17),
                label: Text(label),
                selected: _section == section,
                onSelected: (_) => setState(() => _section = section),
              ),
          ],
        ),
        const SizedBox(height: 14),
        ..._content(overview),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: ColoresVitalia.azulSuave,
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  size: 20, color: ColoresVitalia.azul),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Lectura de apoyo. Verifica cifras, unidades y '
                  'observaciones en los PDF originales. '
                  'Estos datos no sustituyen una evaluación profesional.',
                  style: TextStyle(
                    fontSize: 12,
                    color: ColoresVitalia.texto,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 65,
        title: const Text('Resumen de informes'),
        actions: [
          if (!narrow)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('Consulta privada · DEMO'),
                  backgroundColor: ColoresVitalia.azulSuave,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 14 : 24,
            vertical: narrow ? 17 : 25,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1190),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PortalHeroSil(
                    eyebrow: 'Explorador de informes · SIL DEMO',
                    title: 'Comprende mejor tus exámenes',
                    subtitle:
                        'Consulta las cifras de tus documentos publicados, '
                        'revisa las observaciones de la derivación y compara '
                        'mediciones cuando correspondan.',
                    icon: Icons.monitor_heart_outlined,
                    compact: narrow,
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final selector = _selector();
                      final details = KeyedSubtree(
                        key: _detailsKey,
                        child: _contentArea(),
                      );
                      if (constraints.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 400, child: selector),
                            const SizedBox(width: 18),
                            Expanded(child: details),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          selector,
                          const SizedBox(height: 16),
                          details,
                        ],
                      );
                    },
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(
                      semanticsLabel: 'Leyendo informes seleccionados',
                    ),
                  ],
                  if (_error case final String error) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          )),
                    ),
                  ],
                  const SizedBox(height: 25),
                  const Text(
                    'Vitalia Health · Lectura educativa sobre documentos '
                    'ficticios. Conserva siempre el informe original.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: ColoresVitalia.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
