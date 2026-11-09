import 'package:flutter/material.dart';

import '../../core/tema_vitalia.dart';

/// Centro de orientación de la DEMO SIL. No inventa canales reales de
/// contacto ni afirma que la plataforma entregue atención clínica.
abstract final class PortalAyudaSil {
  static Future<void> _dialog(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 610, maxHeight: 710),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(23),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: ColoresVitalia.azulSuave,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, color: ColoresVitalia.azul, size: 25),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: ColoresVitalia.texto,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: ColoresVitalia.textoSecundario,
                              height: 1.45,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 27),
                ...children,
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Entendido'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _body(String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          value,
          style: const TextStyle(
            color: ColoresVitalia.texto,
            height: 1.55,
            fontSize: 14,
          ),
        ),
      );

  static Widget _highlight(IconData icon, String title, String body) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: ColoresVitalia.verde, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      color: ColoresVitalia.textoSecundario,
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  static Future<void> contacto(
    BuildContext context,
    List<Map<String, dynamic>> reports,
  ) {
    final laboratories = reports
        .map((report) => report['issuingLaboratory'])
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return _dialog(
      context,
      title: 'Contacto con tu laboratorio',
      subtitle: 'Encuentra a qué laboratorio corresponde un informe y '
          'cómo solicitar ayuda por sus canales oficiales.',
      icon: Icons.support_agent_outlined,
      children: [
        if (laboratories.isNotEmpty) ...[
          const Text(
            'LABORATORIO DE TUS INFORMES',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: ColoresVitalia.textoSecundario,
            ),
          ),
          const SizedBox(height: 7),
          for (final name in laboratories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined,
                      color: ColoresVitalia.azul, size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                    child: SelectableText(
                      name,
                      style: const TextStyle(
                        color: ColoresVitalia.texto,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 24),
        ],
        _body(
          'Para preguntar por la publicación de un informe, corregir '
          'datos de tu ficha o solicitar una nueva copia, utiliza el '
          'teléfono, correo o sitio oficial que el laboratorio te '
          'entregó al atenderte.',
        ),
        _highlight(
          Icons.description_outlined,
          'Ten a mano tu comprobante',
          'El número de orden que aparece en tu informe ayuda '
              'al laboratorio a identificar el documento.',
        ),
        _highlight(
          Icons.verified_user_outlined,
          'Protege tus datos',
          'No envíes resultados, contraseñas o códigos de acceso '
              'por canales cuya identidad no hayas verificado.',
        ),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: ColoresVitalia.azulSuave,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'DEMO ACADÉMICA: aún no hay teléfono, dirección, correo '
            'institucional ni mensajería de soporte habilitados. '
            'Vitalia no envía solicitudes de contacto desde esta pantalla.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: ColoresVitalia.azulActivo,
            ),
          ),
        ),
      ],
    );
  }

  static Future<void> preguntasFrecuentes(BuildContext context) => _dialog(
        context,
        title: 'Preguntas frecuentes',
        subtitle: 'Respuestas rápidas para navegar tu portal y '
            'entender qué información puedes consultar.',
        icon: Icons.help_outline,
        children: [
          for (final (question, answer) in const [
            (
              '¿Qué informes puedo consultar?',
              'Únicamente los documentos que el laboratorio haya '
                  'publicado y vinculado a tu cuenta. Una solicitud '
                  'o un borrador interno no aparece aquí.',
            ),
            (
              '¿Por qué no encuentro un examen?',
              'Puede que el laboratorio todavía no lo publique o que '
                  'tu cuenta no esté vinculada a ese informe. '
                  'Consulta los canales oficiales de tu laboratorio.',
            ),
            (
              '¿Cómo leo las cifras de un PDF?',
              'Abre «Ver resultados» en el informe que te interesa. '
                  'Vitalia mostrará las cifras reconocidas, sus unidades '
                  'y explicaciones educativas. Compruébalas siempre '
                  'con el documento original.',
            ),
            (
              '¿Cómo comparo mis resultados?',
              'Si tienes dos o más informes, abre «Comparar informes». '
                  'Vitalia calcula valores descriptivos solamente '
                  'cuando coinciden el analito, la unidad, el examen '
                  'y el laboratorio. Esto no equivale a un diagnóstico.',
            ),
            (
              '¿Cómo recupero mi cuenta?',
              'Ingresa a «Configurar recuperación» desde «Mi cuenta» '
                  'cuando tengas acceso. Guarda la clave de respaldo '
                  'por separado: es de un solo uso. Si tienes problemas '
                  'de acceso, sigue el procedimiento habilitado '
                  'en la pantalla de inicio de sesión.',
            ),
            (
              '¿Qué hago si mis datos están incorrectos?',
              'No modifiques información médica por tu cuenta. '
                  'Comunícate con el laboratorio a través de sus '
                  'canales oficiales para que revise tu ficha o informe.',
            ),
          ])
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              title: Text(
                question,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    answer,
                    style: const TextStyle(
                      color: ColoresVitalia.textoSecundario,
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
        ],
      );

  static Future<void> sobreVitalia(BuildContext context) => _dialog(
        context,
        title: 'Sobre Vitalia Health',
        subtitle: 'Tecnología comprensible para el recorrido '
            'postanalítico de un laboratorio.',
        icon: Icons.favorite_outline,
        children: [
          _body(
            'Vitalia Health es un proyecto académico de Ingeniería '
            'en Informática de Duoc UC, orientado a crear un '
            'Sistema de Información de Laboratorio (SIL) '
            'de alcance postanalítico para laboratorios privados.',
          ),
          _highlight(
            Icons.description_outlined,
            'Información centralizada',
            'Las órdenes e informes publicados se consultan '
                'desde un espacio personal.',
          ),
          _highlight(
            Icons.psychology_alt_outlined,
            'Explicaciones accesibles',
            'La lectura de apoyo facilita comprender los términos '
                'de un documento sin reemplazar al personal clínico.',
          ),
          _highlight(
            Icons.lock_outline,
            'Acceso privado',
            'El portal separa la experiencia del paciente '
                'de las tareas internas del laboratorio.',
          ),
          _body(
            'Esta versión utiliza cuentas y documentos ficticios. '
            'No es un prestador de salud, no toma muestras ni emite '
            'diagnósticos clínicos.',
          ),
        ],
      );

  static Future<void> privacidad(BuildContext context) => _dialog(
        context,
        title: 'Privacidad y uso responsable',
        subtitle: 'Qué significa usar la demostración del portal.',
        icon: Icons.shield_outlined,
        children: [
          _highlight(
            Icons.person_outline,
            'Consulta de tu cuenta',
            'El portal está diseñado para mostrar solamente '
                'los informes publicados asociados a la cuenta autenticada.',
          ),
          _highlight(
            Icons.fact_check_outlined,
            'Documentos originales',
            'La lectura de cifras y texto es una ayuda automatizada: '
                'debe contrastarse con el PDF publicado.',
          ),
          _highlight(
            Icons.medical_information_outlined,
            'Sin recomendaciones clínicas',
            'Los resúmenes y comparaciones no deben usarse para '
                'diagnosticar ni ajustar tratamientos.',
          ),
          _body(
            'Este entorno contiene datos inventados para demostración. '
            'Antes de trabajar con información real, Vitalia requerirá '
            'controles de seguridad, procedimientos del laboratorio '
            'y documentación legal formal revisada.',
          ),
        ],
      );
}

class PortalAyudaFooterSil extends StatelessWidget {
  const PortalAyudaFooterSil({
    super.key,
    required this.reports,
    this.onProfile,
    this.onRecovery,
    this.onReports,
  });

  final List<Map<String, dynamic>> reports;
  final VoidCallback? onProfile;
  final VoidCallback? onRecovery;
  final VoidCallback? onReports;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(23),
          decoration: BoxDecoration(
            color: const Color(0xFFE7F2F2),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: const Color(0xFFCFE5E5)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ESTAMOS PARA ORIENTARTE',
                    style: TextStyle(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: ColoresVitalia.verde,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    '¿Necesitas ayuda con tus informes?',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: ColoresVitalia.texto,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Te mostramos cómo encontrar el laboratorio '
                    'responsable y resolver las dudas frecuentes '
                    'sobre el acceso a tu portal.',
                    style: TextStyle(
                      color: ColoresVitalia.textoSecundario,
                      height: 1.45,
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        PortalAyudaSil.contacto(context, reports),
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text('Contacto del laboratorio'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        PortalAyudaSil.preguntasFrecuentes(context),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Preguntas frecuentes'),
                  ),
                ],
              );
              if (constraints.maxWidth >= 860) {
                return Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 25),
                    Flexible(child: actions),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  text,
                  const SizedBox(height: 18),
                  actions,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF1D3E52),
            borderRadius: BorderRadius.circular(19),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final brand = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.favorite_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Vitalia Health',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 9),
                  Text(
                    'Tu información de laboratorio, '
                    'explicada con claridad y cuidado.',
                    style: TextStyle(
                      color: Color(0xFFD0E4EA),
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Proyecto académico · SIL postanalítico · DEMO',
                    style: TextStyle(
                      color: Color(0xFFAFCAD5),
                      fontSize: 11,
                    ),
                  ),
                ],
              );
              final portal = _FooterGroup(
                title: 'TU PORTAL',
                links: [
                  if (onReports != null)
                    ('Mis informes', onReports!),
                  if (onProfile != null)
                    ('Consultar mi ficha', onProfile!),
                  if (onRecovery != null)
                    ('Recuperación de acceso', onRecovery!),
                  (
                    'Centro de ayuda',
                    () => PortalAyudaSil.preguntasFrecuentes(context),
                  ),
                ],
              );
              final info = _FooterGroup(
                title: 'INFORMACIÓN',
                links: [
                  (
                    'Sobre Vitalia',
                    () => PortalAyudaSil.sobreVitalia(context),
                  ),
                  (
                    'Contacto del laboratorio',
                    () => PortalAyudaSil.contacto(context, reports),
                  ),
                  (
                    'Privacidad y uso responsable',
                    () => PortalAyudaSil.privacidad(context),
                  ),
                ],
              );
              if (constraints.maxWidth >= 800) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: brand),
                    const SizedBox(width: 35),
                    Expanded(flex: 3, child: portal),
                    const SizedBox(width: 25),
                    Expanded(flex: 3, child: info),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  brand,
                  const SizedBox(height: 25),
                  portal,
                  const SizedBox(height: 20),
                  info,
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FooterGroup extends StatelessWidget {
  const _FooterGroup({required this.title, required this.links});

  final String title;
  final List<(String, VoidCallback)> links;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFD0E4EA),
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        for (final (label, action) in links)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: action,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 5,
                ),
                minimumSize: const Size(0, 36),
              ),
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
          ),
      ],
    );
  }
}
