import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'core/di/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'presentation/controllers/iptv_controller.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Error widget global para não crashar o app em erros de UI (especialmente TV)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF090C10),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 54),
              const SizedBox(height: 16),
              const Text(
                'Oops! Algo deu errado',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString().split('\n').first,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => SystemNavigator.pop(),
                icon: const Icon(Icons.restart_alt, color: Colors.black),
                label: const Text('Reiniciar App', style: TextStyle(color: Colors.black)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Stick de 1 GB: o cache de imagens padrão (100 MB de pôsteres) disputa
  // RAM com o vídeo e ajuda o sistema a matar o app. Teto de 24 MB.
  // Reduzido de 32MB para dar mais folga para o player de vídeo.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 24 << 20;
  // Limita também o número de imagens em cache para evitar fragmentação
  PaintingBinding.instance.imageCache.maximumSize = 100;

  // Configuração inicial de orientação e sistema
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Inicializar serviços via Service Locator (singletons compartilhados)
  await sl.initStorage();
  final iptvController = IptvController(
    storageService: sl.storage,
    apiClient: sl.apiClient,
    xtreamApi: sl.xtreamApi,
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
