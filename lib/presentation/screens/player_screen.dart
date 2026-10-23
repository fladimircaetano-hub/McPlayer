import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/back_navigation_mixin.dart';
import '../../core/utils/playback_math.dart';
import '../../data/models/stream_item.dart';
import '../widgets/tv_focusable.dart';

enum PlayerAspect {
  fit16x9('16:9', 16 / 9, BoxFit.contain),
  fit4x3('4:3', 4 / 3, BoxFit.contain),
  fill('Preencher', null, BoxFit.cover),
  stretch('Esticar', null, BoxFit.fill),
  original('Original', null, BoxFit.contain);

  final String label;
  final double? ratio;
  final BoxFit fit;
  const PlayerAspect(this.label, this.ratio, this.fit);
}

class PlayerScreen extends StatefulWidget {
  final StreamItem item;
  final List<StreamItem>? playlist;
  final int? initialIndex;
  final bool keepScreenOn;

  const PlayerScreen({
    super.key,
    required this.item,
    this.playlist,
    this.initialIndex,
    this.keepScreenOn = true,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with BackNavigationMixin {
  Player? _player;
  VideoController? _videoController;
  late StreamItem _currentItem;
  late List<StreamItem> _playlist;
  int _currentIndex = -1;

  /// Web não tem mpv nativo: mostra preview do layout sem reproduzir.
  bool get _isWebPreview => kIsWeb;

  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  Timer? _hideTimer;

  bool _isPlaying = false;
  bool _isBuffering = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Tracks? _tracks;
  bool _isSeeking = false;
  double? _seekPreview;

  /// Segura a posição otimista por alguns instantes após um seek, para o
  /// stream antigo do mpv não "puxar" a barra de volta.
  Duration? _seekHoldPosition;
  DateTime? _seekHoldUntil;
  DateTime? _lastSurfaceTapAt;

  int _retryCount = 0;
  static const int _maxRetries = 2;
  int _openGeneration = 0;

  /// Watchdog anti-travamento: detecta buffering infinito ou frame
  /// congelado (posição sem avançar em VOD) e reconecta sozinho.
  Timer? _stallTimer;
  DateTime? _bufferingSince;
  DateTime _lastProgressAt = DateTime.now();
  static const _bufferTimeout = Duration(seconds: 25);
  static const _stallTimeout = Duration(seconds: 20);
  bool _watchdogActive = false;
  
  // Para detectar "frame congelado" em live streams com timestamp parado
  int _lastKnownPosition = -1;
  int _stallPositionCount = 0;

  PlayerAspect _currentAspect = PlayerAspect.original;

  double _volume = 1.0;
  double _brightness = 0.5;
  bool _isAdjustingVolume = false;
  bool _isAdjustingBrightness = false;

  final List<StreamSubscription> _subs = [];

  final FocusNode _playPauseNode = FocusNode();
  final FocusNode _reconnectNode = FocusNode();
  final FocusNode _aspectNode = FocusNode();
  final FocusNode _backNode = FocusNode();
  final FocusNode _prevNode = FocusNode();
  final FocusNode _nextNode = FocusNode();
  final FocusNode _back10Node = FocusNode();
  final FocusNode _fwd10Node = FocusNode();
  final FocusNode _sliderNode = FocusNode();

  /// Nós da tela de erro: o overlay entra depois do build inicial, então o
  /// autofocus sozinho nem sempre entrega o foco no Fire TV (D-pad). Sem
  /// foco, o OK não ativa nenhum botão — por isso forçamos o foco via
  /// [_focusErrorOverlay] sempre que o erro aparece.
  final FocusNode _errorBackNode = FocusNode();
  final FocusNode _errorRetryNode = FocusNode();

  static const _uaHeaders = {
    'User-Agent': 'IPTVSmarters/1.0.0 (Linux; Android 12)',
  };

  @override
  void initState() {
    super.initState();
    // Libera os pôsteres da RAM ao abrir o player (as listas ficam na
    // pilha de navegação segurando imagens; no stick de 1 GB isso conta).
    PaintingBinding.instance.imageCache.clear();
    _playlist = widget.playlist == null
        ? <StreamItem>[]
        : orderPlaylistForPlayback(widget.playlist!);
    _currentItem = widget.item;
    if (_playlist.isNotEmpty) {
      // Depois da ordenação (séries), o índice recebido pode não valer mais:
      // localiza pelo item de verdade e só usa o índice como fallback.
      final found = _playlist.indexWhere(
        (e) => e.id == widget.item.id && e.streamUrl == widget.item.streamUrl,
      );
      if (found >= 0) {
        _currentIndex = found;
        _currentItem = _playlist[found];
      } else {
        final initial = widget.initialIndex;
        if (initial != null && initial >= 0 && initial < _playlist.length) {
          _currentIndex = initial;
          _currentItem = _playlist[initial];
        }
      }
    }

    if (_isWebPreview) {
      // Preview web: sem player nativo, só layout + aviso.
      _isBuffering = false;
    } else {
      _initNativePlayer();
    }

    if (widget.keepScreenOn) {
      WakelockPlus.enable();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _initBrightness();
  }

  /// Inicialização ordenada do player nativo: cria, liga a decodificação
  /// por hardware e só então abre a stream. `auto-safe` seleciona o decodificador
  /// por hardware ideal para a plataforma (MediaCodec no Android, D3D11VA no Windows)
  /// e faz fallback limpo para software se não disponível.
  Future<void> _initNativePlayer() async {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'MC Player',
        osc: false,
      ),
    );
    try {
      final platform = _player!.platform;
      if (platform != null) {
        final dyn = platform as dynamic;
        
        // ========== DECODIFICAÇÃO DE HARDWARE ==========
        // auto-safe: tenta hwdec, cai para software se falhar
        await dyn
            .setProperty('hwdec', 'auto-safe')
            .timeout(const Duration(seconds: 5));
        
        // ========== BUFFER/MEMÓRIA (OTIMIZADO P/ 1 GB RAM) ==========
        // Stick de 1 GB: o padrão do mpv (250 MB + 100 MB back) estoura a RAM
        // e o sistema mata o app (LMK). Valores reduzidos com margem de segurança.
        await dyn
            .setProperty('demuxer-max-bytes', '48MiB')     // era 64MiB
            .timeout(const Duration(seconds: 5));
        await dyn
            .setProperty('demuxer-max-back-bytes', '8MiB')  // era 16MiB
            .timeout(const Duration(seconds: 5));
        
        // Cache de rede: menor = menos RAM, mas pode travar em rede instável
        // 8s é equilíbrio para HLS live; VOD busca sob demanda
        await dyn
            .setProperty('cache-secs', '8')                 // era 10
            .timeout(const Duration(seconds: 3));
        await dyn
            .setProperty('cache-pause', 'yes')              // pausa download quando pausado
            .timeout(const Duration(seconds: 3));
        
        // ========== ESTABILIDADE DE REDE ==========
        // Reconexão automática em falhas de rede transitórias
        await dyn
            .setProperty('network-timeout', '20')           // timeout de rede (segundos)
            .timeout(const Duration(seconds: 3));
        await dyn
            .setProperty('reconnect-streamed', 'yes')       // reconecta streams ao vivo
            .timeout(const Duration(seconds: 3));
        await dyn
            .setProperty('reconnect-delay-max', '5')        // max delay entre retries
            .timeout(const Duration(seconds: 3));
        
        // ========== HLS ESPECÍFICO ==========
        // Melhora robustez de HLS (muito usado em IPTV)
        await dyn
            .setProperty('hls-bitrate', 'auto')             // seleção adaptativa
            .timeout(const Duration(seconds: 3));
        await dyn
            .setProperty('hls-max-bitrate', '5000000')      // limite 5 Mbps p/ sticks
            .timeout(const Duration(seconds: 3));
        
        // ========== BAIXA LATÊNCIA (LIVE) ==========
        // Reduz buffer para canais ao vivo (zapping mais rápido)
        await dyn
            .setProperty('cache-pause-initial', 'yes')      // não bufferiza antes do play
            .timeout(const Duration(seconds: 3));
        
        // ========== LOGGING DEBUG (DESABILITADO EM PRODUÇÃO) ==========
        // await dyn.setProperty('msg-level', 'all=warn');   // reduz logs verbosos
      }
    } catch (e) {
      // Aparelho sem suporte: segue em software.
      debugPrint('[Player] hwdec/setup failed (fallback to software): $e');
    }
    if (!mounted) return;
    setState(() {
      _videoController = VideoController(
        _player!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
    });
    _subscribe();
    _open(_currentItem.streamUrl);
    _startStallWatchdog();
  }

  void _subscribe() {
    _subs.add(_player!.stream.playing.listen((playing) {
      if (mounted && playing != _isPlaying) {
        setState(() => _isPlaying = playing);
        if (playing) _resetControlsTimeout();
      }
    }, onError: (e) {
      debugPrint('[Player] playing stream error: $e');
    }));
    _subs.add(_player!.stream.position.listen((pos) {
      // Throttle: só rebuild quando o segundo muda e não está arrastando.
      if (_isSeeking) return;
      // Após um seek, ignora posições antigas até o mpv alcançar o alvo.
      if (_shouldIgnoreStalePosition(pos)) return;
      if (mounted && pos.inSeconds != _position.inSeconds) {
        setState(() => _position = pos);
      }
      // Sinal de vida para o watchdog (mesmo sem rebuild).
      _lastProgressAt = DateTime.now();
    }, onError: (e) {
      debugPrint('[Player] position stream error: $e');
    }));
    _subs.add(_player!.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    }, onError: (e) {
      debugPrint('[Player] duration stream error: $e');
    }));
    _subs.add(_player!.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
      if (buffering) {
        _bufferingSince ??= DateTime.now();
      } else {
        _bufferingSince = null;
        _lastProgressAt = DateTime.now();
      }
    }, onError: (e) {
      debugPrint('[Player] buffering stream error: $e');
    }));
    _subs.add(_player!.stream.tracks.listen((tracks) {
      if (mounted) setState(() => _tracks = tracks);
    }, onError: (e) {
      debugPrint('[Player] tracks stream error: $e');
    }));
    _subs.add(_player!.stream.error.listen((error) {
      if (error.isNotEmpty) _onPlayerError(error);
    }, onError: (e) {
      debugPrint('[Player] error stream error: $e');
    }));
    _subs.add(_player!.stream.completed.listen((completed) {
      if (completed && mounted) _onCompleted();
    }, onError: (e) {
      debugPrint('[Player] completed stream error: $e');
    }));
  }

  void _startStallWatchdog() {
    _stallTimer?.cancel();
    _lastProgressAt = DateTime.now();
    _bufferingSince = DateTime.now();
    _lastKnownPosition = -1;
    _stallPositionCount = 0;
    _watchdogActive = true;
    _stallTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _isWebPreview || _hasError || _player == null || !_watchdogActive) return;
      final now = DateTime.now();

      // 1) Buffering infinito: nunca saiu do loading.
      if (_isBuffering && _bufferingSince != null) {
        if (now.difference(_bufferingSince!) >= _bufferTimeout) {
          _bufferingSince = now; // evita disparo duplo no próximo tick
          _autoReconnect('travou no carregamento');
        }
        return;
      }

      // 2) Frame congelado (apenas VOD): tocando, sem buffering, mas posição parada.
      // Em canais ao vivo (HLS/MPEG-TS), a posição costuma ficar estática em 0.
      if (!_isLive && _isPlaying && !_isBuffering) {
        final atEnd = _duration.inSeconds > 0 &&
            _position.inSeconds >= _duration.inSeconds - 1;
        if (!atEnd && now.difference(_lastProgressAt) >= _stallTimeout) {
          _lastProgressAt = now;
          _autoReconnect('imagem congelada');
        }
        return;
      }
      
      // 3) Live stream com timestamp parado (às vezes HLS para de atualizar posição)
      // Detecta se a posição não muda por muito tempo em stream ao vivo
      if (_isLive && _isPlaying && !_isBuffering) {
        final currentPos = _position.inSeconds;
        if (currentPos == _lastKnownPosition) {
          _stallPositionCount++;
          // Se posição não muda por 30s em live, pode ser stream travado
          if (_stallPositionCount >= 15) { // 15 * 2s = 30s
            _stallPositionCount = 0;
            _lastKnownPosition = -1;
            _autoReconnect('stream ao vivo sem progresso');
          }
        } else {
          _stallPositionCount = 0;
          _lastKnownPosition = currentPos;
        }
      }
    });
  }

  void _autoReconnect(String motivo) {
    if (!mounted || _hasError || !_watchdogActive) return;
    if (_retryCount >= _maxRetries) {
      _fail(
          'Conexão instável ($motivo após ${_maxRetries + 1} tentativas). Toque em Tentar Novamente.');
      return;
    }
    _retryCount++;
    if (mounted) setState(() => _isBuffering = true);
    _open(_currentItem.streamUrl, isRetry: true);
  }

  Future<void> _initBrightness() async {
    try {
      _brightness = await ScreenBrightness().system;
    } catch (_) {
      _brightness = 0.5;
    }
  }

  Future<void> _open(String url, {bool isRetry = false}) async {
    if (!isRetry) _retryCount = 0;
    // Geração: zaps rápidos disparam _open concorrentes no mesmo player
    // nativo — o atrasado (stale) deve abortar em vez de disputar o mpv,
    // o que derrubava o app principalmente em filmes (VOD).
    final gen = ++_openGeneration;
    _lastProgressAt = DateTime.now();
    _bufferingSince = DateTime.now();
    if (mounted) {
      setState(() {
        _hasError = false;
        _errorMessage = '';
        _isBuffering = true;
      });
    }
    try {
      // Suporte a URLs com headers no formato pipe: url|User-Agent=...&Referer=...
      String cleanUrl = url.trim();
      final headers = Map<String, String>.from(_uaHeaders);
      final pipeIndex = cleanUrl.indexOf('|');
      if (pipeIndex != -1) {
        final queryHeaders = cleanUrl.substring(pipeIndex + 1);
        cleanUrl = cleanUrl.substring(0, pipeIndex).trim();
        final pairs = queryHeaders.split('&');
        for (final pair in pairs) {
          final eq = pair.indexOf('=');
          if (eq != -1) {
            final k = pair.substring(0, eq).trim();
            final v = pair.substring(eq + 1).trim();
            if (k.isNotEmpty && v.isNotEmpty) {
              headers[k] = v;
            }
          }
        }
      }

      await _player!
          .open(Media(cleanUrl, httpHeaders: headers), play: true)
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw TimeoutException('Tempo esgotado (25s).'),
          );
      if (!mounted || gen != _openGeneration) return;
      await _player!.setVolume(_volume * 100);
      try {
        final _ = await (_player!.platform as dynamic)
            .getProperty('hwdec-current')
            .timeout(const Duration(seconds: 3));
        // debugPrint('[Player] hwdec-current=$current url=${_currentItem.streamUrl}');
      } catch (_) {}
      if (mounted) {
        _resetControlsTimeout();
      }
    } on TimeoutException catch (_) {
      if (!mounted || gen != _openGeneration) return;
      if (_retryCount < _maxRetries && mounted) {
        _retryCount++;
        await Future.delayed(Duration(seconds: _retryCount));
        if (mounted) return _open(url, isRetry: true);
      }
      if (mounted) {
        _fail('Tempo esgotado (tentativa ${_retryCount + 1}/${_maxRetries + 1}). Verifique a internet ou reconecte.');
      }
    } catch (e) {
      if (!mounted || gen != _openGeneration) return;
      final msg = e.toString().replaceAll('Exception:', '').trim();
      
      // Erro definitivo (DNS, servidor fora, bloqueio, auth): repetir não
      // adianta — mostra a falha na hora em vez de enrolar no retry.
      if (_isFatalError(msg)) {
        if (mounted) _fail('Falha ao conectar: $msg');
        return;
      }
      
      // Erro transitório (timeout, 5xx, rede instável): tenta retry com backoff
      if (_isTransientError(msg) && _retryCount < _maxRetries && mounted) {
        _retryCount++;
        final delay = Duration(seconds: _retryCount * 2); // backoff exponencial simples: 2s, 4s, 6s
        debugPrint('[Player] Transient error, retry $_retryCount/$_maxRetries in ${delay.inSeconds}s: $msg');
        await Future.delayed(delay);
        if (mounted) return _open(url, isRetry: true);
      }
      
      // Outros erros: tenta retry simples uma vez
      if (_retryCount < _maxRetries && mounted) {
        _retryCount++;
        await Future.delayed(Duration(seconds: _retryCount));
        if (mounted) return _open(url, isRetry: true);
      }
      if (mounted) {
        _fail('Falha ao conectar: $msg');
      }
    }
  }

  /// Erros que retry não resolve: DNS inexistente, conexão recusada,
  /// rede inalcançável e HTTP 401/403/404.
  bool _isFatalError(String message) {
    final m = message.toLowerCase();
    return m.contains('failed to resolve hostname') ||
        m.contains('no address associated with hostname') ||
        m.contains('connection refused') ||
        m.contains('connection reset') ||
        m.contains('network is unreachable') ||
        m.contains('no route to host') ||
        m.contains('http error 401') ||
        m.contains('http error 403') ||
        m.contains('http error 404') ||
        m.contains('http error 410') ||    // Gone
        m.contains('http error 503') ||    // Service Unavailable
        m.contains('ssl handshake') ||     // SSL/TLS falhou
        m.contains('certificate verify');  // Certificado inválido
  }

  /// Verifica se o erro é temporário e vale retry (rede instável, timeout)
  bool _isTransientError(String message) {
    final m = message.toLowerCase();
    return m.contains('timeout') ||
        m.contains('timed out') ||
        m.contains('connection reset') ||
        m.contains('broken pipe') ||
        m.contains('eof') ||
        m.contains('http error 500') ||    // Internal server error
        m.contains('http error 502') ||    // Bad gateway
        m.contains('http error 504');      // Gateway timeout
  }

  void _onPlayerError(String error) {
    if (!mounted || _hasError || !_watchdogActive) return;
    if (_isFatalError(error)) {
      _fail(error.length > 220 ? '${error.substring(0, 220)}...' : error);
      return;
    }
    
    // Erro transitório: usa backoff exponencial
    if (_isTransientError(error) && _retryCount < _maxRetries) {
      _retryCount++;
      final delay = Duration(seconds: _retryCount * 2);
      debugPrint('[Player] Stream error (transient), retry $_retryCount/$_maxRetries in ${delay.inSeconds}s: $error');
      Future.delayed(delay, () {
        if (mounted && _watchdogActive) _open(_currentItem.streamUrl, isRetry: true);
      });
      return;
    }
    
    // Outros erros: retry simples
    if (_retryCount < _maxRetries) {
      _retryCount++;
      Future.delayed(Duration(seconds: _retryCount), () {
        if (mounted && _watchdogActive) _open(_currentItem.streamUrl, isRetry: true);
      });
    } else {
      _fail(error.length > 220 ? '${error.substring(0, 220)}...' : error);
    }
  }

  /// Mostra a tela de erro e garante o foco no botão principal.
  /// Sem isso, no Fire TV o D-pad pode ficar sem alvo focado e o OK
  /// (nem o Voltar) responde.
  void _fail(String message) {
    if (!mounted) return;
    _watchdogActive = false; // Para o watchdog ao mostrar erro
    setState(() {
      _hasError = true;
      _isBuffering = false;
      _errorMessage = message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hasError) {
        _errorRetryNode.requestFocus();
      }
    });
  }

  void _onCompleted() {
    if (!_hasPlaylist) {
      if (mounted) setState(() => _showControls = true);
      return;
    }
    // Ao vivo mantém o rodízio; filmes/séries param no último item.
    final next = _isLive
        ? (_currentIndex + 1) % _playlist.length
        : nextIndex(_currentIndex, _playlist.length);
    if (next != null) {
      _zapTo(next);
    } else if (mounted) {
      setState(() => _showControls = true);
    }
  }

  bool get _hasPlaylist => _playlist.length > 1 && _currentIndex >= 0;

  bool get _isLive => _currentItem.streamType == StreamType.live;

  /// Teclado/controle: no Android (TV/box) as setas precisam navegar entre os
  /// botões; em desktop/web as setas buscam ±10s. Teclas de mídia funcionam
  /// em todos.
  bool get _arrowKeysSeek =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.android;

  int? get _prevTarget {
    if (!_hasPlaylist) return null;
    if (_isLive) return (_currentIndex - 1 + _playlist.length) % _playlist.length;
    return previousIndex(_currentIndex, _playlist.length);
  }

  int? get _nextTarget {
    if (!_hasPlaylist) return null;
    if (_isLive) return (_currentIndex + 1) % _playlist.length;
    return nextIndex(_currentIndex, _playlist.length);
  }

  bool get _canPrev => _prevTarget != null;
  bool get _canNext => _nextTarget != null;

  Future<void> _zapTo(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    if (_isWebPreview) {
      // Preview web: troca o item exibido sem reproduzir.
      setState(() {
        _currentIndex = index;
        _currentItem = _playlist[index];
        _showControls = true;
        _position = Duration.zero;
        _duration = Duration.zero;
        _seekPreview = null;
      });
      return;
    }
    _retryCount = 0;
    _seekHoldUntil = null;
    _seekHoldPosition = null;
    setState(() {
      _currentIndex = index;
      _currentItem = _playlist[index];
      _position = Duration.zero;
      _duration = Duration.zero;
      _seekPreview = null;
      _isSeeking = false;
      _isBuffering = true;
      // Mantém os controles visíveis para o usuário ver o novo título e o
      // contador (n/total); o timer esconde quando o vídeo engatar.
      _showControls = true;
    });
    _hideTimer?.cancel();
    await _open(_currentItem.streamUrl);
  }

  void _zapNext() {
    final target = _nextTarget;
    if (target != null) _zapTo(target);
  }

  void _zapPrev() {
    final target = _prevTarget;
    if (target != null) _zapTo(target);
  }

  void _reconnect() {
    if (_isWebPreview) {
      _webNotice();
      return;
    }
    _retryCount = 0;
    _watchdogActive = true; // Reativa watchdog ao reconectar manualmente
    _open(_currentItem.streamUrl);
  }

  void _webNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Preview web: reprodução com vídeo disponível no Windows/Android.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _togglePlay() {
    if (_isWebPreview) {
      _webNotice();
      return;
    }
    final player = _player;
    if (player == null) return;
    // Estado otimista: o botão responde na hora mesmo com o stream do mpv
    // atrasado (cliques rápidos não "perdem" o segundo clique).
    final next = !_isPlaying;
    setState(() => _isPlaying = next);
    player.playOrPause();
    _resetControlsTimeout();
  }

  void _play() {
    if (_isWebPreview || _player == null || _isPlaying) return;
    setState(() => _isPlaying = true);
    _player!.play();
    _resetControlsTimeout();
  }

  void _pause() {
    if (_isWebPreview || _player == null || !_isPlaying) return;
    setState(() => _isPlaying = false);
    _player!.pause();
    _resetControlsTimeout();
  }

  /// Posição antiga do mpv logo após um seek: ignora por até 1,2s, a menos
  /// que já esteja perto do alvo (aí o seek terminou).
  bool _shouldIgnoreStalePosition(Duration pos) {
    final until = _seekHoldUntil;
    final anchor = _seekHoldPosition;
    if (until == null || anchor == null) return false;
    if (DateTime.now().isAfter(until)) {
      _seekHoldUntil = null;
      _seekHoldPosition = null;
      return false;
    }
    if ((pos - anchor).abs() <= const Duration(seconds: 2)) {
      _seekHoldUntil = null;
      _seekHoldPosition = null;
      return false;
    }
    return true;
  }

  /// Aplica um seek com limite [0, duração], atualizando a barra na hora.
  void _seekTo(Duration target) {
    if (_isWebPreview || _isLive) return;
    var t = target;
    if (t < Duration.zero) t = Duration.zero;
    if (_duration > Duration.zero && t > _duration) t = _duration;

    _seekHoldPosition = t;
    _seekHoldUntil = DateTime.now().add(const Duration(milliseconds: 1200));
    _hideTimer?.cancel();
    setState(() {
      _position = t;
      _isSeeking = false;
      _seekPreview = null;
    });
    _player?.seek(t);
    _resetControlsTimeout();
  }

  void _seekBy(int seconds) {
    if (_isWebPreview || _isLive) return;
    _seekTo(clampSeekTarget(_position, seconds, _duration));
  }

  /// Toque/clique na área do vídeo: 1 toque mostra/esconde os controles,
  /// 2 toques rápidos alternam play/pause. Feito à mão (sem onDoubleTap)
  /// porque o reconhecedor de duplo toque do pai engolia os toques dos
  /// botões e da barra de progresso.
  void _handleSurfaceTap() {
    final now = DateTime.now();
    final last = _lastSurfaceTapAt;
    _lastSurfaceTapAt = now;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 320)) {
      _lastSurfaceTapAt = null;
      _togglePlay();
      return;
    }
    _toggleControls();
  }

  /// Select/Enter só chegam aqui quando nenhum botão focado consumiu a tecla
  /// (o TvFocusable trata select/enter dos botões).
  void _onSelectKey() {
    if (_hasError) return;
    if (!_showControls) _toggleControls();
  }

  void _resetControlsTimeout() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _resetControlsTimeout();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _cycleAspectRatio() {
    final next = (_currentAspect.index + 1) % PlayerAspect.values.length;
    setState(() => _currentAspect = PlayerAspect.values[next]);
    _resetControlsTimeout();
  }

  Future<void> _handleVerticalDragUpdate(DragUpdateDetails details, double screenWidth) async {
    final isLeft = details.globalPosition.dx < (screenWidth / 2);
    final delta = -details.primaryDelta! / 250;
    if (isLeft) {
      setState(() {
        _isAdjustingBrightness = true;
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
      });
      try {
        await ScreenBrightness().setApplicationScreenBrightness(_brightness);
      } catch (_) {
        // Fire TV e TVs não têm esse controle — ignora sem derrubar o app.
      }
    } else {
      setState(() {
        _isAdjustingVolume = true;
        _volume = (_volume + delta).clamp(0.0, 1.0);
      });
      _player?.setVolume(_volume * 100);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _isAdjustingBrightness = false;
          _isAdjustingVolume = false;
        });
      }
    });
  }

  void _showTracksSheet() {
    final tracks = _tracks;
    if (tracks == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Faixas de áudio / legendas',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                const Text('Áudio', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ...tracks.audio.map((t) => ListTile(
                      dense: true,
                      title: Text(t.title ?? t.language ?? t.id,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                      trailing: _player!.state.track.audio.id == t.id
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () {
                        _player!.setAudioTrack(t);
                        Navigator.pop(context);
                      },
                    )),
                const SizedBox(height: 8),
                const Text('Legendas', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ListTile(
                  dense: true,
                  title: const Text('Desativadas', style: TextStyle(color: Colors.white, fontSize: 13)),
                  trailing: _player!.state.track.subtitle.id == 'no'
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    _player!.setSubtitleTrack(SubtitleTrack.no());
                    Navigator.pop(context);
                  },
                ),
                ...tracks.subtitle.map((t) => ListTile(
                      dense: true,
                      title: Text(t.title ?? t.language ?? t.id,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                      trailing: _player!.state.track.subtitle.id == t.id
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () {
                        _player!.setSubtitleTrack(t);
                        Navigator.pop(context);
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _watchdogActive = false;
    _hideTimer?.cancel();
    _stallTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _playPauseNode.dispose();
    _reconnectNode.dispose();
    _aspectNode.dispose();
    _backNode.dispose();
    _prevNode.dispose();
    _nextNode.dispose();
    _back10Node.dispose();
    _fwd10Node.dispose();
    _sliderNode.dispose();
    _errorBackNode.dispose();
    _errorRetryNode.dispose();
    _player?.dispose();
    WakelockPlus.disable();
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return buildWithBackGuard(
      child: Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.select): _onSelectKey,
          const SingleActivator(LogicalKeyboardKey.enter): _onSelectKey,
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _togglePlay,
          const SingleActivator(LogicalKeyboardKey.mediaPlay): _play,
          const SingleActivator(LogicalKeyboardKey.mediaPause): _pause,
          const SingleActivator(LogicalKeyboardKey.mediaRewind): () =>
              _seekBy(-10),
          const SingleActivator(LogicalKeyboardKey.mediaFastForward): () =>
              _seekBy(10),
          const SingleActivator(LogicalKeyboardKey.channelUp): _zapPrev,
          const SingleActivator(LogicalKeyboardKey.channelDown): _zapNext,
          if (_arrowKeysSeek) ...{
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _seekBy(-10),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _seekBy(10),
            const SingleActivator(LogicalKeyboardKey.arrowUp): _zapPrev,
            const SingleActivator(LogicalKeyboardKey.arrowDown): _zapNext,
          },
        },
        child: FocusScope(
          autofocus: true,
          child: GestureDetector(
            // Sem onDoubleTap: o reconhecedor de duplo toque do pai vencia a
            // disputa e anulava o toque dos botões e da barra.
            onTap: _handleSurfaceTap,
            onVerticalDragUpdate: (d) => _handleVerticalDragUpdate(d, size.width),
            onVerticalDragEnd: _handleVerticalDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildVideoSurface(),
                if (_isAdjustingBrightness) _buildBrightnessHud(),
                if (_isAdjustingVolume) _buildVolumeHud(),
                if (_isBuffering && !_hasError)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 3),
                        if (_retryCount > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Reconectando (tentativa ${_retryCount + 1}/${_maxRetries + 1})…',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TvFocusable(
                          borderRadius: BorderRadius.circular(10),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: const Text('Cancelar',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_hasError) _buildErrorOverlay(),
                if (_showControls && !_hasError) _buildControlsOverlay(),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    if (_isWebPreview) {
      // Preview web: sem platform view (que cobriria o chrome Flutter).
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Icon(Icons.live_tv_rounded,
                    color: AppColors.primary, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                _currentItem.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _currentItem.category,
                style:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'PREVIEW WEB — vídeo liberado no app Windows/Android',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }
    const fallbackRatio = 16 / 9;
    final ratio = _currentAspect.ratio ?? fallbackRatio;
    final controller = _videoController;
    if (controller == null) {
      // O VideoController só existe depois da configuração assíncrona do
      // mpv; no 1º frame ele ainda é nulo e `_videoController!` quebraria
      // o build (flash de "Oops" ao entrar no player).
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: ratio,
        child: Video(
          controller: controller,
          fit: _currentAspect.fit,
          controls: NoVideoControls,
        ),
      ),
    );
  }

  Widget _circleControl({
    required FocusNode node,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
    bool autofocus = false,
  }) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: TvFocusable(
        focusNode: node,
        autofocus: autofocus,
        enabled: enabled,
        borderRadius: BorderRadius.circular(40),
        scaleOnFocus: primary ? 1.06 : 1.1,
        onPressed: onPressed,
        child: Container(
          padding: EdgeInsets.all(primary ? 16 : 12),
          decoration: BoxDecoration(
            color: primary
                ? AppColors.primary.withValues(alpha: 0.9)
                : Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(
            icon,
            color: primary ? Colors.black : Colors.white,
            size: primary ? 46 : 30,
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    final maxSeconds =
        _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0;
    final currentSeconds = (_seekPreview ??
            (_position.inSeconds > 0 ? _position.inSeconds.toDouble() : 0.0))
        .clamp(0.0, maxSeconds)
        .toDouble();
    final shownPosition =
        _seekPreview != null ? Duration(seconds: _seekPreview!.round()) : _position;

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: SafeArea(
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  TvFocusable(
                    focusNode: _backNode,
                    borderRadius: BorderRadius.circular(20),
                    onPressed: handleBackButton,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentItem.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _hasPlaylist
                              ? '${_currentItem.category} • ${_currentIndex + 1}/${_playlist.length}'
                              : _currentItem.category,
                          maxLines: 1,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_tracks != null &&
                      (_tracks!.audio.length > 1 ||
                          _tracks!.subtitle.isNotEmpty))
                    TvFocusable(
                      borderRadius: BorderRadius.circular(8),
                      onPressed: _showTracksSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: const Icon(Icons.closed_caption,
                            color: AppColors.primary, size: 16),
                      ),
                    ),
                  const SizedBox(width: 8),
                  TvFocusable(
                    focusNode: _aspectNode,
                    borderRadius: BorderRadius.circular(8),
                    onPressed: _cycleAspectRatio,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.aspect_ratio,
                              color: AppColors.primary, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _currentAspect.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TvFocusable(
                    focusNode: _reconnectNode,
                    borderRadius: BorderRadius.circular(8),
                    onPressed: _reconnect,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              color: AppColors.primary, size: 16),
                          SizedBox(width: 4),
                          Text('Reconectar',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_hasPlaylist) ...[
                    _circleControl(
                      node: _prevNode,
                      icon: Icons.skip_previous_rounded,
                      onPressed: _canPrev ? _zapPrev : null,
                    ),
                    const SizedBox(width: 20),
                  ],
                  if (!_isLive) ...[
                    _circleControl(
                      node: _back10Node,
                      icon: Icons.replay_10,
                      onPressed: () => _seekBy(-10),
                    ),
                    const SizedBox(width: 20),
                  ],
                  _circleControl(
                    node: _playPauseNode,
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    onPressed: _togglePlay,
                    primary: true,
                    autofocus: true,
                  ),
                  if (!_isLive) ...[
                    const SizedBox(width: 20),
                    _circleControl(
                      node: _fwd10Node,
                      icon: Icons.forward_10,
                      onPressed: () => _seekBy(10),
                    ),
                  ],
                  if (_hasPlaylist) ...[
                    const SizedBox(width: 20),
                    _circleControl(
                      node: _nextNode,
                      icon: Icons.skip_next_rounded,
                      onPressed: _canNext ? _zapNext : null,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: _isLive
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accentLive,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.fiber_manual_record,
                                  color: Colors.white, size: 10),
                              SizedBox(width: 4),
                              Text(
                                'TRANSMISSÃO AO VIVO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'mpv • HLS/TS',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppColors.primary,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 18),
                            trackHeight: 4,
                          ),
                          child: Slider(
                            focusNode: _sliderNode,
                            value: currentSeconds,
                            max: maxSeconds,
                            // Sem duração ainda não há como buscar: desativa
                            // em vez de mandar o vídeo para o segundo 1.
                            onChangeStart: _duration.inSeconds > 0
                                ? (v) {
                                    _hideTimer?.cancel();
                                    setState(() {
                                      _isSeeking = true;
                                      _seekPreview = v;
                                    });
                                  }
                                : null,
                            onChanged: _duration.inSeconds > 0
                                ? (v) {
                                    setState(() => _seekPreview = v);
                                  }
                                : null,
                            onChangeEnd: _duration.inSeconds > 0
                                ? (v) => _seekTo(
                                    Duration(seconds: v.round()))
                                : null,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(shownPosition),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Text(_formatDuration(_duration),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        // Escopo próprio: o D-pad circula só entre Voltar/Tentar.
        // O voltar do controle é tratado pelo PopScope externo (pop único
        // com debounce) — sem handler aqui para não dar pop duplo.
        child: FocusScope(
          autofocus: true,
          child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 54),
              const SizedBox(height: 12),
              const Text(
                'Falha na Reprodução',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                maxLines: 3,
                style:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvFocusable(
                    focusNode: _errorBackNode,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Voltar',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  TvFocusable(
                    focusNode: _errorRetryNode,
                    autofocus: true,
                    onPressed: _reconnect,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Tentar Novamente',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildBrightnessHud() {
    return Positioned(
      left: 30,
      top: 0,
      bottom: 0,
      child: Center(
        child: _buildHudIndicator(
          icon: Icons.brightness_6,
          value: _brightness,
        ),
      ),
    );
  }

  Widget _buildVolumeHud() {
    return Positioned(
      right: 30,
      top: 0,
      bottom: 0,
      child: Center(
        child: _buildHudIndicator(
          icon: _volume == 0 ? Icons.volume_off : Icons.volume_up,
          value: _volume,
        ),
      ),
    );
  }

  Widget _buildHudIndicator({required IconData icon, required double value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary, size: 28),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            width: 8,
            child: RotatedBox(
              quarterTurns: 3,
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white24,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${(value * 100).toInt()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }
}
