import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/parser/m3u_parser.dart';
import '../../core/storage/storage_service.dart';
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

  int get totalLiveCount => _liveItems.length;
  int get totalMoviesCount => _movieItems.length;
  int get totalSeriesCount => _seriesItems.length;
  int get totalFavoritesCount => _favorites.length;

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

      _organizeItems(items);
      _loadedListName = url.split('/').last.split('?').first;
      if (_loadedListName == null || _loadedListName!.isEmpty) {
        _loadedListName = 'Lista M3U Online';
      }

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

      _organizeItems(items);
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
      _organizeItems(combined);
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

  /// Busca episódios de uma série específica (Xtream)
  Future<List<StreamItem>> getSeriesEpisodes(int seriesId) async {
    if (_currentAccount == null) return [];
    try {
      return await xtreamApi.getSeriesEpisodes(_currentAccount!, seriesId);
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
      notifyListeners();
    } catch (_) {
      // EPG é opcional: guia funciona sem programação.
    }
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
      item.isFavorite = _favorites.contains(item.id);

      switch (item.streamType) {
        case StreamType.live:
          _liveItems.add(item);
          liveCatMap.putIfAbsent(item.category, () => []).add(item);
          break;
        case StreamType.movie:
          _movieItems.add(item);
          movieCatMap.putIfAbsent(item.category, () => []).add(item);
          break;
        case StreamType.series:
          _seriesItems.add(item);
          seriesCatMap.putIfAbsent(item.category, () => []).add(item);
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
}
