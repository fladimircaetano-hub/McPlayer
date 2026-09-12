import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/tv_focusable.dart';
import 'entry_screen.dart';

/// Tela "Listas": mostra a lista ativa, recentes e troca de lista.
class ListsScreen extends StatelessWidget {
  final IptvController controller;

  const ListsScreen({super.key, required this.controller});

  Future<void> _loadRecent(BuildContext context, String url) async {
    final ok = await controller.loadFromM3uUrl(url);
    if (ok && context.mounted) {
      // Volta ao menu, que reflete a nova lista automaticamente.
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lista carregada com sucesso.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final recents = controller.storageService.getRecentUrls();
        final current = controller.loadedListName;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Listas',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionTitle('LISTA ATIVA'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.playlist_play_rounded,
                                color: AppColors.primary, size: 28),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  current ?? 'Nenhuma lista carregada',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _describeCurrent(),
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TvFocusable(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) =>
                              EntryScreen(controller: controller),
                        ),
                      );
                    },
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Adicionar / trocar lista'),
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) =>
                                EntryScreen(controller: controller),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (recents.isNotEmpty) ...[
                    _sectionTitle('RECENTES'),
                    ...recents.map((url) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.history_rounded,
                                color: AppColors.textSecondary),
                            title: Text(
                              url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                            trailing: const Icon(
                                Icons.cloud_download_rounded,
                                color: AppColors.primary),
                            onTap: () => _loadRecent(context, url),
                          ),
                        )),
                  ],
                ],
              ),
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
        );
      },
    );
  }

  String _describeCurrent() {
    final account = controller.currentAccount;
    if (account != null) {
      var desc = 'Xtream • ${account.username} • ${account.serverUrl}';
      if (controller.totalLiveCount +
              controller.totalMoviesCount +
              controller.totalSeriesCount >
          0) {
        desc +=
            '\n${controller.totalLiveCount} canais • ${controller.totalMoviesCount} filmes • ${controller.totalSeriesCount} séries';
      }
      return desc;
    }
    final url = controller.storageService.getLastM3uUrl();
    if (url != null && url.isNotEmpty) {
      return 'M3U • $url\n${controller.totalLiveCount} canais • ${controller.totalMoviesCount} filmes • ${controller.totalSeriesCount} séries';
    }
    return 'Toque abaixo para adicionar sua primeira lista.';
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
