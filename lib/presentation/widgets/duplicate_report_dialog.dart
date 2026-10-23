import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/duplicates.dart';
import 'tv_focusable.dart';

enum DuplicateAction { remove, keep }

/// Relatório de repetidos com confirmação antes de remover.
///
/// Nunca remove nada por conta própria: devolve a escolha do usuário para o
/// chamador (que só então aplica a lista limpa, com backup já salvo).
Future<DuplicateAction?> showDuplicateReportDialog(
  BuildContext context, {
  required DuplicateReport report,
}) {
  return showDialog<DuplicateAction>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DuplicateReportDialog(report: report),
  );
}

class _DuplicateReportDialog extends StatefulWidget {
  final DuplicateReport report;

  const _DuplicateReportDialog({required this.report});

  @override
  State<_DuplicateReportDialog> createState() => _DuplicateReportDialogState();
}

class _DuplicateReportDialogState extends State<_DuplicateReportDialog> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return AlertDialog(
      scrollable: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.content_copy_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Repetidos encontrados',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Encontramos ${report.removedCount} item(ns) repetido(s): '
              '${report.removedMovies} filme(s), '
              '${report.removedSeries} série(s) e '
              '${report.removedEpisodes} episódio(s).',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Será mantida a melhor cópia de cada item (link, capa, '
              'descrição e qualidade). Um backup é salvo antes da remoção e '
              'seus favoritos são preservados.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TvFocusable(
              borderRadius: BorderRadius.circular(8),
              onPressed: () => setState(() => _showDetails = !_showDetails),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showDetails
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showDetails
                          ? 'Ocultar detalhes'
                          : 'Ver detalhes (${report.entries.length} grupo(s))',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
            if (_showDetails) ...[
              const SizedBox(height: 10),
              for (final e in report.entries.take(40)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            e.kind == 'filme'
                                ? Icons.movie_rounded
                                : Icons.live_tv_rounded,
                            color: AppColors.primary,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              e.kept.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Motivo: ${e.reason} • remover '
                        '${e.removed.length} cópia(s)',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.cardBorder),
              ],
              if (report.entries.length > 40)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '… e mais ${report.entries.length - 40} grupo(s). '
                    'O relatório completo fica salvo no aparelho.',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11.5),
                  ),
                ),
            ],
          ],
        ),
      ),
      actionsPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      actions: [
        TvFocusable(
          borderRadius: BorderRadius.circular(10),
          onPressed: () => Navigator.of(context).pop(DuplicateAction.keep),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Text(
              'Manter tudo',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        TvFocusable(
          autofocus: true,
          borderRadius: BorderRadius.circular(10),
          onPressed: () => Navigator.of(context).pop(DuplicateAction.remove),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Remover repetidos',
              style: TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
