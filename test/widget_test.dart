import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/activation/activation_service.dart';
import 'package:mcplayer/core/network/api_client.dart';
import 'package:mcplayer/core/storage/storage_service.dart';
import 'package:mcplayer/data/datasources/xtream_api.dart';
import 'package:mcplayer/main.dart';
import 'package:mcplayer/presentation/controllers/iptv_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    // Desliga a ativação remota: evita rede real e timer de polling
    // periódico na EntryScreen (quebra o teste com "Timer still pending").
    ActivationService.testBypass = true;
    // media_kit nativo (libmpv) não existe no ambiente de teste — ignora.
    try {
      MediaKit.ensureInitialized();
    } catch (_) {}
  });

  testWidgets('McPlayerApp renderiza a tela de Splash com sucesso', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final apiClient = ApiClient();
    final xtreamApi = XtreamApi(apiClient.dio);

    final controller = IptvController(
      storageService: storage,
      apiClient: apiClient,
      xtreamApi: xtreamApi,
    );

    await tester.pumpWidget(McPlayerApp(controller: controller));

    expect(find.text('MCPLAYER'), findsOneWidget);

    // Avançar o tempo para que os timers de animação e splash sejam drenados
    await tester.pump(const Duration(seconds: 3));
  });
}
