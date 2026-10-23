import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/utils/duplicates.dart';
import 'package:mcplayer/data/models/stream_item.dart';

StreamItem _item({
  required String id,
  required String name,
  StreamType type = StreamType.movie,
  String? url,
  String? logo,
  String? rating,
  String? release,
  int? seriesId,
  int? season,
  int? episode,
}) {
  return StreamItem(
    id: id,
    name: name,
    streamUrl: url ?? 'https://exemplo.com/$id.mp4',
    category: 'TESTE',
    streamType: type,
    logoUrl: logo,
    rating: rating,
    releaseDate: release,
    seriesId: seriesId,
    seasonNumber: season,
    episodeNumber: episode,
  );
}

void main() {
  group('normalização de título', () {
    test('remove acentos, ano, tags e qualidade', () {
      expect(normalizeTitle('Ação (2022) [1080p]'), 'acao');
    });

    test('mantém o texto base de dublado/legendado fora da chave', () {
      expect(normalizeTitle('Filme Dublado'), 'filme');
      expect(normalizeTitle('Filme [LEG]'), 'filme');
      expect(normalizeTitle('Filme HD'), 'filme');
    });

    test('detecta a variante de áudio', () {
      expect(titleVariant('Filme Dublado'), 'dub');
      expect(titleVariant('Filme [DUB]'), 'dub');
      expect(titleVariant('Filme [LEG]'), 'leg');
      expect(titleVariant('Filme Legendado'), 'leg');
      expect(titleVariant('Filme Dual Áudio'), 'dual');
      expect(titleVariant('Filme'), '');
    });

    test('ano sai do releaseDate ou do nome', () {
      expect(extractYear(_item(id: 'a', name: 'X', release: '2022-05-01')), 2022);
      expect(extractYear(_item(id: 'b', name: 'X (2021)')), 2021);
      expect(extractYear(_item(id: 'c', name: 'X')), isNull);
    });

    test('URL ignora headers e fragmento', () {
      expect(
        canonicalUrl(' https://Exemplo.com/a.mp4|User-Agent=x#t=10 '),
        'https://exemplo.com/a.mp4',
      );
    });
  });

  group('scanCatalogDuplicates — filmes', () {
    test('mesmo título e ano: mantém uma cópia', () {
      final scan = scanCatalogDuplicates([
        _item(id: 'a', name: 'O Filme (2022)', release: '2022'),
        _item(id: 'b', name: 'o filme [1080p] (2022)', release: '2022'),
      ]);
      expect(scan.cleaned.map((e) => e.id), ['a']);
      expect(scan.report.removedCount, 1);
      expect(scan.report.removedMovies, 1);
      expect(scan.report.entries.single.kind, 'filme');
    });

    test('melhor versão vence (https + capa + mp4)', () {
      final scan = scanCatalogDuplicates([
        _item(
          id: 'simples',
          name: 'Filme (2020)',
          url: 'http://exemplo.com/simples.avi',
          release: '2020',
        ),
        _item(
          id: 'completa',
          name: 'Filme (2020)',
          url: 'https://exemplo.com/completa.mp4',
          logo: 'https://exemplo.com/capa.jpg',
          rating: '8.5',
          release: '2020',
        ),
      ]);
      expect(scan.report.entries.single.kept.id, 'completa');
      expect(scan.cleaned.map((e) => e.id), ['completa']);
    });

    test('remakes com anos diferentes NÃO são duplicados', () {
      final scan = scanCatalogDuplicates([
        _item(id: 'a', name: 'Creepshow (1982)', release: '1982'),
        _item(id: 'b', name: 'Creepshow (2019)', release: '2019'),
      ]);
      expect(scan.hasDuplicates, isFalse);
      expect(scan.cleaned.length, 2);
    });

    test('dublado x legendado NÃO são duplicados', () {
      final scan = scanCatalogDuplicates([
        _item(id: 'dub', name: 'Filme [DUB] (2020)', release: '2020'),
        _item(id: 'leg', name: 'Filme [LEG] (2020)', release: '2020'),
      ]);
      expect(scan.hasDuplicates, isFalse);
      expect(scan.cleaned.length, 2);
    });

    test('mesma URL é duplicado mesmo com nome diferente', () {
      final scan = scanCatalogDuplicates([
        _item(id: 'a', name: 'Nome A', url: 'https://exemplo.com/x.mp4'),
        _item(id: 'b', name: 'Nome B', url: 'https://exemplo.com/x.mp4'),
      ]);
      expect(scan.report.removedCount, 1);
      expect(scan.report.entries.single.reason, contains('URL'));
    });

    test('favorito migra para a cópia mantida', () {
      final scan = scanCatalogDuplicates([
        _item(id: 'a', name: 'Filme (2022)', release: '2022'),
        _item(id: 'b', name: 'Filme (2022)', release: '2022'),
      ]);
      expect(scan.report.idRemap, {'b': 'a'});
    });
  });

  group('scanCatalogDuplicates — ao vivo', () {
    test('canais ao vivo nunca são removidos', () {
      final scan = scanCatalogDuplicates([
        _item(
          id: 'l1',
          name: 'Canal',
          type: StreamType.live,
          url: 'https://exemplo.com/live/1.m3u8',
        ),
        _item(
          id: 'l2',
          name: 'Canal',
          type: StreamType.live,
          url: 'https://exemplo.com/live/1.m3u8',
        ),
      ]);
      expect(scan.hasDuplicates, isFalse);
      expect(scan.cleaned.length, 2);
    });

    test('live não interfere nos filmes', () {
      final scan = scanCatalogDuplicates([
        _item(id: 'l1', name: 'Canal', type: StreamType.live),
        _item(id: 'm1', name: 'Filme (2020)', release: '2020'),
        _item(id: 'm2', name: 'Filme (2020)', release: '2020'),
      ]);
      expect(scan.cleaned.map((e) => e.id), ['l1', 'm1']);
    });
  });

  group('scanCatalogDuplicates — séries', () {
    test('mesma série (seriesId) só uma entrada', () {
      final scan = scanCatalogDuplicates([
        _item(
          id: 's1',
          name: 'Série',
          type: StreamType.series,
          seriesId: 10,
          logo: 'https://exemplo.com/capa.jpg',
        ),
        _item(
          id: 's2',
          name: 'Série',
          type: StreamType.series,
          seriesId: 10,
        ),
      ]);
      expect(scan.cleaned.length, 1);
      expect(scan.report.entries.single.kind, 'serie');
    });

    test('seriesId diferente não é duplicado', () {
      final scan = scanCatalogDuplicates([
        _item(id: 's1', name: 'Série', type: StreamType.series, seriesId: 10),
        _item(id: 's2', name: 'Série', type: StreamType.series, seriesId: 11),
      ]);
      expect(scan.hasDuplicates, isFalse);
    });
  });

  group('dedupeEpisodes', () {
    test('mesma temporada/episódio mantém a melhor cópia', () {
      final eps = [
        _item(
          id: 'e1',
          name: 'T1E1',
          type: StreamType.series,
          seriesId: 10,
          season: 1,
          episode: 1,
          logo: 'https://exemplo.com/capa.jpg',
        ),
        _item(
          id: 'e2',
          name: 'T1E1',
          type: StreamType.series,
          seriesId: 10,
          season: 1,
          episode: 1,
        ),
      ];
      final cleaned = dedupeEpisodes(eps);
      expect(cleaned.single.id, 'e1');
    });

    test('episódios diferentes são mantidos', () {
      final eps = [
        _item(
            id: 'e1',
            name: 'T1E1',
            type: StreamType.series,
            seriesId: 10,
            season: 1,
            episode: 1),
        _item(
            id: 'e2',
            name: 'T2E1',
            type: StreamType.series,
            seriesId: 10,
            season: 2,
            episode: 1),
      ];
      expect(dedupeEpisodes(eps).length, 2);
    });

    test('mesma URL elimina a cópia', () {
      final eps = [
        _item(
          id: 'e1',
          name: 'T1E1',
          type: StreamType.series,
          season: 1,
          episode: 1,
          url: 'https://exemplo.com/ep.mp4',
        ),
        _item(
          id: 'e2',
          name: 'T1E1 (cópia)',
          type: StreamType.series,
          season: 1,
          episode: 2,
          url: 'https://exemplo.com/ep.mp4',
        ),
      ];
      expect(dedupeEpisodes(eps).length, 1);
    });
  });

  group('fingerprint', () {
    test('estável para a mesma lista e diferente ao mudar', () {
      final a = [_item(id: 'a', name: 'A')];
      final b = [_item(id: 'a', name: 'A')];
      final c = [_item(id: 'b', name: 'B')];
      expect(fingerprintOf(a), fingerprintOf(b));
      expect(fingerprintOf(a), isNot(fingerprintOf(c)));
    });
  });

  group('relatório', () {
    test('texto lista mantido e removidos', () {
      final scan = scanCatalogDuplicates([
        _item(id: 'a', name: 'Filme (2022)', release: '2022'),
        _item(id: 'b', name: 'Filme (2022)', release: '2022'),
      ]);
      final text = scan.report.toText();
      expect(text, contains('Repetidos encontrados: 1'));
      expect(text, contains('manter: Filme (2022)'));
      expect(text, contains('remover: Filme (2022)'));
    });

    test('JSON traz os grupos e ids', () {
      final scan = scanCatalogDuplicates([
        _item(id: 'a', name: 'Filme (2022)', release: '2022'),
        _item(id: 'b', name: 'Filme (2022)', release: '2022'),
      ]);
      final json = scan.report.encode();
      expect(json, contains('"removed":1'));
      expect(json, contains('"id":"a"'));
      expect(json, contains('"id":"b"'));
    });
  });
}
