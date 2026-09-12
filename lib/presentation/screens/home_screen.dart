import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/stream_item.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/app_logo.dart';
import '../widgets/starfield_background.dart';
import '../widgets/tv_focusable.dart';
import 'content_section_screen.dart';
import 'lists_screen.dart';
import 'settings_screen.dart';

/// Menu principal estilo TV (modelo DreamTV): logo McPlayer ao centro,
/// 5 botões circulares, Recarregar e chave/MAC no canto inferior direito.
class HomeScreen extends StatelessWidget {
  final IptvController controller;

  const HomeScreen({super.key, required this.controller});

  void _openSection(BuildContext context, StreamType type) {
    controller.setSearchQuery('');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ContentSectionScreen(controller: controller, type: type),
      ),
    );
  }

  Future<void> _reload(BuildContext context) async {
    final ok = await controller.reload();
    if (context.mounted && !ok && controller.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage!),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyMac(BuildContext context, String mac) {
    Clipboard.setData(ClipboardData(text: mac));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('MAC copiado: $mac'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final size = MediaQuery.of(context).size;
        final isWide = size.width >= 900;
        final deviceId = controller.storageService.getDeviceId();
        final mac = controller.storageService.getDeviceMac();
        final hidden =
            controller.storageService.getHiddenSections();
        final showCounts =
            controller.storageService.getShowCounts();

        final buttons = [
          if (!hidden.contains('live'))
            _MenuEntry(
              icon: Icons.live_tv_rounded,
              label: 'TV ao vivo',
              sub: showCounts ? '${controller.totalLiveCount}' : null,
              autofocus: true,
              onTap: () => _openSection(context, StreamType.live),
            ),
          if (!hidden.contains('movie'))
            _MenuEntry(
              icon: Icons.video_collection_rounded,
              label: 'Filmes',
              sub: showCounts ? '${controller.totalMoviesCount}' : null,
              onTap: () => _openSection(context, StreamType.movie),
            ),
          if (!hidden.contains('series'))
            _MenuEntry(
              icon: Icons.movie_filter_rounded,
              label: 'Séries',
              sub: showCounts ? '${controller.totalSeriesCount}' : null,
              onTap: () => _openSection(context, StreamType.series),
            ),
          _MenuEntry(
            icon: Icons.library_music_rounded,
            label: 'Listas',
            sub: controller.loadedListName,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListsScreen(controller: controller),
                ),
              );
            },
          ),
          _MenuEntry(
            icon: Icons.settings_rounded,
            label: 'Configurações',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(controller: controller),
                ),
              );
            },
          ),
        ];

        return Scaffold(
          body: StarfieldBackground(
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppLogo(
                            iconSize: isWide ? 64 : 52,
                            titleSize: isWide ? 38 : 30,
                          ),
                          SizedBox(height: isWide ? 40 : 28),
                          if (isWide)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0; i < buttons.length; i++) ...[
                                  _MenuCircle(entry: buttons[i]),
                                  if (i < buttons.length - 1)
                                    const SizedBox(width: 28),
                                ],
                              ],
                            )
                          else
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 20,
                              runSpacing: 20,
                              children: [
                                for (final b in buttons)
                                  _MenuCircle(entry: b, compact: true),
                              ],
                            ),
                          SizedBox(height: isWide ? 36 : 28),
                          // Botão Recarregar
                          TvFocusable(
                            borderRadius: BorderRadius.circular(24),
                            onPressed: () => _reload(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 40, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.25)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh_rounded,
                                      color: Colors.white, size: 22),
                                  SizedBox(width: 12),
                                  Text(
                                    'Recarregar',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 56),
                        ],
                      ),
                    ),
                  ),
                  // Identificação do aparelho (canto inferior direito, como no modelo)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Chave do dispositivo: $deviceId',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: () => _copyMac(context, mac),
                          child: Text(
                            'Endereço Mac: $mac',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Loading overlay
                  if (controller.isLoading)
                    Container(
                      color: Colors.black.withValues(alpha: 0.7),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                                color: AppColors.primary),
                            const SizedBox(height: 16),
                            Text(
                              controller.loadingStatus.isNotEmpty
                                  ? controller.loadingStatus
                                  : 'Carregando...',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuEntry {
  final IconData icon;
  final String label;
  final String? sub;
  final bool autofocus;
  final VoidCallback onTap;

  const _MenuEntry({
    required this.icon,
    required this.label,
    this.sub,
    this.autofocus = false,
    required this.onTap,
  });
}

class _MenuCircle extends StatelessWidget {
  final _MenuEntry entry;
  final bool compact;

  const _MenuCircle({required this.entry, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final diameter = compact ? 104.0 : 128.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TvFocusable(
          autofocus: entry.autofocus,
          borderRadius: BorderRadius.circular(diameter / 2),
          onPressed: entry.onTap,
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.22),
                  Colors.white.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: diameter * 0.72,
                height: diameter * 0.72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  entry.icon,
                  color: Colors.white,
                  size: diameter * 0.34,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          entry.label,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (entry.sub != null && entry.sub!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              entry.sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}
