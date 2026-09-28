import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/network/api_client.dart';
import 'package:mcplayer/data/datasources/xtream_api.dart';
import 'package:mcplayer/data/models/xtream_account.dart';

void main() {
  group('ApiClient Tests', () {
    test('Decodifica playlist com acentuação Latin-1 / ISO-8859-1 com sucesso', () async {
      final dio = Dio();
      final client = ApiClient(dio);

      // Cria bytes em Latin-1 com caracteres como 'ã', 'ç', 'é'
      const rawText = '#EXTM3U\n#EXTINF:-1 group-title="Ação e Emoção",Canal Ficção HD\nhttp://stream.com/live/1.m3u8';
      final latin1Bytes = latin1.encode(rawText);

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: latin1Bytes,
                statusCode: 200,
              ),
            );
          },
        ),
      );

      final content = await client.fetchM3uContent('http://exemplo.com/playlist.m3u');
      expect(content.contains('Ação e Emoção'), isTrue);
      expect(content.contains('Ficção HD'), isTrue);
    });

    test('Normaliza URL sem scheme inserindo http://', () async {
      final dio = Dio();
      final client = ApiClient(dio);

      String requestedUrl = '';
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedUrl = options.path;
            handler.resolve(
              Response(
                requestOptions: options,
                data: utf8.encode('#EXTM3U\n#EXTINF:-1,Teste\nhttp://exemplo.com/live.m3u8'),
                statusCode: 200,
              ),
            );
          },
        ),
      );

      await client.fetchM3uContent('meu-servidor.com:8080/lista.m3u');
      expect(requestedUrl, 'https://meu-servidor.com:8080/lista.m3u');
    });
  });

  group('XtreamApi Tests', () {
    test('getSeriesEpisodes não quebra quando episodes é retornado como List vazia []', () async {
      final dio = Dio();
      final api = XtreamApi(dio);

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'episodes': [], // Em PHP, array vazio vira List no JSON
                },
                statusCode: 200,
              ),
            );
          },
        ),
      );

      final account = XtreamAccount(
        serverUrl: 'http://test.com',
        username: 'user',
        password: 'pass',
      );

      final episodes = await api.getSeriesEpisodes(account, 123);
      expect(episodes, isEmpty);
    });

    test('getSeriesEpisodes extrai episódios corretamente quando episodes é Map', () async {
      final dio = Dio();
      final api = XtreamApi(dio);

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'episodes': {
                    '1': [
                      {
                        'id': 101,
                        'title': 'Episódio Piloto',
                        'episode_num': 1,
                        'container_extension': 'mp4',
                      }
                    ]
                  }
                },
                statusCode: 200,
              ),
            );
          },
        ),
      );

      final account = XtreamAccount(
        serverUrl: 'http://test.com',
        username: 'user',
        password: 'pass',
      );

      final episodes = await api.getSeriesEpisodes(account, 123);
      expect(episodes.length, 1);
      expect(episodes.first.name, 'T1:E1 - Episódio Piloto');
      expect(episodes.first.streamUrl, 'http://test.com/series/user/pass/101.mp4');
    });
  });

  group('Player URL Pipe Headers Test', () {
    test('Separa URL e extrai headers passados via pipe |', () {
      const urlWithHeaders = 'http://exemplo.com/live/stream.m3u8|User-Agent=CustomPlayer&Referer=http://origem.com';
      String cleanUrl = urlWithHeaders.trim();
      final headers = <String, String>{};
      final pipeIndex = cleanUrl.indexOf('|');
      if (pipeIndex != -1) {
        final queryHeaders = cleanUrl.substring(pipeIndex + 1);
        cleanUrl = cleanUrl.substring(0, pipeIndex).trim();
        final pairs = queryHeaders.split('&');
        for (final pair in pairs) {
          final eq = pair.indexOf('=');
          if (eq != -1) {
            final k = pair.substring(0, eq).trim();
            final v = pair.substring(eq + 1).trim();
            if (k.isNotEmpty && v.isNotEmpty) {
              headers[k] = v;
            }
          }
        }
      }

      expect(cleanUrl, 'http://exemplo.com/live/stream.m3u8');
      expect(headers['User-Agent'], 'CustomPlayer');
      expect(headers['Referer'], 'http://origem.com');
    });
  });
}
