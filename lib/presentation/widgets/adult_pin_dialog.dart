import 'package:flutter/material.dart';

import '../../core/storage/storage_service.dart';
import '../../core/theme/app_theme.dart';
import 'tv_focusable.dart';

/// Controle dos pais do conteúdo adulto.
///
/// Regra pedida: o PIN é solicitado na PRIMEIRA abertura de conteúdo adulto
/// (canal, filme ou série). Depois de acertar, fica liberado até o app ser
/// fechado — não pede de novo a cada item.
///
/// O PIN é o definido em Configurações > Código PIN. Se o operador nunca
/// definiu um, vale o padrão de fábrica **0000**.
bool _adultUnlocked = false;

bool get adultContentUnlocked => _adultUnlocked;

@visibleForTesting
void resetAdultContentUnlocked() => _adultUnlocked = false;

/// PIN efetivo: 4 dígitos salvos ou "0000" quando não há PIN válido.
String adultPinOrDefault(String? storedPin) {
  final pin = (storedPin ?? '').trim();
  return RegExp(r'^\d{4}$').hasMatch(pin) ? pin : '0000';
}

String effectiveAdultPin(StorageService storage) =>
    adultPinOrDefault(storage.getPin());

/// Garante acesso ao conteúdo adulto. Retorna false quando o usuário
/// cancela ou erra o PIN e fecha o diálogo.
Future<bool> ensureAdultAccess(
  BuildContext context, {
  required StorageService storage,
  String? title,
}) async {
  if (_adultUnlocked) return true;
  if (!context.mounted) return false;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AdultPinDialog(
      expectedPin: effectiveAdultPin(storage),
      title: title,
    ),
  );

  if (ok == true) {
    _adultUnlocked = true;
    return true;
  }
  return false;
}

/// Teclado numérico próprio (funciona no D-pad da TV e no toque do celular),
/// sem depender do teclado do sistema — na Fire TV o teclado virtual cobre a
/// tela e atrapalha a digitação com o controle.
class AdultPinDialog extends StatefulWidget {
  final String expectedPin;
  final String? title;

  const AdultPinDialog({super.key, required this.expectedPin, this.title});

  @override
  State<AdultPinDialog> createState() => _AdultPinDialogState();
}

class _AdultPinDialogState extends State<AdultPinDialog> {
  String _digits = '';
  String? _error;
  bool _checking = false;

  void _press(String digit) {
    if (_checking) return;
    if (_digits.length >= 4) return;
    setState(() {
      _digits += digit;
      _error = null;
    });
    if (_digits.length == 4) _submit();
  }

  void _backspace() {
    if (_checking || _digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _error = null;
    });
  }

  void _submit() {
    if (_checking) return;
    if (_digits.length < 4) {
      setState(() => _error = 'Digite os 4 dígitos do PIN');
      return;
    }
    if (_digits == widget.expectedPin) {
      _checking = true;
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _digits = '';
      _error = 'PIN incorreto. Tente novamente.';
    });
  }

  Widget _key(String label, {VoidCallback? onPressed, bool autofocus = false}) {
    return TvFocusable(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed ?? () => _press(label),
      child: Container(
        width: 76,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _row(List<String> labels) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final label in labels) ...[
          _key(label, autofocus: label == '1'),
          const SizedBox(width: 10),
        ],
      ]..removeLast(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.title ?? '').trim();
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: FocusScope(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.55),
                  ),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Conteúdo adulto',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name.isEmpty
                    ? 'Digite o PIN para liberar o conteúdo adulto.'
                    : 'Digite o PIN para abrir "$name".',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),

              // Quatro caixas do PIN
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    Container(
                      width: 42,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: i < _digits.length
                              ? AppColors.primary
                              : AppColors.cardBorder,
                          width: i < _digits.length ? 2 : 1,
                        ),
                      ),
                      child: i < _digits.length
                          ? Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                    ),
                    if (i < 3) const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 18,
                child: Text(
                  _error ?? '',
                  style: const TextStyle(
                    color: AppColors.accentLive,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),

              _row(const ['1', '2', '3']),
              const SizedBox(height: 10),
              _row(const ['4', '5', '6']),
              const SizedBox(height: 10),
              _row(const ['7', '8', '9']),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _key('⌫', onPressed: _backspace),
                  const SizedBox(width: 10),
                  _key('0'),
                  const SizedBox(width: 10),
                  _key('OK', onPressed: _submit),
                ],
              ),
              const SizedBox(height: 14),
              TvFocusable(
                borderRadius: BorderRadius.circular(8),
                onPressed: () => Navigator.of(context).pop(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'PIN padrão de fábrica: 0000',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
