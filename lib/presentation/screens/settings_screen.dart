import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/device_id_card.dart';
import '../widgets/tv_focusable.dart';
import 'entry_screen.dart';

/// Tela "Configurações": dados da lista/conta, aparelho, recarregar e sair.
class SettingsScreen extends StatelessWidget {
  final IptvController controller;

  const SettingsScreen({super.key, required this.controller});

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

  Future<void> _logout(BuildContext context) async {
    await controller.logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => EntryScreen(controller: controller)),
        (r) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final account = controller.currentAccount;
        final deviceId = controller.storageService.getDeviceId();
        final mac = controller.storageService.getDeviceMac();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Configurações',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionTitle('CONTA / LISTA'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.loadedListName ?? 'Sem lista ativa',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                          const SizedBox(height: 6),
                          if (account != null) ...[
                            _info('Servidor', account.serverUrl),
                            _info('Usuário', account.username),
                            if ((account.status ?? '').isNotEmpty)
                              _info('Status', account.status!),
                            if ((account.expDate ?? '').isNotEmpty)
                              _info('Expira em', account.expDate!),
                          ] else ...[
                            _info('Fonte', 'Lista M3U'),
                            _info('URL',
                                controller.storageService.getLastM3uUrl() ?? '-'),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            '${controller.totalLiveCount} canais • ${controller.totalMoviesCount} filmes • ${controller.totalSeriesCount} séries • ${controller.totalFavoritesCount} favoritos',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('APARELHO'),
                  DeviceIdCard(deviceId: deviceId, mac: mac),
                  const SizedBox(height: 20),
                  _sectionTitle('AÇÕES'),
                  TvFocusable(
                    onPressed: () => _reload(context),
                    child: ElevatedButton.icon(
                      icon:
                          const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Recarregar lista'),
                      onPressed: () => _reload(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TvFocusable(
                    onPressed: () => _logout(context),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(
                          Icons.power_settings_new_rounded,
                          size: 20),
                      label: const Text('Trocar lista / Sair'),
                      onPressed: () => _logout(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Center(
                    child: Text(
                      'McPlayer • v1.0.0',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
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

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
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
