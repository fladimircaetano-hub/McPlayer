import 'package:flutter/material.dart';

import '../../core/utils/duplicates.dart';
import '../controllers/iptv_controller.dart';
import 'duplicate_report_dialog.dart';

/// Escuta o controller e, quando uma lista de filmes/séries termina de
/// carregar com repetidos, mostra o relatório e pede confirmação.
///
/// Fica no topo da árvore (Home) para funcionar mesmo que o usuário esteja
/// em outra tela quando a carga/recarga termina.
class DuplicatePromptHost extends StatefulWidget {
  final IptvController controller;
  final Widget child;

  const DuplicatePromptHost({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<DuplicatePromptHost> createState() => _DuplicatePromptHostState();
}

class _DuplicatePromptHostState extends State<DuplicatePromptHost> {
  String? _shownFingerprint;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // Se a lista já terminou de carregar antes do host montar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onControllerChanged());
  }

  @override
  void didUpdateWidget(DuplicatePromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted || _dialogOpen) return;
    final report = widget.controller.pendingDuplicates;
    final fingerprint = widget.controller.pendingDuplicatesFingerprint;
    if (report == null || fingerprint == null) return;
    if (fingerprint == _shownFingerprint) return;

    _shownFingerprint = fingerprint;
    WidgetsBinding.instance.addPostFrameCallback((_) => _present(report));
  }

  Future<void> _present(DuplicateReport report) async {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;
    final action = await showDuplicateReportDialog(
      context,
      report: report,
    );
    _dialogOpen = false;
    if (!mounted) return;
    // Fechar por "voltar" equivale a manter tudo.
    if (action == null || action == DuplicateAction.keep) {
      await widget.controller.dismissPendingDuplicates();
      return;
    }

    if (action == DuplicateAction.remove) {
      final removed = report.removedCount;
      await widget.controller.applyPendingDuplicates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$removed repetido(s) removido(s). Backup e relatório salvos.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      await widget.controller.dismissPendingDuplicates();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
