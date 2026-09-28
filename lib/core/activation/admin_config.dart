/// Configuração do PIN de administrador.
///
/// Valor é injetado via `--dart-define` no build:
/// `--dart-define=ADMIN_PIN=seu_pin_seguro`
/// Se não definido, o acesso admin fica DESABILITADO (retorna vazio).
class AdminConfig {
  static const String adminPin = String.fromEnvironment('ADMIN_PIN', defaultValue: '');

  static bool get isEnabled => adminPin.isNotEmpty;
}