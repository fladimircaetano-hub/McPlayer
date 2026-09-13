import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../data/models/stream_item.dart';

class M3uParser {
  /// Executa o parsing em background Isolate usando compute()
  static Future<List<StreamItem>> parseM3u(String content) async {
    return compute(_parseM3uInternal, content);
  }

  static List<StreamItem> _parseM3uInternal(String content) {
    final List<StreamItem> items = [];
    final lines = const LineSplitter().convert(content);

    String? currentTvgId;
    String? currentTvgName;
    String? currentLogo;
    String? currentGroup;
    String? currentName;

    final regexSeries = RegExp(r'[sS]\d{1,2}\s*[eE]\d{1,2}', caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        // Extrair atributos da linha #EXTINF
        currentTvgId = _extractAttribute(line, 'tvg-id');
        currentTvgName = _extractAttribute(line, 'tvg-name');
        currentLogo = _extractAttribute(line, 'tvg-logo');
        currentGroup = _extractAttribute(line, 'group-title');

        // Extrair nome após a última vírgula
        final commaIndex = line.lastIndexOf(',');
        if (commaIndex != -1 && commaIndex < line.length - 1) {
          currentName = line.substring(commaIndex + 1).trim();
        } else {
          currentName = currentTvgName ?? 'Sem Nome';
        }
      } else if (!line.startsWith('#')) {
        // É uma URL de stream
        final streamUrl = line;
        final name = currentName ?? currentTvgName ?? 'Canal ${items.length + 1}';
        final group = (currentGroup != null && currentGroup.isNotEmpty)
            ? currentGroup
            : 'Outros';

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
            logoUrl: (currentLogo != null && currentLogo.isNotEmpty) ? currentLogo : null,
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
      }
    }

    return items;
  }

  static String? _extractAttribute(String line, String attributeName) {
    final pattern = '$attributeName="';
    final startIndex = line.indexOf(pattern);
    if (startIndex == -1) {
      // Tentar sem aspas
      final patternNoQuotes = '$attributeName=';
      final startNoQ = line.indexOf(patternNoQuotes);
      if (startNoQ == -1) return null;
      final valueStart = startNoQ + patternNoQuotes.length;
      final spaceIndex = line.indexOf(' ', valueStart);
      if (spaceIndex == -1) {
        return line.substring(valueStart);
      }
      return line.substring(valueStart, spaceIndex);
    }

    final valueStart = startIndex + pattern.length;
    final endIndex = line.indexOf('"', valueStart);
    if (endIndex == -1) return null;

    return line.substring(valueStart, endIndex);
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
    final regexEpisode = RegExp(
        r'(\bs\d{1,2}\s*e\d{1,2}\b|\bt\d{1,2}\s*:\s*e\d{1,2}\b|\bep\.?\s*\d{1,3}\b|\bcap\.?\s*\d{1,3}\b|\bcapitulo\s+\d{1,3}\b|\bepisodio\s+\d{1,3}\b)',
        caseSensitive: false);
    if (regexSeries.hasMatch(name) ||
        regexSeries.hasMatch(url) ||
        regexEpisode.hasMatch(lowerName)) {
      return StreamType.series;
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
