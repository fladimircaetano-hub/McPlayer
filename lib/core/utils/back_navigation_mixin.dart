import 'package:flutter/material.dart';
import '../../presentation/widgets/double_back_to_exit.dart';
import '../../presentation/widgets/tv_focusable.dart';

/// Mixin para unificar navegação "voltar" com debounce global (BackGuard).
///
/// Uso:
///   class MinhaTela extends StatefulWidget { ... }
///   class _MinhaTelaState extends `State<MinhaTela>` with BackNavigationMixin { ... }
///
/// Substitua o PopScope manual por:
///   @override
///   Widget build(BuildContext context) {
///     return buildWithBackGuard(child: SeuConteudo());
///   }
///
/// Para botão de voltar visível na UI:
///   void _onBackButtonPressed() => handleBackButton();
mixin BackNavigationMixin<T extends StatefulWidget> on State<T> {
  bool _allowPop = false;

  /// Handler para o botão "voltar" do sistema/gesto/D-pad.
  /// Chame dentro do onPopInvokedWithResult do PopScope.
  void onSystemBack(bool didPop, Object? _) {
    if (didPop) return;
    if (!BackGuard.claim()) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Handler para botão "voltar" visível na UI (AppBar, toolbar, etc).
  /// Dá pop direto se puder, senão usa a mesma lógica de debounce.
  void handleBackButton() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      onSystemBack(false, null);
    }
  }

  /// Wrapper que injeta o PopScope com canPop controlado pelo mixin.
  Widget buildWithBackGuard({required Widget child}) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: onSystemBack,
      child: child,
    );
  }

  /// Wrapper para telas raiz que precisam de "2 toques para sair".
  /// Combina com DoubleBackToExit se necessário.
  Widget buildWithDoubleBackExit({
    required Widget child,
    String message = 'Pressione voltar novamente para sair',
    DoubleBackController? controller,
  }) {
    return DoubleBackToExit(
      controller: controller,
      message: message,
      child: buildWithBackGuard(child: child),
    );
  }
}