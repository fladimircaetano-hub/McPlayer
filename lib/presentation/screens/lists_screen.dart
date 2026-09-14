import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/activation/activation_models.dart';
import '../../core/activation/activation_service.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/double_back_to_exit.dart';
import '../widgets/tv_focusable.dart';
import 'add_playlist_screen.dart';
import 'home_screen.dart';

/// Tela "Playlist" — entrada do app: título + botão +,
/// linhas numeradas (ativa em branco) com lixeira, rodapé do aparelho.
///
/// Também é o ponto da ativação remota: registra a chave no Dashboard
/// e aplica a lista aprovada sozinha (polling em background).
class ListsScreen extends StatefulWidget {
  final IptvController controller;

  const ListsScreen({super.key, required this.controller});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  IptvController get controller => widget.controller;

  // Voltar unificado (botão visível + gesto/D-pad): volta à Home se
  // veio de lá; se a Playlist é a raiz, 2 toques para sair.
  final DoubleBackController _backController = DoubleBackController();

  // Ativação remota via Dashboard (Supabase), silenciosa: sem aviso
  // visível — a lista aprovada no painel entra sozinha.
  final ActivationService _activation = ActivationService();
  Timer? _pollTimer;
  bool _autoActivating = false;

  late final String _deviceId;
  late final String _deviceMac;

  @override
  void initState() {
    super.initState();
    _deviceId = controller.storageService.getDeviceId();
    _deviceMac = controller.storageService.getDeviceMac();
    _setupActivation();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Ativação remota: registra a chave no Dashboard e observa aprovação
  /// em silêncio. Sem configuração no ActivationConfig, não faz nada.
  Future<void> _setupActivation() async {
    if (!_activation.isEnabled) return;
    final result = await _activation.checkIn(
      deviceId: _deviceId,
      mac: _deviceMac,
    );
    if (!mounted) return;
    if (result.status == ActivationStatus.approved &&
        result.listData != null) {
      _applyRemoteApproval(result.listData!);
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollActivation(),
    );
  }

  Future<void> _pollActivation() async {
    if (!mounted || _autoActivating) return;
    final result = await _activation.fetchStatus(_deviceId);
    if (!mounted || _autoActivating) return;
    if (result.status == ActivationStatus.approved &&
        result.listData != null) {
      _pollTimer?.cancel();
      _applyRemoteApproval(result.listData!);
    } else if (result.status == ActivationStatus.rejected) {
      _pollTimer?.cancel();
    }
  }

  /// Aplica a lista vinculada pelo operador e entra direto, sem aviso.
  Future<void> _applyRemoteApproval(ActivationListData list) async {
    _autoActivating = true;
    bool success = false;
    if (list.isXtream &&
        list.serverUrl != null &&
        list.username != null &&
        list.password != null) {
      success = await controller.loginXtream(
        serverUrl: list.serverUrl!,
        username: list.username!,
        password: list.password!,
      );
    } else if (list.isM3u && list.url != null && list.url!.isNotEmpty) {
      success = await controller.loadFromM3uUrl(list.url!);
    }
    if (success && mounted) {
      _openActive();
    } else {
      _autoActivating = false;
    }
  }

  Future<void> _loadRecent(BuildContext context, String url) async {
    final ok = await controller.loadFromM3uUrl(url);
    if (ok && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (context.mounted && controller.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage!),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeActive(BuildContext context) async {
    await controller.logout();
  }

  void _openActive() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => HomeScreen(controller: controller)),
      (r) => false,
    );
  }

  /// Botão voltar visível: retorna à Home se veio de lá (botão Listas);
  /// se a Playlist é a raiz, exige 2 toques para sair (mesma lógica do
  /// gesto/D-pad, via [_backController] compartilhado).
  void _onBackButton() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    if (_backController.registerPress()) {
      SystemNavigator.pop();
    } else {
      showExitHint(context, 'Pressione voltar novamente para sair');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final storage = controller.storageService;
        final account = controller.currentAccount;
        final lastUrl = storage.getLastM3uUrl();
        final recents = storage
            .getRecentUrls()
            .where((u) => u != lastUrl)
            .toList();

        final hasActive =
            account != null || (lastUrl != null && lastUrl.isNotEmpty);
        final activeName = account != null
            ? account.username
            : (controller.loadedListName ?? lastUrl ?? '');
        final rows = <_PlaylistRow>[];
        if (hasActive) {
          rows.add(_PlaylistRow(
              name: activeName, url: lastUrl, isXtream: account != null));
        }
        for (final u in recents) {
          rows.add(_PlaylistRow(name: u, url: u, isXtream: false));
        }

        return DoubleBackToExit(
          controller: _backController,
          child: Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TvFocusable(
                            borderRadius: BorderRadius.circular(10),
                            onPressed: _onBackButton,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                  size: 26),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Playlist',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 30)),
                          ),
                          TvFocusable(
                            borderRadius: BorderRadius.circular(8),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AddPlaylistScreen(
                                      controller: controller),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.cardBorder),
                              ),
                              child: const Text('+',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (rows.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Text(
                                'Nenhuma playlist. Toque em + para adicionar.',
                                style: TextStyle(
                                    color: AppColors.textSecondary)),
                          ),
                        )
                      else
                        ...rows.asMap().entries.map((e) {
                          final i = e.key;
                          final row = e.value;
                          final selected = i == 0 && hasActive;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TvFocusable(
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    onPressed: () {
                                      if (i == 0 && hasActive) {
                                        _openActive();
                                      } else if (row.url != null) {
                                        _loadRecent(context, row.url!);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 16),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? Colors.white
                                            : AppColors.surface,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: selected
                                                ? Colors.white
                                                : AppColors.cardBorder),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 36,
                                            child: Text('${i + 1}',
                                                style: TextStyle(
                                                    color: selected
                                                        ? Colors.black54
                                                        : AppColors
                                                            .textSecondary,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontSize: 16)),
                                          ),
                                          Expanded(
                                            child: Text(
                                              row.name,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: selected
                                                      ? Colors.black
                                                      : Colors.white,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  fontSize: 16),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TvFocusable(
                                  borderRadius:
                                      BorderRadius.circular(24),
                                  onPressed: () async {
                                    if (i == 0 && hasActive) {
                                      await _removeActive(context);
                                    } else if (row.url != null) {
                                      await storage
                                          .removeRecentUrl(row.url!);
                                      controller.refresh();
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: AppColors.cardBorder),
                                    ),
                                    child: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.white70,
                                        size: 20),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const Spacer(),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                                'Web Page: https://mcplayer.app',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                          Text('Device key: $_deviceId',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('Mac Address: $_deviceMac',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    ],
                  ),
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
          ),
          ),
        );
      },
    );
  }
}

class _PlaylistRow {
  final String name;
  final String? url;
  final bool isXtream;

  _PlaylistRow({required this.name, this.url, required this.isXtream});
}
