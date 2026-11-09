import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/stream_item.dart';

/// Cache em disco do catálogo já interpretado (M3U ou Xtream).
///
/// O objetivo é abrir o app sem baixar/parsear a lista inteira de novo:
/// a abertura lê este arquivo (em isolate) e o provedor só é consultado em
/// segundo plano para saber se a lista mudou.
class CatalogCacheMeta {
  final String sourceKey;
  final String kind;
  final String listName;
  final DateTime savedAt;
  final int itemCount;

  /// ETag / Last-Modified do arquivo remoto no momento do download.
  final String? etag;
  final String? lastModified;
  final int? contentLength;

  /// Impressão digital do conteúdo (itens), usada para detectar que o
  /// provedor baixou de novo mas o catálogo é o mesmo.
  final String? contentHash;

  const CatalogCacheMeta({
    required this.sourceKey,
    required this.kind,
    required this.listName,
    required this.savedAt,
    required this.itemCount,
    this.etag,
    this.lastModified,
    this.contentLength,
    this.contentHash,
  });

  CatalogCacheMeta copyWith({
    DateTime? savedAt,
    int? itemCount,
    String? etag,
    String? lastModified,
    int? contentLength,
    String? contentHash,
  }) {
    return CatalogCacheMeta(
      sourceKey: sourceKey,
      kind: kind,
      listName: listName,
      savedAt: savedAt ?? this.savedAt,
      itemCount: itemCount ?? this.itemCount,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      contentLength: contentLength ?? this.contentLength,
      contentHash: contentHash ?? this.contentHash,
    );
  }

  Map<String, dynamic> toJson() => {
    'v': CatalogCache.formatVersion,
    'sourceKey': sourceKey,
    'kind': kind,
    'listName': listName,
    'savedAt': savedAt.toIso8601String(),
    'itemCount': itemCount,
    'etag': etag,
    'lastModified': lastModified,
    'contentLength': contentLength,
    'contentHash': contentHash,
  };

  static CatalogCacheMeta? fromJson(Map<String, dynamic> json) {
    if (json['v'] != CatalogCache.formatVersion) return null;
    final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
    final sourceKey = json['sourceKey'] as String? ?? '';
    if (savedAt == null || sourceKey.isEmpty) return null;
    return CatalogCacheMeta(
      sourceKey: sourceKey,
      kind: json['kind'] as String? ?? '',
      listName: json['listName'] as String? ?? '',
      savedAt: savedAt,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
      contentLength: (json['contentLength'] as num?)?.toInt(),
      contentHash: json['contentHash'] as String?,
    );
  }
}

class CatalogCacheData {
  final CatalogCacheMeta meta;
  final List<StreamItem> items;

  const CatalogCacheData({required this.meta, required this.items});
}

/// Decisão da revalidação em segundo plano na abertura do app.
enum CatalogRefreshDecision {
  /// Recente o bastante: nem consulta o provedor.
  keep,

  /// Consulta leve (HEAD) para comparar ETag/Last-Modified.
  check,

  /// Baixa de novo (sem validadores e TTL vencido).
  refresh,
}

/// Intervalo mínimo entre checagens da mesma lista (evita HEAD a cada
/// reabertura do app).
const Duration catalogRevalidateMinAge = Duration(minutes: 20);

/// TTL de lista M3U remota sem ETag nem Last-Modified.
const Duration catalogM3uTtl = Duration(hours: 24);

/// TTL do catálogo Xtream (a API não expõe validadores de arquivo).
const Duration catalogXtreamTtl = Duration(hours: 12);

CatalogRefreshDecision decideM3uRefresh(
  CatalogCacheMeta meta,
  DateTime now, {
  Duration minAge = catalogRevalidateMinAge,
  Duration ttl = catalogM3uTtl,
}) {
  final age = now.difference(meta.savedAt);
  if (age < minAge) return CatalogRefreshDecision.keep;
  final hasValidators =
      (meta.etag ?? '').isNotEmpty || (meta.lastModified ?? '').isNotEmpty;
  if (hasValidators) return CatalogRefreshDecision.check;
  return age >= ttl
      ? CatalogRefreshDecision.refresh
      : CatalogRefreshDecision.keep;
}

/// true quando o provedor mudou o arquivo desde o download salvo.
/// Sem par comparável (um dos lados nulo) preserva o cache.
bool catalogRemoteChanged({
  String? cachedEtag,
  String? cachedLastModified,
  String? etag,
  String? lastModified,
}) {
  if ((cachedEtag ?? '').isNotEmpty && (etag ?? '').isNotEmpty) {
    return cachedEtag != etag;
  }
  if ((cachedLastModified ?? '').isNotEmpty &&
      (lastModified ?? '').isNotEmpty) {
    return cachedLastModified != lastModified;
  }
  return false;
}

class CatalogCache {
  CatalogCache({this.baseDir, this.useIsolate = true});

  /// Versão do formato do arquivo. Mudou = cache antigo é ignorado.
  static const int formatVersion = 1;
  static const String _header = 'MCPLAYER-CATALOG\t1';
  static const int _maxFiles = 4;

  final Directory? baseDir;
  final bool useIsolate;
  final Map<String, Completer<void>> _locks = {};

  @visibleForTesting
  String fileNameFor(String sourceKey) => 'catalog_${_fnv1a(sourceKey)}.cache';

  Future<Directory> _dir() async {
    final base = baseDir;
    if (base != null) return base;
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}catalog');
  }

  Future<File> _fileFor(String sourceKey) async {
    final dir = await _dir();
    return File(
      '${dir.path}${Platform.pathSeparator}${fileNameFor(sourceKey)}',
    );
  }

  Future<CatalogCacheData?> read(String sourceKey) async {
    final file = await _fileFor(sourceKey);
    if (!await file.exists()) return null;
    final path = file.path;
    final data = useIsolate
        ? await compute(_readCatalogFile, path)
        : _readCatalogFile(path);
    if (data == null) return null;
    if (data.meta.sourceKey != sourceKey) return null;
    return data;
  }

  Future<void> write({
    required CatalogCacheMeta meta,
    required List<StreamItem> items,
  }) async {
    // Serializa gravações da mesma fonte (carga normal x atualização em
    // segundo plano podem terminar quase juntas).
    while (_locks[meta.sourceKey] != null) {
      await _locks[meta.sourceKey]!.future;
    }
    final lock = Completer<void>();
    _locks[meta.sourceKey] = lock;
    try {
      await _writeFile(meta, items);
    } finally {
      _locks.remove(meta.sourceKey);
      lock.complete();
    }
  }

  Future<void> _writeFile(CatalogCacheMeta meta, List<StreamItem> items) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    final file = await _fileFor(meta.sourceKey);
    final tmp = File('${file.path}.tmp');

    final fullMeta = meta.copyWith(itemCount: items.length);
    final sink = tmp.openWrite();
    try {
      sink.writeln(_header);
      sink.writeln(jsonEncode(fullMeta.toJson()));
      sink.writeln(items.length);
      final buffer = StringBuffer();
      for (var i = 0; i < items.length; i++) {
        buffer.writeln(_encodeItem(items[i]));
        if (buffer.length >= 1 << 20) {
          sink.write(buffer.toString());
          buffer.clear();
          // Devolve o controle para a UI enquanto uma lista de 100k+ itens
          // é convertida em texto.
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (buffer.isNotEmpty) sink.write(buffer.toString());
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // Rename sobrescreve no Android; no Windows pode falhar.
      }
    }
    await tmp.rename(file.path);
    await _pruneOld(dir);
  }

  Future<void> _pruneOld(Directory dir) async {
    try {
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.cache')) {
          files.add(entity);
        }
      }
      if (files.length <= _maxFiles) return;
      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      for (final old in files.skip(_maxFiles)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    } catch (_) {
      // Limpeza é opcional: nunca derruba a carga.
    }
  }
}

/// Impressão digital barata (FNV-1a 64) do catálogo: id + url + nome.
String catalogFingerprint(List<StreamItem> items) {
  var hash = 0xcbf29ce484222325;
  for (final item in items) {
    for (final unit in item.id.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    hash ^= 0x09;
    for (final unit in item.streamUrl.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    hash ^= 0x09;
    for (final unit in item.name.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    hash ^= 0x0A;
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

String _fnv1a(String value) {
  var hash = 0xcbf29ce484222325;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash *= 0x100000001b3;
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

String _encodeItem(StreamItem item) {
  final type = switch (item.streamType) {
    StreamType.live => 'L',
    StreamType.movie => 'M',
    StreamType.series => 'S',
  };
  return [
    type,
    _cleanField(item.id),
    _cleanField(item.name),
    _cleanField(item.streamUrl),
    _cleanField(item.logoUrl ?? ''),
    _cleanField(item.category),
    _cleanField(item.epgId ?? ''),
    _cleanField(item.rating ?? ''),
    _cleanField(item.releaseDate ?? ''),
    item.seriesId?.toString() ?? '',
    item.seasonNumber?.toString() ?? '',
    item.episodeNumber?.toString() ?? '',
  ].join('\t');
}

String _cleanField(String value) {
  if (!value.contains('\t') && !value.contains('\n') && !value.contains('\r')) {
    return value;
  }
  return value.replaceAll('\t', ' ').replaceAll('\n', ' ').replaceAll('\r', '');
}

CatalogCacheData? _readCatalogFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final content = file.readAsStringSync();
    final headerEnd = content.indexOf('\n');
    if (headerEnd <= 0) return null;
    if (content.substring(0, headerEnd) != CatalogCache._header) return null;

    final metaEnd = content.indexOf('\n', headerEnd + 1);
    if (metaEnd < 0) return null;
    final metaJson = jsonDecode(content.substring(headerEnd + 1, metaEnd));
    if (metaJson is! Map<String, dynamic>) return null;
    final meta = CatalogCacheMeta.fromJson(metaJson);
    if (meta == null) return null;

    final countEnd = content.indexOf('\n', metaEnd + 1);
    if (countEnd < 0) return null;

    final items = <StreamItem>[];
    var start = countEnd + 1;
    while (start < content.length) {
      var end = content.indexOf('\n', start);
      if (end < 0) end = content.length;
      if (end > start) {
        final item = _decodeItem(content.substring(start, end));
        if (item != null) items.add(item);
      }
      start = end + 1;
    }

    // Arquivo truncado/corrompido: melhor baixar de novo.
    if (items.length != meta.itemCount) return null;
    return CatalogCacheData(meta: meta, items: items);
  } catch (_) {
    return null;
  }
}

StreamItem? _decodeItem(String line) {
  final parts = line.split('\t');
  if (parts.length < 12) return null;
  final type = switch (parts[0]) {
    'L' => StreamType.live,
    'M' => StreamType.movie,
    'S' => StreamType.series,
    _ => null,
  };
  if (type == null) return null;
  return StreamItem(
    id: parts[1],
    name: parts[2],
    streamUrl: parts[3],
    logoUrl: parts[4].isEmpty ? null : parts[4],
    category: parts[5],
    streamType: type,
    epgId: parts[6].isEmpty ? null : parts[6],
    rating: parts[7].isEmpty ? null : parts[7],
    releaseDate: parts[8].isEmpty ? null : parts[8],
    seriesId: int.tryParse(parts[9]),
    seasonNumber: int.tryParse(parts[10]),
    episodeNumber: int.tryParse(parts[11]),
  );
}
