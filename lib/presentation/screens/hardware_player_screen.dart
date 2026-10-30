import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/stream_item.dart';
import '../widgets/tv_focusable.dart' show BackGuard;
import 'player_screen.dart';

/// Player de hardware (ExoPlayer/Surface) usado no Android para conteúdo 4K.
///
/// Por que existe: o mpv do media_kit entrega os frames 4K pela textura do
/// Flutter. Em TV boxes Allwinner (Transpeed etc.) o decodificador devolve os
/// buffers em AFBC/escala interna e o resultado na tela são as listras verdes
/// (ou tela preta). Já o caminho MediaCodec -> Surface, que é o mesmo usado
/// pelo player nativo da TV, funciona nesses aparelhos. Por isso o 4K sai por
/// aqui e o restante (1080p, canais, séries leves) continua no mpv, que tem
/// troca de áudio/legenda.
class HardwarePlayerScreen extends StatefulWidget {
  final StreamItem item;
  final List<StreamItem>? playlist;
  final int? initialIndex;
  final bool keepScreenOn;

  const HardwarePlayerScreen({
    super.key,
    required this.item,
    this.playlist,
    this.initialIndex,
    this.keepScreenOn = true,
  });

  @override
  State<HardwarePlayerScreen> createState() => _HardwarePlayerScreenState();
}

enum _Fit { original, fill }

class _HardwarePlayerScreenState extends State<HardwarePlayerScreen> {
  VideoPlayerController? _controller;
  late StreamItem _item;
  late List<StreamItem> _playlist;
  int _index = 0;

  bool _hasError = false;
  String _errorMessage = '';
  bool _initializing = true;
  bool _showControls = true;
  Timer? _hideTimer;
  _Fit _fit = _Fit.original;

  // Navegação dos controles feita manualmente pelo D-pad.
  //
  // Em TV box com PlatformView (SurfaceView do ExoPlayer) o sistema de foco
  // direcional do Flutter não consegue mover o foco entre os botões — as
  // setas chegam, mas nada acontece. Por isso a seleção é controlada por
  // índices: linha 0 = barra superior (Sair / Original), linha 1 = botões
  // centrais. Assim o comportamento é o mesmo em qualquer controle.
  int _row = 1;
  int _topSel = 0; // 0 = Sair, 1 = Original/Preencher
  int _centerSel = 0;
  int _errSel = 0; // 0 = Tentar novamente, 1 = Player alternativo, 2 = Voltar

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = true;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _playlist = widget.playlist ?? <StreamItem>[];
    if (_playlist.isNotEmpty) {
      final found = _playlist.indexWhere(
        (e) => e.id == widget.item.id && e.streamUrl == widget.item.streamUrl,
      );
      _index = found >= 0
          ? found
          : (widget.initialIndex ?? 0).clamp(0, _playlist.length - 1);
      _item = _playlist[_index];
    }
    _centerSel = _playIndex;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (widget.keepScreenOn) WakelockPlus.enable();

    _start();
  }

  // ---------------------------------------------------------------- playback

  /// Separa a URL dos cabeçalhos no formato `url|User-Agent=...&Referer=...`
  /// usado por algumas listas.
  ({String url, Map<String, String> headers}) _splitUrl(String raw) {
    var url = raw.trim();
    final headers = <String, String>{};
    final pipe = url.indexOf('|');
    if (pipe != -1) {
      final query = url.substring(pipe + 1);
      url = url.substring(0, pipe).trim();
      for (final pair in query.split('&')) {
        final eq = pair.indexOf('=');
        if (eq > 0) {
          headers[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
        }
      }
    }
    return (url: url, headers: headers);
  }

  Future<void> _start() async {
    await _disposeController();
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _errSel = 0;
      _initializing = true;
      _isBuffering = true;
      _showControls = true;
      _row = 1;
      _centerSel = _playIndex;
      _position = Duration.zero;
      _duration = Duration.zero;
    });

    final parts = _splitUrl(_item.streamUrl);
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(parts.url),
        httpHeaders: parts.headers,
        // SurfaceView real (composição do sistema): é o caminho que o
        // decodificador da Allwinner entrega sem listras. A textura do
        // Flutter (padrão) passa por um caminho que quebra no 4K desta TV.
        viewType: VideoViewType.platformView,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );
      _controller = controller;
      controller.addListener(_onTick);
      await controller.initialize().timeout(
        // O servidor desta lista demora a responder o primeiro range
        // (>= 11s no HEAD) e o ExoPlayer ainda precisa configurar o
        // decodificador 4K: 120s evita "falha" antes de começar.
        const Duration(seconds: 120),
        onTimeout: () => throw TimeoutException('Tempo esgotado ao abrir.'),
      );
      if (!mounted || _controller != controller) return;
      await controller.play();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _duration = controller.value.duration;
      });
      _resetControlsTimeout();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _hasError = true;
        _errorMessage = _friendlyError(e);
        _showControls = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString();
    if (msg.contains('TimeoutException')) {
      return 'O servidor demorou para responder. Verifique a internet e tente novamente.';
    }
    if (msg.toLowerCase().contains('source error') ||
        msg.toLowerCase().contains('unrecognized')) {
      return 'Este arquivo não pôde ser aberto pelo player de hardware. '
          'Tente a versão Full HD do filme.';
    }
    return 'Não foi possível reproduzir este vídeo.\n$msg';
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = _friendlyError(v.errorDescription ?? 'erro');
        _isBuffering = false;
        _showControls = false;
        _errSel = 0;
      });
      return;
    }
    final position = v.position;
    final playing = v.isPlaying;
    final buffering = v.isBuffering;
    if (position == _position &&
        playing == _isPlaying &&
        buffering == _isBuffering) {
      return;
    }
    setState(() {
      _position = position;
      _duration = v.duration;
      _isPlaying = playing;
      _isBuffering = buffering;
    });
    if (playing && _hideTimer == null) _resetControlsTimeout();
  }

  Future<void> _disposeController() async {
    final old = _controller;
    _controller = null;
    if (old == null) return;
    old.removeListener(_onTick);
    await old.dispose();
  }

  // ---------------------------------------------------------------- controles

  void _resetControlsTimeout() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 7), () {
      // Zera a referência: sem isso o `_onTick` acha que ainda existe um
      // timer pendente e nunca mais rearma o auto-hide.
      _hideTimer = null;
      if (mounted && _isPlaying && !_hasError) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsAgain() {
    if (!mounted) return;
    if (!_showControls) {
      setState(() {
        _showControls = true;
        _row = 1;
        _centerSel = _playIndex;
      });
    }
    _resetControlsTimeout();
  }

  void _hideControls() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_showControls) return;
    setState(() => _showControls = false);
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || _hasError) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _resetControlsTimeout();
  }

  Future<void> _seekBy(int seconds) async {
    final c = _controller;
    if (c == null || _hasError) return;
    final target = c.value.position + Duration(seconds: seconds);
    final max = c.value.duration;
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (max > Duration.zero && clamped > max) clamped = max;
    await c.seekTo(clamped);
    setState(() {
      _position = clamped;
      _showControls = true;
    });
    _resetControlsTimeout();
  }

  bool get _hasPlaylist => _playlist.length > 1;

  /// Índice do botão play dentro de [_centerActions].
  int get _playIndex => _hasPlaylist ? 2 : 1;

  /// Botões centrais na ordem exibida. O índice em [_centerSel] referencia
  /// esta lista.
  List<({IconData icon, VoidCallback onPressed, bool primary})>
  get _centerActions => [
    if (_hasPlaylist)
      (
        icon: Icons.skip_previous,
        onPressed: () => _zap(-1),
        primary: false,
      ),
    (icon: Icons.replay_10, onPressed: () => _seekBy(-10), primary: false),
    (
      icon: _isPlaying ? Icons.pause : Icons.play_arrow,
      onPressed: _togglePlay,
      primary: true,
    ),
    (icon: Icons.forward_10, onPressed: () => _seekBy(10), primary: false),
    if (_hasPlaylist)
      (icon: Icons.skip_next, onPressed: () => _zap(1), primary: false),
  ];

  void _zap(int delta) {
    if (!_hasPlaylist) return;
    final next = (_index + delta + _playlist.length) % _playlist.length;
    setState(() {
      _index = next;
      _item = _playlist[next];
      _showControls = true;
      _row = 1;
    });
    _start();
  }

  void _toggleFit() {
    setState(() {
      _fit = _fit == _Fit.original ? _Fit.fill : _Fit.original;
    });
    _resetControlsTimeout();
  }

  /// Movimenta a seleção dos controles (dx = horizontal, dy = vertical).
  void _moveSelection(int dx, int dy) {
    _resetControlsTimeout();
    if (dy < 0) {
      // Sobe para a barra superior (Sair / Original).
      if (_row != 0) setState(() => _row = 0);
      return;
    }
    if (dy > 0) {
      // Desce de volta para os botões centrais.
      if (_row != 1) setState(() => _row = 1);
      return;
    }
    if (dx == 0) return;
    if (_row == 0) {
      setState(() => _topSel = (_topSel + dx).clamp(0, 1));
    } else {
      final last = _centerActions.length - 1;
      setState(() => _centerSel = (_centerSel + dx).clamp(0, last));
    }
  }

  void _activateSelection() {
    if (_row == 0) {
      if (_topSel == 0) {
        _exit();
      } else {
        _toggleFit();
      }
      return;
    }
    final actions = _centerActions;
    if (_centerSel < 0 || _centerSel >= actions.length) return;
    actions[_centerSel].onPressed();
  }

  void _moveError(int delta) {
    setState(() => _errSel = (_errSel + delta).clamp(0, 2));
  }

  void _activateError() {
    switch (_errSel) {
      case 0:
        _start();
        break;
      case 1:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              item: _item,
              playlist: widget.playlist,
              initialIndex: widget.initialIndex,
              keepScreenOn: widget.keepScreenOn,
            ),
          ),
        );
        break;
      default:
        _exit();
    }
  }

  void _exit() {
    // `canPop` fica em false por causa do PopScope (para o Voltar esconder
    // os controles primeiro); o botão "Sair" força a saída.
    Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------- build

  /// Atalhos globais do player.
  ///
  /// Com os controles escondidos, qualquer seta/OK só revela a barra: evita
  /// trocar de filme sem querer (relato: "apertei para ver os controles e o
  /// filme mudou"). Com a barra visível, as setas navegam entre os botões.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    if (_hasError) {
      return {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _moveError(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _moveError(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveError(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveError(1),
        const SingleActivator(LogicalKeyboardKey.enter): _activateError,
        const SingleActivator(LogicalKeyboardKey.select): _activateError,
        const SingleActivator(LogicalKeyboardKey.gameButtonA): _activateError,
      };
    }
    if (!_showControls) {
      return {
        const SingleActivator(LogicalKeyboardKey.select): _showControlsAgain,
        const SingleActivator(LogicalKeyboardKey.enter): _showControlsAgain,
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            _showControlsAgain,
        const SingleActivator(LogicalKeyboardKey.space): _showControlsAgain,
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            _showControlsAgain,
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            _showControlsAgain,
        const SingleActivator(LogicalKeyboardKey.arrowUp): _showControlsAgain,
        const SingleActivator(LogicalKeyboardKey.arrowDown): _showControlsAgain,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _togglePlay,
      };
    }
    return {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _moveSelection(-1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _moveSelection(1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          _moveSelection(0, -1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          _moveSelection(0, 1),
      const SingleActivator(LogicalKeyboardKey.enter): _activateSelection,
      const SingleActivator(LogicalKeyboardKey.select): _activateSelection,
      const SingleActivator(LogicalKeyboardKey.gameButtonA): _activateSelection,
      const SingleActivator(LogicalKeyboardKey.space): _activateSelection,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _togglePlay,
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Com os controles na tela, o Voltar apenas esconde a barra; um segundo
      // Voltar (ou o botão "Sair") fecha o player.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!BackGuard.claim()) return;
        if (_showControls) {
          _hideControls();
          return;
        }
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: CallbackShortcuts(
          bindings: _shortcuts,
          child: FocusScope(
            autofocus: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildVideo(),
                if (_isBuffering && !_hasError && !_initializing)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                if (_initializing && !_hasError)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                if (_hasError) _buildError(),
                if (!_hasError && _showControls) _buildControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    final c = _controller;
    if (c == null || _hasError || _initializing) {
      return const ColoredBox(color: Colors.black);
    }
    final videoRatio = c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;
    final screen = MediaQuery.of(context).size;
    if (_fit == _Fit.fill) {
      // Preencher = cobrir a tela inteira sem tarjas. Escala pelo MAIOR
      // fator entre largura e altura; usar só a largura deixava tarja
      // preta em material 4:3 (ou 21:9) numa TV 16:9.
      final fillByWidth = screen.width / videoRatio >= screen.height;
      final width = fillByWidth ? screen.width : screen.height * videoRatio;
      final height = fillByWidth ? screen.width / videoRatio : screen.height;
      return ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: width,
            height: height,
            child: VideoPlayer(c),
          ),
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: videoRatio,
        child: VideoPlayer(c),
      ),
    );
  }

  Widget _buildControls() {
    final max = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final value = _position.inMilliseconds.clamp(0, max.toInt()).toDouble();
    final actions = _centerActions;

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _HwButton(
                    selected: _row == 0 && _topSel == 0,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _exit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Sair',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _hasPlaylist
                              ? '${_item.category} • ${_index + 1}/${_playlist.length}'
                              : _item.category,
                          maxLines: 1,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _HwButton(
                    selected: _row == 0 && _topSel == 1,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _toggleFit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        _fit == _Fit.original ? 'Original' : 'Preencher',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0)
                    SizedBox(width: actions[i].primary ? 24 : 16),
                  _HwButton(
                    selected: _row == 1 && _centerSel == i,
                    borderRadius: BorderRadius.circular(
                      actions[i].primary ? 40 : 30,
                    ),
                    onPressed: actions[i].onPressed,
                    child: _circleButton(
                      actions[i].icon,
                      primary: actions[i].primary,
                    ),
                  ),
                ],
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: value / max,
                      minHeight: 5,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(_position),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _duration.inSeconds > 0 ? _fmt(_duration) : '--:--',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        'OK seleciona  •  ↑↓ navega',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
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

  Widget _circleButton(IconData icon, {bool primary = false}) {
    return Container(
      width: primary ? 76 : 56,
      height: primary ? 76 : 56,
      decoration: BoxDecoration(
        color: primary
            ? AppColors.primary
            : Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
        border: primary ? null : Border.all(color: Colors.white24),
      ),
      child: Icon(icon, color: Colors.white, size: primary ? 40 : 26),
    );
  }

  Widget _buildError() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 44),
              const SizedBox(height: 12),
              const Text(
                'Falha na Reprodução',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HwButton(
                    selected: _errSel == 0,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _start,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh, color: Colors.white, size: 17),
                          SizedBox(width: 6),
                          Text(
                            'Tentar novamente',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HwButton(
                    selected: _errSel == 1,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(
                          item: _item,
                          playlist: widget.playlist,
                          initialIndex: widget.initialIndex,
                          keepScreenOn: widget.keepScreenOn,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        'Player alternativo',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HwButton(
                    selected: _errSel == 2,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _exit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        'Voltar',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Use ← → para escolher e OK para confirmar',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    WakelockPlus.disable();
    // Mesma restauração do PlayerScreen (mpv): sem isso, ao voltar para a
    // grade o app continua em paisagem e com as barras do sistema escondidas.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }
}

/// Botão dos controles com realce controlado por índice (não por foco).
///
/// O foco do Flutter não funciona sobre o SurfaceView do ExoPlayer nesta TV,
/// então o destaque é desenhado a partir da seleção manual do D-pad.
class _HwButton extends StatelessWidget {
  final bool selected;
  final BorderRadius borderRadius;
  final VoidCallback? onPressed;
  final Widget child;

  const _HwButton({
    required this.selected,
    required this.borderRadius,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedScale(
          scale: selected ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: selected ? AppColors.primary : Colors.transparent,
                width: selected ? 2.5 : 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
