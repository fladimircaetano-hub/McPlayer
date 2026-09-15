import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'core/network/api_client.dart';
import 'core/storage/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/xtream_api.dart';
import 'presentation/controllers/iptv_controller.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Stick de 1 GB: o cache de imagens padrão (100 MB de pôsteres) disputa
  // RAM com o vídeo e ajuda o sistema a matar o app. Teto de 32 MB.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 << 20;

  // Configuração inicial de orientação e sistema
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Inicializar serviços de persistência e rede
  final storage = await StorageService.init();
  final apiClient = ApiClient();
  final xtreamApi = XtreamApi(apiClient.dio);

  final iptvController = IptvController(
    storageService: storage,
    apiClient: apiClient,
    xtreamApi: xtreamApi,
  );

  runApp(McPlayerApp(controller: iptvController));
}

class McPlayerApp extends StatelessWidget {
  final IptvController controller;

  const McPlayerApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MC IPTV Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: SplashScreen(controller: controller),
    );
  }
}
