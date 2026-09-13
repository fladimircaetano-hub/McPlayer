import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../core/theme/app_theme.dart';
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

class _PlayerScreenState extends State<PlayerScreen> {
  Player? _player;
  VideoController? _videoController;
  late StreamItem _currentItem;
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

  int _retryCount = 0;
  static const int _maxRetries = 3;

  /// Watchdog anti-travamento: detecta buffering infinito ou frame
  /// congelado (posição sem avançar) e reconecta sozinho.
  Timer? _stallTimer;
  DateTime? _bufferingSince;
  DateTime _lastProgressAt = DateTime.now();
  static const _bufferTimeout = Duration(seconds: 20);
  static const _stallTimeout = Duration(seconds: 10);

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

  static const _uaHeaders = {
    'User-Agent': 'IPTVSmarters/1.0.0 (Linux; Android 12)',
  };

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    if (widget.playlist != null && widget.initialIndex != null) {
      _currentIndex = widget.initialIndex!;
    }

    if (_isWebPreview) {
      // Preview web: sem player nativo, só layout + aviso.
      _isBuffering = false;
    } else {
      _player = Player(
        configuration: const PlayerConfiguration(
          title: 'MC Player',
          osc: false,
        ),
      );
      _videoController = VideoController(
        _player!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
      _subscribe();
      _open(_currentItem.streamUrl);
      _startStallWatchdog();
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

  void _subscribe() {
    _subs.add(_player!.stream.playing.listen((playing) {
      if (mounted && playing != _isPlaying) {
        setState(() => _isPlaying = playing);
        if (playing) _resetControlsTimeout();
      }
    }));
    _subs.add(_player!.stream.position.listen((pos) {
      // Throttle: só rebuild quando o segundo muda e não está arrastando.
      if (_isSeeking) return;
      if (mounted && pos.inSeconds != _position.inSeconds) {
        setState(() => _position = pos);
      }
      // Sinal de vida para o watchdog (mesmo sem rebuild).
      _lastProgressAt = DateTime.now();
    }));
    _subs.add(_player!.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    }));
    _subs.add(_player!.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
      if (buffering) {
        _bufferingSince ??= DateTime.now();
      } else {
        _bufferingSince = null;
        _lastProgressAt = DateTime.now();
      }
    }));
    _subs.add(_player!.stream.tracks.listen((tracks) {
      if (mounted) setState(() => _tracks = tracks);
    }));
    _subs.add(_player!.stream.error.listen((error) {
      if (error.isNotEmpty) _onPlayerError(error);
    }));
    _subs.add(_player!.stream.completed.listen((completed) {
      if (completed && mounted) _onCompleted();
    }));
  }

  void _startStallWatchdog() {
    _stallTimer?.cancel();
    _lastProgressAt = DateTime.now();
    _bufferingSince = DateTime.now();
    _stallTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _isWebPreview || _hasError || _player == null) return;
      final now = DateTime.now();

      // 1) Buffering infinito: nunca saiu do loading.
      if (_isBuffering && _bufferingSince != null) {
        if (now.difference(_bufferingSince!) >= _bufferTimeout) {
          _bufferingSince = now; // evita disparo duplo no próximo tick
          _autoReconnect('travou no carregamento');
        }
        return;
      }

      // 2) Frame congelado: tocando, sem buffering, mas posição parada.
      // VOD pausado ou no fim não conta.
      if (_isPlaying && !_isBuffering) {
        final atEnd = !_isLive &&
            _duration.inSeconds > 0 &&
            _position.inSeconds >= _duration.inSeconds - 1;
        if (!atEnd && now.difference(_lastProgressAt) >= _stallTimeout) {
          _lastProgressAt = now;
          _autoReconnect('imagem congelada');
        }
      }
    });
  }

  void _autoReconnect(String motivo) {
    if (!mounted || _hasError) return;
    if (_retryCount >= _maxRetries) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isBuffering = false;
          _errorMessage =
              'Conexão instável ($motivo após ${_maxRetries + 1} tentativas). Toque em Tentar Novamente.';
        });
      }
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
      await _player!
          .open(Media(url, httpHeaders: _uaHeaders), play: true)
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw TimeoutException('Tempo esgotado (25s).'),
          );
      await _player!.setVolume(_volume * 100);
      if (mounted) {
        _resetControlsTimeout();
      }
    } catch (e) {
      if (_retryCount < _maxRetries && mounted) {
        _retryCount++;
        await Future.delayed(Duration(seconds: _retryCount * 2));
        if (mounted) return _open(url, isRetry: true);
      }
      if (mounted) {
        setState(() {
          _hasError = true;
          _isBuffering = false;
          _errorMessage = e is TimeoutException
              ? 'Tempo esgotado (tentativa ${_retryCount + 1}/${_maxRetries + 1}). Verifique a internet ou reconecte.'
              : 'Falha ao conectar: ${e.toString().replaceAll('Exception:', '').trim()}';
        });
      }
    }
  }

  void _onPlayerError(String error) {
    if (!mounted || _hasError) return;
    if (_retryCount < _maxRetries) {
      _retryCount++;
      Future.delayed(Duration(seconds: _retryCount * 2), () {
        if (mounted) _open(_currentItem.streamUrl, isRetry: true);
      });
    } else {
      setState(() {
        _hasError = true;
        _isBuffering = false;
        _errorMessage = error.length > 220 ? '${error.substring(0, 220)}...' : error;
      });
    }
  }

  void _onCompleted() {
    if (_hasPlaylist && _currentIndex + 1 < widget.playlist!.length) {
      _zapTo(_currentIndex + 1);
    } else {
      setState(() => _showControls = true);
    }
  }

  bool get _hasPlaylist =>
      widget.playlist != null && widget.playlist!.length > 1 && _currentIndex >= 0;

  bool get _isLive => _currentItem.streamType == StreamType.live;

  Future<void> _zapTo(int index) async {
    final list = widget.playlist!;
    if (index < 0 || index >= list.length) return;
    if (_isWebPreview) {
      // Preview web: troca o item exibido sem reproduzir.
      setState(() {
        _currentIndex = index;
        _currentItem = list[index];
        _showControls = true;
      });
      return;
    }
    _retryCount = 0;
    setState(() {
      _currentIndex = index;
      _currentItem = list[index];
      _position = Duration.zero;
      _duration = Duration.zero;
      _showControls = false;
    });
    await _open(_currentItem.streamUrl);
  }

  void _zapNext() {
    if (_hasPlaylist) {
      _zapTo((_currentIndex + 1) % widget.playlist!.length);
    }
  }

  void _zapPrev() {
    if (_hasPlaylist) {
      final len = widget.playlist!.length;
      _zapTo((_currentIndex - 1 + len) % len);
    }
  }

  void _reconnect() {
    if (_isWebPreview) {
      _webNotice();
      return;
    }
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
    _player!.playOrPause();
    _resetControlsTimeout();
  }

  void _seekBy(int seconds) {
    if (_isWebPreview || _isLive) return;
    final target = _position + Duration(seconds: seconds);
    _player?.seek(target < Duration.zero ? Duration.zero : target);
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

  void _handleVerticalDragUpdate(DragUpdateDetails details, double screenWidth) {
    final isLeft = details.globalPosition.dx < (screenWidth / 2);
    final delta = -details.primaryDelta! / 250;
    if (isLeft) {
      setState(() {
        _isAdjustingBrightness = true;
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
      });
      ScreenBrightness().setApplicationScreenBrightness(_brightness);
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
    _hideTimer?.cancel();
    _stallTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _playPauseNode.dispose();
    _reconnectNode.dispose();
    _aspectNode.dispose();
    _backNode.dispose();
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.select): () {
            if (!_showControls) _toggleControls();
          },
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (!_showControls) _toggleControls();
          },
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _togglePlay,
          const SingleActivator(LogicalKeyboardKey.arrowUp): _zapPrev,
          const SingleActivator(LogicalKeyboardKey.arrowDown): _zapNext,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-10),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(10),
          const SingleActivator(LogicalKeyboardKey.goBack): () =>
              Navigator.of(context).maybePop(),
        },
        child: FocusScope(
          autofocus: true,
          child: GestureDetector(
            onTap: _toggleControls,
            onDoubleTap: _togglePlay,
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
    return Center(
      child: AspectRatio(
        aspectRatio: ratio,
        child: Video(
          controller: _videoController!,
          fit: _currentAspect.fit,
          controls: NoVideoControls,
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  TvFocusable(
                    focusNode: _backNode,
                    borderRadius: BorderRadius.circular(20),
                    onPressed: () => Navigator.of(context).pop(),
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
                              ? '${_currentItem.category} • ${_currentIndex + 1}/${widget.playlist!.length}'
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
                  if (_hasPlaylist)
                    TvFocusable(
                      borderRadius: BorderRadius.circular(30),
                      onPressed: _zapPrev,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.skip_previous_rounded,
                            color: Colors.white, size: 30),
                      ),
                    ),
                  const SizedBox(width: 20),
                  TvFocusable(
                    focusNode: _playPauseNode,
                    autofocus: true,
                    borderRadius: BorderRadius.circular(40),
                    onPressed: _togglePlay,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 46,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  if (_hasPlaylist)
                    TvFocusable(
                      borderRadius: BorderRadius.circular(30),
                      onPressed: _zapNext,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.skip_next_rounded,
                            color: Colors.white, size: 30),
                      ),
                    ),
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
                            inactiveTrackColor: Colors.white12,
                            thumbColor: AppColors.primary,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7),
                            overlayShape: SliderComponentShape.noOverlay,
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: _seekPreview ??
                                (_duration.inSeconds > 0
                                    ? _position.inSeconds
                                        .clamp(0, _duration.inSeconds)
                                        .toDouble()
                                    : 0),
                            max: (_duration.inSeconds > 0
                                    ? _duration.inSeconds
                                    : 1)
                                .toDouble(),
                            onChanged: (v) {
                              // Preview local sem seek a cada tick.
                              setState(() {
                                _isSeeking = true;
                                _seekPreview = v;
                              });
                            },
                            onChangeEnd: (v) {
                              _player?.seek(Duration(seconds: v.toInt()));
                              setState(() {
                                _position = Duration(seconds: v.toInt());
                                _isSeeking = false;
                                _seekPreview = null;
                              });
                              _resetControlsTimeout();
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(_position),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            Text(_formatDuration(_duration),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
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
