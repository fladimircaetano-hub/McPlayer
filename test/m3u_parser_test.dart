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

    test('Formato da URL manda: canais ao vivo não vazam p/ Filmes/Séries',
        () async {
      const tricky = '''
#EXTM3U
#EXTINF:-1 group-title="FILME E SERIES",SPORTV HD
http://pro.exemplo.com:8080/u/p/1001.m3u8
#EXTINF:-1 group-title="CANAIS",TNT SERIES HD
http://pro.exemplo.com:8080/u/p/1002.m3u8
#EXTINF:-1 group-title="ESPORTES",SPORTV+ HD
http://pro.exemplo.com:8080/u/p/1003.m3u8
#EXTINF:-1 group-title="ESPORTES PAY-PER",PREMIERE HD
http://pro.exemplo.com:8080/u/p/1004.m3u8
#EXTINF:-1 group-title="CANAIS PORTUGAL",SPORT TV+ HD
http://pro.exemplo.com:8080/u/p/1005.m3u8
#EXTINF:-1 group-title="CINEMA",CINEMAX HD
http://pro.exemplo.com:8080/u/p/1006.m3u8
#EXTINF:-1 group-title="QUALQUER COISA",GLOBO SP HD
http://pro.exemplo.com:8080/live/u/p/2001.m3u8
#EXTINF:-1 group-title="QUALQUER COISA",Avatar (2009)
http://pro.exemplo.com:8080/movie/u/p/3001.mp4
#EXTINF:-1 group-title="QUALQUER COISA",Loki S01 E01
http://pro.exemplo.com:8080/series/u/p/4001.mp4
#EXTINF:-1 group-title="SERIES",Loki S02 E03
http://pro.exemplo.com:8080/u/p/4002.m3u8
#EXTINF:-1 group-title="FILMES",Avatar (2009)
http://pro.exemplo.com/f/5001.mp4?token=abc123
#EXTINF:-1 group-title="ABERTOS",GLOBO SP HD
http://pro.exemplo.com/u/p/6001.m3u8?token=abc123
#EXTINF:-1 group-title="NETFLIX",Bird Box
http://pro.exemplo.com/s/7001
#EXTINF:-1 group-title="NOVELAS",Reis Cap 45
http://pro.exemplo.com/s/7002
''';
      final items = await M3uParser.parseM3u(tricky);
      expect(items.length, 14);

      // 0-5: canais ao vivo em grupos com nome "suspeito" continuam ao vivo.
      for (var i = 0; i <= 5; i++) {
        expect(items[i].streamType, StreamType.live,
            reason: '${items[i].name} [${items[i].category}]');
      }
      // 6-8: path Xtream decide.
      expect(items[6].streamType, StreamType.live);
      expect(items[7].streamType, StreamType.movie);
      expect(items[8].streamType, StreamType.series);
      // 9: episódio HLS continua série.
      expect(items[9].streamType, StreamType.series);
      // 10-11: query string não quebra a extensão.
      expect(items[10].streamType, StreamType.movie);
      expect(items[11].streamType, StreamType.live);
      // 12-13: sem formato na URL, grupo desempata.
      expect(items[12].streamType, StreamType.movie);
      expect(items[13].streamType, StreamType.series);
    });

    test('Deve suportar #extinf minúsculo, #EXTGRP, vírgulas no título e atributos variados', () async {
      const sample = '''
#extm3u
#extinf:-1 tvg-id="globo.sp" TVG-NAME="Globo SP" LOGO="http://img.com/globo.png",Globo SP, Canal 5
#EXTGRP:Canais Abertos
http://stream.com/live/101.m3u8

#extinf:-1 group-title="Filmes, Ação e Aventura",Missão Impossível 2, O Retorno
http://stream.com/movie/mi2.mp4

#EXTINF -1 GROUP-TITLE=Séries,Breaking Bad S01 E01
http://stream.com/series/bb_s01e01.mp4
''';
      final items = await M3uParser.parseM3u(sample);
      expect(items.length, 3);

      // 1. #extinf minúsculo + #EXTGRP + vírgula no título preservada + LOGO maiúsculo
      expect(items[0].name, 'Globo SP, Canal 5');
      expect(items[0].category, 'Canais Abertos');
      expect(items[0].logoUrl, 'http://img.com/globo.png');
      expect(items[0].streamType, StreamType.live);

      // 2. group-title com vírgula dentro de aspas + título com vírgula preservada
      expect(items[1].name, 'Missão Impossível 2, O Retorno');
      expect(items[1].category, 'Filmes, Ação e Aventura');
      expect(items[1].streamType, StreamType.movie);

      // 3. #EXTINF sem dois-pontos + GROUP-TITLE sem aspas
      expect(items[2].name, 'Breaking Bad S01 E01');
      expect(items[2].category, 'Séries');
      expect(items[2].streamType, StreamType.series);
    });
  });
}
