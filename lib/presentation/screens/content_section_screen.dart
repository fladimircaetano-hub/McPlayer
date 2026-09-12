import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/iptv_category.dart';
import '../../data/models/stream_item.dart';
import '../../data/services/epg_service.dart';
import '../controllers/iptv_controller.dart';
import '../widgets/stream_card.dart';
import '../widgets/tv_focusable.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

/// Tela de seção.
///
/// - TV ao vivo: layout 3 colunas estilo TV Box (categorias/canais à
///   esquerda, preview + programação no centro, relógio + dias à direita).
/// - Filmes/Séries: grade de pôsteres (será refinada com o próximo modelo).
/// - Celular (< 900px): mesmo conteúdo empilhado e adaptado.
class ContentSectionScreen extends StatefulWidget {
  final IptvController controller;
  final StreamType type;

  const ContentSectionScreen({
    super.key,
    required this.controller,
    required this.type,
  });

  @override
  State<ContentSectionScreen> createState() => _ContentSectionScreenState();
}

class _ContentSectionScreenState extends State<ContentSectionScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _clockTimer;

  /// EPG compartilhado do controller (cache carregado após login/lista).
  EpgService get _epgService => widget.controller.epgService;
  int _epgToken = 0;

  // Navegação do guia (ao vivo): categorias filtram, canais dão preview.
  String? _selectedCategory;
  int _selectedIndex = 0;

  bool _showOnlyFavorites = false;
  bool _sortAZ = false;
  bool _isSearching = false;

  DateTime _now = DateTime.now();
  List<EpgProgram> _epg = const [];
  bool _epgLoading = false;
  int _epgDayOffset = 0;

  StreamType get _type => widget.type;
  bool get _isLive => _type == StreamType.live;
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
    _now = DateTime.now();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _tickClock());
    if (_isLive) {
      final cats = widget.controller.getCategories(_type);
      _selectedCategory = cats.isNotEmpty ? cats.first.name : 'TODOS';
      _loadEpg();
    }
  }

  void _tickClock() {
    if (mounted) setState(() => _now = DateTime.now());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _clockTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      widget.controller.setSearchQuery(val);
      if (_isLive && mounted) {
        setState(() => _selectedIndex = 0);
        _loadEpg();
      }
    });
  }

  // ---------- dados ----------

  List<IptvCategory> get _cats => widget.controller.getCategories(_type);

  List<StreamItem> _channels() {
    var items = widget.controller.getFilteredItems(
      _type,
      selectedCategory: _selectedCategory,
      onlyFavorites: _showOnlyFavorites,
    );
    if (_sortAZ) {
      items = [...items]
        ..sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return items;
  }

  StreamItem? get _selectedChannel {
    final list = _channels();
    if (list.isEmpty) return null;
    return list[_selectedIndex.clamp(0, list.length - 1)];
  }

  EpgProgram? get _liveProgram {
    for (final p in _epg) {
      if (p.isLiveAt(_now)) return p;
    }
    return null;
  }

  EpgProgram? get _nextProgram {
    if (_epg.isEmpty) return null;
    final live = _liveProgram;
    if (live == null) return _epg.first;
    final i = _epg.indexOf(live);
    return (i >= 0 && i + 1 < _epg.length) ? _epg[i + 1] : null;
  }

  Future<void> _loadEpg() async {
    final ch = _selectedChannel;
    if (ch == null) {
      if (mounted) setState(() => _epg = const []);
      return;
    }
    final token = ++_epgToken;
    setState(() => _epgLoading = true);
    final day = DateTime(_now.year, _now.month, _now.day)
        .add(Duration(days: _epgDayOffset));
    final programs = await _epgService.getPrograms(ch, day: day);
    if (mounted && token == _epgToken) {
      setState(() {
        _epg = programs;
        _epgLoading = false;
      });
    }
  }

  void _selectCategory(String name) {
    if (_selectedCategory == name) return;
    setState(() {
      _selectedCategory = name;
      _selectedIndex = 0;
      _epgDayOffset = 0;
    });
    _loadEpg();
  }

  void _selectChannel(int i) {
    if (_selectedIndex == i) return;
    setState(() => _selectedIndex = i);
    _loadEpg();
  }

  // ---------- player ----------

  void _openPlayer(List<StreamItem> playlist, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: playlist[index],
          playlist: playlist,
          initialIndex: index,
        ),
      ),
    );
  }

  void _openSeriesEpisodes(List<StreamItem> playlist, int index) async {
    final series = playlist[index];
    if (series.seriesId != null && widget.controller.currentAccount != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
      final episodes =
          await widget.controller.getSeriesEpisodes(series.seriesId!);
      if (mounted) {
        Navigator.of(context).pop();
        if (episodes.isEmpty) {
          _openPlayer(playlist, index);
        } else {
          _showEpisodesSheet(series, episodes);
        }
      }
    } else {
      _openPlayer(playlist, index);
    }
  }

  /// Fluxo em 2 níveis: temporadas da série -> episódios da temporada.
  void _showEpisodesSheet(StreamItem series, List<StreamItem> episodes) {
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
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceLight,
                                      borderRadius:
                                          BorderRadius.circular(8),
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
                                return ListTile(
                                  leading: Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceLight,
                                      borderRadius:
                                          BorderRadius.circular(6),
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
                                  onTap: () {
                                    Navigator.pop(context);
                                    _openPlayer(seasonEps, idx);
                                  },
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

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!_isLive) return _buildVodScaffold();

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.goBack): _onBack,
          },
          child: FocusScope(
            autofocus: true,
            child: Scaffold(
              body: SafeArea(
                child: _isTv ? _buildTvGuide() : _buildMobileGuide(),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onBack() {
    Navigator.of(context).maybePop();
  }

  String get _clockLabel =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  // ----- TV: guia 3 colunas -----

  Widget _buildTvGuide() {
    return Column(
      children: [
        _buildTvTopBar(),
        if (_isSearching) _buildSearchRow(),
        _buildGuideHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 250, child: _buildCategoryCol()),
                const SizedBox(width: 12),
                SizedBox(width: 300, child: _buildChannelCol()),
                const SizedBox(width: 12),
                Expanded(child: _buildCenter()),
                const SizedBox(width: 12),
                SizedBox(width: 120, child: _buildRightRail()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Faixa "All + total + Sort ... data" como no modelo.
  Widget _buildGuideHeader() {
    final total = widget.controller.totalLiveCount;
    final date =
        '${_now.year}/${_now.month.toString().padLeft(2, '0')}/${_now.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          const Icon(Icons.grid_view_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Text('All',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(width: 24),
          Text('$total',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(width: 16),
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            onPressed: _toggleSort,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('Sort${_sortAZ ? ' ✓' : ''}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(date,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
        ],
      ),
    );
  }

  void _toggleSort() {
    setState(() {
      _sortAZ = !_sortAZ;
      _selectedIndex = 0;
    });
    _loadEpg();
  }

  Widget _buildTvTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.surface,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _colorAction(
                    color: Colors.redAccent,
                    label: 'Organizar${_sortAZ ? ' ✓' : ''}',
                    onTap: _toggleSort,
                  ),
                  const SizedBox(width: 16),
                  _colorAction(
                    color: AppColors.accentGreen,
                    label: 'Categoria',
                    onTap: () => _selectCategory('TODOS'),
                  ),
                  const SizedBox(width: 16),
                  _colorAction(
                    color: AppColors.accentOrange,
                    label: 'Favoritos${_showOnlyFavorites ? ' ✓' : ''}',
                    onTap: () => setState(
                        () => _showOnlyFavorites = !_showOnlyFavorites),
                  ),
                  const SizedBox(width: 16),
                  _colorAction(
                    color: AppColors.primary,
                    label: 'Menu',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Text(
              _clockLabel,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Pesquisar canais...',
          prefixIcon: Icon(Icons.search, size: 20),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  /// Coluna 1: categorias com contagem (foco seleciona e filtra).
  Widget _buildCategoryCol() {
    final cats = _cats;
    return Column(
      children: [
        _navHeader(
            icon: Icons.grid_view_rounded,
            title: 'CATEGORIAS',
            count: null),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: cats.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _categoryRow(
                  name: 'TODOS',
                  count: widget.controller.totalLiveCount,
                  selected: _selectedCategory == 'TODOS',
                  autofocus: true,
                  onFocus: (_) => _selectCategory('TODOS'),
                  onTap: () {},
                );
              }
              final cat = cats[i - 1];
              return _categoryRow(
                name: cat.name,
                count: cat.count,
                selected: _selectedCategory == cat.name,
                onFocus: (_) => _selectCategory(cat.name),
                onTap: () {},
              );
            },
          ),
        ),
      ],
    );
  }

  /// Coluna 2: canais numerados da categoria (foco troca preview + EPG).
  Widget _buildChannelCol() {
    final list = _channels();
    return Column(
      children: [
        _navHeader(
          icon: Icons.grid_view_rounded,
          title: (_selectedCategory ?? '').toUpperCase(),
          count: list.length,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('Nenhum canal',
                      style: TextStyle(color: AppColors.textMuted)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final item = list[i];
                    final selected = i == _selectedIndex;
                    return _channelRow(
                      number: i + 1,
                      item: item,
                      selected: selected,
                      onFocus: (_) => _selectChannel(i),
                      onTap: () => _openPlayer(list, i),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _navHeader({
    required IconData icon,
    required String title,
    required int? count,
    VoidCallback? onBack,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          if (onBack != null)
            TvFocusable(
              borderRadius: BorderRadius.circular(8),
              onPressed: onBack,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.arrow_back,
                    color: AppColors.primary, size: 20),
              ),
            )
          else
            Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
          ),
          if (count != null)
            Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
        ],
      ),
    );
  }

  Widget _categoryRow({
    required String name,
    required int count,
    required bool selected,
    bool autofocus = false,
    required ValueChanged<bool> onFocus,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(10),
        onPressed: onTap,
        onFocusChange: onFocus,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? Colors.white : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? Colors.white : AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              Text('$count',
                  style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _channelRow({
    required int number,
    required StreamItem item,
    required bool selected,
    bool autofocus = false,
    required ValueChanged<bool> onFocus,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(10),
        onPressed: onTap,
        onFocusChange: onFocus,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? Colors.white : AppColors.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text('$number',
                    style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
              _logoThumb(item.logoUrl, 40, 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ),
              InkWell(
                onTap: () => widget.controller.toggleFavorite(item),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    item.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: item.isFavorite
                        ? AppColors.accentOrange
                        : (selected
                            ? Colors.black54
                            : AppColors.textSecondary),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoThumb(String? url, double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              memCacheWidth: 160,
              errorWidget: (_, _, _) => const Icon(
                  Icons.tv_rounded,
                  color: Colors.white70,
                  size: 20),
            )
          : const Icon(Icons.tv_rounded,
              color: Colors.white70, size: 20),
    );
  }

  Widget _buildCenter() {
    final ch = _selectedChannel;
    final logo = ch?.logoUrl;
    return Column(
      children: [
        // Preview 16:9
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (logo != null && logo.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: logo,
                    fit: BoxFit.contain,
                    memCacheWidth: 800,
                    errorWidget: (_, _, _) =>
                        _previewPlaceholder(ch),
                  )
                else
                  _previewPlaceholder(ch),
                // Faixa inferior: número + nome + categoria
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.9),
                        ],
                      ),
                    ),
                    child: ch == null
                        ? const Text('Nenhum canal selecionado',
                            style: TextStyle(color: Colors.white70))
                        : Row(
                            children: [
                              Text('${_selectedIndex + 1}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18)),
                              const SizedBox(width: 12),
                              _logoThumb(ch.logoUrl, 52, 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(ch.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    if (_liveProgram != null)
                                      Text(
                                          '${_liveProgram!.rangeLabel()}  ${_liveProgram!.title}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                    if (_nextProgram != null &&
                                        _nextProgram != _liveProgram)
                                      Text(
                                          '${_nextProgram!.rangeLabel()}  ${_nextProgram!.title}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color:
                                                  AppColors.textSecondary,
                                              fontSize: 12)),
                                    if (_liveProgram == null)
                                      Text(ch.category,
                                          maxLines: 1,
                                          style: const TextStyle(
                                              color:
                                                  AppColors.textSecondary,
                                              fontSize: 12)),
                                  ],
                                ),
                              ),
                              TvFocusable(
                                borderRadius:
                                    BorderRadius.circular(10),
                                onPressed: () => _openPlayer(
                                    _channels(), _selectedIndex),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: const Text('Assistir',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Programação
        Expanded(child: _buildEpgBox()),
      ],
    );
  }

  Widget _previewPlaceholder(StreamItem? ch) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.live_tv_rounded,
              color: AppColors.textMuted, size: 56),
          const SizedBox(height: 8),
          Text(
            ch?.name ?? 'Selecione um canal',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEpgBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PROGRAMAÇÃO',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Expanded(
            child: _epgLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary),
                    ),
                  )
                : _epg.isEmpty
                    ? const Center(
                        child: Text(
                          'Guia de programação indisponível para esta lista.\nSelecione um canal e pressione OK para assistir.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _epg.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final p = _epg[i];
                          final live = p.isLiveAt(_now);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: live
                                        ? AppColors.accentGreen
                                        : Colors.white70,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(p.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Text(p.rangeLabel(),
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightRail() {
    const days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: 10,
            itemBuilder: (context, i) {
              final day = DateTime(_now.year, _now.month, _now.day)
                  .add(Duration(days: i));
              final selected = i == _epgDayOffset;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TvFocusable(
                  borderRadius: BorderRadius.circular(10),
                  onPressed: () {
                    setState(() => _epgDayOffset = i);
                    _loadEpg();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected
                              ? Colors.white
                              : AppColors.cardBorder),
                    ),
                    child: Column(
                      children: [
                        Text('${day.day}',
                            style: TextStyle(
                                color: selected
                                    ? Colors.black
                                    : Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18)),
                        Text(days[day.weekday - 1],
                            style: TextStyle(
                                color: selected
                                    ? Colors.black
                                    : AppColors.textSecondary,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ----- Mobile: empilhado -----

  Widget _buildMobileGuide() {
    final list = _channels();
    final ch = _selectedChannel;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            const Icon(Icons.live_tv_rounded,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Text(_title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          TvFocusable(
            borderRadius: BorderRadius.circular(20),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchCtrl.clear();
                  widget.controller.setSearchQuery('');
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color:
                      _isSearching ? AppColors.primary : Colors.white),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: AppColors.surface,
            onSelected: (v) {
              if (v == 'sort') setState(() => _sortAZ = !_sortAZ);
              if (v == 'fav') {
                setState(
                    () => _showOnlyFavorites = !_showOnlyFavorites);
              }
              if (v == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SettingsScreen(controller: widget.controller),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'sort',
                checked: _sortAZ,
                child: const Text('Ordenar A–Z',
                    style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem(
                value: 'fav',
                checked: _showOnlyFavorites,
                child: const Text('Só favoritos',
                    style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Configurações',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: _isSearching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Pesquisar canais...',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // Preview compacto
          if (ch != null)
            Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: (ch.logoUrl != null &&
                            ch.logoUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: ch.logoUrl!,
                            fit: BoxFit.contain,
                            memCacheWidth: 700,
                            errorWidget: (_, _, _) =>
                                _previewPlaceholder(ch),
                          )
                        : _previewPlaceholder(ch),
                  ),
                  ListTile(
                    dense: true,
                    title: Text(ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    subtitle: Text(ch.category,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12)),
                    trailing: ElevatedButton(
                      onPressed: () =>
                          _openPlayer(list, _selectedIndex),
                      child: const Text('Assistir'),
                    ),
                  ),
                ],
              ),
            ),
          // Categorias
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _mChip('TODOS', _selectedCategory == 'TODOS',
                    () => _selectCategory('TODOS')),
                _mChip('FAVORITOS ★', _showOnlyFavorites,
                    () => setState(() {
                          _showOnlyFavorites = !_showOnlyFavorites;
                          _selectedIndex = 0;
                        }),
                    highlight: AppColors.accentOrange),
                ..._cats.map((c) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _mChip(
                          '${c.name} (${c.count})',
                          _selectedCategory == c.name &&
                              !_showOnlyFavorites,
                          () => _selectCategory(c.name)),
                    )),
              ],
            ),
          ),
          // Canais
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('Nenhum canal encontrado',
                        style: TextStyle(
                            color: AppColors.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final item = list[i];
                      return Card(
                        child: ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 30,
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ),
                              _logoThumb(item.logoUrl, 46, 32),
                            ],
                          ),
                          title: Text(item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(item.category,
                              style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12)),
                          trailing: InkWell(
                            onTap: () => widget.controller
                                .toggleFavorite(item),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                item.isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: item.isFavorite
                                    ? AppColors.accentOrange
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          selected: i == _selectedIndex,
                          onTap: () {
                            _selectChannel(i);
                            _openPlayer(list, i);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mChip(String label, bool selected, VoidCallback onTap,
      {Color? highlight}) {
    final active = highlight ?? AppColors.primary;
    return TvFocusable(
      borderRadius: BorderRadius.circular(20),
      onPressed: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? active.withValues(alpha: 0.18)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? active : AppColors.cardBorder),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: selected ? active : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.w500)),
        ),
      ),
    );
  }

  // ----- VOD: grade de pôsteres (será refinada no próximo modelo) -----

  Widget _buildVodScaffold() {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Text(_title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900)),
        actions: [
          TvFocusable(
            borderRadius: BorderRadius.circular(20),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchCtrl.clear();
                  widget.controller.setSearchQuery('');
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color:
                      _isSearching ? AppColors.primary : Colors.white),
            ),
          ),
          TvFocusable(
            borderRadius: BorderRadius.circular(20),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsScreen(controller: widget.controller),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.all(8),
              child:
                  Icon(Icons.settings_rounded, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
        ],
        bottom: _isSearching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Pesquisar...',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
              )
            : null,
      ),
      body: Builder(
        builder: (context) {
          final items = widget.controller.getFilteredItems(
            _type,
            selectedCategory: _selectedCategory,
            onlyFavorites: _showOnlyFavorites,
          );
          final cats = widget.controller.getCategories(_type);
          if (items.isEmpty && cats.isEmpty) {
            return const Center(
              child: Text('Nenhum conteúdo encontrado',
                  style:
                      TextStyle(color: AppColors.textSecondary)),
            );
          }
          final crossAxisCount = _isTv
              ? 6
              : (MediaQuery.of(context).size.width > 600 ? 4 : 2);
          return Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _mChip('TODOS',
                        !_showOnlyFavorites &&
                            (_selectedCategory == 'TODOS' ||
                                _selectedCategory == null), () {
                      setState(() {
                        _showOnlyFavorites = false;
                        _selectedCategory = 'TODOS';
                      });
                    }),
                    _mChip('FAVORITOS ★', _showOnlyFavorites, () {
                      setState(() => _showOnlyFavorites =
                          !_showOnlyFavorites);
                    }, highlight: AppColors.accentOrange),
                    ...cats.map((c) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _mChip(
                              '${c.name} (${c.count})',
                              !_showOnlyFavorites &&
                                  _selectedCategory == c.name,
                              () => setState(() {
                                    _showOnlyFavorites = false;
                                    _selectedCategory = c.name;
                                  })),
                        )),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text('Nenhum conteúdo encontrado',
                            style: TextStyle(
                                color: AppColors.textSecondary)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.65,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return StreamCard(
                            item: item,
                            isVod: true,
                            onTap: () {
                              if (_type == StreamType.series) {
                                _openSeriesEpisodes(items, index);
                              } else {
                                _openPlayer(items, index);
                              }
                            },
                            onToggleFavorite: () =>
                                widget.controller.toggleFavorite(item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
