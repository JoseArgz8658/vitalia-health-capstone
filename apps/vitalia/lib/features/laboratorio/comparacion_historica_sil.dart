import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Gráfico exclusivamente descriptivo: no usa umbrales ni interpreta salud.
class ComparacionHistoricaSil extends StatelessWidget {
  const ComparacionHistoricaSil({
    super.key,
    required this.analyte,
    required this.unit,
    required this.measurements,
  });

  final String analyte;
  final String unit;
  final List<Map> measurements;

  String _number(double value) {
    var text = value.toStringAsFixed(4);
    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text.replaceAll('.', ',');
  }

  String _date(DateTime date) => '${date.day}/${date.month}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final points = <_HistoryPoint>[];
    for (final measurement in measurements) {
      final rawValue = measurement['value'];
      final date = DateTime.tryParse(
        (measurement['authorizedAt'] ?? '').toString(),
      )?.toLocal();
      if (rawValue is! num || !rawValue.isFinite || date == null) continue;
      points.add(_HistoryPoint(
        date: date,
        value: rawValue.toDouble(),
        orderNumber: (measurement['orderNumber'] ?? '').toString(),
      ));
    }
    points.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0
          ? byDate
          : a.orderNumber.compareTo(b.orderNumber);
    });

    if (points.length < 2) {
      return const Text(
        'No hay suficientes mediciones con fecha y valor válido para graficar.',
      );
    }

    final minimum = points.map((point) => point.value).reduce(math.min);
    final maximum = points.map((point) => point.value).reduce(math.max);
    final sameDate = points.first.date.isAtSameMomentAs(points.last.date);
    final description = points
        .map((point) =>
            '${_date(point.date)}: ${_number(point.value)} $unit, orden ${point.orderNumber}')
        .join('; ');

    return Padding(
      padding: const EdgeInsets.only(top: 9, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Evolución visual por fecha',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          const Text(
            'La escala se ajusta a los valores seleccionados; '
            'sus extremos no son límites clínicos. La línea no indica '
            'mejoría ni empeoramiento.',
            style: TextStyle(
              color: ColoresVitalia.textoSecundario,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Gráfico descriptivo de $analyte. $description',
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ColoresVitalia.fondoAzul,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ColoresVitalia.bordeTenue),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Mayor valor observado: ${_number(maximum)} $unit',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 108,
                      width: double.infinity,
                      child: CustomPaint(
                        key: const Key('sil-comparacion-historica-grafico'),
                        painter: _HistoryPainter(points, minimum, maximum),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Menor valor observado: ${_number(minimum)} $unit',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _date(points.first.date),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _date(points.last.date),
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (sameDate)
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Text(
                'Las fechas coinciden: los puntos se separan solo para '
                'distinguir los documentos.',
                style: TextStyle(
                  color: ColoresVitalia.textoSecundario,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryPoint {
  const _HistoryPoint({
    required this.date,
    required this.value,
    required this.orderNumber,
  });

  final DateTime date;
  final double value;
  final String orderNumber;
}

class _HistoryPainter extends CustomPainter {
  const _HistoryPainter(this.points, this.minimum, this.maximum);

  final List<_HistoryPoint> points;
  final double minimum;
  final double maximum;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 10.0;
    final width = math.max(1.0, size.width - inset * 2);
    final height = math.max(1.0, size.height - inset * 2);
    final grid = Paint()
      ..color = ColoresVitalia.borde
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = inset + height * fraction;
      canvas.drawLine(Offset(inset, y), Offset(inset + width, y), grid);
    }

    final start = points.first.date.millisecondsSinceEpoch;
    final duration = points.last.date.millisecondsSinceEpoch - start;
    final difference = maximum - minimum;
    final positions = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final xFactor = duration == 0
          ? i / (points.length - 1)
          : (point.date.millisecondsSinceEpoch - start) / duration;
      final yFactor =
          difference == 0 ? 0.5 : (maximum - point.value) / difference;
      positions.add(Offset(
        inset + width * xFactor,
        inset + height * yFactor,
      ));
    }

    final line = Paint()
      ..color = ColoresVitalia.azul
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(positions.first.dx, positions.first.dy);
    for (final point in positions.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, line);

    final dots = Paint()
      ..color = ColoresVitalia.azul
      ..style = PaintingStyle.fill;
    for (final point in positions) {
      canvas.drawCircle(point, 4.5, dots);
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) => true;
}
