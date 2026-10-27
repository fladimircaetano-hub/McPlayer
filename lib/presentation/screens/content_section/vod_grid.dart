import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/back_navigation_mixin.dart';
import '../../../data/models/iptv_category.dart';
import '../../../data/models/stream_item.dart';
import '../../controllers/iptv_controller.dart';
import '../../widgets/stream_card.dart';
import '../../widgets/tv_focusable.dart';
import '../player_screen.dart';
import 'category_tree.dart';
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

/// Rótulo de release exibido na tela. O split por ABI altera o
/// versionCode (arm32 = 3018), então o rótulo é injetado no build:
/// `--dart-define=RELEASE_TAG=2018`.
const String _releaseTag = String.fromEnvironment('RELEASE_TAG');

/// Subtítulo do cartão de série: esconde o rótulo redundante da seção.
String _seriesCardSubtitle(String category) =>
    _redundantSectionLabels.contains(category.trim()) ? '' : category;

/// Sentinela: subcategoria "todas" selecionada (navegação mobile).
const _kAllSubs = '__ALL_SUBCATEGORIES__';

typedef _CatNode = CategoryNode;

List<_CatNode> _buildCatTree(List<IptvCategory> cats) =>
    buildCategoryTree(cats);

String _categoryParent(String raw) => categoryParent(raw);

String _categorySubLabel(String raw) => categorySubLabel(raw);

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
  final FocusNode _searchNode = FocusNode();
  final FocusNode _backNode = FocusNode();
  Timer? _searchDebounce;

  bool _showOnlyFavorites = false;
  int _sortMode = 0; // 0=original, 1=A–Z, 2=Z–A
  String get _sortSuffix => _sortMode == 1
      ? ' A–Z ✓'
      : _sortMode == 2
      ? ' Z–A ✓'
      : '';
  bool _isSearching = false;
  String _appVersion = '';

  /// Categoria ativa do VOD. 'TODOS' = catálogo completo; quando o
  /// provedor usa hierarquia ("Filmes | Ação"), [_selectedSub] guarda a
  /// folha exata (nome completo) e [_selectedParent] o agrupamento.
  String _selectedParent = '';
  String? _selectedSub;

  StreamType get _type => widget.type;
  bool get _isSeries => _type == StreamType.series;
  bool get _isTv => MediaQuery.of(context).size.width >= 900;

  /// Na TV, a aba Filmes é a única com o agrupamento "Filmes" criado a
  /// partir de "Filmes | Ação". Esse pai é redundante com o título da
  /// tela e foi removido da coluna: suas subcategorias ficam visíveis
  /// desde o início, à espera da escolha do usuário.
  bool get _isTvMovies => _isTv && _type == StreamType.movie;

  List<IptvCategory> get _cats => widget.controller.getCategories(_type);

  /// Pais + folhas (categorias reais) do provedor.
  List<_CatNode> get _catTree => _buildCatTree(_cats);

  /// Agrupamento "Filmes" criado a partir de "Filmes | Ação". Na TV ele
  /// não aparece como linha na coluna de categorias: fica selecionado
  /// internamente para a coluna de SUBCATEGORIAS continuar visível.
  _CatNode? get _hiddenMoviesRoot =>
      _isTvMovies ? findCategoryNode(_catTree, 'Filmes') : null;

  _CatNode? get _selectedNode {
    if (_selectedParent == 'TODOS') return null;
    if (_selectedParent.isEmpty &&
        !_showOnlyFavorites &&
        _hiddenMoviesRoot != null) {
      return _hiddenMoviesRoot;
    }
    for (final node in _catTree) {
      if (node.name == _selectedParent) return node;
    }
    return null;
  }

  /// Categoria com subcategorias, mas ainda sem subcategoria escolhida:
  /// a TV mostra só a lista de subcategorias, nunca o catálogo inteiro.
  bool get _awaitingSubcategory {
    if (!_isTvMovies || _showOnlyFavorites) return false;
    final node = _selectedNode;
    return node != null && node.hasSubs && _selectedSub == null;
  }

  bool get _noCategorySelected =>
      _selectedParent.isEmpty &&
      !_showOnlyFavorites &&
      !(_isTvMovies && _hiddenMoviesRoot != null);

  /// Busca ativa ignora o nível de categorias: o usuário espera ver
  /// resultados imediatamente, não a grade de pastas.
  bool get _searchActive => widget.controller.searchQuery.trim().isNotEmpty;

  bool get _isAllSelected => !_showOnlyFavorites && _selectedParent == 'TODOS';

  String get _title {
    if (_searchActive) return 'Busca';
    if (_showOnlyFavorites) return 'Favoritos';
    if (!_isTv && _selectedParent.isNotEmpty) {
      if (_selectedParent == 'TODOS') {
        return _type == StreamType.movie
            ? 'Todos os Filmes'
            : 'Todas as Séries';
      }
      final sub = _selectedSub;
      if (sub != null && sub != _kAllSubs) {
        return _categorySubLabel(sub);
      }
      return _selectedParent;
    }
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
    // A barra de busca da TV fica sempre visível: o listener garante que
    // o botão "Cancelar" apareça assim que o campo recebe foco.
    _searchNode.addListener(_onSearchFocusChanged);
    _loadAppVersion();
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = _releaseTag.isNotEmpty ? _releaseTag : info.buildNumber;
      if (mounted) {
        setState(() => _appVersion = '${info.version}+$build');
      }
    } catch (_) {
      // Versão é só indicador de build: nunca quebra a tela.
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchNode.removeListener(_onSearchFocusChanged);
    _searchNode.dispose();
    _backNode.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      widget.controller.setSearchQuery(val);
    });
  }

  bool get _searchEngaged =>
      _isSearching || _searchNode.hasFocus || _searchCtrl.text.isNotEmpty;

  void _hideKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// Sai do campo de busca: fecha o teclado, limpa o filtro e devolve o
  /// foco ao botão Voltar. Chamado pelo "Cancelar" e pelo botão Back do
  /// controle — antes o D-pad ficava preso no TextField.
  void _cancelSearch() {
    _searchDebounce?.cancel();
    if (_searchCtrl.text.isNotEmpty) _searchCtrl.clear();
    if (widget.controller.searchQuery.isNotEmpty) {
      widget.controller.setSearchQuery('');
    }
    _searchNode.unfocus();
    _hideKeyboard();
    if (_isSearching) {
      setState(() => _isSearching = false);
    } else if (mounted) {
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backNode.requestFocus();
    });
  }

  /// D-pad preso no TextField: setas verticais não movem o cursor, então
  /// devolvem a navegação para a lista de categorias.
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _cancelSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _searchNode.unfocus();
      _hideKeyboard();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).focusInDirection(
          key == LogicalKeyboardKey.arrowDown
              ? TraversalDirection.down
              : TraversalDirection.up,
        );
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------- dados ----------

  List<StreamItem> _filteredItems() {
    var items = widget.controller.getFilteredItems(
      _type,
      onlyFavorites: _showOnlyFavorites,
    );
    // Categoria/subcategoria é aplicada aqui para suportar hierarquia
    // ("Filmes | Ação"): o controller filtra por nome exato, então o pai
    // precisa do prefixo e a subcategoria da folha exata. Na TV, o pai
    // "Filmes" fica oculto mas continua ativo (só a coluna de
    // subcategorias aparece).
    final parent = _selectedParent.isNotEmpty
        ? _selectedParent
        : (_isTvMovies ? _hiddenMoviesRoot?.name : null);
    if (!_showOnlyFavorites &&
        parent != null &&
        parent.isNotEmpty &&
        parent != 'TODOS') {
      items = items
          .where((item) => _categoryParent(item.category) == parent)
          .toList();
      final sub = _selectedSub;
      if (sub != null && sub != _kAllSubs) {
        items = items.where((item) => item.category == sub).toList();
      }
    }
    // Ordenação
    if (_sortMode != 0) {
      final asc = _sortMode == 1;
      items = [...items]
        ..sort(
          (a, b) => asc
              ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
              : b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
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
          keepScreenOn: widget.controller.storageService.getKeepScreenOn(),
        ),
      ),
    );
  }

  Future<void> _onSeriesTap(SeriesGroup group) async {
    // Xtream: a lista traz 1 item por série; os episódios vêm da API
    // (get_series_info). Sem isso o toque tentaria tocar a URL da série.
    if (group.seriesId != null && widget.controller.currentAccount != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
      final episodes = await widget.controller.getSeriesEpisodes(
        group.seriesId!,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (episodes.isEmpty) {
        _openPlayer(group.episodes, 0);
      } else {
        _showEpisodes(group.rep, episodes);
      }
      return;
    }
    if (group.episodes.length == 1 &&
        parseSeasonEpisodeFast(group.episodes.first.name, 1) == null) {
      _openPlayer(group.episodes, 0);
      return;
    }
    _showEpisodes(group.rep, normalizeSeriesEpisodes(group.episodes));
  }

  void _showEpisodes(StreamItem series, List<StreamItem> episodes) {
    showEpisodesSheet(
      context: context,
      series: series,
      episodes: episodes,
      onOpenPlayer: (playlist, index) => _openPlayer(playlist, index),
    );
  }

  void _toggleSort() {
    setState(() => _sortMode = (_sortMode + 1) % 3);
  }

  // ---------- navegação por níveis (mobile) ----------

  /// Retorna true se conseguiu voltar um nível na hierarquia.
  bool _goBackLevel() {
    // Na TV, só a aba Filmes tem níveis para voltar (Séries e TV ao vivo
    // devem continuar exatamente como estão).
    if (_isTv && !_isTvMovies) return false;
    if (_showOnlyFavorites) {
      setState(() => _showOnlyFavorites = false);
      return true;
    }
    if (_selectedSub != null) {
      setState(() => _selectedSub = null);
      return true;
    }
    if (_selectedParent.isNotEmpty) {
      setState(() {
        _selectedParent = '';
        _selectedSub = null;
      });
      return true;
    }
    return false;
  }

  @override
  void onSystemBack(bool didPop, Object? result) {
    if (didPop) return;
    // 1º Back: sai da busca (teclado + foco). 2º Back: volta um nível/sai.
    if (_searchEngaged) {
      _cancelSearch();
      return;
    }
    if (_goBackLevel()) return;
    super.onSystemBack(didPop, result);
  }

  @override
  void handleBackButton() {
    if (_searchEngaged) {
      _cancelSearch();
      return;
    }
    if (_goBackLevel()) return;
    super.handleBackButton();
  }

  void _selectParent(String name) {
    setState(() {
      _selectedParent = name;
      _selectedSub = null;
      _showOnlyFavorites = false;
    });
  }

  void _selectSub(String? fullName) {
    setState(() {
      _selectedSub = fullName;
      _showOnlyFavorites = false;
    });
  }

  void _toggleFavorites() {
    setState(() => _showOnlyFavorites = !_showOnlyFavorites);
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return buildWithBackGuard(
      child: FocusScope(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                if (!_isTv && _isSearching) _buildSearchRow(),
                if (!_isTv) _buildMobileBreadcrumb(),
                Expanded(child: _isTv ? _buildTvBody() : _buildMobileBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// TV: categorias + subcategorias + busca à esquerda, pôsteres à direita
  /// (mesmo padrão do guia de TV ao vivo).
  Widget _buildTvBody() {
    final node = _selectedNode;
    final showSubs = node != null && node.hasSubs && !_showOnlyFavorites;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 230, child: _buildCategorySidebar()),
          const SizedBox(width: 12),
          if (showSubs) ...[
            SizedBox(width: 230, child: _buildSubcategorySidebar(node)),
            const SizedBox(width: 12),
          ],
          Expanded(child: _buildGridPanel()),
        ],
      ),
    );
  }

  Widget _buildCategorySidebar() {
    final tree = _catTree;
    final hidden = _hiddenMoviesRoot;
    final visibleCount = tree.length - (hidden != null ? 1 : 0);
    final total = _isSeries
        ? widget.controller.totalSeriesCount
        : widget.controller.totalMoviesCount;
    return Column(
      children: [
        _sidebarHeader('CATEGORIAS', subtitle: '$visibleCount'),
        const SizedBox(height: 8),
        _buildSearchField(),
        if (_searchEngaged) ...[
          const SizedBox(height: 6),
          _buildSearchCancelButton(compact: true),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              _categoryRow(
                name: 'TODOS',
                count: total,
                selected: _isAllSelected,
                // Com o pai "Filmes" oculto, o foco começa nas
                // subcategorias (a escolha seguinte), não em TODOS.
                autofocus: _hiddenMoviesRoot == null,
                onTap: () => _selectParent('TODOS'),
              ),
              _categoryRow(
                name: 'FAVORITOS',
                count: widget.controller.totalFavoritesCount,
                selected: _showOnlyFavorites,
                accent: AppColors.accentOrange,
                onTap: _toggleFavorites,
              ),
              ...tree
                  .where((node) => hidden == null || node.name != hidden.name)
                  .map(
                    (node) => _categoryRow(
                      name: node.name,
                      count: node.count,
                      selected:
                          !_showOnlyFavorites && _selectedParent == node.name,
                      onTap: () => _selectParent(node.name),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubcategorySidebar(_CatNode node) {
    return Column(
      children: [
        _sidebarHeader('SUBCATEGORIAS', subtitle: '${node.count}'),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              _categoryRow(
                name: 'TODAS',
                count: node.count,
                selected: _selectedSub == null || _selectedSub == _kAllSubs,
                autofocus: true,
                onTap: () => _selectSub(_kAllSubs),
              ),
              ...node.leaves.map(
                (leaf) => _categoryRow(
                  name: _categorySubLabel(leaf.name),
                  count: leaf.count,
                  selected: _selectedSub == leaf.name,
                  onTap: () => _selectSub(leaf.name),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sidebarHeader(String title, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.grid_view_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow({
    required String name,
    required int count,
    required bool selected,
    bool autofocus = false,
    Color? accent,
    required VoidCallback onTap,
  }) {
    final active = accent ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(10),
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? active.withValues(alpha: 0.18)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? active : AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? active : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: selected ? active : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridPanel() {
    final awaitingSub = _awaitingSubcategory;
    if ((_noCategorySelected || awaitingSub) && !_searchActive) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isSeries
                    ? Icons.movie_filter_rounded
                    : Icons.video_collection_rounded,
                color: AppColors.primary.withValues(alpha: 0.5),
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                awaitingSub
                    ? 'Selecione uma subcategoria de filmes'
                    : _isSeries
                    ? 'Selecione uma categoria de séries'
                    : 'Selecione uma categoria de filmes',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                awaitingSub
                    ? 'Navegue pelas subcategorias ao lado'
                    : 'Navegue pelas categorias à esquerda',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final items = _filteredItems();
    final count = _isSeries ? seriesGroups(items).length : items.length;
    final sub = _selectedSub;
    final parentLabel = _selectedParent.isNotEmpty
        ? _selectedParent
        : (_isTvMovies ? (_hiddenMoviesRoot?.name ?? '') : '');
    final label = _showOnlyFavorites
        ? 'FAVORITOS'
        : _searchActive
        ? 'BUSCA'
        : (_selectedParent == 'TODOS'
              ? 'TODOS'
              : sub != null
              ? '$parentLabel  ›  ${sub == _kAllSubs ? 'TODAS' : _categorySubLabel(sub)}'
              : parentLabel);
    return Container(
      decoration: BoxDecoration(
        // Grade translúcida; categorias à esquerda seguem opacas.
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  /// Celular: navegação por níveis (Categorias → Subcategorias → Grade).
  Widget _buildMobileBody() {
    // Busca global: mostra resultados de todas as categorias na hora.
    if (_searchActive) return _buildGrid();

    // Nível 1: grade de cards de categorias
    if (_noCategorySelected) {
      return _buildMobileCategoriesView();
    }

    // Nível 2: grade de cards de subcategorias (se existirem)
    final node = _selectedNode;
    if (node != null &&
        node.hasSubs &&
        _selectedSub == null &&
        !_showOnlyFavorites) {
      return _buildMobileSubcategoriesView(node);
    }

    // Nível 3: grade de conteúdo filtrado
    return _buildGrid();
  }

  /// Painel translúcido de contexto: mostra em que nível o usuário está
  /// (Categorias › Pai › Subcategoria) e permite voltar um nível.
  Widget _buildMobileBreadcrumb() {
    if (!_showOnlyFavorites && _selectedParent.isEmpty) {
      return const SizedBox.shrink();
    }
    final parts = <String>['Categorias'];
    if (_showOnlyFavorites) {
      parts.add('Favoritos');
    } else {
      parts.add(_selectedParent == 'TODOS' ? 'Todos' : _selectedParent);
      final sub = _selectedSub;
      if (sub != null) {
        parts.add(sub == _kAllSubs ? 'Todas' : _categorySubLabel(sub));
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          TvFocusable(
            borderRadius: BorderRadius.circular(6),
            onPressed: _goBackLevel,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white70,
                size: 14,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join('  ›  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _categoryGradients = [
    [Color(0xFF1A237E), Color(0xFF283593)],
    [Color(0xFF004D40), Color(0xFF00695C)],
    [Color(0xFF880E4F), Color(0xFFC2185B)],
    [Color(0xFF1B5E20), Color(0xFF2E7D32)],
    [Color(0xFF4A148C), Color(0xFF6A1B9A)],
    [Color(0xFFE65100), Color(0xFFEF6C00)],
    [Color(0xFF0D47A1), Color(0xFF1565C0)],
    [Color(0xFF3E2723), Color(0xFF5D4037)],
    [Color(0xFF006064), Color(0xFF00838F)],
    [Color(0xFFBF360C), Color(0xFFD84315)],
  ];

  Widget _buildMobileCategoriesView() {
    final tree = _catTree;
    final total = _isSeries
        ? widget.controller.totalSeriesCount
        : widget.controller.totalMoviesCount;
    final totalItems = tree.length + 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(
                Icons.folder_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Categorias',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              Text(
                '${tree.length} cat. · $total itens',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: totalItems,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _mobileCategoryCard(
                  name: 'TODOS',
                  count: total,
                  icon: Icons.apps_rounded,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.35),
                    AppColors.primary.withValues(alpha: 0.12),
                  ],
                  onTap: () => _selectParent('TODOS'),
                );
              }
              if (i == 1) {
                return _mobileCategoryCard(
                  name: 'FAVORITOS',
                  count: widget.controller.totalFavoritesCount,
                  icon: Icons.star_rounded,
                  colors: [
                    AppColors.accentOrange.withValues(alpha: 0.35),
                    AppColors.accentOrange.withValues(alpha: 0.12),
                  ],
                  onTap: _toggleFavorites,
                );
              }
              final node = tree[i - 2];
              final gi = (i - 2) % _categoryGradients.length;
              return _mobileCategoryCard(
                name: node.name,
                count: node.count,
                icon: Icons.folder_rounded,
                colors: [
                  _categoryGradients[gi][0].withValues(alpha: 0.55),
                  _categoryGradients[gi][1].withValues(alpha: 0.25),
                ],
                onTap: () => _selectParent(node.name),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileSubcategoriesView(_CatNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(
                Icons.subdirectory_arrow_right_rounded,
                color: AppColors.accentGreen,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              Text(
                '${node.leaves.length} subcategorias',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: node.leaves.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _mobileCategoryCard(
                  name: 'TODAS',
                  count: node.count,
                  icon: Icons.select_all_rounded,
                  colors: [
                    AppColors.accentGreen.withValues(alpha: 0.35),
                    AppColors.accentGreen.withValues(alpha: 0.12),
                  ],
                  onTap: () => _selectSub(_kAllSubs),
                );
              }
              final leaf = node.leaves[i - 1];
              final gi = (i - 1) % _categoryGradients.length;
              return _mobileCategoryCard(
                name: _categorySubLabel(leaf.name),
                count: leaf.count,
                icon: Icons.label_rounded,
                colors: [
                  _categoryGradients[gi][0].withValues(alpha: 0.55),
                  _categoryGradients[gi][1].withValues(alpha: 0.25),
                ],
                onTap: () => _selectSub(leaf.name),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _mobileCategoryCard({
    required String name,
    required int count,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(14),
      onPressed: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count itens',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
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
            focusNode: _backNode,
            borderRadius: BorderRadius.circular(8),
            onPressed: handleBackButton,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ),
          if (_appVersion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'v$_appVersion',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
              onTap: _toggleFavorites,
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
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Campo de busca compartilhado entre TV (sidebar) e celular.
  /// O [Focus] externo só intercepta teclas que o TextField ignorou
  /// (setas verticais/Escape) para o D-pad não ficar preso no campo.
  Widget _buildSearchField() {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onSearchKey,
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchNode,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: _isSeries ? 'Pesquisar séries...' : 'Pesquisar filmes...',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          suffixIcon: _searchCtrl.text.isEmpty && !_searchNode.hasFocus
              ? null
              : IconButton(
                  tooltip: 'Limpar busca',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _cancelSearch,
                ),
        ),
        onChanged: (v) {
          _onSearchChanged(v);
          // Rebuild local para o "X" aparecer enquanto digita.
          if (mounted) setState(() {});
        },
        onSubmitted: (_) {
          // Enter/OK no teclado apenas recolhe o teclado e mantém os
          // resultados; não fecha a tela nem deixa o foco preso.
          _searchNode.unfocus();
          _hideKeyboard();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _buildSearchCancelButton({bool compact = false}) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(8),
      onPressed: _cancelSearch,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: compact ? 8 : 11,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.keyboard_backspace_rounded,
              color: AppColors.primary,
              size: 17,
            ),
            SizedBox(width: 6),
            Text(
              'Cancelar busca',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onSearchKey,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _isSeries
                      ? 'Pesquisar séries...'
                      : 'Pesquisar filmes...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
                onChanged: (v) {
                  _onSearchChanged(v);
                  if (mounted) setState(() {});
                },
                onSubmitted: (_) {
                  _searchNode.unfocus();
                  _hideKeyboard();
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 148, child: _buildSearchCancelButton()),
        ],
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
      if (width >= 1200) {
        crossAxisCount = 6;
      } else if (width >= 900) {
        crossAxisCount = 5;
      } else {
        crossAxisCount = 4;
      }
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
        // StreamCard já é um TvFocusable: um único clique pressiona OK,
        // abre o player e desenha o foco. O wrapper externo duplicava os
        // eventos e exigia um segundo toque em alguns controles.
        return StreamCard(
          item: item,
          onTap: () => _openPlayer(items, i),
          onToggleFavorite: () => widget.controller.toggleFavorite(item),
          isVod: true,
        );
      },
    );
  }

  Widget _buildSeriesGrid(List<SeriesGroup> groups) {
    // Calcula colunas baseado na largura
    int crossAxisCount;
    if (_isTv) {
      final width = MediaQuery.of(context).size.width;
      if (width >= 1200) {
        crossAxisCount = 6;
      } else if (width >= 900) {
        crossAxisCount = 5;
      } else {
        crossAxisCount = 4;
      }
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
        // O cartão mostra o nome da SÉRIE (group.name), não do episódio
        // representativo: no M3U o rep é "Nome S01 E01" e sem isso a grade
        // exibiria "Zatch Bell! EP01" em vez de "Zatch Bell".
        final displayItem = group.rep.copyWith(
          name: group.name,
          logoUrl: group.logoUrl ?? group.rep.logoUrl,
          category: group.episodes.length == 1
              ? _seriesCardSubtitle(group.category)
              : '${group.episodes.length} episódios',
        );
        return StreamCard(
          item: displayItem,
          onTap: () => _onSeriesTap(group),
          onToggleFavorite: () => widget.controller.toggleFavorite(group.rep),
          isVod: true,
        );
      },
    );
  }
}
