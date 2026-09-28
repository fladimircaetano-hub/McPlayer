/// Configuração da ativação remota (McPlayer <-> Dashboard).
///
/// Valores são injetados via `--dart-define` no build:
/// `--dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_ANON_KEY=...`
/// Se não definidos, a ativação remota fica DESLIGADA e o app
/// funciona normalmente no modo manual (digitar M3U/Xtream).
class ActivationConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Nome do app enviado no check-in (aparece no painel).
  static const String appName = 'McPlayer';

  /// Intervalo do polling na tela de entrada.
  static const Duration pollInterval = Duration(seconds: 10);

  static bool get isEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
