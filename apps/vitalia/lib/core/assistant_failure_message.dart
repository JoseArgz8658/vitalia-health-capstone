import 'dart:convert';

String assistantFailureMessage(String body) {
  String? code;
  try {
    final data = jsonDecode(body);
    if (data is Map && data['error'] is Map) {
      final value = data['error']['code'];
      if (value is String) code = value;
    }
  } catch (_) { /* Una respuesta inválida conserva el mensaje genérico. */ }
  return switch (code) {
    'ASSISTANT_TIMEOUT' => 'La IA superó el límite de dos minutos y no se guardó una explicación. Actualiza la consulta antes de reintentar.',
    'ASSISTANT_MODEL_UNAVAILABLE' => 'No se pudo obtener una respuesta del servidor local de IA. Comprueba que Ollama y el modelo estén disponibles.',
    'ASSISTANT_CONFIGURATION' => 'La configuración del asistente no permite generar esta respuesta. Revisa la configuración del backend.',
    'ASSISTANT_BUSY' => 'Hay una solicitud del asistente en curso. Espera y actualiza la consulta.',
    'ASSISTANT_COOLDOWN' => 'Espera treinta segundos desde el intento anterior antes de generar otra explicación.',
    'ASSISTANT_RESPONSE_REJECTED' => 'La respuesta de IA no pasó las validaciones y no se muestra. Actualiza la consulta antes de reintentar.',
    _ => 'El servicio del asistente no está disponible. Actualiza la consulta e intenta más adelante.',
  };
}
