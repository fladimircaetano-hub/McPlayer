import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/utils/playback_math.dart';
import 'package:mcplayer/data/models/stream_item.dart';

StreamItem _item(
  String id, {
  StreamType type = StreamType.movie,
  int? season,
  int? episode,
}) {
  return StreamItem(
    id: id,
    name: id,
    streamUrl: 'https://exemplo.com/$id.mp4',
    category: 'TESTE',
    streamType: type,
    seasonNumber: season,
    episodeNumber: episode,
  );
}

void main() {
  group('clampSeekTarget', () {
    test('voltar 10s perto do início vai para zero (sem negativo)', () {
      expect(
        clampSeekTarget(
          const Duration(seconds: 5),
          -10,
          const Duration(minutes: 2),
        ),
        Duration.zero,
      );
    });

    test('adiantar 10s além do fim para na duração', () {
      expect(
        clampSeekTarget(
          const Duration(minutes: 1, seconds: 50),
          10,
          const Duration(minutes: 1, seconds: 55),
        ),
        const Duration(minutes: 1, seconds: 55),
      );
    });

    test('sem duração conhecida só impede negativo', () {
      expect(
        clampSeekTarget(const Duration(seconds: 5), 10, Duration.zero),
        const Duration(seconds: 15),
      );
    });

    test('clique na barra usa o alvo exato dentro dos limites', () {
      expect(
        clampSeekTarget(
          const Duration(minutes: 1),
          0,
          const Duration(minutes: 3),
        ),
        const Duration(minutes: 1),
      );
    });
  });

  group('limites da playlist', () {
    test('anterior desativado no primeiro item', () {
      expect(previousIndex(0, 5), isNull);
    });

    test('próximo desativado no último item', () {
      expect(nextIndex(4, 5), isNull);
    });

    test('meio da lista navega nos dois sentidos', () {
      expect(previousIndex(2, 5), 1);
      expect(nextIndex(2, 5), 3);
    });
  });

  group('orderPlaylistForPlayback', () {
    test('séries seguem temporada e episódio (troca de temporada)', () {
      final list = [
        _item('s1e2', type: StreamType.series, season: 1, episode: 2),
        _item('s2e1', type: StreamType.series, season: 2, episode: 1),
        _item('s1e1', type: StreamType.series, season: 1, episode: 1),
        _item('s2e2', type: StreamType.series, season: 2, episode: 2),
      ];
      final ordered = orderPlaylistForPlayback(list);
      expect(ordered.map((e) => e.id), ['s1e1', 's1e2', 's2e1', 's2e2']);
      // A lista original não é alterada.
      expect(list.first.id, 's1e2');
    });

    test('filmes mantêm a ordem original', () {
      final list = [
        _item('b'),
        _item('a'),
        _item('c'),
      ];
      expect(orderPlaylistForPlayback(list).map((e) => e.id), ['b', 'a', 'c']);
    });

    test('canais ao vivo nunca são reordenados', () {
      final list = [
        _item('canal-b', type: StreamType.live),
        _item('canal-a', type: StreamType.live),
      ];
      expect(
        orderPlaylistForPlayback(list).map((e) => e.id),
        ['canal-b', 'canal-a'],
      );
    });
  });

  group('formatPlaybackTime', () {
    test('posição sem hora', () {
      expect(formatPlaybackTime(const Duration(seconds: 26)), '00:26');
    });

    test('duração com hora', () {
      expect(
        formatPlaybackTime(
            const Duration(hours: 1, minutes: 13, seconds: 55)),
        '1:13:55',
      );
    });

    test('negativo vira zero', () {
      expect(formatPlaybackTime(const Duration(seconds: -5)), '00:00');
    });
  });
}
