import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/network/api_client.dart';
import 'package:mcplayer/core/storage/catalog_cache.dart';
import 'package:mcplayer/core/storage/storage_service.dart';
import 'package:mcplayer/data/datasources/xtream_api.dart';
import 'package:mcplayer/data/models/stream_item.dart';
import 'package:mcplayer/presentation/controllers/iptv_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

StreamItem _item(
  String id, {
  StreamType type = StreamType.movie,
  String? name,
  String? url,
  String? logo,
  String? category,
  String? epgId,
  String? rating,
  String? release,
  int? seriesId,
  int? season,
  int? episode,
}) {
  return StreamItem(
    id: id,
    name: name ?? 'Item $id',
    streamUrl: url ?? 'http://exemplo.test/play/$id',
    logoUrl: logo,
    category: category ?? 'Filmes',
    streamType: type,
    epgId: epgId,
    rating: rating,
    releaseDate: release,
    seriesId: seriesId,
    seasonNumber: season,
    episodeNumber: episode,
  );
}

CatalogCacheMeta _meta(String sourceKey, {String? hash, DateTime? savedAt}) {
  return CatalogCacheMeta(
    sourceKey: sourceKey,
    kind: 'm3u',
    listName: 'lista.m3u',
    savedAt: savedAt ?? DateTime.now(),
    itemCount: 3,
    etag: '"abc"',
    lastModified: 'Wed, 29 Oct 2026 10:00:00 GMT',
    contentHash: hash,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CatalogCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mcplayer_cache_test');
    cache = CatalogCache(baseDir: tempDir, useIsolate: false);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CatalogCache', () {
    test('grava e lê todos os campos de todos os tipos', () async {
      final items = [
        _item(
          '1',
          name: 'Canal Um',
          type: StreamType.live,
          url: 'http://exemplo.test/play/tok/ts',
          logo: 'http://exemplo.test/logo.png',
          category: 'Notícias',
          epgId: 'canal1',
        ),
        _item(
          '2',
          type: StreamType.movie,
          rating: '7.5',
          release: '2024-01-01',
        ),
        _item(
          '3',
          type: StreamType.series,
          seriesId: 99,
          season: 2,
          episode: 7,
        ),
      ];

      await cache.write(
        meta: _meta('m3u:http://exemplo.test/lista.m3u'),
        items: items,
      );
      final data = await cache.read('m3u:http://exemplo.test/lista.m3u');

      expect(data, isNotNull);
      expect(data!.meta.sourceKey, 'm3u:http://exemplo.test/lista.m3u');
      expect(data.meta.itemCount, 3);
      expect(data.meta.etag, '"abc"');
      expect(data.items, hasLength(3));

      final live = data.items[0];
      expect(live.streamType, StreamType.live);
      expect(live.logoUrl, 'http://exemplo.test/logo.png');
      expect(live.epgId, 'canal1');
      expect(data.items[1].rating, '7.5');
      expect(data.items[1].releaseDate, '2024-01-01');
      expect(data.items[2].seriesId, 99);
      expect(data.items[2].seasonNumber, 2);
      expect(data.items[2].episodeNumber, 7);
    });

    test('troca de fonte não reaproveita cache de outra lista', () async {
      await cache.write(
        meta: _meta('m3u:http://exemplo.test/a.m3u'),
        items: [_item('1')],
      );
      expect(await cache.read('m3u:http://exemplo.test/b.m3u'), isNull);
    });

    test('arquivo corrompido é ignorado', () async {
      const source = 'm3u:http://exemplo.test/quebrada.m3u';
      final file = File('${tempDir.path}/${cache.fileNameFor(source)}');
      await file.writeAsString('lixo\nsem cabecalho\n');
      expect(await cache.read(source), isNull);
    });

    test('arquivo truncado (menos itens que o cabeçalho) é ignorado', () async {
      const source = 'm3u:http://exemplo.test/truncada.m3u';
      await cache.write(meta: _meta(source), items: [_item('1'), _item('2')]);
      final file = File('${tempDir.path}/${cache.fileNameFor(source)}');
      final lines = await file.readAsLines();
      await file.writeAsString('${lines.take(lines.length - 1).join('\n')}\n');
      expect(await cache.read(source), isNull);
    });

    test('tabs e quebras de linha no nome não quebram o formato', () async {
      const source = 'm3u:http://exemplo.test/nome.m3u';
      await cache.write(
        meta: _meta(source),
        items: [_item('1', name: 'Nome\tcom\ttab\ne quebra')],
      );
      final data = await cache.read(source);
      expect(data, isNotNull);
      expect(data!.items.single.name, 'Nome com tab e quebra');
    });

    test('mantém no máximo 4 arquivos de cache', () async {
      for (var i = 0; i < 7; i++) {
        await cache.write(
          meta: _meta('m3u:http://exemplo.test/$i.m3u'),
          items: [_item('$i')],
        );
      }
      final files = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.cache'))
          .toList();
      expect(files.length, lessThanOrEqualTo(4));
    });
  });

  group('impressão digital do catálogo', () {
    test('muda quando um item muda e é estável caso contrário', () {
      final a = [_item('1'), _item('2')];
      final b = [_item('1'), _item('2')];
      expect(catalogFingerprint(a), catalogFingerprint(b));
      expect(
        catalogFingerprint(a),
        isNot(catalogFingerprint([_item('1'), _item('3')])),
      );
      expect(
        catalogFingerprint(a),
        isNot(catalogFingerprint([_item('1', name: 'Outro nome'), _item('2')])),
      );
    });
  });

  group('decisão de revalidação', () {
    final now = DateTime(2026, 10, 30, 12);

    test('cache recente não consulta o provedor', () {
      final meta = _meta(
        'm3u:x',
        savedAt: now.subtract(const Duration(minutes: 5)),
      );
      expect(decideM3uRefresh(meta, now), CatalogRefreshDecision.keep);
    });

    test('com ETag, checa com HEAD depois da idade mínima', () {
      final meta = _meta(
        'm3u:x',
        savedAt: now.subtract(const Duration(hours: 2)),
      );
      expect(decideM3uRefresh(meta, now), CatalogRefreshDecision.check);
    });

    test('sem ETag, só baixa de novo quando o TTL vence', () {
      final meta = CatalogCacheMeta(
        sourceKey: 'm3u:x',
        kind: 'm3u',
        listName: 'x',
        savedAt: now.subtract(const Duration(hours: 2)),
        itemCount: 1,
      );
      expect(decideM3uRefresh(meta, now), CatalogRefreshDecision.keep);
      final old = CatalogCacheMeta(
        sourceKey: 'm3u:x',
        kind: 'm3u',
        listName: 'x',
        savedAt: now.subtract(const Duration(hours: 30)),
        itemCount: 1,
      );
      expect(decideM3uRefresh(old, now), CatalogRefreshDecision.refresh);
    });

    test('compara ETag/Last-Modified quando disponíveis', () {
      expect(
        catalogRemoteChanged(
          cachedEtag: '"a"',
          etag: '"a"',
          cachedLastModified: 'x',
          lastModified: 'y',
        ),
        isFalse,
      );
      expect(catalogRemoteChanged(cachedEtag: '"a"', etag: '"b"'), isTrue);
      expect(
        catalogRemoteChanged(
          cachedEtag: '"a"',
          cachedLastModified: 'x',
          lastModified: 'y',
        ),
        isTrue,
      );
      expect(catalogRemoteChanged(cachedEtag: '"a"'), isFalse);
    });
  });

  group('abertura pelo cache', () {
    test('loadFromM3uUrl usa o cache sem tocar na rede', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      const source = 'm3u:http://exemplo.test/cache.m3u';
      await cache.write(
        meta: CatalogCacheMeta(
          sourceKey: source,
          kind: 'm3u',
          listName: 'cache.m3u',
          savedAt: DateTime.now(),
          itemCount: 3,
        ),
        items: [
          _item('1', type: StreamType.live, category: 'Notícias'),
          _item('2', type: StreamType.movie, category: 'Filmes'),
          _item('3', type: StreamType.series, category: 'Séries'),
        ],
      );

      final apiClient = ApiClient();
      final controller = IptvController(
        storageService: storage,
        apiClient: apiClient,
        xtreamApi: XtreamApi(),
        catalogCache: cache,
      )..debugDisableAutoRevalidate = true;

      final ok = await controller.loadFromM3uUrl(
        'http://exemplo.test/cache.m3u',
        allowCache: true,
      );

      expect(ok, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.loadedListName, 'cache.m3u');
      expect(controller.totalLiveCount, 1);
      expect(controller.totalMoviesCount, 1);
      expect(controller.totalSeriesCount, 1);
      expect(storage.getLastM3uUrl(), 'http://exemplo.test/cache.m3u');
    });

    test('Xtream acha o cache mesmo com URL em formato diferente', () async {
      // A chave é gravada com a URL normalizada (sem barra final), mas a
      // abertura pode receber a URL do painel com barra.
      const canonical = 'xtream:user@http://127.0.0.1:9';
      await cache.write(
        meta: CatalogCacheMeta(
          sourceKey: canonical,
          kind: 'xtream',
          listName: 'Xtream: user',
          savedAt: DateTime.now(),
          itemCount: 1,
        ),
        items: [_item('1', type: StreamType.live, category: 'Canais')],
      );

      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      final controller = IptvController(
        storageService: storage,
        apiClient: ApiClient(),
        xtreamApi: XtreamApi(),
        catalogCache: cache,
      )..debugDisableAutoRevalidate = true;

      final ok = await controller.loginXtream(
        serverUrl: 'http://127.0.0.1:9/',
        username: 'user',
        password: 'senha',
        allowCache: true,
      );

      expect(ok, isTrue);
      expect(controller.loadedListName, 'Xtream: user');
      expect(controller.totalLiveCount, 1);
      expect(controller.currentAccount?.serverUrl, 'http://127.0.0.1:9');
      expect(
        XtreamApi.normalizeServerUrl('exemplo.test:8080/'),
        'https://exemplo.test:8080',
      );
    });
  });
}
