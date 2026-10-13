import 'package:flutter_test/flutter_test.dart';
import 'package:vitalia_health/core/assistant_failure_message.dart';

void main() {
  test('distingue espera y rechazo sin mostrar mensajes externos', () {
    expect(assistantFailureMessage('{"error":{"code":"ASSISTANT_BUSY"}}'), contains('en curso'));
    expect(assistantFailureMessage('{"error":{"code":"ASSISTANT_RESPONSE_REJECTED"}}'), contains('validaciones'));
    expect(assistantFailureMessage('{"error":{"code":"ASSISTANT_COOLDOWN"}}'), contains('treinta'));
    expect(assistantFailureMessage('{"error":{"code":"ASSISTANT_TIMEOUT"}}'), contains('dos minutos'));
    expect(assistantFailureMessage('{"error":{"code":"ASSISTANT_MODEL_UNAVAILABLE"}}'), contains('Ollama'));
    expect(assistantFailureMessage('invalid'), contains('no está disponible'));
    expect(assistantFailureMessage('{"error":{"message":"secreto"}}'), isNot(contains('secreto')));
  });
}
