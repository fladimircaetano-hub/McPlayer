/// Configuração da ativação remota (McPlayer/NexPlay <-> Dashboard).
///
/// O build PADRÃO já sai com a ativação remota LIGADA: os valores abaixo são
/// embutidos no APK sem precisar de `--dart-define`. Isso evita o APK
/// "sem painel" (aparelho não aparece no dashboard).
///
/// A chave usada é a **anon key** (pública, a mesma de `dashboard/js/config.js`);
/// quem controla o acesso são as RLS + RPCs do Supabase, nunca a chave.
/// NUNCA colocar a `service_role` key aqui.
///
/// Para sobrescrever (outro projeto Supabase, outro nome de app ou build em
/// modo manual), basta passar os defines no build:
/// `--dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_ANON_KEY=... --dart-define=APP_NAME=McPlayer`
/// `--dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_ANON_KEY=... --dart-define=APP_NAME=NexPlay`
/// Para gerar um APK SEM ativação remota (modo manual), passe vazio:
/// `--dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=`
class ActivationConfig {
  /// Projeto Supabase usado pelo Dashboard (`mcplayer-dashboard.vercel.app`).
  static const String _defaultSupabaseUrl =
      'https://pfpmizermpxhwaekoylq.supabase.co';

  /// Chave ANON (pública) do mesmo projeto. Ver `dashboard/js/config.js`.
  static const String _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBmcG1pemVybXB4aHdhZWtveWxxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyNDk3ODIsImV4cCI6MjEwNDgyNTc4Mn0.'
      'Bu9cr3bhTFhc92Ilbz0UVWEPiD55Yi3TBU2VvI_sw70';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultSupabaseAnonKey,
  );

  /// Nome do app enviado no check-in (aparece no painel).
  /// Permite diferenciar apps no mesmo Dashboard: 'McPlayer' | 'NexPlay'.
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'McPlayer',
  );

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
