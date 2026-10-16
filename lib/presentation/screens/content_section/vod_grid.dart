import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/back_navigation_mixin.dart';
import '../../../data/models/stream_item.dart';
import '../../controllers/iptv_controller.dart';
import '../../widgets/stream_card.dart';
import '../../widgets/tv_focusable.dart';
import '../player_screen.dart';
import 'episodes_sheet.dart';
import 'series_grouping.dart';

/// Rótulos genéricos de seção: quando a categoria do item é só o nome
/// da seção ("Séries" dentro de Séries), o subtítulo do cartão é
/// redundante e fica oculto. Categorias reais do provedor (Netflix,
/// Ação...) continuam visíveis.
const _redundantSectionLabels = {
  'Séries',
  'Series',
  'Filmes',
  'Movies',
  'Geral',
  'General',
};

/// Subtítulo do cartão de série: esconde o rótulo redundante da seção.
String _seriesCardSubtitle(String category) =>
    _redundantSectionLabels.contains(category.trim()) ? '' : category;

/// Grade de pôsteres para Filmes e Séries.
/// - Layout responsivo (2/3/4 colunas conforme largura)
/// - Séries agrupadas (1 cartão por série, abre sheet de temporadas/episódios)
/// - Busca, favoritos, ordenação
class VodGrid extends StatefulWidget {
  final IptvController controller;
  final StreamType type;

  const VodGrid({super.key, required this.controller, required this.type});

  @override
  State<VodGrid> createState() => _VodGridState();
}

class _VodGridState extends State<VodGrid> with BackNavigationMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  bool _showOnlyFavorites = false;
  int _sortMode = 0; // 0=original, 1=A–Z, 2=Z–A
  String get _sortSuffix =>
      _sortMode == 1 ? ' A–Z ✓' : _sortMode == 2 ? ' Z–A ✓' : '';
  bool _isSearching = false;

  StreamType get _type => widget.type;
  bool get _isSeries => _type == StreamType.series;
  bool get _isTv => MediaQuery.of(context).size.width >= 900;

  String get _title {
    switch (_type) {
      case StreamType.live:
        return 'TV ao vivo';
      case StreamType.movie:
        return 'Filmes';
      case StreamType.series:
        return 'Séries';
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.setSearchQuery('');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      widget.controller.setSearchQuery(val);
    });
  }

  // ---------- dados ----------

  List<StreamItem> _filteredItems() {
    var items = widget.controller.getFilteredItems(
      _type,
      onlyFavorites: _showOnlyFavorites,
    );
    // Ordenação
    if (_sortMode != 0) {
      final asc = _sortMode == 1;
      items = [...items]
        ..sort((a, b) => asc
            ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
            : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    }
    return items;
  }

  // Para séries: agrupa em SeriesGroup
  List<SeriesGroup> _seriesGroupsList() {
    if (!_isSeries) return [];
    final items = _filteredItems();
    return seriesGroups(items);
  }

  // ---------- ações ----------

  void _openPlayer(List<StreamItem> playlist, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: playlist[index],
          playlist: playlist,
          initialIndex: index,
          keepScreenOn:
              widget.controller.storageService.getKeepScreenOn(),
        ),
      ),
    );
  }

  void _onSeriesTap(SeriesGroup group) {
    if (group.episodes.length == 1 &&
        parseSeasonEpisodeFast(group.episodes.first.name, 1) == null) {
      _openPlayer(group.episodes, 0);
      return;
    }
    showEpisodesSheet(
      context: context,
      series: group.rep,
      episodes: group.episodes,
      onOpenPlayer: () => _openPlayer(group.episodes, 0),
    );
  }

  void _toggleSort() {
    setState(() => _sortMode = (_sortMode + 1) % 3);
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return buildWithBackGuard(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              if (_isSearching) _buildSearchRow(),
              Expanded(child: _buildGrid()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.surface,
      child: Row(
        children: [
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            onPressed: handleBackButton,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24),
            ),
          ),
          if (_isTv) ...[
            _colorAction(
              color: Colors.redAccent,
              label: 'Organizar$_sortSuffix',
              onTap: _toggleSort,
            ),
            const SizedBox(width: 16),
            _colorAction(
              color: AppColors.accentOrange,
              label: 'Favoritos${_showOnlyFavorites ? ' ✓' : ''}',
              onTap: () => setState(() {
                _showOnlyFavorites = !_showOnlyFavorites;
              }),
            ),
            const SizedBox(width: 16),
            _colorAction(
              color: AppColors.primary,
              label: 'Menu',
              onTap: () => Navigator.of(context).pop(),
            ),
          ] else ...[
            TvFocusable(
              borderRadius: BorderRadius.circular(8),
              onPressed: () => setState(() => _isSearching = true),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.search, color: Colors.white, size: 24),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _colorAction({
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(8),
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: _isSeries ? 'Pesquisar séries...' : 'Pesquisar filmes...',
          prefixIcon: const Icon(Icons.search, size: 20),
        ),
        onChanged: _onSearchChanged,
        onSubmitted: (_) => setState(() => _isSearching = false),
      ),
    );
  }

  Widget _buildGrid() {
    if (_isSeries) {
      final groups = _seriesGroupsList();
      if (groups.isEmpty) {
        return Center(
          child: Text(
            _showOnlyFavorites
                ? 'Nenhuma série nos favoritos'
                : 'Nenhuma série na lista',
            style: const TextStyle(color: AppColors.textMuted),
          ),
        );
      }
      return _buildSeriesGrid(groups);
    }

    // Filmes: grid simples de StreamItem
    final items = _filteredItems();
    if (items.isEmpty) {
      return Center(
        child: Text(
          _showOnlyFavorites
              ? 'Nenhum filme nos favoritos'
              : 'Nenhum filme na lista',
          style: const TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return _buildMoviesGrid(items);
  }

  Widget _buildMoviesGrid(List<StreamItem> items) {
    // Calcula colunas baseado na largura
    int crossAxisCount;
    if (_isTv) {
      final width = MediaQuery.of(context).size.width;
      if (width >= 1200) crossAxisCount = 6;
      else if (width >= 900) crossAxisCount = 5;
      else crossAxisCount = 4;
    } else {
      crossAxisCount = 3;
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.68, // pôster 2:3
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return TvFocusable(
          borderRadius: BorderRadius.circular(8),
          onPressed: () => _openPlayer(items, i),
          child: StreamCard(
            item: item,
            onTap: () => _openPlayer(items, i),
            onToggleFavorite: () => widget.controller.toggleFavorite(item),
            isVod: true,
          ),
        );
      },
    );
  }

  Widget _buildSeriesGrid(List<SeriesGroup> groups) {
    // Calcula colunas baseado na largura
    int crossAxisCount;
    if (_isTv) {
      final width = MediaQuery.of(context).size.width;
      if (width >= 1200) crossAxisCount = 6;
      else if (width >= 900) crossAxisCount = 5;
      else crossAxisCount = 4;
    } else {
      crossAxisCount = 3;
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final group = groups[i];
        final displayItem = group.episodes.length == 1
            ? group.rep.copyWith(category: _seriesCardSubtitle(group.category))
            : group.rep.copyWith(category: '${group.episodes.length} episódios');
        return TvFocusable(
          borderRadius: BorderRadius.circular(8),
          onPressed: () => _onSeriesTap(group),
          child: StreamCard(
            item: displayItem,
            onTap: () => _onSeriesTap(group),
            onToggleFavorite: () => widget.controller.toggleFavorite(group.rep),
            isVod: true,
          ),
        );
      },
    );
  }
}