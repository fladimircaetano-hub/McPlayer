import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'tv_focusable.dart';

/// Fecha o aplicativo de forma controlada, sempre com confirmação.
///
/// Antes o usuário só conseguia sair usando o botão "Home" do controle.
/// O diálogo tem foco próprio para funcionar no D-pad (TV/Android) e no
/// mouse, com "Cancelar" focado por padrão para evitar saída acidental.
Future<void> confirmExitApp(BuildContext context) async {
  final shouldExit = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _ExitConfirmationDialog(),
  );

  if (shouldExit == true) {
    // Encerra a activity no Android (TV box / Fire TV). Em plataformas
    // onde o sistema não permite fechar, o chamado é inofensivo.
    await SystemNavigator.pop();
  }
}

class _ExitConfirmationDialog extends StatelessWidget {
  const _ExitConfirmationDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: FocusScope(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accentLive.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accentLive.withValues(alpha: 0.55),
                  ),
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: AppColors.accentLive,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sair do McPlayer?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'O aplicativo será fechado.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TvFocusable(
                    autofocus: true,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  TvFocusable(
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentLive,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Sair',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
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
}
