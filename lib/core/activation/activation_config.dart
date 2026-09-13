/// Configuração da ativação remota (McPlayer <-> Dashboard).
///
/// Preencha [supabaseUrl] e [supabaseAnonKey] com os mesmos valores do `.env`
/// do Dashboard (`VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`).
/// Enquanto estiverem vazios, a ativação remota fica DESLIGADA e o app
/// funciona normalmente no modo manual (digitar M3U/Xtream).
class ActivationConfig {
  static const String supabaseUrl =
      'https://jtytonknduyllkbmsgys.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_rdGe_pXvpA6wdOsmglwj8g_UOPeD7DE';

  /// Nome do app enviado no check-in (aparece no painel).
  static const String appName = 'McPlayer';

  /// Intervalo do polling na tela de entrada.
  static const Duration pollInterval = Duration(seconds: 10);

  static bool get isEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
