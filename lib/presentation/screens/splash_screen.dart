import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/app_logo.dart';
import '../../core/activation/activation_config.dart';
import '../../core/activation/activation_models.dart';
import 'home_screen.dart';
import 'lists_screen.dart';

/// Tempo mínimo antes de tentar baixar de novo uma lista do painel que falhou.
const Duration _panelListRetryDelay = Duration(hours: 6);

class SplashScreen extends StatefulWidget {
  final IptvController controller;

  const SplashScreen({super.key, required this.controller});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));

    _animController.forward();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    final storage = widget.controller.storageService;

    // 1. Se a ativação remota do Dashboard estiver ativa, consulta o Supabase primeiro!
    if (ActivationConfig.isEnabled) {
      final activation = sl.activationService;
      if (activation == null) return;
      // Fire TV liga o Wi-Fi alguns segundos depois do app abrir. Uma única
      // tentativa podia falhar e o aparelho nunca aparecia no painel.
      // Repetimos só em erro de rede/5xx (4xx é definitivo).
      ActivationResult result = const ActivationResult(
        status: ActivationStatus.notFound,
      );
      for (var attempt = 1; attempt <= 3; attempt++) {
        result = await activation.checkIn(
          deviceId: storage.getDeviceId(),
          mac: storage.getDeviceMac(),
          regenerateDeviceId: storage.newDeviceId,
        );
        if (!mounted) return;
        if (result.status != ActivationStatus.notFound) break;
        final httpStatus = activation.lastHttpStatus;
        if (httpStatus != null && httpStatus >= 400 && httpStatus < 500) {
          break;
        }
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
          if (!mounted) return;
        }
      }

      if (result.status == ActivationStatus.approved &&
          result.listData != null) {
        // Voltou ao modo MAC + código: a sessão por credenciais deixa de
        // valer sobre um bloqueio feito no painel.
        await storage.setCredentialLogin(false);
        final list = result.listData!;

        // A lista que o aparelho já tem salva abre na hora. Baixar só
        // acontece na troca de lista (painel diferente) ou no Recarregar.
        if (await _loadPanelList(list, cacheOnly: true)) {
          _openHome();
          return;
        }

        // Painel apontando para uma lista nova, mas já existe outra salva:
        // abre a salva e busca a do painel em segundo plano.
        if (await _openFromCache()) {
          _openHome();
          final panelKey = _panelSourceKey(list);
          if (panelKey != null &&
              widget.controller.catalogSourceKey != panelKey) {
            unawaited(_syncPanelList(list, panelKey));
          }
          return;
        }

        // Primeira abertura no aparelho: baixa a lista do painel.
        if (await _loadPanelList(list)) {
          _openHome();
          return;
        }
      } else if (result.status == ActivationStatus.pending ||
          result.status == ActivationStatus.rejected ||
          result.status == ActivationStatus.blocked) {
        // Quem entrou com usuário/senha não fica preso na aprovação por MAC:
        // a conta Xtream ativa é a própria liberação.
        if (storage.getCredentialLogin()) {
          final saved = storage.getXtreamAccount();
          if (saved != null) {
            final cached = await widget.controller.loginXtream(
              serverUrl: saved.serverUrl,
              username: saved.username,
              password: saved.password,
              allowCache: true,
              cacheOnly: true,
            );
            if (cached) {
              _openHome();
              return;
            }
            if (mounted) {
              try {
                await widget.controller.xtreamApi.authenticate(
                  serverUrl: saved.serverUrl,
                  username: saved.username,
                  password: saved.password,
                );
                final ok = await widget.controller.loginXtream(
                  serverUrl: saved.serverUrl,
                  username: saved.username,
                  password: saved.password,
                  allowCache: true,
                );
                if (ok) {
                  _openHome();
                  return;
                }
              } catch (e) {
                debugPrint('[Splash] conta por credenciais indisponível: $e');
              }
            }
          }
        }
        // Aparelho pendente de aprovação ou rejeitado:
        // Abre direto a tela de Listas/Ativação onde mostra a chave e faz polling
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ListsScreen(controller: widget.controller),
          ),
        );
        return;
      }
    }

    // 2. Lista salva no aparelho (conta Xtream, M3U ou arquivo local)
    if (await _openFromCache()) {
      _openHome();
      return;
    }

    // 3. Nada salvo ainda: tenta baixar a lista da conta guardada
    final savedAccount = storage.getXtreamAccount();
    if (savedAccount != null) {
      final success = await widget.controller.loginXtream(
        serverUrl: savedAccount.serverUrl,
        username: savedAccount.username,
        password: savedAccount.password,
        allowCache: true,
      );
      if (success) {
        _openHome();
        return;
      }
    }

    final lastUrl = storage.getLastM3uUrl();
    if (lastUrl != null && lastUrl.isNotEmpty) {
      final success = await widget.controller.loadFromM3uUrl(
        lastUrl,
        allowCache: true,
      );
      if (success) {
        _openHome();
        return;
      }
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ListsScreen(controller: widget.controller),
        ),
      );
    }
  }

  void _openHome() {
    if (!mounted) return;
    _registerActiveAccount();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(controller: widget.controller),
      ),
    );
  }

  /// Avisa o painel qual aparelho está usando a conta Xtream. Roda em toda
  /// abertura (inclusive com catálogo do cache) para o painel mostrar os
  /// aparelhos conectados e atualizar o "último acesso" — antes só acontecia
  /// no login manual, então quem nunca redigitava a senha não aparecia.
  void _registerActiveAccount() {
    final activation = sl.activationService;
    final account = widget.controller.currentAccount;
    if (activation == null || account == null) return;
    final storage = widget.controller.storageService;
    unawaited(
      activation.registerXtreamLogin(
        serverUrl: account.serverUrl,
        username: account.username,
        deviceId: storage.getDeviceId(),
        mac: storage.getDeviceMac(),
        status: account.status,
        expDate: account.expDateIso,
      ),
    );
  }

  /// Abre a lista que já está salva no aparelho, sem tocar na rede.
  Future<bool> _openFromCache() async {
    final storage = widget.controller.storageService;
    final saved = storage.getXtreamAccount();
    if (saved != null) {
      final ok = await widget.controller.loginXtream(
        serverUrl: saved.serverUrl,
        username: saved.username,
        password: saved.password,
        allowCache: true,
        cacheOnly: true,
      );
      if (ok) return true;
    }
    final url = storage.getLastM3uUrl();
    if (url != null && url.isNotEmpty) {
      final ok = await widget.controller.loadFromM3uUrl(
        url,
        allowCache: true,
        cacheOnly: true,
      );
      if (ok) return true;
    }
    final path = storage.getLastM3uPath();
    if (path != null && path.isNotEmpty) {
      return widget.controller.loadFromLocalFile(
        path,
        allowCache: true,
        cacheOnly: true,
      );
    }
    return false;
  }

  Future<bool> _loadPanelList(
    ActivationListData list, {
    bool cacheOnly = false,
    bool silent = false,
  }) {
    if (list.isXtream &&
        list.serverUrl != null &&
        list.username != null &&
        list.password != null) {
      return widget.controller.loginXtream(
        serverUrl: list.serverUrl!,
        username: list.username!,
        password: list.password!,
        allowCache: true,
        cacheOnly: cacheOnly,
        silent: silent,
      );
    }
    if (list.isM3u && (list.url ?? '').isNotEmpty) {
      return widget.controller.loadFromM3uUrl(
        list.url!,
        allowCache: true,
        cacheOnly: cacheOnly,
        silent: silent,
      );
    }
    return Future<bool>.value(false);
  }

  String? _panelSourceKey(ActivationListData list) {
    if (list.isXtream && list.serverUrl != null && list.username != null) {
      return widget.controller.sourceKeyForXtream(
        list.serverUrl!,
        list.username!,
      );
    }
    final url = list.url;
    if (list.isM3u && url != null && url.isNotEmpty) {
      return widget.controller.sourceKeyForM3u(url);
    }
    return null;
  }

  /// Baixa em segundo plano a lista que o painel mandou e troca o catálogo
  /// quando terminar. Uma lista que já falhou não é tentada de novo por
  /// [_panelListRetryDelay] — assim a abertura não gasta rede todo dia com
  /// uma lista que o aparelho não consegue carregar.
  ///
  /// Vale só para Xtream: M3U do painel pode ter centenas de milhares de
  /// linhas e não dá para arriscar um download em segundo plano sem o
  /// cliente pedir (Recarregar/troca de lista).
  Future<void> _syncPanelList(
    ActivationListData list,
    String panelKey,
  ) async {
    if (!list.isXtream) return;
    final storage = widget.controller.storageService;
    final failure = storage.getPanelListFailure();
    if (failure != null &&
        failure.sourceKey == panelKey &&
        DateTime.now().difference(failure.at) < _panelListRetryDelay) {
      return;
    }
    final ok = await _loadPanelList(list, silent: true);
    if (ok) {
      await storage.clearPanelListFailure();
    } else {
      await storage.setPanelListFailure(panelKey);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(iconSize: 84, titleSize: 36),
                const SizedBox(height: 36),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
