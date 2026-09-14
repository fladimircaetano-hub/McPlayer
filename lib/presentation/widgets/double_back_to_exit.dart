import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Telas raiz (Playlist, Home): 1º voltar mostra aviso, 2º em 2s sai.
/// Sem isso, o voltar do sistema fecha o app de imediato (reclamação).
/// Só intercepta a rota onde está: telas empilhadas acima dão pop normal.
class DoubleBackToExit extends StatefulWidget {
  final Widget child;
  final String message;

  const DoubleBackToExit({
    super.key,
    required this.child,
    this.message = 'Pressione voltar novamente para sair',
  });

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _lastBackAt;

  void _onPop() {
    final now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
