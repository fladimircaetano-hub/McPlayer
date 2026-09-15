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

  /// Cache da filtragem/agrupamento (ver [_channels]).
  List<StreamItem>? _chCache;
  String _chCacheKey = '';
  List<_SeriesGroup>? _grCache;
  String _grCacheKey = '';

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
    // Memo: a grade rebuilda a cada setState (relógio, foco, EPG...);
    // revarrer 100k+ itens e reagrupar séries a cada frame travava o Fire.
    final key =
        '$_selectedCategory|$_showOnlyFavorites|${widget.controller.searchQuery}|$_sortAZ|'
        '${widget.controller.totalLiveCount}|${widget.controller.totalMoviesCount}|${widget.controller.totalSeriesCount}';
    final cached = _chCache;
    if (cached != null && _chCacheKey == key) return cached;
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
    _chCache = items;
    _chCacheKey = key;
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
          keepScreenOn:
              widget.controller.storageService.getKeepScreenOn(),
        ),
      ),
    );
  }

  /// Agrupa itens avulsos (ex.: "Nome S01 E01") por série.
  /// Xtream entrega 1 item por série (com seriesId); M3U entrega 1 item
  /// por episódio — aqui viram um grupo só na grade.
  List<_SeriesGroup> _seriesGroups(List<StreamItem> items) {
    // Memo junto de [_channels]: reagrupar 100k episódios a cada rebuild
    // congelava o Fire (ANR). A lista `items` é a mesma instância memoizada.
    final key = '${identityHashCode(items)}|${items.length}';
    final cached = _grCache;
    if (cached != null && _grCacheKey == key) return cached;
    final map = <String, _SeriesGroup>{};
    for (final item in items) {
      if (item.seriesId != null) {
        map['xtream:${item.seriesId}'] = _SeriesGroup(
          name: item.name,
          logoUrl: item.logoUrl,
          category: item.category,
          seriesId: item.seriesId,
          rep: item,
          episodes: [item],
        );
        continue;
      }
      final key = _seriesKey(item.name);
      final g = map[key];
      if (g == null) {
        map[key] = _SeriesGroup(
          name: _seriesDisplayName(item.name),
          logoUrl: item.logoUrl,
          category: item.category,
          seriesId: null,
          rep: item,
          episodes: [item],
        );
      } else {
        g.episodes.add(item);
        if ((g.logoUrl == null || g.logoUrl!.isEmpty) &&
            item.logoUrl != null &&
            item.logoUrl!.isNotEmpty) {
          g.logoUrl = item.logoUrl;
        }
      }
    }
    // Provedores que entregam 1 item por TEMPORADA ("Zatch Bell! 1"..
    // "Zatch Bell! 9", "Fairy Tail [LEG] 0..9"): funde num cartão só por
    // série. Na busca/grade aparece 1 série; temporadas/episódios só
    // depois do clique.
    _mergeSeasonSplits(map);
    final groups = map.values.toList();
    _grCache = groups;
    _grCacheKey = '${identityHashCode(items)}|${items.length}';
    return groups;
  }

  static final _seRegex = RegExp(r'[sS](\d{1,2})\s*[eE](\d{1,2})');
  static final _tPrefixRegex =
      RegExp(r'^[tT]\d+\s*:\s*[eE]\d+\s*[-–—]\s*');

  /// "T01 E01" / "T1 E12" em qualquer posição (só p/ numeração).
  static final _tRegex = RegExp(r'\b[tT](\d{1,2})\s+[eE](\d{1,3})\b');

  /// "1x01" / "02x13" (só p/ numeração).
  static final _xRegex = RegExp(r'\b(\d{1,2})x(\d{1,3})\b');

  /// Número do episódio avulso p/ [_parseSeasonEpisode]: EP01, Cap 3...
  static final _epNumRegex = RegExp(
      r'(?:\b[Ee][Pp]?|epis[oó]dio|cap(?:í|i)tulo|cap\.?|parte|part\.?)\s*\.?\s*(\d{1,3})\b',
      caseSensitive: false);

  /// TODOS os marcadores num único padrão global (uma varredura só).
  /// Passar 11 regex separados por item travava a grade em listas
  /// gigantes (ANR -> app fechado pelo sistema no Fire).
  /// Cobre: S01E01, T01 E01, 1x01, E01/EP12/E01-E07, Episódio/Cap/Parte N,
  /// tags (Dublado)/[4K], palavras soltas no fim (dublado, 4K, 1080p...),
  /// "Temporada/Season N". Ano (1999) NÃO sai (não junta remakes).
  static final _markersRegex = RegExp(
    r'[sS]\d{1,2}\s*[eE]\d{1,2}'
    r'|\b[tT]\d{1,2}\s+[eE]\d{1,3}\b'
    r'|\b\d{1,2}x\d{1,3}\b'
    r'|[\(\[]\s*(dublado|legendado|dual\s*audio|dual-audio|dual|leg|dub|nacional|original|4k|uhd|fhd|full\s*hd|hd|sd|hdcam|cam|1080p|720p|480p|2160p|hevc|x264|x265|h264|h265|[ld])\s*[\)\]]'
    r'|\s+(epis[oó]dio|cap(?:í|i)tulo|cap\.?|parte|part\.?)\s*\.?\s*\d{1,3}\s*$'
    r'|\s+[Ee][Pp]?\d{1,3}(\s*[-–—]\s*[Ee]?[Pp]?\d{1,3})?\s*$'
    r'|\s+[-–—:]?\s*(temporada|season|temp\.?)\s*\.?\s*\d{1,3}\s*$'
    r'|\s+[-–—:]?\s*(dublado|legendado|dual\s*audio|dual-audio|dual|nacional|original|4k|uhd|fhd|full\s*hd|hd|sd|hdcam|cam|1080p|720p|480p|2160p|hevc|x264|x265|h264|h265)\s*$',
    caseSensitive: false,
  );
  static final _spacesRegex = RegExp(r'\s{2,}');
  static final _trailSepRegex = RegExp(r'\s*[-–—:|!?]\s*$');

  /// Caso dominante ("Nome S01 E01", com ou sem espaço): fatia a base
  /// direto com 1 match ancorado em vez de varrer todos os padrões.
  static final _fastSeRegex =
      RegExp(r'^(.*)\s+[sS]\d{1,2}\s*[eE]\d{1,3}\s*$');

  /// Cache nome -> base normalizada: a grade recalcula os grupos a cada
  /// rebuild; sem cache o custo se repetia. Teto p/ não pesar a RAM.
  static final Map<String, String> _stripCache = {};

  /// Remove marcadores de episódio/temporada/tags para agrupar itens da
  /// mesma série. Via rápida para "Nome S01 E01" (90%+ da lista) + no
  /// máx. 2 passagens completas (marcadores podem empilhar).
  String _stripSeriesVariant(String name) {
    final cached = _stripCache[name];
    if (cached != null) return cached;
    var k = name.replaceAll(_tPrefixRegex, '');
    final fast = _fastSeRegex.firstMatch(k);
    if (fast != null) {
      k = _tidy((fast.group(1) ?? k).replaceAll(_markersRegex, ''));
    } else {
      for (var i = 0; i < 2; i++) {
        final before = k;
        k = _tidy(k.replaceAll(_markersRegex, ''));
        if (k == before) break;
      }
    }
    if (_stripCache.length > 50000) _stripCache.clear();
    _stripCache[name] = k;
    return k;
  }

  String _tidy(String s) {
    var k = s.replaceAll(_spacesRegex, ' ').trim();
    return k.replaceAll(_trailSepRegex, '').trim();
  }

  String _seriesKey(String name) {
    final k = _stripSeriesVariant(name);
    if (k.isEmpty) return name.toLowerCase();
    // Dobra acentos só na chave: "esquadrão" junta com "esquadrao".
    return _foldAccents(k.toLowerCase());
  }

  static String _foldAccents(String s) {
    const accents = 'áàâãéêíóôõúüç';
    const plain = 'aaaaeeiooouuc';
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final idx = accents.indexOf(ch);
      buf.write(idx == -1 ? ch : plain[idx]);
    }
    return buf.toString();
  }

  String _seriesDisplayName(String name) {
    final k = _stripSeriesVariant(name);
    return k.isEmpty ? name : k;
  }

  /// Sufixo de temporada avulso no fim do nome ("Zatch Bell! 9",
  /// "Fairy Tail 7" já sem a tag [LEG]): número solto de 1-2 dígitos.
  /// Ano (1999, 4 dígitos) nunca casa — não junta remakes/sequências por ano.
  static final _seasonSuffixRegex =
      RegExp(r'^(.+?)[\s\-–—:.]+(\d{1,2})\s*$');

  /// "Zatch Bell! 9" -> "Zatch Bell"; sem sufixo de temporada -> null.
  /// Passa por [_tidy] para a chave bater com [_seriesKey].
  String? _stripSeasonSuffix(String base) {
    final m = _seasonSuffixRegex.firstMatch(base);
    if (m == null) return null;
    final pre = _tidy(m.group(1) ?? '');
    return pre.isEmpty ? null : pre;
  }

  /// Temporada a partir do trecho ANTES do marcador de episódio:
  /// "Zatch Bell! 9 EP03" -> prefixo "Zatch Bell! 9 " -> 9.
  int? _seasonFromPrefix(String prefix) {
    final m = _seasonSuffixRegex.firstMatch(prefix.trim());
    if (m == null) return null;
    return int.tryParse(m.group(2) ?? '');
  }

  /// 2ª passada do agrupamento: funde grupos que são temporadas da mesma
  /// série ("Zatch Bell! 1".."Zatch Bell! 9" -> "Zatch Bell").
  /// Só funde quando a base sem número já existe como grupo ou quando há
  /// >=2 temporadas irmãs — assim "Ben 10" sozinho nunca vira "Ben".
  /// Xtream (seriesId) não entra: a API já devolve 1 item por série.
  void _mergeSeasonSplits(Map<String, _SeriesGroup> map) {
    final parentOf = <String, String>{};
    final parentName = <String, String>{};
    for (final entry in map.entries) {
      final g = entry.value;
      if (g.seriesId != null) continue;
      final parent = _stripSeasonSuffix(g.name);
      if (parent == null) continue;
      final pKey = _foldAccents(parent.toLowerCase());
      if (pKey.isEmpty || pKey == entry.key) continue;
      parentOf[entry.key] = pKey;
      parentName.putIfAbsent(pKey, () => parent);
    }
    if (parentOf.isEmpty) return;
    // Resolve a raiz (cadeias tipo "X 1 2" -> "X 1" -> "X" fundem direto em "X").
    String rootOf(String k) {
      var cur = k;
      final seen = <String>{};
      while (parentOf.containsKey(cur) && !seen.contains(cur)) {
        seen.add(cur);
        cur = parentOf[cur]!;
      }
      return cur;
    }

    final byRoot = <String, List<String>>{};
    for (final childKey in parentOf.keys) {
      final root = rootOf(childKey);
      if (root == childKey) continue;
      byRoot.putIfAbsent(root, () => []).add(childKey);
    }
    final remove = <String>[];
    byRoot.forEach((rootKey, childKeys) {
      var target = map[rootKey];
      if (target == null && childKeys.length < 2) return;
      target ??= _SeriesGroup(
        name: parentName[rootKey] ?? rootKey,
        logoUrl: null,
        category: map[childKeys.first]!.category,
        seriesId: null,
        rep: map[childKeys.first]!.rep,
        episodes: [],
      );
      map[rootKey] = target;
      for (final ck in childKeys) {
        final child = map[ck];
        if (child == null || identical(child, target)) continue;
        target.episodes.addAll(child.episodes);
        if ((target.logoUrl == null || target.logoUrl!.isEmpty) &&
            child.logoUrl != null &&
            child.logoUrl!.isNotEmpty) {
          target.logoUrl = child.logoUrl;
        }
        remove.add(ck);
      }
    });
    for (final k in remove) {
      map.remove(k);
    }
  }

  /// Tem número de episódio explícito (S01E01, T01 E01, 1x01, EP01...)?
  /// Usado para renumerar por temporada só os episódios sem número próprio.
  bool _hasExplicitEpNumber(String name) {
    return _seRegex.hasMatch(name) ||
        _tRegex.hasMatch(name) ||
        _xRegex.hasMatch(name) ||
        _epNumRegex.hasMatch(name);
  }

  /// Extrai (temporada, episódio) de nomes tipo "Nome S01 E01".
  /// Também entende "T01 E01", "1x01", avulsos ("EP01", "Cap 3") e o
  /// sufixo de temporada solto ("Zatch Bell! 9 EP03" -> T9 E3;
  /// "Fairy Tail 7" sem marcador -> T7).
  (int, int)? _parseSeasonEpisode(String name, int fallbackEp) {
    var m = _seRegex.firstMatch(name);
    if (m != null) {
      final s = int.tryParse(m.group(1) ?? '') ?? 1;
      final e = int.tryParse(m.group(2) ?? '') ?? fallbackEp;
      return (s, e);
    }
    m = _tRegex.firstMatch(name);
    if (m != null) {
      final s = int.tryParse(m.group(1) ?? '') ?? 1;
      final e = int.tryParse(m.group(2) ?? '') ?? fallbackEp;
      return (s, e);
    }
    m = _xRegex.firstMatch(name);
    if (m != null) {
      final s = int.tryParse(m.group(1) ?? '') ?? 1;
      final e = int.tryParse(m.group(2) ?? '') ?? fallbackEp;
      return (s, e);
    }
    m = _epNumRegex.firstMatch(name);
    if (m != null) {
      final e = int.tryParse(m.group(1) ?? '') ?? fallbackEp;
      final s =
          _seasonFromPrefix(name.substring(0, m.start)) ?? 1;
      return (s, e);
    }
    final s = _seasonFromPrefix(name);
    if (s != null) return (s, fallbackEp);
    return null;
  }

  /// Toque numa série da grade: Xtream busca na API; M3U agrupa os
  /// episódios da lista. Item único sem padrão de episódio toca direto.
  Future<void> _openSeriesGroup(_SeriesGroup g) async {
    if (g.seriesId != null && widget.controller.currentAccount != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
      final episodes =
          await widget.controller.getSeriesEpisodes(g.seriesId!);
      if (mounted) {
        Navigator.of(context).pop();
        if (episodes.isEmpty) {
          _openPlayer(g.episodes, 0);
        } else {
          _showEpisodesSheet(g.rep, episodes);
        }
      }
      return;
    }
    if (g.episodes.length == 1 &&
        _parseSeasonEpisode(g.episodes.first.name, 1) == null) {
      _openPlayer(g.episodes, 0);
      return;
    }
    final eps = <StreamItem>[];
    final autoEp = <int>[];
    for (var i = 0; i < g.episodes.length; i++) {
      final ep = g.episodes[i];
      if (ep.seasonNumber != null) {
        eps.add(ep);
      } else {
        final se = _parseSeasonEpisode(ep.name, i + 1);
        if (se == null) {
          eps.add(ep.copyWith(seasonNumber: 1, episodeNumber: i + 1));
          autoEp.add(eps.length - 1);
        } else {
          eps.add(
              ep.copyWith(seasonNumber: se.$1, episodeNumber: se.$2));
          if (!_hasExplicitEpNumber(ep.name)) {
            autoEp.add(eps.length - 1);
          }
        }
      }
    }
    // Episódios sem número próprio (ex.: 5 itens "Zatch Bell! 9")
    // ganham E1..E5 dentro da sua temporada em vez do índice global
    // do grupo fundido (que mostraria E46..E50).
    if (autoEp.isNotEmpty) {
      final bySeasonIdx = <int, List<int>>{};
      for (final idx in autoEp) {
        bySeasonIdx
            .putIfAbsent(eps[idx].seasonNumber ?? 1, () => [])
            .add(idx);
      }
      for (final idxs in bySeasonIdx.values) {
        idxs.sort((a, b) => (eps[a].episodeNumber ?? 0)
            .compareTo(eps[b].episodeNumber ?? 0));
        for (var n = 0; n < idxs.length; n++) {
          final idx = idxs[n];
          eps[idx] = eps[idx].copyWith(episodeNumber: n + 1);
        }
      }
    }
    _showEpisodesSheet(g.rep, eps);
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
    if (!BackGuard.claim()) return;
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
                  onTap: () => _selectCategory('TODOS'),
                );
              }
              final cat = cats[i - 1];
              return _categoryRow(
                name: cat.name,
                count: cat.count,
                selected: _selectedCategory == cat.name,
                onFocus: (_) => _selectCategory(cat.name),
                onTap: () => _selectCategory(cat.name),
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
                      // 1º clique seleciona (preview); 2º abre o player.
                      onTap: () {
                        if (_selectedIndex == i) {
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
    // Programa atual do canal em destaque (ou categoria como fallback):
    // a faixa identifica o canal mesmo sem logo/arte.
    final nowTitle = ch == null
        ? null
        : _epgService.liveNow(ch.id, _now)?.title;
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
          // Busca (padrão do exemplo)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Pesquisa por canal...',
                hintStyle: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceLight,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style:
                  const TextStyle(color: Colors.white, fontSize: 13),
              onChanged: _onSearchChanged,
            ),
          ),
          // Faixa compacta do canal em destaque (altura fixa ~72px):
          // identifica número + nome + programa atual mesmo sem logo,
          // e nunca estoura a coluna (era um preview 16:9 + ficha que
          // causava BOTTOM OVERFLOWED em telas menores).
          if (ch != null)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  _logoThumb(ch.logoUrl, 52, 36),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            '${(_selectedIndex + 1).toString().padLeft(3, '0')}  ${ch.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                        Text(
                            (nowTitle != null && nowTitle.isNotEmpty)
                                ? nowTitle
                                : ch.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () =>
                        widget.controller.toggleFavorite(ch),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        ch.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color: ch.isFavorite
                            ? AppColors.accentOrange
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                      minimumSize: Size.zero,
                      tapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        _openPlayer(list, _selectedIndex),
                    child: const Text('Assistir'),
                  ),
                ],
              ),
            ),
          // Abas Canais | Favoritos (padrão do exemplo)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                Expanded(
                    child: _liveTab('Canais', !_showOnlyFavorites,
                        () {
                  setState(() {
                    _showOnlyFavorites = false;
                    _selectedIndex = 0;
                  });
                })),
                Container(
                    width: 1,
                    height: 18,
                    color: AppColors.cardBorder),
                Expanded(
                    child: _liveTab('Favoritos', _showOnlyFavorites,
                        () {
                  setState(() {
                    _showOnlyFavorites = true;
                    _selectedIndex = 0;
                  });
                })),
              ],
            ),
          ),
          // Categorias à esquerda + canais à direita
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _liveSideBar(),
                Expanded(
                  child: list.isEmpty
                      ? const Center(
                          child: Text('Nenhum canal encontrado',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              0, 2, 8, 8),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final item = list[i];
                            final selected =
                                i == _selectedIndex;
                            final nowTitle = _epgService
                                .liveNow(item.id, _now)
                                ?.title;
                            return _liveRow(
                              item: item,
                              index: i,
                              selected: selected,
                              subtitle: (nowTitle != null &&
                                      nowTitle.isNotEmpty)
                                  ? nowTitle
                                  : item.category,
                              onTap: () {
                                _selectChannel(i);
                                _openPlayer(list, i);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Aba de texto do guia mobile (Canais | Favoritos).
  Widget _liveTab(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800)),
      ),
    );
  }

  /// Coluna de categorias à esquerda (padrão do exemplo).
  Widget _liveSideBar() {
    Widget catItem(String label, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border(
                left: BorderSide(
                    color: selected
                        ? AppColors.primary
                        : Colors.transparent,
                    width: 3)),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected
                      ? Colors.white
                      : AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: selected
                      ? FontWeight.bold
                      : FontWeight.w500)),
        ),
      );
    }

    return SizedBox(
      width: 112,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 2),
        children: [
          catItem('Todos', _selectedCategory == 'TODOS',
              () => _selectCategory('TODOS')),
          catItem('Favoritos', _showOnlyFavorites, () {
            setState(() {
              _showOnlyFavorites = true;
              _selectedIndex = 0;
            });
          }),
          ..._cats.map((c) => catItem(
              c.name,
              _selectedCategory == c.name &&
                  !_showOnlyFavorites,
              () => _selectCategory(c.name))),
        ],
      ),
    );
  }

  /// Linha do canal: logo + número/nome + programa atual + seta.
  Widget _liveRow({
    required StreamItem item,
    required int index,
    required bool selected,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final num = (index + 1).toString().padLeft(3, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.38),
                  AppColors.primary.withValues(alpha: 0.16),
                ],
              )
            : null,
        color: selected ? null : AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 6, vertical: 6),
          child: Row(
            children: [
              _logoThumb(item.logoUrl, 40, 26),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$num  ${item.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10)),
                  ],
                ),
              ),
              InkWell(
                onTap: () =>
                    widget.controller.toggleFavorite(item),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    item.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 16,
                    color: item.isFavorite
                        ? AppColors.accentOrange
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
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
    final content = _isTv ? _buildVodTv() : _buildVodMobile();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.goBack):
            _onBack,
      },
      child: FocusScope(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(child: content),
        ),
      ),
    );
  }

  /// VOD na TV como nas fotos: busca + categorias à esquerda,
  /// título "All" + grade de pôsteres à direita.
  Widget _buildVodTv() {
    final cats = widget.controller.getCategories(_type);
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
    final total = _type == StreamType.movie
        ? widget.controller.totalMoviesCount
        : widget.controller.totalSeriesCount;
    return Column(
      children: [
        _buildTvTopBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 340,
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 8),
                _categoryRow(
                  name: 'TODOS',
                  count: total,
                  selected: !_showOnlyFavorites &&
                      (_selectedCategory == 'TODOS' ||
                          _selectedCategory == null),
                  autofocus: true,
                  onFocus: (_) => _selectVodCategory('TODOS'),
                  onTap: () => _selectVodCategory('TODOS'),
                ),
                _categoryRow(
                  name: 'FAVORITOS ★',
                  count: widget.controller.totalFavoritesCount,
                  selected: _showOnlyFavorites,
                  onFocus: (_) => _showVodFavorites(),
                  onTap: () => _showVodFavorites(),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: cats.length,
                    itemBuilder: (context, i) {
                      final cat = cats[i];
                      return _categoryRow(
                        name: cat.name,
                        count: cat.count,
                        selected: !_showOnlyFavorites &&
                            _selectedCategory == cat.name,
                        onFocus: (_) =>
                            _selectVodCategory(cat.name),
                        onTap: () =>
                            _selectVodCategory(cat.name),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    _showOnlyFavorites
                        ? 'Favoritos (${items.length})'
                        : 'All',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 28),
                  ),
                ),
                Expanded(child: _vodPosterGrid(items, 4)),
              ],
            ),
          ),
        ],
      ),
        ),
        ),
      ],
    );
  }

  void _selectVodCategory(String name) {
    if (_selectedCategory == name && !_showOnlyFavorites) return;
    setState(() {
      _selectedCategory = name;
      _showOnlyFavorites = false;
    });
  }

  void _showVodFavorites() {
    if (_showOnlyFavorites) return;
    setState(() => _showOnlyFavorites = true);
  }

  /// Grade de pôsteres compartilhada (TV 4 colunas / mobile responsivo).
  /// Em séries, cada cartão é uma série (episódios agrupados por nome).
  Widget _vodPosterGrid(List<StreamItem> items, int crossAxisCount) {
    final isSeries = _type == StreamType.series;
    final groups = isSeries ? _seriesGroups(items) : null;
    final count = isSeries ? groups!.length : items.length;
    if (count == 0) {
      return const Center(
        child: Text('Nenhum conteúdo encontrado',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (isSeries) {
          final g = groups![index];
          final card = StreamItem(
            id: 'group:${g.name}',
            name: g.name,
            streamUrl: g.rep.streamUrl,
            logoUrl: g.logoUrl,
            category: g.episodes.length == 1
                ? g.category
                : '${g.episodes.length} episódios',
            streamType: StreamType.series,
            seriesId: g.seriesId,
            isFavorite: g.rep.isFavorite,
          );
          return StreamCard(
            item: card,
            isVod: true,
            onTap: () => _openSeriesGroup(g),
            onToggleFavorite: () =>
                widget.controller.toggleFavorite(g.rep),
          );
        }
        final item = items[index];
        return StreamCard(
          item: item,
          isVod: true,
          onTap: () => _openPlayer(items, index),
          onToggleFavorite: () =>
              widget.controller.toggleFavorite(item),
        );
      },
    );
  }

  /// Sidebar de categorias p/ celular em retrato (estreita, à esquerda).
  Widget _vodMobileSideBar(List<IptvCategory> cats) {
    Widget sideBtn(String label, bool selected, VoidCallback onTap,
        {Color? highlight}) {
      final active = highlight ?? AppColors.primary;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TvFocusable(
          borderRadius: BorderRadius.circular(8),
          onPressed: onTap,
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? active.withValues(alpha: 0.18)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? active : AppColors.cardBorder),
            ),
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: selected ? active : AppColors.textPrimary,
                    fontSize: 10,
                    fontWeight: selected
                        ? FontWeight.bold
                        : FontWeight.w500)),
          ),
        ),
      );
    }

    return Container(
      width: 100,
      padding: const EdgeInsets.fromLTRB(6, 8, 2, 8),
      child: ListView(
        children: [
          sideBtn(
              'TODOS',
              !_showOnlyFavorites &&
                  (_selectedCategory == 'TODOS' ||
                      _selectedCategory == null), () {
            setState(() {
              _showOnlyFavorites = false;
              _selectedCategory = 'TODOS';
            });
          }),
          sideBtn('FAV ★', _showOnlyFavorites, () {
            setState(
                () => _showOnlyFavorites = !_showOnlyFavorites);
          }, highlight: AppColors.accentOrange),
          ...cats.map((c) => sideBtn(
                  '${c.name} (${c.count})',
                  !_showOnlyFavorites &&
                      _selectedCategory == c.name, () {
                setState(() {
                  _showOnlyFavorites = false;
                  _selectedCategory = c.name;
                });
              })),
        ],
      ),
    );
  }

  /// Lista compacta p/ celular em retrato: thumb pequena + nome.
  /// Séries entram agrupadas (1 linha por série).
  Widget _vodCompactList(List<StreamItem> items) {
    final isSeries = _type == StreamType.series;
    final groups = isSeries ? _seriesGroups(items) : null;
    final count = isSeries ? groups!.length : items.length;
    if (count == 0) {
      return const Center(
        child: Text('Nenhum conteúdo encontrado',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.builder(
      padding:
          const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: count,
      itemBuilder: (context, index) {
        late final StreamItem item;
        late final VoidCallback onTap;
        if (isSeries) {
          final g = groups![index];
          item = StreamItem(
            id: 'group:${g.name}',
            name: g.name,
            streamUrl: g.rep.streamUrl,
            logoUrl: g.logoUrl,
            category: g.episodes.length == 1
                ? g.category
                : '${g.episodes.length} episódios',
            streamType: StreamType.series,
            seriesId: g.seriesId,
            isFavorite: g.rep.isFavorite,
          );
          onTap = () => _openSeriesGroup(g);
        } else {
          item = items[index];
          onTap = () => _openPlayer(items, index);
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 0),
            leading: _vodThumb(item.logoUrl),
            title: Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(item.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 9)),
            trailing: InkWell(
              onTap: () =>
                  widget.controller.toggleFavorite(isSeries
                      ? groups![index].rep
                      : item),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  item.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 16,
                  color: item.isFavorite
                      ? AppColors.accentOrange
                      : AppColors.textSecondary,
                ),
              ),
            ),
            onTap: onTap,
          ),
        );
      },
    );
  }

  /// Thumb pequena (só identificação) da lista compacta.
  Widget _vodThumb(String? url) {
    return Container(
      width: 24,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              memCacheHeight: 144,
              errorWidget: (_, _, _) => const Icon(
                  Icons.movie_rounded,
                  color: Colors.white70,
                  size: 14),
            )
          : const Icon(Icons.movie_rounded,
              color: Colors.white70, size: 14),
    );
  }

  Widget _buildVodMobile() {
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
          // Retrato no celular: categorias à esquerda + lista compacta
          // (logos pequenos, só identificação). Paisagem mantém a grade.
          final isPortrait = MediaQuery.of(context).orientation ==
              Orientation.portrait;
          if (isPortrait &&
              MediaQuery.of(context).size.width < 600) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _vodMobileSideBar(cats),
                Expanded(
                  child: _vodCompactList(items),
                ),
              ],
            );
          }
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
                child: _vodPosterGrid(items, crossAxisCount),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Uma série na grade: 1 item Xtream ou N episódios M3U agrupados.
class _SeriesGroup {
  final String name;
  String? logoUrl;
  final String category;
  final int? seriesId;
  final StreamItem rep;
  final List<StreamItem> episodes;

  _SeriesGroup({
    required this.name,
    required this.logoUrl,
    required this.category,
    required this.seriesId,
    required this.rep,
    required this.episodes,
  });
}
