import '../../../data/models/stream_item.dart';

/// Agrupa itens avulsos (ex.: "Nome S01 E01") por série.
/// Xtream entrega 1 item por série (com seriesId); M3U entrega 1 item
/// por episódio — aqui viram um grupo só na grade.
List<SeriesGroup> seriesGroups(List<StreamItem> items) {
  // Memo: reagrupar 100k episódios a cada rebuild congelava o Fire (ANR).
  final key = '${identityHashCode(items)}|${items.length}';
  final cached = _grCache;
  if (cached != null && _grCacheKey == key) return cached;

  final map = <String, SeriesGroup>{};
  for (final item in items) {
    if (item.seriesId != null) {
      map['xtream:${item.seriesId}'] = SeriesGroup(
        name: item.name,
        logoUrl: item.logoUrl,
        category: item.category,
        seriesId: item.seriesId,
        rep: item,
        episodes: [item],
      );
      continue;
    }
    // Fast path: evita regex pesado para a maioria dos casos
    final baseName = _stripSeriesVariantFast(item.name);
    final sKey = _foldAccents(baseName.toLowerCase());
    final g = map[sKey];
    if (g == null) {
      map[sKey] = SeriesGroup(
        name: _seriesDisplayNameFast(item.name, baseName),
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

/// Grupo de série para exibição na grade.
class SeriesGroup {
  final String name;
  String? logoUrl; // mutable para permitir atualização
  final String category;
  final int? seriesId; // Xtream series_id
  final StreamItem rep; // Item representativo (para abrir player)
  final List<StreamItem> episodes;

  SeriesGroup({
    required this.name,
    this.logoUrl,
    required this.category,
    this.seriesId,
    required this.rep,
    required this.episodes,
  });
}

// ========== Regex e utilitários de parsing ==========

final _seRegex = RegExp(r'[sS](\d{1,2})\s*[eE](\d{1,2})');
final _tPrefixRegex =
    RegExp(r'^[tT]\d+\s*:\s*[eE]\d+\s*[-–—]\s*');
final _tRegex = RegExp(r'\b[tT](\d{1,2})\s+[eE](\d{1,3})\b');
final _xRegex = RegExp(r'\b(\d{1,2})x(\d{1,3})\b');
final _epNumRegex = RegExp(
    r'(?:\b[Ee][Pp]?|epis[oó]dio|cap(?:í|i)tulo|cap\.?|parte|part\.?)\s*\.?\s*(\d{1,3})\b',
    caseSensitive: false);

/// TODOS os marcadores num único padrão global (uma varredura só).
final _markersRegex = RegExp(
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
final _spacesRegex = RegExp(r'\s{2,}');
final _trailSepRegex = RegExp(r'\s*[-–—:|!?]\s*$');

/// Caso dominante ("Nome S01 E01", com ou sem espaço): fatia a base
/// direto com 1 match ancorado em vez de varrer todos os padrões.
final _fastSeRegex =
    RegExp(r'^(.*)\s+[sS]\d{1,2}\s*[eE]\d{1,3}\s*$');

/// Cache nome -> base normalizada: a grade recalcula os grupos a cada
/// rebuild; sem cache o custo se repetia. Teto p/ não pesar a RAM.
final Map<String, String> _stripCache = {};
List<SeriesGroup>? _grCache;
String _grCacheKey = '';

String _tidy(String s) {
  var k = s.replaceAll(_spacesRegex, ' ').trim();
  return k.replaceAll(_trailSepRegex, '').trim();
}

/// Dobra acentos só na chave: "esquadrão" junta com "esquadrao".
String _foldAccents(String s) {
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

/// Sufixo de temporada avulso no fim do nome ("Zatch Bell! 9",
/// "Fairy Tail 7" já sem a tag [LEG]): número solto de 1-2 dígitos.
/// Ano (1999, 4 dígitos) nunca casa — não junta remakes/sequências por ano.
final _seasonSuffixRegex =
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
void _mergeSeasonSplits(Map<String, SeriesGroup> map) {
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
    target ??= SeriesGroup(
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

/// Versão rápida do _stripSeriesVariant usando apenas o regex principal
/// S01E01. Evita as múltiplas passagens do método completo.
String _stripSeriesVariantFast(String name) {
  final cached = _stripCache[name];
  if (cached != null) return cached;
  // Só remove o padrão SXXEXX no final - cobre 90%+ dos casos
  var k = name.replaceAll(_tPrefixRegex, '');
  final fast = _fastSeRegex.firstMatch(k);
  if (fast != null) {
    k = _tidy((fast.group(1) ?? k).replaceAll(_markersRegex, ''));
  } else {
    // Uma passagem apenas
    k = _tidy(k.replaceAll(_markersRegex, ''));
  }
  if (_stripCache.length > 50000) _stripCache.clear();
  _stripCache[name] = k;
  return k;
}

/// Versão rápida do _seriesDisplayName
String _seriesDisplayNameFast(String originalName, String strippedName) {
  return strippedName.isEmpty ? originalName : strippedName;
}

/// Versão rápida do _parseSeasonEpisode - cobre os casos principais
/// SXXEXX, TXX EXX, número de temporada no sufixo, e EP/Cap no final.
/// Pública para uso em outros arquivos (ex.: vod_grid.dart)
(int, int)? parseSeasonEpisodeFast(String name, int fallbackEp) {
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
  // Verifica EP/Cap no final
  m = _epNumRegex.firstMatch(name);
  if (m != null) {
    final e = int.tryParse(m.group(1) ?? '') ?? fallbackEp;
    final s = _seasonFromPrefix(name.substring(0, m.start)) ?? 1;
    return (s, e);
  }
  // Fallback: só verifica se tem número de temporada no sufixo
  final s = _seasonFromPrefix(name);
  if (s != null) return (s, fallbackEp);
  return null;
}

/// Tem número de episódio explícito (S01E01, T01 E01, 1x01, EP01...)?
/// Usado para renumerar por temporada só os episódios sem número próprio.
bool _hasExplicitEpNumber(String name) {
  return _seRegex.hasMatch(name) ||
      _tRegex.hasMatch(name) ||
      _xRegex.hasMatch(name) ||
      _epNumRegex.hasMatch(name);
}

/// Normaliza temporada/episódio antes de abrir o sheet de episódios:
/// infere a temporada pelo nome ("Zatch Bell! 2 EP01" -> T2 E1) e
/// renumera os episódios sem número próprio dentro da própria temporada
/// (senão o grupo fundido mostraria E46..E50). Sem isso, itens M3U sem
/// `seasonNumber` caem todos em "Temporada 1".
List<StreamItem> normalizeSeriesEpisodes(List<StreamItem> episodes) {
  final eps = <StreamItem>[];
  final autoEp = <int>[];
  for (var i = 0; i < episodes.length; i++) {
    final ep = episodes[i];
    if (ep.seasonNumber != null) {
      eps.add(ep);
      continue;
    }
    final se = parseSeasonEpisodeFast(ep.name, i + 1);
    if (se == null) {
      eps.add(ep.copyWith(seasonNumber: 1, episodeNumber: i + 1));
      autoEp.add(eps.length - 1);
    } else {
      eps.add(ep.copyWith(seasonNumber: se.$1, episodeNumber: se.$2));
      if (!_hasExplicitEpNumber(ep.name)) autoEp.add(eps.length - 1);
    }
  }
  if (autoEp.isNotEmpty) {
    final bySeasonIdx = <int, List<int>>{};
    for (final idx in autoEp) {
      bySeasonIdx.putIfAbsent(eps[idx].seasonNumber ?? 1, () => []).add(idx);
    }
    for (final idxs in bySeasonIdx.values) {
      idxs.sort((a, b) =>
          (eps[a].episodeNumber ?? 0).compareTo(eps[b].episodeNumber ?? 0));
      for (var n = 0; n < idxs.length; n++) {
        final idx = idxs[n];
        eps[idx] = eps[idx].copyWith(episodeNumber: n + 1);
      }
    }
  }
  return eps;
}