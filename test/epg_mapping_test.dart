// Regression: no Xtream o id interno é `xtream_live_<stream_id>`, enquanto
// o XMLTV usa o `epg_channel_id`. O EPG precisa consultar o epgId antes do
// id, senão o painel "NO AR" fica eternamente sem programação.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/data/datasources/xtream_api.dart';
import 'package:mcplayer/data/models/stream_item.dart';
import 'package:mcplayer/data/models/xtream_account.dart';
import 'package:mcplayer/data/services/epg_service.dart';

StreamItem _channel({required String id, String? epgId}) => StreamItem(
      id: id,
      name: 'Canal',
      streamUrl: 'http://exemplo/live.m3u8',
      category: 'Geral',
      streamType: StreamType.live,
      epgId: epgId,
    );

void main() {
  final now = DateTime.now();
  final program = EpgProgram(
    title: 'Programa Atual',
    start: now.subtract(const Duration(minutes: 10)).toUtc(),
    end: now.add(const Duration(minutes: 50)).toUtc(),
  );

  test('Xtream: encontra EPG pelo epgId quando o id interno é diferente', () async {
    final epg = EpgService()
      ..setCache({
        'canal.epg': [program],
      });

    final ch = _channel(id: 'xtream_live_123', epgId: 'canal.epg');
    final programs = await epg.getPrograms(ch, day: now);

    expect(programs, hasLength(1));
    expect(programs.first.title, 'Programa Atual');
    expect(programs.first.isLiveAt(now), isTrue);
  });

  test('M3U: cai no id quando epgId não está preenchido', () async {
    final epg = EpgService()
      ..setCache({
        'canal.m3u': [program],
      });

    final ch = _channel(id: 'canal.m3u');
    final programs = await epg.getPrograms(ch, day: now);

    expect(programs, hasLength(1));
  });

  test('Canal sem EPG devolve lista vazia (nunca lança)', () async {
    final epg = EpgService();
    final programs =
        await epg.getPrograms(_channel(id: 'sem.epg'), day: now);
    expect(programs, isEmpty);
  });

  test('Xtream: getLiveStreams lê epg_channel_id separado do id interno',
      () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final action = options.queryParameters['action'];
          final data = action == 'get_live_categories'
              ? [
                  {'category_id': '1', 'category_name': 'Canais | Abertos'},
                ]
              : [
                  {
                    'stream_id': 10,
                    'name': 'Canal Teste',
                    'category_id': '1',
                    'epg_channel_id': 'canal.epg',
                  },
                ];
          handler.resolve(
            Response(
              requestOptions: options,
              data: data,
              statusCode: 200,
            ),
          );
        },
      ),
    );

    final api = XtreamApi(dio);
    final items = await api.getLiveStreams(
      XtreamAccount(
        serverUrl: 'http://teste.local',
        username: 'user',
        password: 'pass',
      ),
    );

    expect(items, hasLength(1));
    expect(items.single.id, 'xtream_live_10');
    expect(items.single.epgId, 'canal.epg');
  });
}
