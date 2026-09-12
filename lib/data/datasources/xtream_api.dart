import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/stream_item.dart';
import '../models/xtream_account.dart';

class XtreamApi {
  final Dio _dio;

  XtreamApi([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 25),
                receiveTimeout: const Duration(seconds: 40),
                headers: {
                  'User-Agent': 'IPTVSmarters/1.0.0 (Linux; Android 12)',
                  'Accept': 'application/json, text/plain, */*',
                },
                validateStatus: (status) => status != null && status < 500,
              ),
            );

  String _cleanUrl(String url) {
    var clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  /// Autentica na API Xtream Codes
  Future<XtreamAccount> authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    if (username.trim().isEmpty || password.trim().isEmpty) {
      throw Exception('Usuário e senha são obrigatórios.');
    }
    final base = _cleanUrl(serverUrl);
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme || !baseUri.host.contains('.')) {
      throw Exception('URL do servidor inválida. Ex: http://iptv.exemplo.com:8080');
    }
    final endpoint = '$base/player_api.php';

    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'username': username.trim(),
          'password': password.trim(),
        },
      );

      if (response.statusCode != null && response.statusCode! >= 400) {
        throw Exception('Servidor respondeu HTTP ${response.statusCode}.');
      }

      dynamic data = response.data;
      if (data is String) {
        final trimmed = data.trim();
        if (trimmed.isEmpty) {
          throw Exception('Resposta vazia do servidor.');
        }
        try {
          data = jsonDecode(trimmed);
        } catch (_) {
          throw Exception('Resposta não-JSON do servidor. Confira a URL.');
        }
      }

      if (data is Map<String, dynamic>) {
        final userInfo = data['user_info'];
        if (userInfo is Map<String, dynamic>) {
          final auth = userInfo['auth'];
          final status = userInfo['status']?.toString();
          final authOk = auth == 1 || auth == '1' || status?.toLowerCase() == 'active';
          if (authOk) {
            return XtreamAccount(
              serverUrl: base,
              username: username.trim(),
              password: password.trim(),
              status: status ?? 'Ativo',
              expDate: userInfo['exp_date']?.toString(),
              message: userInfo['message']?.toString(),
            );
          } else {
            final msg = userInfo['message']?.toString();
            throw Exception(msg?.isNotEmpty == true
                ? msg!
                : 'Usuário/senha inválidos ou assinatura expirada.');
          }
        }
      }
      throw Exception('Resposta inválida do servidor Xtream Codes.');
    } on DioException catch (e) {
      throw Exception(_friendlyDio(e));
    }
  }

  String _friendlyDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Tempo esgotado ao falar com o servidor Xtream.';
      case DioExceptionType.connectionError:
        return 'Sem conexão com o servidor Xtream. Confira URL/rede.';
      case DioExceptionType.badResponse:
        return 'Xtream respondeu ${e.response?.statusCode ?? 'com erro'}.';
      case DioExceptionType.cancel:
        return 'Autenticação cancelada.';
      default:
        return 'Falha Xtream: ${e.message ?? 'erro desconhecido'}';
    }
  }

  /// Busca mapa category_id -> category_name. Nunca lança: retorna {} em falha.
  Future<Map<String, String>> _fetchCategoryMap(
    XtreamAccount account,
    String action,
  ) async {
    try {
      final endpoint = '${account.serverUrl}/player_api.php';
      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'username': account.username,
          'password': account.password,
          'action': action,
        },
      );
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      if (data is! List) return {};
      final map = <String, String>{};
      for (final raw in data) {
        if (raw is Map<String, dynamic>) {
          final id = raw['category_id']?.toString();
          final name = raw['category_name']?.toString();
          if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
            map[id] = name;
          }
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Busca todos os canais ao vivo e categorias.
  /// [ext] vem da preferência (m3u8 ou m3u8/ts).
  /// Nunca lança: falha parcial retorna [] para não derrubar o login.
  Future<List<StreamItem>> getLiveStreams(
    XtreamAccount account, {
    String ext = 'm3u8',
  }) async {
    try {
      final endpoint = '${account.serverUrl}/player_api.php';
      final categoryMap =
          await _fetchCategoryMap(account, 'get_live_categories');
      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'username': account.username,
          'password': account.password,
          'action': 'get_live_streams',
        },
      );

      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return [];
        }
      }
      if (data is! List) return [];

    final List<StreamItem> items = [];
    for (final raw in data) {
      if (raw is Map<String, dynamic>) {
        final streamId = raw['stream_id']?.toString() ?? '';
        final name = raw['name']?.toString() ?? 'Canal';
        final logo = raw['stream_icon']?.toString();
        final categoryId = raw['category_id']?.toString();
        final category = raw['category_name']?.toString() ??
            (categoryId != null ? categoryMap[categoryId] : null) ??
            'Geral';
        
        // URL da stream ao vivo HLS (.m3u8) ou TS (.ts)
        final suffix = ext == 'mpegts' ? 'ts' : 'm3u8';
        final streamUrl = '${account.serverUrl}/live/${account.username}/${account.password}/$streamId.$suffix';

        items.add(
          StreamItem(
            id: 'xtream_live_$streamId',
            name: name,
            streamUrl: streamUrl,
            logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
            category: category,
            streamType: StreamType.live,
            rating: raw['rating']?.toString(),
          ),
        );
      }
    }
    return items;
    } catch (_) {
      return [];
    }
  }

  /// Busca filmes VOD. Nunca lança: falha parcial retorna [].
  Future<List<StreamItem>> getVodStreams(XtreamAccount account) async {
    try {
      final endpoint = '${account.serverUrl}/player_api.php';
      final categoryMap =
          await _fetchCategoryMap(account, 'get_vod_categories');
      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'username': account.username,
          'password': account.password,
          'action': 'get_vod_streams',
        },
      );

      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return [];
        }
      }
      if (data is! List) return [];

    final List<StreamItem> items = [];
    for (final raw in data) {
      if (raw is Map<String, dynamic>) {
        final streamId = raw['stream_id']?.toString() ?? '';
        final name = raw['name']?.toString() ?? 'Filme';
        final logo = raw['stream_icon']?.toString();
        final categoryId = raw['category_id']?.toString();
        final category = raw['category_name']?.toString() ??
            (categoryId != null ? categoryMap[categoryId] : null) ??
            'Filmes';
        final ext = raw['container_extension']?.toString() ?? 'mp4';

        final streamUrl = '${account.serverUrl}/movie/${account.username}/${account.password}/$streamId.$ext';

        items.add(
          StreamItem(
            id: 'xtream_vod_$streamId',
            name: name,
            streamUrl: streamUrl,
            logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
            category: category,
            streamType: StreamType.movie,
            rating: raw['rating']?.toString(),
            releaseDate: raw['year']?.toString(),
          ),
        );
      }
    }
    return items;
    } catch (_) {
      return [];
    }
  }

  /// Busca Séries. Nunca lança: falha parcial retorna [].
  Future<List<StreamItem>> getSeriesStreams(XtreamAccount account) async {
    try {
      final endpoint = '${account.serverUrl}/player_api.php';
      final categoryMap =
          await _fetchCategoryMap(account, 'get_series_categories');
      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'username': account.username,
          'password': account.password,
          'action': 'get_series',
        },
      );

      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return [];
        }
      }
      if (data is! List) return [];

    final List<StreamItem> items = [];
    for (final raw in data) {
      if (raw is Map<String, dynamic>) {
        final seriesId = raw['series_id'];
        final name = raw['name']?.toString() ?? 'Série';
        final logo = raw['cover']?.toString();
        final categoryId = raw['category_id']?.toString();
        final category = raw['category_name']?.toString() ??
            (categoryId != null ? categoryMap[categoryId] : null) ??
            'Séries';

        items.add(
          StreamItem(
            id: 'xtream_series_$seriesId',
            name: name,
            streamUrl: '${account.serverUrl}/series/${account.username}/${account.password}/$seriesId.mp4',
            logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
            category: category,
            streamType: StreamType.series,
            rating: raw['rating']?.toString(),
            releaseDate: raw['releaseDate']?.toString(),
            seriesId: seriesId is int ? seriesId : int.tryParse(seriesId.toString()),
          ),
        );
      }
    }
    return items;
    } catch (_) {
      return [];
    }
  }

  /// Busca episódios de uma série específica. Nunca lança: retorna [] em falha.
  Future<List<StreamItem>> getSeriesEpisodes(XtreamAccount account, int seriesId) async {
    try {
      final endpoint = '${account.serverUrl}/player_api.php';
      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'username': account.username,
          'password': account.password,
          'action': 'get_series_info',
          'series_id': seriesId,
        },
      );

      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return [];
        }
      }
      if (data is! Map<String, dynamic>) return [];

    final episodesMap = data['episodes'] as Map<String, dynamic>?;
    if (episodesMap == null) return [];

    final List<StreamItem> episodeItems = [];
    episodesMap.forEach((seasonStr, epList) {
      final seasonNum = int.tryParse(seasonStr) ?? 1;
      if (epList is List) {
        for (final ep in epList) {
          if (ep is Map<String, dynamic>) {
            final epId = ep['id']?.toString() ?? '';
            final title = ep['title']?.toString() ?? 'Episódio';
            final epNum = int.tryParse(ep['episode_num']?.toString() ?? '1') ?? 1;
            final ext = ep['container_extension']?.toString() ?? 'mp4';
            final streamUrl = '${account.serverUrl}/series/${account.username}/${account.password}/$epId.$ext';

            episodeItems.add(
              StreamItem(
                id: 'xtream_ep_$epId',
                name: 'T$seasonNum:E$epNum - $title',
                streamUrl: streamUrl,
                logoUrl: ep['info']?['movie_image']?.toString(),
                category: 'Temporada $seasonNum',
                streamType: StreamType.series,
                seriesId: seriesId,
                seasonNumber: seasonNum,
                episodeNumber: epNum,
              ),
            );
          }
        }
      }
      });

      return episodeItems;
    } catch (_) {
      return [];
    }
  }
}
