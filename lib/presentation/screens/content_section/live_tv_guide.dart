import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/back_navigation_mixin.dart';
import '../../../data/models/iptv_category.dart';
import '../../../data/models/stream_item.dart';
import '../../../data/services/epg_service.dart';
import '../../controllers/iptv_controller.dart';
import '../../widgets/tv_focusable.dart';
import '../player_screen.dart';

/// Guia de TV ao vivo (layout 3 colunas estilo TV Box).
/// - Categorias à esquerda (opacas)
/// - Canais no centro (translúcidos, preview só no clique)
/// - Preview + EPG à direita
class LiveTvGuide extends StatefulWidget {
  final IptvController controller;

  const LiveTvGuide({super.key, required this.controller});

  @override
  State<LiveTvGuide> createState() => _LiveTvGuideState();
}

class _LiveTvGuideState extends State<LiveTvGuide> with BackNavigationMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _clockTimer;

  EpgService get _epgService => widget.controller.epgService;
  int _epgToken = 0;

  // Navegação: categorias filtram, canais dão preview.
  String? _selectedCategory;
  int _selectedIndex = 0;
  // Prévia só após escolha explícita: 1º clique seleciona, 2º abre player.
  bool _channelChosen = false;

  bool _showOnlyFavorites = false;
  int _sortMode = 0; // 0=original, 1=A–Z, 2=Z–A
  String get _sortSuffix =>
      _sortMode == 1 ? ' A–Z ✓' : _sortMode == 2 ? ' Z–A ✓' : '';
  bool _isSearching = false;
  DateTime _now = DateTime.now();
  List<EpgProgram> _epg = const [];
  bool _epgLoading = false;
  int _epgDayOffset = 0;

  /// Cache da filtragem/agrupamento.
  List<StreamItem>? _chCache;
  String _chCacheKey = '';

  bool get _isTv => MediaQuery.of(context).size.width >= 900;

  @override
  void initState() {
    super.initState();
    widget.controller.setSearchQuery('');
    _now = DateTime.now();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _tickClock());
    final cats = widget.controller.getCategories(StreamType.live);
    _selectedCategory = cats.isNotEmpty ? cats.first.name : 'TODOS';
    _selectedIndex = 0;
    _channelChosen = false;
    _epg = const [];
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
      if (mounted) {
        setState(() {
          _selectedIndex = 0;
          _channelChosen = false;
          _epg = const [];
        });
      }
    });
  }

  // ---------- dados ----------

  List<IptvCategory> get _cats => widget.controller.getCategories(StreamType.live);

  List<StreamItem> _channels() {
    final key =
        '$_selectedCategory|$_showOnlyFavorites|${widget.controller.searchQuery}|$_sortMode|'
        '${widget.controller.totalLiveCount}';
    final cached = _chCache;
    if (cached != null && _chCacheKey == key) return cached;
    var items = widget.controller.getFilteredItems(
      StreamType.live,
      selectedCategory: _selectedCategory,
      onlyFavorites: _showOnlyFavorites,
    );
    items = _applySort(items);
    _chCache = items;
    _chCacheKey = key;
    return items;
  }

  StreamItem? get _selectedChannel {
    if (!_channelChosen) return null;
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
    if (!_channelChosen) {
      if (mounted) setState(() => _epg = const []);
      return;
    }
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
      _channelChosen = false;
      _epgDayOffset = 0;
      _epg = const [];
    });
  }

  void _selectChannel(int i) {
    if (_selectedIndex == i && _channelChosen) return;
    setState(() {
      _selectedIndex = i;
      _channelChosen = true;
    });
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
          keepScreenOn:
              widget.controller.storageService.getKeepScreenOn(),
        ),
      ),
    );
  }

  // ---------- ordenação ----------

  List<StreamItem> _applySort(List<StreamItem> items) {
    if (_sortMode == 0) return items;
    final asc = _sortMode == 1;
    return [...items]
      ..sort((a, b) => asc
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
  }

  void _toggleSort() {
    setState(() {
      _sortMode = (_sortMode + 1) % 3;
      _selectedIndex = 0;
      _channelChosen = false;
      _epg = const [];
    });
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return buildWithBackGuard(
      child: FocusScope(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: _isTv ? _buildTvGuide() : _buildMobileGuide(),
          ),
        ),
      ),
    );
  }

  String get _clockLabel =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  // ----- TV: guia 3 colunas -----

  Widget _buildTvGuide() {
    final chosenLogo = _selectedChannel?.logoUrl;
    return Stack(
      children: [
        if (_channelChosen &&
            chosenLogo != null &&
            chosenLogo.isNotEmpty)
          Positioned.fill(
            child: Opacity(
              opacity: 0.14,
              child: CachedNetworkImage(
                imageUrl: chosenLogo,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        if (_channelChosen)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
        Column(
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
                  ],
                ),
              ),
            ),
          ],
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
                  Text('Sort$_sortSuffix',
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

  Widget _buildTvTopBar() {
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _colorAction(
                    color: Colors.redAccent,
                    label: 'Organizar$_sortSuffix',
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
                    onTap: () => setState(() {
                      _showOnlyFavorites = !_showOnlyFavorites;
                      _selectedIndex = 0;
                      _channelChosen = false;
                      _epg = const [];
                    }),
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
                  onFocus: (_) {},
                  onTap: () => _selectCategory('TODOS'),
                );
              }
              final cat = cats[i - 1];
              return _categoryRow(
                name: cat.name,
                count: cat.count,
                selected: _selectedCategory == cat.name,
                onFocus: (_) {},
                onTap: () => _selectCategory(cat.name),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Coluna 2: canais numerados da categoria.
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
                    final selected =
                        _channelChosen && i == _selectedIndex;
                    return _channelRow(
                      number: i + 1,
                      item: item,
                      selected: selected,
                      onFocus: (_) {},
                      onTap: () {
                        if (_channelChosen && _selectedIndex == i) {
                          _openPlayer(list, i);
                        } else {
                          _selectChannel(i);
                        }
                      },
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
            color: selected
                ? Colors.white
                : AppColors.surface.withValues(alpha: 0.55),
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
              memCacheWidth: 120,
              memCacheHeight: 90,
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
        // Preview 16:9 (só após escolha; antes fica translúcido vazio)
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
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
                    memCacheWidth: 400,
                    memCacheHeight: 225,
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
                        ? const Text(
                            'Nenhum canal escolhido — toque num canal para ver a prévia',
                            textAlign: TextAlign.center,
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
                                  children: [
                                    Text(
                                      ch.name,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                    Text(
                                      ch.category,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12),
                                    ),
                                  ],
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
        const SizedBox(height: 12),
        // EPG / Programação
        Expanded(child: _buildEpgPanel()),
      ],
    );
  }

  Widget _previewPlaceholder(StreamItem? ch) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Icon(Icons.live_tv_rounded,
                color: AppColors.primary, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            ch?.name ?? 'Selecione um canal',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEpgPanel() {
    if (_epgLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_epg.isEmpty) {
      return Center(
        child: Text(
          _channelChosen
              ? 'Sem programação para este canal'
              : 'Selecione um canal para ver a programação',
          style: const TextStyle(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: _epg.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.cardBorder),
      itemBuilder: (context, i) {
        final p = _epg[i];
        final isLive = p.isLiveAt(_now);
        return Container(
          color: isLive
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(p.rangeLabel(),
                  style: TextStyle(
                      color: isLive ? AppColors.primary : Colors.white70,
                      fontWeight: isLive ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isLive ? Colors.white : Colors.white70,
                      fontWeight: isLive ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13),
                ),
              ),
              if (isLive)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.accentGreen,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ----- Mobile: guia simplificado -----

  Widget _buildMobileGuide() {
    return Column(
      children: [
        _buildMobileTopBar(),
        if (_isSearching) _buildSearchRow(),
        // Categoria selecionada
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedCategory ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
              TvFocusable(
                borderRadius: BorderRadius.circular(8),
                onPressed: _toggleSort,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      Text('Sort$_sortSuffix',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Lista de canais
        Expanded(
          child: _buildChannelCol(),
        ),
        // Preview + EPG compacto
        if (_channelChosen) _buildMobilePreview(),
      ],
    );
  }

  Widget _buildMobileTopBar() {
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
              'TV ao vivo',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20),
            ),
          ),
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            onPressed: () => setState(() => _isSearching = true),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.search, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobilePreview() {
    final ch = _selectedChannel;
    if (ch == null) return const SizedBox.shrink();
    final logo = ch.logoUrl;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: (logo != null && logo.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.tv_rounded,
                              color: Colors.white38, size: 48),
                    )
                  : const Icon(Icons.tv_rounded,
                      color: Colors.white38, size: 48),
            ),
          ),
          const SizedBox(height: 8),
          Text(ch.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          Text(ch.category,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          if (_epg.isNotEmpty) ...[
            const Text('Próximos:',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            const SizedBox(height: 4),
            ...(_epg.take(3).map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(p.rangeLabel(),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                    ],
                  ),
                ))),
          ],
        ],
      ),
    );
  }
}