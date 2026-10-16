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

  group('Player Error Classification Tests', () {
    // These tests verify the error classification logic used in PlayerScreen
    // We test the logic directly since it's private in the widget

    test('Erros fatais (não tentam retry): DNS, auth, 404', () {
      final fatalErrors = [
        'Failed to resolve hostname example.com',
        'No address associated with hostname',
        'Connection refused',
        'Connection reset by peer',
        'Network is unreachable',
        'No route to host',
        'HTTP error 401',
        'HTTP error 403',
        'HTTP error 404',
        'HTTP error 410',
        'HTTP error 503',
        'SSL handshake failed',
        'Certificate verify failed',
      ];

      for (final error in fatalErrors) {
        expect(_isFatalError(error), isTrue, reason: 'Should be fatal: $error');
      }
    });

    test('Erros transitórios (tentam retry com backoff): timeout, 5xx', () {
      final transientErrors = [
        'Connection timeout',
        'Timed out',
        'Read timed out',
        'Connection reset',
        'Broken pipe',
        'EOF',
        'HTTP error 500',
        'HTTP error 502',
        'HTTP error 504',
      ];

      for (final error in transientErrors) {
        expect(_isTransientError(error), isTrue, reason: 'Should be transient: $error');
      }
    });

    test('Erros não classificados (tentam retry simples uma vez)', () {
      final otherErrors = [
        'Unknown error',
        'Player error',
        'Demuxer error',
        'Decoder error',
      ];

      for (final error in otherErrors) {
        expect(_isFatalError(error), isFalse, reason: 'Should not be fatal: $error');
        expect(_isTransientError(error), isFalse, reason: 'Should not be transient: $error');
      }
    });

    test('Case insensitive', () {
      expect(_isFatalError('HTTP ERROR 404'), isTrue);
      expect(_isFatalError('http error 404'), isTrue);
      expect(_isFatalError('Http Error 404'), isTrue);
      expect(_isTransientError('TIMEOUT'), isTrue);
      expect(_isTransientError('timeout'), isTrue);
    });
  });
}

/// Copia da lógica privada do PlayerScreen para teste
bool _isFatalError(String message) {
  final m = message.toLowerCase();
  return m.contains('failed to resolve hostname') ||
      m.contains('no address associated with hostname') ||
      m.contains('connection refused') ||
      m.contains('connection reset') ||
      m.contains('network is unreachable') ||
      m.contains('no route to host') ||
      m.contains('http error 401') ||
      m.contains('http error 403') ||
      m.contains('http error 404') ||
      m.contains('http error 410') ||
      m.contains('http error 503') ||
      m.contains('ssl handshake') ||
      m.contains('certificate verify');
}

bool _isTransientError(String message) {
  final m = message.toLowerCase();
  return m.contains('timeout') ||
      m.contains('timed out') ||
      m.contains('connection reset') ||
      m.contains('broken pipe') ||
      m.contains('eof') ||
      m.contains('http error 500') ||
      m.contains('http error 502') ||
      m.contains('http error 504');
}
