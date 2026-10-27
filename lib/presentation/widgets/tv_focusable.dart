import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final BorderRadius? borderRadius;
  final double scaleOnFocus;
  final EdgeInsetsGeometry padding;

  /// Desativado: não recebe foco, não responde a toque/tecla e fica sem
  /// realce. Usado nos limites (primeiro/último item da playlist, por ex.).
  final bool enabled;

  /// Chamado ao ganhar/perder foco (ex.: atualizar preview ao navegar no D-pad).
  final ValueChanged<bool>? onFocusChange;

  const TvFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius,
    this.scaleOnFocus = 1.04,
    this.padding = EdgeInsets.zero,
    this.enabled = true,
    this.onFocusChange,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _node;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted && _isFocused != _node.hasFocus) {
      setState(() {
        _isFocused = _node.hasFocus;
      });
      widget.onFocusChange?.call(_node.hasFocus);
    }
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      final oldNode = _node;
      oldNode.removeListener(_handleFocusChange);
      // Nó interno (criado por nós) precisa ser descartado na troca;
      // nó externo pertence ao pai — só removemos o listener.
      if (oldWidget.focusNode == null) oldNode.dispose();
      _node = widget.focusNode ?? FocusNode();
      _node.addListener(_handleFocusChange);
      _isFocused = _node.hasFocus;
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _node.dispose();
    } else {
      _node.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(12);
    final active = widget.enabled;

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus && active,
      canRequestFocus: active,
      skipTraversal: !active,
      onKeyEvent: (node, event) {
        if (!active) return KeyEventResult.ignored;
        if (event is KeyDownEvent) {
          // Alguns controles/TVs mandam OK como gameButtonA (ou espaço, em
          // teclados USB). Sem isso, o primeiro OK só focava o item e o
          // usuário precisava apertar duas vezes para selecionar.
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.space) {
            widget.onPressed?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) {
          if (active && mounted) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (_isHovered && mounted) setState(() => _isHovered = false);
        },
        child: GestureDetector(
          // Foca no toque/clique já no "down": a seleção visual (borda,
          // escala e preview) aparece no primeiro clique, não no segundo.
          onTapDown: active ? (_) => _node.requestFocus() : null,
          onTap: active ? widget.onPressed : null,
          onLongPress: active ? widget.onLongPress : null,
          child: AnimatedScale(
            scale: _isFocused
                ? widget.scaleOnFocus
                : (_isHovered && active ? 1.02 : 1.0),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: _isFocused
                      ? AppColors.primary
                      : (_isHovered && active
                            ? Colors.white38
                            : Colors.transparent),
                  width: _isFocused ? 2.5 : 1.5,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Guarda global do botão voltar (D-pad/controle).
///
/// Segurar o voltar no Fire TV gera eventos repetidos: o primeiro fecha o
/// player e os seguintes — ainda com o botão segurado — fechariam a lista
/// também, pulando 2 telas. Como cada tela tem seu próprio handler, um
/// debounce local não adianta: o estado precisa ser compartilhado.
/// [claim] retorna true uma vez por janela e false para as repetições.
class BackGuard {
  static DateTime? _lastClaim;

  static bool claim({int windowMs = 900}) {
    final now = DateTime.now();
    if (_lastClaim != null &&
        now.difference(_lastClaim!).inMilliseconds < windowMs) {
      return false;
    }
    _lastClaim = now;
    return true;
  }
}
