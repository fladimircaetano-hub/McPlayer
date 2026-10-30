import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/parser/m3u_parser.dart';
import '../../core/storage/storage_service.dart';
import '../../core/utils/adult_content.dart';
import '../../core/utils/duplicates.dart';
import '../../data/datasources/xtream_api.dart';
import '../../data/models/iptv_category.dart';
import '../../data/models/stream_item.dart';
import '../../data/models/xtream_account.dart';
import '../../data/services/epg_service.dart';

class IptvController extends ChangeNotifier {
  final StorageService storageService;
  final ApiClient apiClient;
  final XtreamApi xtreamApi;

  IptvController({
    required this.storageService,
    required this.apiClient,
    required this.xtreamApi,
  }) {
    _favorites = storageService.getFavorites();
  }

  bool _isLoading = false;
  String? _errorMessage;
  String _loadingStatus = '';

  List<StreamItem> _allItems = [];
  List<StreamItem> _liveItems = [];
  List<StreamItem> _movieItems = [];
  List<StreamItem> _seriesItems = [];

  Map<StreamType, List<IptvCategory>> _categoriesMap = {
    StreamType.live: [],
    StreamType.movie: [],
    StreamType.series: [],
  };

  Set<String> _favorites = {};
  String _searchQuery = '';
  XtreamAccount? _currentAccount;
  String? _loadedListName;

  /// Varredura de repetidos aguardando confirmação do usuário.
  DuplicateScan? _pendingScan;
  String _pendingSource = '';
  String? _pendingFingerprint;

  /// EPG compartilhado (cache em memória). A tela guia lê daqui.
  final EpgService epgService = EpgService();
  bool get hasEpg => epgService.hasData;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get loadingStatus => _loadingStatus;
  Set<String> get favorites => _favorites;
  String get searchQuery => _searchQuery;
  XtreamAccount? get currentAccount => _currentAccount;
  String? get loadedListName => _loadedListName;

  /// Repetidos encontrados na última carga, aguardando confirmação.
  DuplicateReport? get pendingDuplicates => _pendingScan?.report;
  String? get pendingDuplicatesFingerprint => _pendingFingerprint;

  /// Relatório legível da última limpeza (Configurações/ suporte).
  String? get lastDuplicateReport => storageService.getDedupeReport();

  int get totalLiveCount => _liveItems.length;
  int get totalMoviesCount => _movieItems.length;
  int get totalSeriesCount => _seriesItems.length;
  int get totalFavoritesCount => _favorites.length;

  // ---------- diagnóstico EPG ----------

  /// Canais ao vivo que têm chave de EPG (tvg-id no M3U, epg_channel_id
  /// no Xtream). Se for 0, o provedor não entrega a chave e o guia não
  /// tem como casar canal x programação.
  int get liveChannelsWithEpgId => _liveItems
      .where((c) => (c.epgId ?? '').trim().isNotEmpty)
      .length;

  /// Canais cujo id/epgId existe no XMLTV carregado.
  int get liveChannelsMatchedEpg =>
      _liveItems.where(epgService.hasProgramsFor).length;

  int get epgChannelCount => epgService.channelCount;
  int get epgProgramCount => epgService.programCount;

  /// Recarrega o XMLTV sem refazer login (útil para validar o provedor).
  Future<void> refreshEpg() async {
    final account = _currentAccount;
    if (account != null) {
      await _refreshEpgForXtream(account);
      return;
    }
    final url = storageService.getLastM3uUrl();
    if (url != null && url.isNotEmpty) {
      await _refreshEpgForM3u(url);
    }
  }

  List<IptvCategory> getCategories(StreamType type) => _categoriesMap[type] ?? [];

  /// Filtra itens da aba com base na categoria selecionada, busca e favoritos
  List<StreamItem> getFilteredItems(
    StreamType type, {
    String? selectedCategory,
    bool onlyFavorites = false,
  }) {
    List<StreamItem> base;
    switch (type) {
      case StreamType.live:
        base = _liveItems;
        break;
      case StreamType.movie:
        base = _movieItems;
        break;
      case StreamType.series:
        base = _seriesItems;
        break;
    }

    if (onlyFavorites) {
      base = base.where((item) => _favorites.contains(item.id)).toList();
    } else if (selectedCategory != null &&
        selectedCategory.isNotEmpty &&
        selectedCategory != 'TODOS') {
      base = base.where((item) => item.category == selectedCategory).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      base = base.where((item) {
        return item.name.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query);
      }).toList();
    }

    return base;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Alterna o status de favorito de um canal/filme/série
  Future<void> toggleFavorite(StreamItem item) async {
    await storageService.toggleFavorite(item.id);
    _favorites = storageService.getFavorites();

    item.isFavorite = _favorites.contains(item.id);
    notifyListeners();
  }

  /// Carrega lista M3U por URL remota
  Future<bool> loadFromM3uUrl(String url) async {
    _startLoading('Baixando lista M3U...');
    try {
      final content = await apiClient.fetchM3uContent(url);
      _updateStatus('Processando canais e categorias...');
      final items = await M3uParser.parseM3u(content);

      if (items.isEmpty) {
        throw Exception('Nenhuma stream válida encontrada na lista informada.');
      }

      await _prepareItems(items, 'm3u:$url');
      _loadedListName = url.split('/').last.split('?').first;
      if (_loadedListName == null || _loadedListName!.isEmpty) {
        _loadedListName = 'Lista M3U Online';
      }

      // Diagnóstico temporário: como vêm os grupos das séries no M3U
      // (group-title). Vai pro logcat p/ leitura via adb.
      final seriesGroups = <String, int>{};
      for (final it in items) {
        if (it.streamType == StreamType.series) {
          seriesGroups.update(it.category, (v) => v + 1,
              ifAbsent: () => 1);
        }
      }
      final _ = seriesGroups.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      await storageService.saveLastM3uUrl(url);
      // EPG em segundo plano: nunca bloqueia nem derruba o carregamento.
      unawaited(_refreshEpgForM3u(url));
      _finishLoading();
      return true;
    } catch (e) {
      _setError('Erro ao carregar lista: ${e.toString().replaceAll('Exception:', '')}');
      return false;
    }
  }

  /// Carrega lista M3U de arquivo local
  Future<bool> loadFromLocalFile(String filePath) async {
    _startLoading('Lendo arquivo local...');
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Arquivo não encontrado no dispositivo.');
      }

      final content = await file.readAsString();
      _updateStatus('Processando conteúdo do arquivo...');
      final items = await M3uParser.parseM3u(content);

      if (items.isEmpty) {
        throw Exception('Nenhum canal encontrado dentro do arquivo M3U.');
      }

      await _prepareItems(items, 'file:$filePath');
      _loadedListName = file.uri.pathSegments.last;
      await storageService.saveLastM3uPath(filePath);
      // Arquivo local não tem credenciais: limpa EPG anterior.
      epgService.clear();
      _finishLoading();
      return true;
    } catch (e) {
      _setError('Erro ao ler arquivo: ${e.toString().replaceAll('Exception:', '')}');
      return false;
    }
  }

  /// Login e carregamento via Xtream Codes API.
  /// Live/VOD/Séries carregam em paralelo; falha parcial não derruba o login.
  Future<bool> loginXtream({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    _startLoading('Autenticando no servidor Xtream Codes...');
    try {
      final account = await xtreamApi.authenticate(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );

      _currentAccount = account;
      await storageService.saveXtreamAccount(account);

      _updateStatus('Carregando canais, filmes e séries...');
      final results = await Future.wait(
        [
          xtreamApi.getLiveStreams(account,
              ext: storageService.getStreamFormat()),
          xtreamApi.getVodStreams(account),
          xtreamApi.getSeriesStreams(account),
        ],
        eagerError: false,
      ).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException(
            'Tempo esgotado ao carregar catálogo (90s). Tente novamente.'),
      );

      final live = results[0];
      final movies = results[1];
      final series = results[2];

      final combined = [...live, ...movies, ...series];
      if (combined.isEmpty) {
        throw Exception(
            'Login OK, mas nenhum conteúdo retornado. Verifique a assinatura.');
      }
      await _prepareItems(
        combined,
        'xtream:${account.username}@${account.serverUrl}',
      );
      _loadedListName = 'Xtream: ${account.username}';
      // EPG em segundo plano: nunca bloqueia nem derruba o login.
      unawaited(_refreshEpgForXtream(account));
      _finishLoading();
      return true;
    } on TimeoutException catch (e) {
      _setError(e.message ?? 'Tempo esgotado.');
      return false;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception:', '').trim());
      return false;
    }
  }

  /// Recarrega a lista salva (Xtream > M3U URL > arquivo local).
  /// Usado pelo botão "Recarregar" do menu e das configurações.
  Future<bool> reload() async {
    final account = storageService.getXtreamAccount();
    if (account != null) {
      return loginXtream(
        serverUrl: account.serverUrl,
        username: account.username,
        password: account.password,
      );
    }
    final url = storageService.getLastM3uUrl();
    if (url != null && url.isNotEmpty) {
      return loadFromM3uUrl(url);
    }
    final path = storageService.getLastM3uPath();
    if (path != null && path.isNotEmpty) {
      return loadFromLocalFile(path);
    }
    _setError('Nenhuma lista salva para recarregar.');
    return false;
  }

  /// Busca episódios de uma série específica (Xtream).
  ///
  /// A lista do provedor costuma repetir o mesmo episódio (mesmo
  /// temporada/episódio com stream_id diferente). A deduplicação é feita só
  /// na exibição: a fonte não é alterada e, se precisar, o próximo fetch
  /// traz tudo de novo.
  Future<List<StreamItem>> getSeriesEpisodes(int seriesId) async {
    if (_currentAccount == null) return [];
    try {
      final episodes =
          await xtreamApi.getSeriesEpisodes(_currentAccount!, seriesId);
      final cleaned = dedupeEpisodes(episodes);
      if (cleaned.length != episodes.length) {
        debugPrint('[Dedupe] série $seriesId: '
            '${episodes.length - cleaned.length} episódio(s) repetido(s)');
      }
      return cleaned;
    } catch (_) {
      return [];
    }
  }

  /// Baixa o XMLTV em segundo plano e guarda no cache do [epgService].
  /// Falha de rede ou XML gigante nunca derruba a lista: só loga e segue.
  Future<void> _refreshEpgForM3u(String m3uUrl) async {
    try {
      final data = await epgService.tryFromM3uUrl(m3uUrl);
      epgService.setCache(data);
      _logEpgDiagnostics('M3U');
      notifyListeners();
    } catch (_) {
      // EPG é opcional: guia funciona sem programação.
    }
  }

  Future<void> _refreshEpgForXtream(XtreamAccount account) async {
    try {
      final data = await epgService.loadXtream(
        serverUrl: account.serverUrl,
        username: account.username,
        password: account.password,
      );
      epgService.setCache(data);
      _logEpgDiagnostics('Xtream');
      notifyListeners();
    } catch (_) {
      // EPG é opcional: guia funciona sem programação.
    }
  }

  /// Loga no logcat o funil de casamento do EPG. Serve para diagnosticar
  /// provedores que não enviam epg_channel_id sem expor credenciais.
  void _logEpgDiagnostics(String source) {
    if (!kDebugMode) return;
    debugPrint(
      '[EPG] $source: canais no XMLTV=${epgService.channelCount}, '
      'programas=${epgService.programCount}, '
      'canais com chave de EPG=$liveChannelsWithEpgId/$totalLiveCount, '
      'casados=$liveChannelsMatchedEpg/$totalLiveCount',
    );
  }

  /// Injeta itens direto, sem rede (testes de widget).
  @visibleForTesting
  void debugLoadItems(List<StreamItem> items, {String name = 'Teste'}) {
    _organizeItems(items);
    _loadedListName = name;
    notifyListeners();
  }

  /// Prepara a lista carregada: procura repetidos em filmes/séries e,
  /// conforme a decisão do usuário (ou preferência já salva), aplica a
  /// limpeza. Canais ao vivo passam intactos.
  Future<void> _prepareItems(List<StreamItem> items, String sourceKey) async {
    final scan = scanCatalogDuplicates(items);
    if (!scan.hasDuplicates) {
      _pendingScan = null;
      _pendingSource = '';
      _pendingFingerprint = null;
      _organizeItems(items);
      return;
    }

    // Já autorizado para esta fonte: limpa direto (relatório + backup são
    // regravados a cada carga, então nada se perde).
    if (storageService.getDedupeAuto(sourceKey)) {
      await _commitDedupe(scan, sourceKey);
      return;
    }

    // Usuário já escolheu "manter tudo" para exatamente esta lista.
    if (storageService.getDedupeIgnored(sourceKey) == scan.fingerprint) {
      _pendingScan = null;
      _pendingSource = '';
      _pendingFingerprint = null;
      _organizeItems(items);
      return;
    }

    // Primeira vez: mostra a lista original e deixa a decisão para a tela
    // (relatório + confirmação).
    _pendingScan = scan;
    _pendingSource = sourceKey;
    _pendingFingerprint = scan.fingerprint;
    _organizeItems(items);
    notifyListeners();
  }

  Future<void> _commitDedupe(DuplicateScan scan, String sourceKey) async {
    final report = scan.report;

    // Backup dos itens envolvidos (não a lista inteira: economiza RAM e
    // armazenamento em listas de 100k+).
    final backup = jsonEncode({
      'generatedAt': report.generatedAt.toIso8601String(),
      'source': sourceKey,
      'removed': report.removedCount,
      'entries': [for (final e in report.entries) e.toJson()],
    });
    await storageService.saveDedupeBackup(backup);
    await storageService.saveDedupeReport(report.toText());

    // Favoritos migram da cópia removida para a mantida.
    await storageService.remapFavorites(report.idRemap);
    _favorites = storageService.getFavorites();

    await storageService.setDedupeAuto(sourceKey, true);

    _pendingScan = null;
    _pendingSource = '';
    _pendingFingerprint = null;
    _organizeItems(scan.cleaned);
    notifyListeners();
  }

  /// Confirma a remoção dos repetidos encontrados na carga atual.
  Future<void> applyPendingDuplicates() async {
    final scan = _pendingScan;
    if (scan == null) return;
    await _commitDedupe(scan, _pendingSource);
  }

  /// Mantém a lista como está e não pergunta de novo até ela mudar.
  Future<void> dismissPendingDuplicates() async {
    final fp = _pendingFingerprint;
    if (fp != null && _pendingSource.isNotEmpty) {
      await storageService.setDedupeIgnored(_pendingSource, fp);
    }
    _pendingScan = null;
    _pendingSource = '';
    _pendingFingerprint = null;
    notifyListeners();
  }

  /// Organiza os itens carregados em abas e categorias
  void _organizeItems(List<StreamItem> items) {
    _allItems = items;
    _liveItems = [];
    _movieItems = [];
    _seriesItems = [];

    final Map<String, List<StreamItem>> liveCatMap = {};
    final Map<String, List<StreamItem>> movieCatMap = {};
    final Map<String, List<StreamItem>> seriesCatMap = {};

    for (final item in items) {
      // Categorias adultas viram "Adulto | <categoria original>" já na carga:
      // assim TV ao vivo, Filmes e Séries mostram um pai único "Adulto" com
      // as subcategorias do provedor (XXX, Pornô, +18...), e os filtros por
      // categoria continuam funcionando sem tratamento especial.
      var normalized = item;
      if (isAdultCategoryName(normalized.category)) {
        final grouped = groupedAdultCategory(normalized.category);
        if (grouped != normalized.category) {
          normalized = normalized.copyWith(category: grouped);
        }
      }
      normalized.isFavorite = _favorites.contains(normalized.id);

      switch (normalized.streamType) {
        case StreamType.live:
          _liveItems.add(normalized);
          liveCatMap.putIfAbsent(normalized.category, () => []).add(normalized);
          break;
        case StreamType.movie:
          _movieItems.add(normalized);
          movieCatMap.putIfAbsent(normalized.category, () => []).add(normalized);
          break;
        case StreamType.series:
          _seriesItems.add(normalized);
          seriesCatMap
              .putIfAbsent(normalized.category, () => [])
              .add(normalized);
          break;
      }
    }

    _categoriesMap = {
      StreamType.live: liveCatMap.entries
          .map((e) => IptvCategory(id: e.key, name: e.key, streamType: StreamType.live, items: e.value))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      StreamType.movie: movieCatMap.entries
          .map((e) => IptvCategory(id: e.key, name: e.key, streamType: StreamType.movie, items: e.value))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      StreamType.series: seriesCatMap.entries
          .map((e) => IptvCategory(id: e.key, name: e.key, streamType: StreamType.series, items: e.value))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
    };
  }

  void _startLoading(String status) {
    _isLoading = true;
    _errorMessage = null;
    _loadingStatus = status;
    notifyListeners();
  }

  void _updateStatus(String status) {
    _loadingStatus = status;
    notifyListeners();
  }

  void _finishLoading() {
    _isLoading = false;
    _errorMessage = null;
    _loadingStatus = '';
    notifyListeners();
  }

  void _setError(String message) {
    _isLoading = false;
    _errorMessage = message;
    _loadingStatus = '';
    notifyListeners();
  }

  Future<void> logout() async {
    _allItems.clear();
    _liveItems.clear();
    _movieItems.clear();
    _seriesItems.clear();
    _categoriesMap = {StreamType.live: [], StreamType.movie: [], StreamType.series: []};
    _currentAccount = null;
    _loadedListName = null;
    _searchQuery = '';
    epgService.clear();
    _showOnlyFavoritesReset();
    await storageService.clearSession();
    notifyListeners();
  }

  void _showOnlyFavoritesReset() {
    // Estado de filtro fica na HomeScreen; aqui só garantimos busca limpa.
  }

  /// Força reconstrução das telas (ex.: após remover URL recente).
  void refresh() => notifyListeners();
}
