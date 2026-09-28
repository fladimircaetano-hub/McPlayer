import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../data/models/stream_item.dart';

class M3uParser {
  /// Compilado uma vez: antes era recriado a cada item (233 mil vezes).
  static final RegExp regexEpisode = RegExp(
      r'(\bs\d{1,2}\s*e\d{1,2}\b|\bt\d{1,2}\s*:\s*e\d{1,2}\b|\bep\.?\s*\d{1,3}\b|\bcap\.?\s*\d{1,3}\b|\bcapitulo\s+\d{1,3}\b|\bepisodio\s+\d{1,3}\b)',
      caseSensitive: false);

  static final RegExp _numericStreamUrl = RegExp(r'/\d+/\d+/\d+\s*$');

  /// Grupos que são canais ao vivo (estrutura do provedor). Só vale quando
  /// a URL não tem cara de VOD (/movie/, /series/, .mp4...) nem o nome tem
  /// marcador de episódio — nesses casos as regras 1 e 2 já decidiram.
  static bool _isLiveGroup(String lowerGroup) {
    return lowerGroup.contains('ao vivo') ||
        lowerGroup.contains('canais') ||
        lowerGroup.contains('tv aberta') ||
        lowerGroup.contains('tv fechada') ||
        lowerGroup.contains('24/7') ||
        lowerGroup.contains('24h');
  }
  static final _tvgIdRegex =
      RegExp(r'(?:tvg-id|id)="([^"]*)"', caseSensitive: false);
  static final _tvgNameRegex =
      RegExp(r'(?:tvg-name|name)="([^"]*)"', caseSensitive: false);
  static final _tvgLogoRegex =
      RegExp(r'(?:tvg-logo|logo)="([^"]*)"', caseSensitive: false);
  static final _groupTitleRegex =
      RegExp(r'(?:group-title|group)="([^"]*)"', caseSensitive: false);

  static final _tvgIdUnquoted =
      RegExp(r'(?:tvg-id|id)=([^\s,"]+)', caseSensitive: false);
  static final _tvgNameUnquoted =
      RegExp(r'(?:tvg-name|name)=([^\s,"]+)', caseSensitive: false);
  static final _tvgLogoUnquoted =
      RegExp(r'(?:tvg-logo|logo)=([^\s,"]+)', caseSensitive: false);
  static final _groupTitleUnquoted =
      RegExp(r'(?:group-title|group)=([^\s,"]+)', caseSensitive: false);

  /// Executa o parsing em background Isolate usando compute()
  static Future<List<StreamItem>> parseM3u(String content) async {
    return compute(_parseM3uInternal, content);
  }

  static int _findTitleComma(String line) {
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        return i;
      }
    }
    return -1;
  }

  static List<StreamItem> _parseM3uInternal(String content) {
    final List<StreamItem> items = [];
    final lines = const LineSplitter().convert(content);

    String? currentTvgId;
    String? currentTvgName;
    String? currentLogo;
    String? currentGroup;
    String? currentName;
    // #EXTINF acumulado: alguns provedores quebram a linha no meio
    // (ex.: tvg-logo longo) — a continuação vem na linha seguinte.
    String? pendingExtinf;

    void readExtinf(String line) {
      currentTvgId = _tvgIdRegex.firstMatch(line)?.group(1) ??
          _tvgIdUnquoted.firstMatch(line)?.group(1);
      currentTvgName = _tvgNameRegex.firstMatch(line)?.group(1) ??
          _tvgNameUnquoted.firstMatch(line)?.group(1);
      currentLogo = _tvgLogoRegex.firstMatch(line)?.group(1) ??
          _tvgLogoUnquoted.firstMatch(line)?.group(1);
      final grp = _groupTitleRegex.firstMatch(line)?.group(1) ??
          _groupTitleUnquoted.firstMatch(line)?.group(1);
      if (grp != null && grp.isNotEmpty) {
        currentGroup = grp;
      }

      // Extrair nome após a primeira vírgula fora de aspas
      final commaIndex = _findTitleComma(line);
      if (commaIndex != -1 && commaIndex < line.length - 1) {
        currentName = line.substring(commaIndex + 1).trim();
      } else {
        currentName = currentTvgName ?? 'Sem Nome';
      }
    }

    final regexSeries = RegExp(r'[sS]\d{1,2}\s*[eE]\d{1,2}', caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final upper = line.toUpperCase();
      if (upper.startsWith('#EXTINF')) {
        pendingExtinf = line;
        readExtinf(line);
      } else if (upper.startsWith('#EXTGRP:')) {
        final grp = line.substring(line.indexOf(':') + 1).trim();
        if (grp.isNotEmpty) {
          currentGroup = grp;
        }
      } else if (!line.startsWith('#')) {
        final isUrl = line.startsWith('http://') ||
            line.startsWith('https://') ||
            line.startsWith('rtmp://') ||
            line.startsWith('rtsp://') ||
            line.startsWith('mms://') ||
            line.startsWith('udp://') ||
            line.contains('://') ||
            line.startsWith('/');

        if (!isUrl) {
          // Não é URL (continuação de EXTINF quebrado): acumula,
          // re-extrai e aguarda a URL real na próxima linha.
          if (pendingExtinf != null) {
            pendingExtinf = '$pendingExtinf $line';
            readExtinf(pendingExtinf);
          }
          continue;
        }
        final streamUrl = line;
        final name = currentName ?? currentTvgName ?? 'Canal ${items.length + 1}';
        final logo = currentLogo;
        final grp = currentGroup;
        final group =
            (grp != null && grp.isNotEmpty) ? grp : 'Outros';

        final streamType = _classifyStreamType(
          name: name,
          group: group,
          url: streamUrl,
          regexSeries: regexSeries,
        );

        items.add(
          StreamItem(
            id: currentTvgId ?? 'item_${items.length}_${streamUrl.hashCode}',
            name: name,
            streamUrl: streamUrl,
            logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
            category: group,
            streamType: streamType,
          ),
        );

        // Resetar buffers temporários
        currentTvgId = null;
        currentTvgName = null;
        currentLogo = null;
        currentGroup = null;
        currentName = null;
        pendingExtinf = null;
      }
    }

    return items;
  }

  /// URL sem query/fragment, em minúsculas (para checar extensão real).
  /// Ex.: `.../12345.m3u8?token=abc` vira `.../12345.m3u8`.
  static String _urlPath(String url) {
    var end = url.length;
    final q = url.indexOf('?');
    if (q != -1) end = q;
    final h = url.indexOf('#');
    if (h != -1 && h < end) end = h;
    return url.substring(0, end).toLowerCase();
  }

  /// Classificação pelo FORMATO da lista, não pelo nome da categoria:
  /// 1. path Xtream (/live/, /movie/, /series/) é determinístico;
  /// 2. episódio marcado no nome (S01E01, T1:E2, EP 12...);
  /// 3. extensão de arquivo VOD (.mp4, .mkv...);
  /// 4. transporte ao vivo (.m3u8, .ts...);
  /// 5. só então o nome do grupo desempata (URLs sem formato claro).
  /// Isso evita que canais ao vivo caiam em Filmes/Séries só porque o
  /// grupo se chama "FILME E SERIES" ou o canal se chama "TNT SERIES".
  static StreamType _classifyStreamType({
    required String name,
    required String group,
    required String url,
    required RegExp regexSeries,
  }) {
    final lowerName = name.toLowerCase();
    final lowerGroup = group.toLowerCase();
    final lowerUrl = url.toLowerCase();
    final path = _urlPath(url);

    // 1. Painel Xtream no path da URL (determinístico).
    if (lowerUrl.contains('/live/')) return StreamType.live;
    if (lowerUrl.contains('/movie/')) return StreamType.movie;
    if (lowerUrl.contains('/series/')) return StreamType.series;

    // 2. Episódio marcado no nome ou na URL.
    if (regexSeries.hasMatch(name) ||
        regexSeries.hasMatch(url) ||
        regexEpisode.hasMatch(lowerName)) {
      return StreamType.series;
    }

    // 2b. URL numérica Xtream sem extensão (/user/pass/12345): stream ao
    // vivo (saída mpegts do get.php). VOD desse formato sempre traz
    // /movie|/series/ e extensão — já resolvidos nas regras 1 e 3.
    if (_numericStreamUrl.hasMatch(path)) {
      return StreamType.live;
    }

    // 3. Arquivo de vídeo (VOD).
    if (path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.avi') ||
        path.endsWith('.mov') ||
        path.endsWith('.mpg') ||
        path.endsWith('.mpeg') ||
        path.endsWith('.flv') ||
        path.endsWith('.webm') ||
        path.endsWith('.wmv')) {
      return StreamType.movie;
    }

    // 4. Transporte de transmissão ao vivo.
    if (path.endsWith('.m3u8') ||
        path.endsWith('.m3u') ||
        path.endsWith('.ts') ||
        path.endsWith('.mpd')) {
      return StreamType.live;
    }

    // 4b. Estrutura do provedor: grupo de canais ao vivo com URL sem
    // formato claro (ex.: 24/7 dentro de grupo "SÉRIES 24H"). Só alcança
    // aqui quem não é episódio nem arquivo VOD/live conhecido.
    if (_isLiveGroup(lowerGroup)) {
      return StreamType.live;
    }

    // 5. Nome do grupo como último recurso (URLs sem formato claro).
    if (lowerGroup.contains('série') ||
        lowerGroup.contains('series') ||
        lowerGroup.contains('temporada') ||
        lowerGroup.contains('season')) {
      return StreamType.series;
    }

    if (lowerGroup.contains('filme') ||
        lowerGroup.contains('movie') ||
        lowerGroup.contains('vod') ||
        lowerGroup.contains('cinema')) {
      return StreamType.movie;
    }

    // 5b. Grupos de catálogo VOD (provedores/streamings) sem extensão na URL.
    const vodProviders = [
      'netflix',
      'prime v',
      'prime video',
      'disney',
      'globoplay',
      'apple tv',
      'appletv',
      'paramount',
      'discovery',
      'hbo max',
      'max ',
      'anime',
      'desenho',
      'cartoon',
      'novela',
      'dorama',
      'hulu',
      'star+',
      'telecine play',
      'outras produtoras',
      'outros streamings',
      'legendadas',
    ];
    if (vodProviders.any(lowerGroup.contains)) {
      return StreamType.movie;
    }

    // 6. Padrão: Canais Ao Vivo
    return StreamType.live;
  }
}
