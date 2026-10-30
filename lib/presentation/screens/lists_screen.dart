import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/activation/activation_models.dart';
import '../../core/activation/activation_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/back_navigation_mixin.dart';
import '../../data/models/xtream_account.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/double_back_to_exit.dart';
import '../widgets/exit_confirmation_dialog.dart';
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

class _ListsScreenState extends State<ListsScreen>
    with BackNavigationMixin, WidgetsBindingObserver {
  IptvController get controller => widget.controller;

  // Ativação remota via Dashboard (Supabase), silenciosa: sem aviso
  // visível — a lista aprovada no painel entra sozinha.
  final ActivationService? _activation = sl.activationService;

  /// True quando o APK foi compilado sem SUPABASE_URL/ANON_KEY.
  /// Nesse caso o aparelho nunca chega ao dashboard — mostra aviso
  /// visível em vez de falhar em silêncio.
  bool get _activationDisabled => _activation == null;
  Timer? _pollTimer;
  bool _autoActivating = false;

  /// Estado do registro no painel (mostrado no rodapé da tela).
  bool _registering = false;
  bool _registered = false;
  String? _activationError;
  int? _activationErrorStatus;

  // Exponential backoff para polling: 10s -> 20s -> 30s -> 30s (max)
  int _pollAttempt = 0;
  static const int _maxPollInterval = 30; // segundos
  static const int _basePollInterval = 10; // segundos

  /// Sempre lê a chave atual do storage: se o Dashboard recusar por colisão,
  /// o `checkIn` gera uma chave nova (persistida) e o polling já usa a nova.
  String get _deviceId => controller.storageService.getDeviceId();
  String get _deviceMac => controller.storageService.getDeviceMac();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupActivation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Na Fire TV o app volta do background pelo controle. Se o primeiro
    // check-in falhou (Wi-Fi ainda subindo), sem isto ele nunca mais era
    // enviado e o aparelho não aparecia no painel. Registra de novo.
    if (state == AppLifecycleState.resumed) {
      _setupActivation();
    }
  }

  /// Calcula o intervalo de polling com exponential backoff
  int _getPollInterval() {
    final interval =
        _basePollInterval *
        (1 << (_pollAttempt.clamp(0, 3))); // 10, 20, 30, 30...
    return interval.clamp(_basePollInterval, _maxPollInterval);
  }

  /// Agenda o próximo polling com backoff
  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    final interval = _getPollInterval();
    _pollTimer = Timer(Duration(seconds: interval), () {
      if (mounted) _pollActivation();
    });
  }

  /// Ativação remota: registra a chave no Dashboard e observa aprovação
  /// em silêncio. Sem configuração no ActivationConfig, não faz nada.
  Future<void> _setupActivation() async {
    final activation = _activation;
    if (activation == null || !activation.isEnabled) return;
    if (_registering) return;
    _registering = true;
    _pollAttempt = 0; // reset no início
    if (mounted) setState(() {});

    final result = await activation.checkIn(
      deviceId: _deviceId,
      mac: _deviceMac,
      regenerateDeviceId: controller.storageService.newDeviceId,
    );
    if (!mounted) return;
    _registering = false;

    switch (result.status) {
      case ActivationStatus.approved:
        _registered = true;
        _activationError = null;
        _activationErrorStatus = null;
        setState(() {});
        if (result.listData != null) {
          _applyRemoteApproval(result.listData!);
          return;
        }
        _scheduleNextPoll();
      case ActivationStatus.pending:
        _registered = true;
        _activationError = null;
        _activationErrorStatus = null;
        setState(() {});
        _scheduleNextPoll();
      case ActivationStatus.rejected:
      case ActivationStatus.blocked:
        _registered = true;
        _activationError = null;
        _activationErrorStatus = null;
        setState(() {});
        _pollTimer?.cancel();
      case ActivationStatus.notFound:
        // O painel não confirmou o registro (rede, URL/projeto errado ou
        // RPC ausente). Guarda o motivo para mostrar na TV e tenta de novo
        // no próximo polling — antes o app só consultava e nunca reenviava.
        _registered = false;
        _activationError = result.message ?? activation.lastError;
        _activationErrorStatus = activation.lastHttpStatus;
        setState(() {});
        _pollAttempt++;
        _scheduleNextPoll();
      case ActivationStatus.disabled:
        break;
    }
  }

  /// Reenvia o check-in manualmente (botão "Tentar novamente" do rodapé).
  Future<void> _retryActivation() => _setupActivation();

  /// Aviso do rodapé: mostra no próprio aparelho se o registro no painel
  /// falhou (com o código HTTP) e permite reenviar sem reinstalar o APK.
  Widget _activationStatusBanner() {
    if (_registering) {
      return _banner(
        color: Colors.white54,
        icon: Icons.cloud_upload_outlined,
        child: const Text(
          'Registrando este aparelho no painel...',
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      );
    }
    if (_activationError != null) {
      final status = _activationErrorStatus;
      return _banner(
        color: Colors.orange,
        icon: Icons.cloud_off_rounded,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Não foi possível registrar no painel'
                '${status != null ? ' (HTTP $status)' : ''}: $_activationError',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            TvFocusable(
              borderRadius: BorderRadius.circular(8),
              onPressed: _retryActivation,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  'Tentar novamente',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_registered) {
      return _banner(
        color: Colors.lightGreenAccent,
        icon: Icons.cloud_done_outlined,
        child: const Text(
          'Aparelho registrado no painel. Aguardando aprovação.',
          style: TextStyle(
            color: Colors.lightGreenAccent,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _banner({
    required Color color,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  Future<void> _pollActivation() async {
    final activation = _activation;
    if (!mounted || _autoActivating || activation == null) return;
    final result = await activation.fetchStatus(_deviceId);
    if (!mounted || _autoActivating) return;
    if (result.status == ActivationStatus.approved && result.listData != null) {
      _registered = true;
      _activationError = null;
      _activationErrorStatus = null;
      setState(() {});
      _pollTimer?.cancel();
      _applyRemoteApproval(result.listData!);
    } else if (result.status == ActivationStatus.rejected ||
        result.status == ActivationStatus.blocked) {
      _registered = true;
      _pollTimer?.cancel();
      // Dispositivo rejeitado/bloqueado: para de fazer polling permanentemente
      // (o usuário terá que falar com o suporte / adicionar lista manualmente)
    } else if (result.status == ActivationStatus.notFound) {
      // Não está (ou deixou de estar) no painel — o 1º check-in pode ter
      // falhado antes do Wi-Fi subir. Refaz o REGISTRO, não só a consulta.
      _activationError = result.message ?? activation.lastError;
      _activationErrorStatus = activation.lastHttpStatus;
      await _setupActivation();
    } else {
      // Ainda pendente: agenda próximo polling com backoff
      _registered = true;
      _activationError = null;
      _activationErrorStatus = null;
      _pollAttempt++;
      _scheduleNextPoll();
    }
  }

  /// Aplica a lista vinculada pelo operador e entra direto, sem aviso.
  /// Se falhar (lista inválida / login Xtream recusado / sem rede),
  /// reagenda o polling em vez de parar — senão o app trava na Playlist
  /// mesmo com o Dashboard mostrando "aprovado".
  Future<void> _applyRemoteApproval(ActivationListData list) async {
    _autoActivating = true;
    bool success = false;
    try {
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
    } catch (_) {
      success = false;
    }
    if (success && mounted) {
      _openActive();
    } else {
      _autoActivating = false;
      // Falhou: continua observando o Dashboard (operador pode corrigir
      // a lista). Mostra o motivo uma vez para não deixar em silêncio.
      if (mounted) {
        final msg = controller.errorMessage;
        if (msg != null && msg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Lista aprovada mas falhou: $msg. Aguardando correção no painel...',
              ),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      _pollAttempt++;
      _scheduleNextPoll();
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

  Future<void> _loadXtream(BuildContext context, XtreamAccount account) async {
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
      MaterialPageRoute(builder: (_) => HomeScreen(controller: controller)),
      (r) => false,
    );
  }

  /// Botão voltar visível: retorna à Home se veio de lá (botão Listas);
  /// se a Playlist é a raiz, NÃO dá pop (dava tela preta) — mostra o
  /// aviso de "voltar 2x para sair", a saída fica com o voltar do sistema.
  void _onBackButton() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
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
          rows.add(
            _PlaylistRow(
              name: activeName,
              url: lastUrl,
              isXtream: account != null,
            ),
          );
        }
        // Multi-listas: contas Xtream salvas (exceto a ativa) p/ trocar
        // sem redigitar. M3U recentes continuam abaixo como antes.
        for (final saved in storage.getXtreamAccounts()) {
          final isActive =
              account != null &&
              saved.serverUrl == account.serverUrl &&
              saved.username == account.username;
          if (isActive) continue;
          if (rows.any(
            (r) =>
                r.account != null &&
                r.account!.serverUrl == saved.serverUrl &&
                r.account!.username == saved.username,
          )) {
            continue;
          }
          rows.add(
            _PlaylistRow(name: saved.username, isXtream: true, account: saved),
          );
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
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Playlist',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 30,
                                ),
                              ),
                            ),
                            TvFocusable(
                              borderRadius: BorderRadius.circular(8),
                              onPressed: () => confirmExitApp(context),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.accentLive.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.accentLive.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.power_settings_new_rounded,
                                  color: AppColors.accentLive,
                                  size: 20,
                                ),
                              ),
                            ),
                            TvFocusable(
                              borderRadius: BorderRadius.circular(8),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AddPlaylistScreen(
                                      controller: controller,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.cardBorder,
                                  ),
                                ),
                                child: const Text(
                                  '+',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  ),
                                ),
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
                                  color: AppColors.textSecondary,
                                ),
                              ),
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
                                      borderRadius: BorderRadius.circular(10),
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
                                          horizontal: 18,
                                          vertical: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? Colors.white
                                              : AppColors.surface,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: selected
                                                ? Colors.white
                                                : AppColors.cardBorder,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 36,
                                              child: Text(
                                                '${i + 1}',
                                                style: TextStyle(
                                                  color: selected
                                                      ? Colors.black54
                                                      : AppColors.textSecondary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                row.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: selected
                                                      ? Colors.black
                                                      : Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  TvFocusable(
                                    borderRadius: BorderRadius.circular(24),
                                    onPressed: () async {
                                      if (i == 0 && hasActive) {
                                        await _removeActive(context);
                                      } else if (row.account != null) {
                                        await storage.removeXtreamAccount(
                                          row.account!,
                                        );
                                        controller.refresh();
                                      } else if (row.url != null) {
                                        await storage.removeRecentUrl(row.url!);
                                        controller.refresh();
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.cardBorder,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        const Spacer(),
                        if (!_activationDisabled) _activationStatusBanner(),
                        if (_activationDisabled)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.6),
                              ),
                            ),
                            child: const Text(
                              'Ativação remota DESLIGADA neste APK: este aparelho não aparece no dashboard. '
                              'Instale o APK oficial (ou compile com SUPABASE_URL e SUPABASE_ANON_KEY) '
                              'e informe a Device key abaixo ao suporte.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Web Page: https://mcplayer.app',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              'Device key: $_deviceId',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Mac Address: $_deviceMac',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
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
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              controller.loadingStatus.isNotEmpty
                                  ? controller.loadingStatus
                                  : 'Carregando...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
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

  _PlaylistRow({
    required this.name,
    this.url,
    required this.isXtream,
    this.account,
  });
}
