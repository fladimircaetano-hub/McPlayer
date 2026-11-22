import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/adult_content.dart';
import '../../data/models/stream_item.dart';
import 'tv_focusable.dart';

class StreamCard extends StatefulWidget {
  final StreamItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final bool isVod;
  final bool compact;

  /// Nó externo para a grade conseguir mandar o foco para este cartão
  /// (ex.: primeiro item depois de escolher a categoria).
  final FocusNode? focusNode;

  /// Chamado quando o card ganha/perde foco. A grade usa isso para rolar até
  /// deixar a capa inteira visível com um único toque no D-pad.
  final ValueChanged<bool>? onFocusChange;

  const StreamCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onToggleFavorite,
    this.isVod = false,
    this.compact = false,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  State<StreamCard> createState() => _StreamCardState();
}

class _StreamCardState extends State<StreamCard> {
  /// InkWell da estrela está aninhado no GestureDetector do card: o Flutter
  /// entrega o tap aos dois. Ignora o tap do card logo após favoritar.
  DateTime? _favTapAt;
  static const _favGuard = Duration(milliseconds: 400);

  StreamItem get item => widget.item;

  void _onFavTap() {
    _favTapAt = DateTime.now();
    widget.onToggleFavorite();
  }

  void _onCardTap() {
    final t = _favTapAt;
    if (t != null && DateTime.now().difference(t) < _favGuard) return;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.compact ? 10.0 : 14.0;
    return TvFocusable(
      focusNode: widget.focusNode,
      onPressed: _onCardTap,
      onFocusChange: widget.onFocusChange,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        decoration: BoxDecoration(
          // Grade translúcida; categorias (sidebar) seguem opacas.
          color: AppColors.surfaceCard.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.cardBorder, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.isVod ? _buildVodLayout(context) : _buildLiveLayout(context),
      ),
    );
  }

  // Layout estilo Poster (Vertical) para Filmes e Séries
  Widget _buildVodLayout(BuildContext context) {
    final isCompact = widget.compact;
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
                top: isCompact ? 4 : 6,
                right: isCompact ? 4 : 6,
                child: _buildFavoriteButton(),
              ),
              // Rating Badge
              if (item.rating != null && item.rating!.isNotEmpty)
                Positioned(
                  bottom: isCompact ? 5 : 8,
                  left: isCompact ? 5 : 8,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 4 : 6,
                      vertical: isCompact ? 1 : 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(isCompact ? 4 : 6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: isCompact ? 11 : 14,
                        ),
                        SizedBox(width: isCompact ? 2 : 3),
                        Text(
                          item.rating!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompact ? 9.5 : 11,
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
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 6 : 10,
            vertical: isCompact ? 5 : 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: isCompact ? 11 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (item.category.isNotEmpty) ...[
                SizedBox(height: isCompact ? 1 : 2),
                Text(
                  displayCategoryName(item.category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: isCompact ? 9.5 : 11,
                  ),
                ),
              ],
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
                        displayCategoryName(item.category),
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
        memCacheWidth: isPoster ? 256 : 128,
        memCacheHeight: isPoster ? 384 : 128,
        maxWidthDiskCache: 320,
        maxHeightDiskCache: 480,
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
    final isCompact = widget.compact;
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _onFavTap,
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 3 : 4),
          child: Icon(
            item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
            color: item.isFavorite ? AppColors.accentOrange : AppColors.textSecondary,
            size: isCompact ? 14 : 16,
          ),
        ),
      ),
    );
  }
}
