/// Configuração da ativação remota (McPlayer/NexPlay <-> Dashboard).
///
/// Valores são injetados via `--dart-define` no build:
/// `--dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_ANON_KEY=... --dart-define=APP_NAME=McPlayer`
/// `--dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_ANON_KEY=... --dart-define=APP_NAME=NexPlay`
/// Se não definidos, a ativação remota fica DESLIGADA e o app
/// funciona normalmente no modo manual (digitar M3U/Xtream).
class ActivationConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Nome do app enviado no check-in (aparece no painel).
  /// Permite diferenciar apps no mesmo Dashboard: 'McPlayer' | 'NexPlay'.
  static const String appName = String.fromEnvironment('APP_NAME', defaultValue: 'McPlayer');

  /// Formato da chave do aparelho (ver `StorageService.getDeviceId`).
  ///
  /// A `device_id` é chave primária da tabela `devices`, ou seja, os dois apps
  /// dividem o MESMO espaço de nomes e não podem gerar o mesmo formato.
  /// - `false` (McPlayer): apenas 6 dígitos.
  /// - `true` (demais apps, ex.: NexPlay): 1 letra + 5 alfanuméricos, ou seja,
  ///   sempre contém letra — impossível colidir com um ID só de dígitos.
  ///
  /// A decisão NÃO depende do texto exato do nome (sem `case`), então renomear
  /// o app (NexPlay/NexPlayer/...) não quebra o formato.
  static bool get idIsAlphanumeric => appName.toLowerCase() != 'mcplayer';

  /// Intervalo do polling na tela de entrada.
  static const Duration pollInterval = Duration(seconds: 10);

  static bool get isEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
