import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Janela do 2º toque para confirmar saída.
const _exitWindow = Duration(seconds: 2);

/// Estado do "voltar 2x para sair", compartilhável entre o botão
/// visível e o voltar do sistema (gesto/D-pad) para não dessincronizar.
class DoubleBackController {
  DateTime? _lastBackAt;

  /// Registra um toque em voltar. Retorna true se é o 2º dentro da
  /// janela (pode sair) ou false se foi o 1º (mostrar aviso).
  bool registerPress() {
    final now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < _exitWindow) {
      return true;
    }
    _lastBackAt = now;
    return false;
  }
}

void showExitHint(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: _exitWindow,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Telas raiz (Playlist, Home): 1º voltar mostra aviso, 2º em 2s sai.
/// Sem isso, o voltar do sistema fecha o app de imediato.
/// Só intercepta a rota onde está: telas empilhadas acima dão pop normal.
class DoubleBackToExit extends StatefulWidget {
  final Widget child;
  final String message;
  final DoubleBackController? controller;

  const DoubleBackToExit({
    super.key,
    required this.child,
    this.message = 'Pressione voltar novamente para sair',
    this.controller,
  });

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  late final DoubleBackController _controller =
      widget.controller ?? DoubleBackController();

  void _onPop() {
    if (_controller.registerPress()) {
      SystemNavigator.pop();
    } else {
      showExitHint(context, widget.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPop();
      },
      child: widget.child,
    );
  }
}
