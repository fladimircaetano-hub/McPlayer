import 'dart:convert';

import '../../data/models/stream_item.dart';

/// Detecção e remoção de itens repetidos em filmes e séries.
///
/// Regras (acordadas com o usuário):
/// - mesmo título normalizado + mesmo ano (quando existir);
/// - ou mesma URL de reprodução;
/// - séries: mesma série + temporada + episódio;
/// - dublado x legendado (x dual) NÃO são duplicados;
/// - remakes/anos diferentes NÃO são duplicados;
/// - canais ao vivo nunca entram na deduplicação.
///
/// A escolha da cópia mantida prioriza link https, capa, nota, ano e
/// container mais compatível (.mp4). Empate: fica a primeira ocorrência.

/// Um grupo de repetidos: 1 mantido + N removidos, com o motivo.
class DuplicateEntry {
  final String key;
  final String kind; // 'filme' | 'serie' | 'episodio'
  final String reason;
  final StreamItem kept;
  final List<StreamItem> removed;

  const DuplicateEntry({
    required this.key,
    required this.kind,
    required this.reason,
    required this.kept,
    required this.removed,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'kind': kind,
        'reason': reason,
        'kept': {'id': kept.id, 'name': kept.name, 'url': kept.streamUrl},
        'removed': [
          for (final r in removed)
            {'id': r.id, 'name': r.name, 'url': r.streamUrl},
        ],
      };

  String toText() {
    final b = StringBuffer('[$kind] $reason\n');
    b.writeln('  manter: ${kept.name}');
    for (final r in removed) {
      b.writeln('  remover: ${r.name}');
    }
    return b.toString();
  }
}

/// Relatório completo de uma varredura.
class DuplicateReport {
  final int scanned;
  final List<DuplicateEntry> entries;
  final DateTime generatedAt;

  DuplicateReport({
    required this.scanned,
    required this.entries,
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now();

  bool get hasDuplicates => entries.isNotEmpty;

  int get removedCount =>
      entries.fold<int>(0, (sum, e) => sum + e.removed.length);

  int get movieEntries =>
      entries.where((e) => e.kind == 'filme').length;

  int get seriesEntries =>
      entries.where((e) => e.kind == 'serie').length;

  int get episodeEntries =>
      entries.where((e) => e.kind == 'episodio').length;

  /// Removidos de filmes (soma dos grupos de filme).
  int get removedMovies => entries
      .where((e) => e.kind == 'filme')
      .fold<int>(0, (s, e) => s + e.removed.length);

  /// Removidos de séries/episódios.
  int get removedEpisodes => entries
      .where((e) => e.kind == 'episodio')
      .fold<int>(0, (s, e) => s + e.removed.length);

  int get removedSeries => entries
      .where((e) => e.kind == 'serie')
      .fold<int>(0, (s, e) => s + e.removed.length);

  /// Mapa id remoto -> id mantido (para migrar favoritos).
  Map<String, String> get idRemap => {
        for (final e in entries)
          for (final r in e.removed) r.id: e.kept.id,
      };

  Map<String, dynamic> toJson() => {
        'scanned': scanned,
        'removed': removedCount,
        'generatedAt': generatedAt.toIso8601String(),
        'entries': [for (final e in entries) e.toJson()],
      };

  String encode() => jsonEncode(toJson());

  String toText() {
    final b = StringBuffer()
      ..writeln('McPlayer — relatório de repetidos')
      ..writeln('Gerado em: ${generatedAt.toLocal()}')
      ..writeln('Itens analisados: $scanned')
      ..writeln('Repetidos encontrados: $removedCount '
          '(filmes: $removedMovies, séries: $removedSeries, '
          'episódios: $removedEpisodes)')
      ..writeln('');
    for (final e in entries) {
      b.write(e.toText());
    }
    return b.toString();
  }
}

/// Resultado da varredura: lista limpa + relatório + impressão digital.
class DuplicateScan {
  final List<StreamItem> cleaned;
  final DuplicateReport report;
  final String fingerprint;

  const DuplicateScan({
    required this.cleaned,
    required this.report,
    required this.fingerprint,
  });

  bool get hasDuplicates => report.hasDuplicates;
}

// ---------------------------------------------------------------------------
// Normalização
// ---------------------------------------------------------------------------

const _accentFrom = 'áàâãäéèêëíìîïóòôõöúùûüçñýÿÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑÝ';
const _accentTo = 'aaaaaeeeeiiiiooooouuuucnyyAAAAAEEEEIIIIOOOOOUUUUCNY';

String foldAccents(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final idx = _accentFrom.indexOf(ch);
    b.write(idx == -1 ? ch : _accentTo[idx]);
  }
  return b.toString();
}

final _brackets = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
final _variantDual = RegExp(r'\bdual\b|\bdual[\s-]?audio\b|\baudio\s*original\b');
final _variantLeg = RegExp(r'\bleg\b|\blegendad[oa]s?\b|\blegenda\b');
final _variantDub = RegExp(r'\bdub\b|\bdublad[oa]s?\b|\bdublagem\b');
final _variantWords = RegExp(
    r'\b(dublado|dublada|dublados|dubladas|legendado|legendada|legendados|legendadas|leg|dub|dual|audio|original|nacional)\b');
final _qualityWords = RegExp(
    r'\b(4k|uhd|fhd|fullhd|full\s*hd|hd|sd|hdcam|cam|1080p|720p|480p|2160p|hevc|x264|x265|h264|h265|bluray|blu-ray|web-?dl|dvdrip|brrip|hdtv|remux|hdr10|hdr)\b');
final _nonAlnum = RegExp(r'[^a-z0-9 ]+');
final _spaces = RegExp(r'\s+');
final _yearRe = RegExp(r'\b(19\d{2}|20\d{2})\b');

/// Variante de áudio: 'dub', 'leg', 'dual' ou '' (indefinida).
///
/// Dublado e legendado são versões diferentes e por isso ficam separadas.
String titleVariant(String raw) {
  final s = foldAccents(raw).toLowerCase();
  if (_variantDual.hasMatch(s)) return 'dual';
  if (_variantLeg.hasMatch(s)) return 'leg';
  if (_variantDub.hasMatch(s)) return 'dub';
  return '';
}

/// Título canônico: sem acento, sem tags entre parênteses/colchetes, sem
/// qualidade, sem pontuação e sem as palavras de variante. Minúsculo.
String normalizeTitle(String raw) {
  var s = foldAccents(raw).toLowerCase();
  s = s.replaceAll(_brackets, ' ');
  s = s.replaceAll(_variantWords, ' ');
  s = s.replaceAll(_qualityWords, ' ');
  s = s.replaceAll(_nonAlnum, ' ');
  s = s.replaceAll(_spaces, ' ').trim();
  return s;
}

/// Ano do item: prioriza [releaseDate], depois procura no nome.
int? extractYear(StreamItem item) {
  final rel = item.releaseDate?.trim();
  if (rel != null && rel.isNotEmpty) {
    final m = _yearRe.firstMatch(rel);
    if (m != null) return int.tryParse(m.group(1)!);
    final asInt = int.tryParse(rel);
    if (asInt != null && asInt >= 1900 && asInt <= 2100) return asInt;
  }
  final m = _yearRe.firstMatch(item.name);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// URL canônica: sem espaços, sem headers `|...` e sem fragmento.
String canonicalUrl(String raw) {
  var url = raw.trim();
  final pipe = url.indexOf('|');
  if (pipe != -1) url = url.substring(0, pipe).trim();
  final hash = url.indexOf('#');
  if (hash != -1) url = url.substring(0, hash);
  return url.toLowerCase();
}

// ---------------------------------------------------------------------------
// Escolha da melhor cópia
// ---------------------------------------------------------------------------

int _score(StreamItem item) {
  var score = 0;
  final url = item.streamUrl.toLowerCase();
  if (url.startsWith('https://')) score += 3;
  if ((item.logoUrl ?? '').isNotEmpty) score += 2;
  if ((item.rating ?? '').isNotEmpty) score += 1;
  if (extractYear(item) != null) score += 1;
  if (url.endsWith('.mp4')) {
    score += 2;
  } else if (url.endsWith('.mkv')) {
    score += 1;
  }
  if (item.streamUrl.contains('|')) score -= 1;
  return score;
}

int _bestIndex(List<StreamItem> items, List<int> indexes) {
  var best = indexes.first;
  var bestScore = _score(items[best]);
  for (final i in indexes.skip(1)) {
    final s = _score(items[i]);
    if (s > bestScore) {
      best = i;
      bestScore = s;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// Union-find simples para agrupar duplicados
// ---------------------------------------------------------------------------

class _Dsu {
  final List<int> _parent;

  _Dsu(int n) : _parent = List<int>.generate(n, (i) => i);

  int find(int x) {
    var root = x;
    while (_parent[root] != root) {
      root = _parent[root];
    }
    var cur = x;
    while (_parent[cur] != cur) {
      final next = _parent[cur];
      _parent[cur] = root;
      cur = next;
    }
    return root;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) _parent[rb] = ra;
  }
}

String _kindOf(StreamType type) {
  switch (type) {
    case StreamType.movie:
      return 'filme';
    case StreamType.series:
      return 'serie';
    case StreamType.live:
      return 'live';
  }
}

String _seriesKey(StreamItem item) {
  if (item.seriesId != null) return 'serie:${item.seriesId}';
  return 'serie:${normalizeTitle(item.name)}|${extractYear(item) ?? ''}';
}

String _titleKey(StreamItem item) {
  if (item.streamType == StreamType.series) return _seriesKey(item);
  return '${normalizeTitle(item.name)}|${titleVariant(item.name)}';
}

bool _yearsCompatible(StreamItem a, StreamItem b) {
  final ya = extractYear(a);
  final yb = extractYear(b);
  if (ya == null || yb == null) return true;
  return ya == yb;
}

/// Impressão digital estável da lista (FNV-1a 64 bits sobre ids e URLs).
/// Não usa [Object.hashCode] porque ele muda entre execuções.
String fingerprintOf(List<StreamItem> items) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  void feed(String s) {
    for (var i = 0; i < s.length; i++) {
      hash ^= s.codeUnitAt(i);
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
  }

  for (final item in items) {
    feed(item.id);
    feed('|');
    feed(canonicalUrl(item.streamUrl));
    feed(';');
  }
  return hash.toRadixString(16);
}

// ---------------------------------------------------------------------------
// Varredura do catálogo (filmes + séries)
// ---------------------------------------------------------------------------

/// Procura repetidos em [items] sem alterar nada.
///
/// Canais ao vivo são ignorados na comparação e permanecem intactos em
/// [DuplicateScan.cleaned].
DuplicateScan scanCatalogDuplicates(List<StreamItem> items) {
  final dsu = _Dsu(items.length);
  final titleGroups = <String, List<int>>{};
  final urlGroups = <String, List<int>>{};

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.streamType == StreamType.live) continue;
    titleGroups.putIfAbsent(_titleKey(item), () => []).add(i);
    final url = canonicalUrl(item.streamUrl);
    if (url.isNotEmpty) {
      urlGroups.putIfAbsent(url, () => []).add(i);
    }
  }

  // Título+ano: remakes (anos diferentes) continuam separados.
  titleGroups.forEach((_, indexes) {
    for (var a = 0; a < indexes.length; a++) {
      for (var b = a + 1; b < indexes.length; b++) {
        if (_yearsCompatible(items[indexes[a]], items[indexes[b]])) {
          dsu.union(indexes[a], indexes[b]);
        }
      }
    }
  });

  // Mesma URL de reprodução: duplicado mesmo com nome diferente.
  urlGroups.forEach((_, indexes) {
    for (var a = 1; a < indexes.length; a++) {
      dsu.union(indexes.first, indexes[a]);
    }
  });

  final byRoot = <int, List<int>>{};
  for (var i = 0; i < items.length; i++) {
    if (items[i].streamType == StreamType.live) continue;
    byRoot.putIfAbsent(dsu.find(i), () => []).add(i);
  }

  final entries = <DuplicateEntry>[];
  final removedIds = <int>{};
  byRoot.forEach((_, indexes) {
    if (indexes.length < 2) return;
    indexes.sort();
    final keptIdx = _bestIndex(items, indexes);
    final kept = items[keptIdx];
    final removed = <StreamItem>[];
    for (final i in indexes) {
      if (i == keptIdx) continue;
      removed.add(items[i]);
      removedIds.add(i);
    }
    final sameUrl = removed.any((r) =>
        canonicalUrl(r.streamUrl) == canonicalUrl(kept.streamUrl));
    final reason = sameUrl ? 'mesma URL de reprodução' : 'mesmo título e ano';
    entries.add(DuplicateEntry(
      key: _titleKey(kept),
      kind: _kindOf(kept.streamType),
      reason: reason,
      kept: kept,
      removed: removed,
    ));
  });

  final cleaned = <StreamItem>[
    for (var i = 0; i < items.length; i++)
      if (!removedIds.contains(i)) items[i],
  ];

  return DuplicateScan(
    cleaned: cleaned,
    report: DuplicateReport(scanned: items.length, entries: entries),
    fingerprint: fingerprintOf(items),
  );
}

/// Remove episódios repetidos de UMA série.
///
/// Chave: temporada+episódio (quando existem) ou título normalizado, e
/// também a URL. Mantém a melhor cópia e a ordem original.
List<StreamItem> dedupeEpisodes(List<StreamItem> episodes) {
  if (episodes.length < 2) return List<StreamItem>.of(episodes);

  String keyOf(StreamItem ep) {
    if (ep.seasonNumber != null && ep.episodeNumber != null) {
      return 'e:${ep.seriesId ?? normalizeTitle(ep.name)}:'
          '${ep.seasonNumber}:${ep.episodeNumber}';
    }
    return 'n:${normalizeTitle(ep.name)}';
  }

  final byKey = <String, List<int>>{};
  final byUrl = <String, List<int>>{};
  for (var i = 0; i < episodes.length; i++) {
    byKey.putIfAbsent(keyOf(episodes[i]), () => []).add(i);
    final url = canonicalUrl(episodes[i].streamUrl);
    if (url.isNotEmpty) byUrl.putIfAbsent(url, () => []).add(i);
  }

  final removed = <int>{};
  void process(Map<String, List<int>> groups) {
    groups.forEach((_, indexes) {
      if (indexes.length < 2) return;
      final kept = _bestIndex(episodes, indexes);
      for (final i in indexes) {
        if (i != kept) removed.add(i);
      }
    });
  }

  process(byKey);
  process(byUrl);

  return <StreamItem>[
    for (var i = 0; i < episodes.length; i++)
      if (!removed.contains(i)) episodes[i],
  ];
}
