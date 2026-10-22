import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/back_navigation_mixin.dart';
import '../../../data/models/iptv_category.dart';
import '../../../data/models/stream_item.dart';
import '../../../data/services/epg_service.dart';
import '../../controllers/iptv_controller.dart';
import '../../widgets/tv_focusable.dart';
import '../player_screen.dart';
import 'category_tree.dart';

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

  Player? _previewPlayer;
  VideoController? _previewVideoController;

  EpgService get _epgService => widget.controller.epgService;
  int _epgToken = 0;

  /// Token do preview: descarta aberturas antigas quando o usuário troca
  /// de canal rápido (zapping). Sem isso, o `open()` de um canal anterior
  /// pode terminar depois e deixar o vídeo errado na tela.
  int _previewToken = 0;
  bool _previewLoading = false;
  bool _previewError = false;

  // Navegação: categorias filtram, canais dão preview.
  String? _selectedCategory;
  int _selectedIndex = 0;
  // Prévia só após escolha explícita: 1º clique seleciona, 2º abre player.
  bool _channelChosen = false;

  // Celular: navegação em níveis Categoria -> Subcategoria -> Canal.
  // _mobileParent é o pai visível (ex.: CANAIS); _mobileSub é a categoria
  // bruta do provedor usada para filtrar os canais.
  String? _mobileParent;
  String? _mobileSub;

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
    try {
      _previewPlayer?.dispose();
    } catch (_) {}
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

  List<CategoryNode> get _mobileTree => buildCategoryTree(_cats);

  CategoryNode? get _mobileNode {
    if (_mobileParent == null) return null;
    return findCategoryNode(_mobileTree, _mobileParent!);
  }

  /// Categoria bruta usada para filtrar os canais no nível atual.
  String? get _activeCategory => _isTv ? _selectedCategory : _mobileSub;

  bool get _mobileAtCategories => !_isTv && _mobileParent == null;

  bool get _mobileAtSubcategories {
    if (_isTv || _mobileParent == null || _mobileSub != null) return false;
    final node = _mobileNode;
    return node != null && node.hasSubs;
  }

  bool get _mobileAtChannels =>
      !_isTv && !_mobileAtCategories && !_mobileAtSubcategories;

  List<StreamItem> _channels() {
    final key =
        '${_activeCategory ?? ''}|$_showOnlyFavorites|${widget.controller.searchQuery}|$_sortMode|'
        '${widget.controller.totalLiveCount}';
    final cached = _chCache;
    if (cached != null && _chCacheKey == key) return cached;
    var items = widget.controller.getFilteredItems(
      StreamType.live,
      selectedCategory: _activeCategory,
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
    try {
      _previewPlayer?.stop();
    } catch (_) {}
    setState(() {
      _selectedCategory = name;
      _selectedIndex = 0;
      _channelChosen = false;
      _previewLoading = false;
      _previewError = false;
      _epgDayOffset = 0;
      _epg = const [];
    });
  }

  // ---------- navegação mobile por níveis ----------

  void _stopPreview() {
    try {
      _previewPlayer?.stop();
    } catch (_) {}
    _previewToken++;
    _previewLoading = false;
    _previewError = false;
  }

  void _selectMobileParent(CategoryNode node) {
    _stopPreview();
    widget.controller.setSearchQuery('');
    setState(() {
      _mobileParent = node.name;
      // Categoria sem subcategorias (ex.: "A FAZENDA") vai direto aos
      // canais; com hierarquia, mostra a lista de subcategorias.
      _mobileSub = node.hasSubs ? null : node.leaves.first.name;
      _selectedIndex = 0;
      _channelChosen = false;
      _epg = const [];
      _isSearching = false;
    });
  }

  void _selectMobileSub(String rawCategory) {
    _stopPreview();
    widget.controller.setSearchQuery('');
    setState(() {
      _mobileSub = rawCategory;
      _selectedIndex = 0;
      _channelChosen = false;
      _epg = const [];
      _isSearching = false;
    });
  }

  /// Atalho "TODOS": mostra o catálogo completo só depois de um toque
  /// explícito, nunca na abertura da tela.
  void _selectMobileAll() {
    _stopPreview();
    widget.controller.setSearchQuery('');
    setState(() {
      _mobileParent = 'TODOS';
      _mobileSub = 'TODOS';
      _selectedIndex = 0;
      _channelChosen = false;
      _epg = const [];
      _isSearching = false;
    });
  }

  /// Volta um nível na navegação do celular. Retorna true quando consumiu
  /// o "voltar"; false deixa o mixin fechar a tela.
  bool _mobileBackLevel() {
    if (_isTv) return false;
    if (_isSearching) {
      widget.controller.setSearchQuery('');
      setState(() => _isSearching = false);
      return true;
    }
    if (_mobileSub != null) {
      final node = _mobileNode;
      final flat = node == null || !node.hasSubs;
      _stopPreview();
      setState(() {
        if (flat) _mobileParent = null;
        _mobileSub = null;
        _selectedIndex = 0;
        _channelChosen = false;
        _epg = const [];
      });
      return true;
    }
    if (_mobileParent != null) {
      _stopPreview();
      setState(() {
        _mobileParent = null;
        _selectedIndex = 0;
        _channelChosen = false;
        _epg = const [];
      });
      return true;
    }
    return false;
  }

  @override
  void onSystemBack(bool didPop, Object? result) {
    if (didPop) return;
    if (_mobileBackLevel()) return;
    super.onSystemBack(didPop, result);
  }

  @override
  void handleBackButton() {
    if (_mobileBackLevel()) return;
    super.handleBackButton();
  }

  void _selectChannel(int i) {
    if (_selectedIndex == i && _channelChosen) {
      final list = _channels();
      if (list.isNotEmpty && i >= 0 && i < list.length) {
        _openPlayer(list, i);
      }
      return;
    }
    setState(() {
      _selectedIndex = i;
      _channelChosen = true;
      // Não deixa a programação do canal anterior na tela enquanto a
      // nova consulta ao cache do EPG não termina.
      _epg = const [];
    });
    _loadEpg();
    final ch = _selectedChannel;
    if (ch != null) {
      _startPreview(ch);
    }
  }

  Future<void> _startPreview(StreamItem ch) async {
    final token = ++_previewToken;
    setState(() {
      _previewLoading = true;
      _previewError = false;
    });
    try {
      _previewPlayer ??= Player(
        configuration: const PlayerConfiguration(
          title: 'MC Player Preview',
          osc: false,
          bufferSize: 32 * 1024 * 1024,
        ),
      );
      _previewVideoController ??= VideoController(
        _previewPlayer!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
      await _previewPlayer!.open(Media(ch.streamUrl));
      // Outro canal foi escolhido enquanto este abria: descarta.
      if (!mounted || token != _previewToken) return;
      setState(() => _previewLoading = false);
    } catch (e) {
      if (!mounted || token != _previewToken) return;
      setState(() {
        _previewLoading = false;
        _previewError = true;
      });
      debugPrint('[LiveTvGuide] Preview video init error: $e');
    }
  }

  EpgProgram? get _currentProgram {
    if (_epg.isEmpty) return null;
    final now = DateTime.now();
    for (final p in _epg) {
      if (p.isLiveAt(now)) return p;
    }
    // EPG desatualizado/fora da janela: não rotula programa passado
    // como "NO AR"; o painel mostra "sem programação no momento".
    return null;
  }

  // ---------- player ----------

  Future<void> _openPlayer(List<StreamItem> playlist, int index) async {
    try {
      await _previewPlayer?.pause();
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(
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
    if (!mounted) return;
    final ch = _selectedChannel;
    if (ch != null) {
      try {
        await _previewPlayer?.play();
      } catch (_) {}
    }
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
    final current = _currentProgram;
    final list = _channels();
    final index = list.isEmpty ? 0 : _selectedIndex.clamp(0, list.length - 1);

    return Column(
      children: [
        // Preview 16:9 interativo (clicar abre tela cheia)
        TvFocusable(
          borderRadius: BorderRadius.circular(10),
          onPressed: () {
            if (_channelChosen && list.isNotEmpty) {
              _openPlayer(list, index);
            }
          },
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Vídeo ou poster/placeholder
                  if (_channelChosen && _previewVideoController != null)
                    Video(
                      controller: _previewVideoController!,
                      fit: BoxFit.contain,
                      controls: NoVideoControls,
                    )
                  else if (logo != null && logo.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.contain,
                      memCacheWidth: 400,
                      memCacheHeight: 225,
                      errorWidget: (_, _, _) => _previewPlaceholder(ch),
                    )
                  else
                    _previewPlaceholder(ch),

                  if (_channelChosen && _previewLoading)
                    const Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  else if (_channelChosen && _previewError)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Não foi possível abrir o canal',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ),

                  // Overlay superior discreto translúcido (Canal + Categoria + Badge tela cheia)
                  if (ch != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.85),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '${_selectedIndex + 1}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    ch.category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fullscreen_rounded, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tela Cheia',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Overlay inferior translúcido com info do programa atual e barra de progresso EPG
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                            Colors.black.withValues(alpha: 0.95),
                          ],
                        ),
                      ),
                      child: ch == null
                          ? const Text(
                              'Selecione um canal para assistir à transmissão',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    if (current != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentGreen.withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.accentGreen, width: 0.8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.circle, color: AppColors.accentGreen, size: 7),
                                            SizedBox(width: 4),
                                            Text(
                                              'NO AR',
                                              style: TextStyle(
                                                color: AppColors.accentGreen,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        current?.title ?? 'Programação não informada',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (current != null)
                                      Text(
                                        current.rangeLabel(),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                                if (current != null) ...[
                                  const SizedBox(height: 6),
                                  _EpgProgressBar(program: current, height: 4),
                                ],
                              ],
                            ),
                    ),
                  ),
                ],
              ),
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
          decoration: BoxDecoration(
            color: isLive
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            border: isLive
                ? const Border(
                    left: BorderSide(color: AppColors.accentGreen, width: 3),
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                p.rangeLabel(),
                style: TextStyle(
                  color: isLive ? AppColors.primary : Colors.white70,
                  fontWeight: isLive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isLive ? Colors.white : Colors.white70,
                    fontWeight: isLive ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              if (isLive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.accentGreen, width: 0.8),
                  ),
                  child: const Text(
                    'NO AR',
                    style: TextStyle(
                      color: AppColors.accentGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ----- Mobile: categorias -> subcategorias -> canais -----

  void _toggleMobileSearch() {
    if (!_mobileAtChannels) return;
    setState(() => _isSearching = !_isSearching);
    if (_isSearching) {
      _searchCtrl.clear();
    } else {
      widget.controller.setSearchQuery('');
    }
  }

  Widget _buildMobileGuide() {
    return Column(
      children: [
        _buildMobileTopBar(),
        if (_mobileAtChannels && _isSearching) _buildMobileSearchRow(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Paisagem ganha mais espaço com a prévia à esquerda; em
              // retrato a prévia fica em cima (1/3) e a navegação embaixo
              // (2/3), como pedido.
              final landscape =
                  constraints.maxWidth > constraints.maxHeight * 1.15;
              final preview = _buildMobilePreview();
              final nav = _buildMobileNavigation();
              if (landscape) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: preview),
                      const SizedBox(width: 8),
                      Expanded(flex: 6, child: nav),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                child: Column(
                  children: [
                    Expanded(flex: 1, child: preview),
                    const SizedBox(height: 6),
                    Expanded(flex: 2, child: nav),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileTopBar() {
    final atRoot = _mobileAtCategories;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.surface,
      child: Row(
        children: [
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            onPressed: atRoot ? handleBackButton : _mobileBackLevel,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'TV ao vivo',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ),
          if (_mobileAtChannels)
            TvFocusable(
              borderRadius: BorderRadius.circular(8),
              onPressed: _toggleMobileSearch,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  _isSearching ? Icons.close_rounded : Icons.search,
                  color: Colors.white,
                  size: 23,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileSearchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 6, 11, 0),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Pesquisar canais...',
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpar busca',
                  icon: const Icon(Icons.close, size: 17),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                    setState(() {});
                  },
                ),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildMobilePreview() {
    final ch = _selectedChannel;
    // Sem canal escolhido não há motivo para carregar a lista inteira
    // (o catálogo do provedor pode ter milhares de canais).
    final list = ch == null ? const <StreamItem>[] : _channels();
    final index = list.isEmpty ? 0 : _selectedIndex.clamp(0, list.length - 1);
    final logo = ch?.logoUrl;
    final current = _currentProgram;

    return GestureDetector(
      key: const Key('live-mobile-preview'),
      onTap: ch == null ? null : () => _openPlayer(list, index),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ch == null)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv_rounded,
                        color: Colors.white24, size: 44),
                    SizedBox(height: 8),
                    Text(
                      'Selecione um canal',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              )
            else ...[
              if (_previewVideoController != null)
                Video(
                  controller: _previewVideoController!,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                ),
              // Logo/ícone cobre o vídeo enquanto ele carrega ou falha; com
              // o canal tocando, o vídeo fica visível (nada por cima).
              if (_previewVideoController == null ||
                  _previewLoading ||
                  _previewError)
                Center(
                  child: logo != null && logo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: logo,
                          fit: BoxFit.contain,
                          memCacheWidth: 220,
                          errorWidget: (_, _, _) => const Icon(
                              Icons.tv_rounded,
                              color: Colors.white38,
                              size: 44),
                        )
                      : const Icon(Icons.tv_rounded,
                          color: Colors.white38, size: 44),
                ),
              if (_previewLoading)
                const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              if (_previewError)
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Não foi possível abrir o canal',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.fromLTRB(10, 22, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (current != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentLive
                                          .withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(
                                          color: AppColors.accentLive,
                                          width: 0.6),
                                    ),
                                    child: const Text(
                                      'AO VIVO',
                                      style: TextStyle(
                                        color: AppColors.accentLive,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              current?.title ?? 'Sem programação no momento',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10.5),
                            ),
                            if (current != null) ...[
                              const SizedBox(height: 3),
                              _EpgProgressBar(program: current, height: 3),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _openPlayer(list, index),
                          child: const Text('Assistir'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileNavigation() {
    final node = _mobileNode;
    final String title;
    final int count;
    final bool showSort;
    final Widget body;
    if (_mobileAtCategories) {
      title = 'Categorias';
      count = _mobileTree.length + 1; // + atalho TODOS
      showSort = false;
      body = _buildMobileCategoryList();
    } else if (_mobileAtSubcategories) {
      title = node?.name ?? 'Subcategorias';
      count = node?.leaves.length ?? 0;
      showSort = false;
      body = _buildMobileSubcategoryList(node);
    } else {
      final list = _channels();
      title = _mobileSub == null
          ? (node?.name ?? 'Canais')
          : categorySubLabel(_mobileSub!);
      count = list.length;
      showSort = true;
      body = _buildMobileChannelList(list);
    }

    return Container(
      key: const Key('live-mobile-nav'),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 43,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  if (!_mobileAtCategories)
                    TvFocusable(
                      borderRadius: BorderRadius.circular(7),
                      onPressed: _mobileBackLevel,
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(Icons.arrow_back_rounded,
                            color: AppColors.primary, size: 19),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(Icons.grid_view_rounded,
                          color: AppColors.primary, size: 18),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13),
                    ),
                  ),
                  Text(
                    '$count',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  if (showSort)
                    TvFocusable(
                      borderRadius: BorderRadius.circular(7),
                      onPressed: _toggleSort,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          _sortMode == 0
                              ? Icons.sort_rounded
                              : Icons.sort_rounded,
                          color: _sortMode == 0
                              ? Colors.white70
                              : AppColors.primary,
                          size: 19,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.cardBorder),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildMobileCategoryList() {
    final tree = _mobileTree;
    if (tree.isEmpty) {
      return const Center(
        child: Text('Nenhuma categoria',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(7, 7, 7, 12),
      itemCount: tree.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 5),
      itemBuilder: (context, i) {
        if (i == 0) {
          final total = widget.controller.totalLiveCount;
          return _mobileCategoryRow(
            name: 'TODOS',
            subtitle: '$total canais',
            count: total,
            hasSubs: false,
            onTap: _selectMobileAll,
          );
        }
        final node = tree[i - 1];
        return _mobileCategoryRow(
          name: node.name,
          subtitle: node.hasSubs
              ? '${node.leaves.length} subcategorias'
              : '${node.count} canais',
          count: node.count,
          hasSubs: node.hasSubs,
          onTap: () => _selectMobileParent(node),
        );
      },
    );
  }

  Widget _buildMobileSubcategoryList(CategoryNode? node) {
    final leaves = node?.leaves ?? const <IptvCategory>[];
    if (leaves.isEmpty) {
      return const Center(
        child: Text('Nenhuma subcategoria',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(7, 7, 7, 12),
      itemCount: leaves.length,
      separatorBuilder: (_, _) => const SizedBox(height: 5),
      itemBuilder: (context, i) {
        final leaf = leaves[i];
        return _mobileCategoryRow(
          name: categorySubLabel(leaf.name),
          subtitle: '${leaf.count} canais',
          count: leaf.count,
          hasSubs: false,
          onTap: () => _selectMobileSub(leaf.name),
        );
      },
    );
  }

  Widget _mobileCategoryRow({
    required String name,
    required String subtitle,
    required int count,
    required bool hasSubs,
    required VoidCallback onTap,
  }) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(9),
      onPressed: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(
              hasSubs ? Icons.folder_rounded : Icons.play_circle_outline_rounded,
              color: hasSubs ? AppColors.primary : AppColors.accentGreen,
              size: 19,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 11),
            ),
            const SizedBox(width: 3),
            Icon(
              hasSubs ? Icons.chevron_right_rounded : Icons.play_arrow_rounded,
              color: Colors.white54,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileChannelList(List<StreamItem> list) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          _isSearching ? 'Nenhum canal encontrado' : 'Nenhum canal',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(7, 7, 7, 12),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final item = list[i];
        final selected = _channelChosen && i == _selectedIndex;
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: TvFocusable(
            borderRadius: BorderRadius.circular(9),
            onPressed: () {
              if (_channelChosen && _selectedIndex == i) {
                _openPlayer(list, i);
              } else {
                _selectChannel(i);
              }
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.16)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.cardBorder,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 25,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: selected ? AppColors.primary : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  _logoThumb(item.logoUrl, 42, 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5),
                        ),
                        if (selected)
                          const Text(
                            'Prévia ao vivo',
                            style: TextStyle(
                                color: AppColors.primary, fontSize: 9.5),
                          ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => widget.controller.toggleFavorite(item),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        item.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: item.isFavorite
                            ? AppColors.accentOrange
                            : AppColors.textSecondary,
                        size: 19,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


}

/// Barra de progresso do programa atual. Atualiza a cada segundo:
/// O relogio global da tela bate a cada 20s (para nao reconstruir as
/// listas), entao a barra teria saltos visiveis sem este timer local.
class _EpgProgressBar extends StatefulWidget {
  final EpgProgram program;
  final double height;

  const _EpgProgressBar({required this.program, this.height = 4});

  @override
  State<_EpgProgressBar> createState() => _EpgProgressBarState();
}

class _EpgProgressBarState extends State<_EpgProgressBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  double get _progress {
    final total = widget.program.end.difference(widget.program.start).inMilliseconds;
    if (total <= 0) return 0;
    final elapsed = DateTime.now().toUtc().difference(widget.program.start).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: LinearProgressIndicator(
        value: _progress,
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
        minHeight: widget.height,
      ),
    );
  }
}
