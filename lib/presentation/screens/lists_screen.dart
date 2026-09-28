import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/activation/activation_models.dart';
import '../../core/activation/activation_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/back_navigation_mixin.dart';
import '../../data/models/xtream_account.dart';
import '../controllers/iptv_controller.dart';
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

class _ListsScreenState extends State<ListsScreen> with BackNavigationMixin {
  IptvController get controller => widget.controller;

  // Ativação remota via Dashboard (Supabase), silenciosa: sem aviso
  // visível — a lista aprovada no painel entra sozinha.
  final ActivationService? _activation = sl.activationService;
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
    final activation = _activation;
    if (activation == null || !activation.isEnabled) return;
    final result = await activation.checkIn(
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
    final activation = _activation;
    if (!mounted || _autoActivating || activation == null) return;
    final result = await activation.fetchStatus(_deviceId);
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
      _openActive();
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

  Future<void> _loadXtream(
      BuildContext context, XtreamAccount account) async {
    final ok = await controller.loginXtream(
      serverUrl: account.serverUrl,
      username: account.username,
      password: account.password,
    );
    if (ok && context.mounted) {
      _openActive();
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
  /// se a Playlist é a raiz, exige 2 toques para sair (via BackGuard).
  void _onBackButton() => handleBackButton();

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
        // Multi-listas: contas Xtream salvas (exceto a ativa) p/ trocar
        // sem redigitar. M3U recentes continuam abaixo como antes.
        for (final saved in storage.getXtreamAccounts()) {
          final isActive = account != null &&
              saved.serverUrl == account.serverUrl &&
              saved.username == account.username;
          if (isActive) continue;
          if (rows.any((r) =>
              r.account != null &&
              r.account!.serverUrl == saved.serverUrl &&
              r.account!.username == saved.username)) {
            continue;
          }
          rows.add(_PlaylistRow(
              name: saved.username, isXtream: true, account: saved));
        }
        for (final u in recents) {
          rows.add(_PlaylistRow(name: u, url: u, isXtream: false));
        }

        return buildWithDoubleBackExit(
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
                                      } else if (row.account != null) {
                                        _loadXtream(context, row.account!);
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
                                    } else if (row.account != null) {
                                      await storage.removeXtreamAccount(
                                          row.account!);
                                      controller.refresh();
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
  final XtreamAccount? account;

  _PlaylistRow(
      {required this.name,
      this.url,
      required this.isXtream,
      this.account});
}