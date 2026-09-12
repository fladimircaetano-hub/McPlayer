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

  static StreamType _classifyStreamType({
    required String name,
    required String group,
    required String url,
    required RegExp regexSeries,
  }) {
    final lowerName = name.toLowerCase();
    final lowerGroup = group.toLowerCase();
    final lowerUrl = url.toLowerCase();

    // 1. Verificação de Série
    if (regexSeries.hasMatch(name) ||
        regexSeries.hasMatch(url) ||
        lowerName.contains('série') ||
        lowerName.contains('series') ||
        lowerGroup.contains('série') ||
        lowerGroup.contains('series') ||
        lowerGroup.contains('temporada') ||
        lowerGroup.contains('season')) {
      return StreamType.series;
    }

    // 2. Verificação de Filmes / VOD
    if (lowerGroup.contains('filme') ||
        lowerGroup.contains('movie') ||
        lowerGroup.contains('vod') ||
        lowerGroup.contains('cinema') ||
        lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mkv') ||
        lowerUrl.endsWith('.avi')) {
      return StreamType.movie;
    }

    // 2b. Grupos de catálogo VOD (provedores/streamings): em listas grandes
    // grupos como "Netflix", "Prime Vídeo", "DISNEY+" trazem
    // filmes e episódios avulsos sem extensão na URL. Antes caíam como live.
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

    // 3. Padrão: Canais Ao Vivo
    return StreamType.live;
  }
}
