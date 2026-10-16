import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/stream_item.dart';
import '../../widgets/tv_focusable.dart';
import '../player_screen.dart';

/// Bottom sheet em 2 níveis: temporadas da série -> episódios da temporada.
void showEpisodesSheet({
  required BuildContext context,
  required StreamItem series,
  required List<StreamItem> episodes,
  required VoidCallback onOpenPlayer,
}) {
  final bySeason = <int, List<StreamItem>>{};
  for (final ep in episodes) {
    bySeason.putIfAbsent(ep.seasonNumber ?? 1, () => []).add(ep);
  }
  final seasons = bySeason.keys.toList()..sort();
  for (final list in bySeason.values) {
    list.sort((a, b) =>
        (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      int? selectedSeason;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final atRoot = selectedSeason == null;
          final seasonEps =
              atRoot ? const <StreamItem>[] : bySeason[selectedSeason]!;
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.9,
            expand: false,
            builder: (_, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (!atRoot)
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white70),
                            onPressed: () => setSheetState(
                                () => selectedSeason = null),
                          )
                        else
                          const Icon(Icons.video_collection_rounded,
                              color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            atRoot
                                ? series.name
                                : '${series.name} • T$selectedSeason',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.cardBorder),
                  Expanded(
                    child: atRoot
                        ? ListView.separated(
                            controller: scrollController,
                            itemCount: seasons.length,
                            separatorBuilder: (context, index) =>
                                const Divider(
                                    height: 1,
                                    color: AppColors.cardBorder),
                            itemBuilder: (context, idx) {
                              final s = seasons[idx];
                              final count = bySeason[s]!.length;
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'T$s',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                title: Text('Temporada $s',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    '$count episódio${count == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12)),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.white54),
                                onTap: () => setSheetState(
                                    () => selectedSeason = s),
                              );
                            },
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: seasonEps.length,
                            separatorBuilder: (context, index) =>
                                const Divider(
                                    height: 1,
                                    color: AppColors.cardBorder),
                            itemBuilder: (context, idx) {
                              final ep = seasonEps[idx];
                              return TvFocusable(
                                borderRadius: BorderRadius.circular(8),
                                onPressed: () {
                                  Navigator.pop(context);
                                  onOpenPlayer();
                                },
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'E${ep.episodeNumber ?? idx + 1}',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  title: Text(ep.name,
                                      style: const TextStyle(
                                          color: Colors.white)),
                                  subtitle: Text(
                                      'Temporada $selectedSeason',
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12)),
                                  trailing: const Icon(
                                      Icons.play_circle_fill,
                                      color: AppColors.primary),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}