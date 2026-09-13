import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/stream_item.dart';
import 'tv_focusable.dart';

class StreamCard extends StatelessWidget {
  final StreamItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final bool isVod;

  const StreamCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onToggleFavorite,
    this.isVod = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: isVod ? _buildVodLayout(context) : _buildLiveLayout(context),
      ),
    );
  }

  // Layout estilo Poster (Vertical) para Filmes e Séries
  Widget _buildVodLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImage(isPoster: true),
              // Gradiente inferior para legibilidade
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC090C10)],
                      stops: [0.6, 1.0],
                    ),
                  ),
                ),
              ),
              // Botão de Favorito no topo
              Positioned(
                top: 6,
                right: 6,
                child: _buildFavoriteButton(),
              ),
              // Rating Badge
              if (item.rating != null && item.rating!.isNotEmpty)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          item.rating!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Layout estilo Canal Ao Vivo (Horizontal/Card com Logo)
  Widget _buildLiveLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          // Logo do Canal (compacto, só identificação)
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.cardBorder),
            ),
            padding: const EdgeInsets.all(2),
            child: _buildImage(isPoster: false),
          ),
          const SizedBox(width: 6),
          // Informações do Canal
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.accentLive.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppColors.accentLive, width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record,
                              color: AppColors.accentLive, size: 6),
                          SizedBox(width: 3),
                          Text(
                            'AO VIVO',
                            style: TextStyle(
                              color: AppColors.accentLive,
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Botão Favorito
          _buildFavoriteButton(),
        ],
      ),
    );
  }

  Widget _buildImage({required bool isPoster}) {
    if (item.logoUrl != null && item.logoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.logoUrl!,
        fit: isPoster ? BoxFit.cover : BoxFit.contain,
        memCacheWidth: isPoster ? 400 : 200,
        memCacheHeight: isPoster ? 600 : 200,
        maxWidthDiskCache: 500,
        maxHeightDiskCache: 750,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, url) => Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildFallbackIcon(),
      );
    }
    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    return Center(
      child: Icon(
        item.streamType == StreamType.live
            ? Icons.tv_rounded
            : (item.streamType == StreamType.series ? Icons.video_collection_rounded : Icons.movie_rounded),
        color: AppColors.textMuted,
        size: 18,
      ),
    );
  }

  Widget _buildFavoriteButton() {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onToggleFavorite,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
            color: item.isFavorite ? AppColors.accentOrange : AppColors.textSecondary,
            size: 16,
          ),
        ),
      ),
    );
  }
}
