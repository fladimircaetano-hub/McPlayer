import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/parser/m3u_parser.dart';
import 'package:mcplayer/data/models/stream_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleM3u = '''
#EXTM3U
#EXTINF:-1 tvg-id="globo.br" tvg-name="TV Globo HD" tvg-logo="https://exemplo.com/globo.png" group-title="Canais Abertos",TV Globo HD (BR)
http://stream.exemplo.com/live/globo.m3u8

#EXTINF:-1 tvg-id="" tvg-name="Vingadores Ultimato" tvg-logo="https://exemplo.com/poster.jpg" group-title="Filmes Ação",Vingadores: Ultimato (2019)
http://stream.exemplo.com/movie/vingadores.mp4

#EXTINF:-1 tvg-id="" tvg-name="Stranger Things S01 E01" tvg-logo="https://exemplo.com/st.jpg" group-title="Séries Ficção",Stranger Things S01 E01
http://stream.exemplo.com/series/st_s01e01.mkv
''';

  group('M3uParser Tests', () {
    test('Deve processar e categorizar itens M3U corretamente', () async {
      final items = await M3uParser.parseM3u(sampleM3u);

      expect(items.length, 3);

      // 1. Canal Ao Vivo
      final liveItem = items[0];
      expect(liveItem.name, 'TV Globo HD (BR)');
      expect(liveItem.category, 'Canais Abertos');
      expect(liveItem.streamType, StreamType.live);
      expect(liveItem.logoUrl, 'https://exemplo.com/globo.png');
      expect(liveItem.streamUrl, 'http://stream.exemplo.com/live/globo.m3u8');

      // 2. Filme VOD
      final movieItem = items[1];
      expect(movieItem.name, 'Vingadores: Ultimato (2019)');
      expect(movieItem.category, 'Filmes Ação');
      expect(movieItem.streamType, StreamType.movie);
      expect(movieItem.streamUrl, 'http://stream.exemplo.com/movie/vingadores.mp4');

      // 3. Série
      final seriesItem = items[2];
      expect(seriesItem.name, 'Stranger Things S01 E01');
      expect(seriesItem.category, 'Séries Ficção');
      expect(seriesItem.streamType, StreamType.series);
    });
  });
}
