import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// Resultado do download de uma lista M3U, com os validadores do HTTP
/// (ETag/Last-Modified) para saber depois se o arquivo remoto mudou.
class M3uFetchResult {
  final String content;
  final String? etag;
  final String? lastModified;
  final int? contentLength;

  const M3uFetchResult({
    required this.content,
    this.etag,
    this.lastModified,
    this.contentLength,
  });
}

/// Informação leve de um arquivo remoto (resposta de HEAD).
class RemoteFileInfo {
  final String? etag;
  final String? lastModified;
  final int? contentLength;

  const RemoteFileInfo({this.etag, this.lastModified, this.contentLength});
}

class ApiClient {
  late final Dio dio;

  ApiClient([Dio? customDio]) {
    dio =
        customDio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 30),
            headers: {
              'User-Agent': 'IPTVSmarters/1.0.0 (Linux; Android 12; Mobile)',
              'Accept': '*/*',
            },
            followRedirects: true,
            maxRedirects: 5,
            validateStatus: (status) => status != null && status < 500,
          ),
        );
  }

  String _cleanUrl(String url) {
    var clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    return clean;
  }

  Future<String> fetchM3uContent(String url) async {
    final result = await fetchM3u(url);
    return result.content;
  }

  /// Baixa a lista e devolve também os validadores HTTP.
  Future<M3uFetchResult> fetchM3u(String url) async {
    final clean = _cleanUrl(url);
    final uri = Uri.tryParse(clean);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw Exception('URL inválida. Use http(s)://seu-servidor/playlist.m3u8');
    }
    try {
      final response = await dio.get<List<int>>(
        clean,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw Exception('Servidor respondeu HTTP ${response.statusCode}.');
      }

      final rawData = response.data;
      if (rawData == null || rawData.isEmpty) {
        throw Exception('Lista vazia ou resposta inválida do servidor.');
      }

      List<int> bytes = rawData;

      // Descompressão automática caso o servidor envie gzip/zlib cru
      if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
        try {
          bytes = gzip.decode(bytes);
        } catch (_) {}
      } else if (bytes.length >= 2 && bytes[0] == 0x78) {
        try {
          bytes = zlib.decode(bytes);
        } catch (_) {}
      }

      // Remover BOM UTF-8 se presente
      if (bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF) {
        bytes = bytes.sublist(3);
      }

      // Decodificação com fallback inteligente (UTF-8 -> UTF-8 tolerante
      // -> Latin-1).
      //
      // Cuidado: algumas listas têm 1 ou 2 linhas em Latin-1 no meio de
      // milhares em UTF-8. Trocar a lista inteira para Latin-1 nesse caso
      // transforma todos os acentos em mojibake ("Três" -> "TrÃªs"), então
      // só caímos para Latin-1 quando o UTF-8 tolerante estraga muito texto.
      String data;
      try {
        data = utf8.decode(bytes);
      } on FormatException {
        final tolerant = utf8.decode(bytes, allowMalformed: true);
        final broken = '\uFFFD'.allMatches(tolerant).length;
        if (broken * 10000 <= bytes.length) {
          data = tolerant;
        } else {
          try {
            data = latin1.decode(bytes);
          } catch (_) {
            data = tolerant;
          }
        }
      } catch (_) {
        data = utf8.decode(bytes, allowMalformed: true);
      }

      // Remover caractere BOM se decodificado como string
      if (data.startsWith('\uFEFF')) {
        data = data.substring(1);
      }

      final trimmed = data.trim();
      if (trimmed.isNotEmpty) {
        final upper = trimmed.toUpperCase();
        if (!upper.contains('#EXTM3U') && !upper.contains('#EXTINF')) {
          throw Exception('Conteúdo não parece uma lista M3U válida.');
        }
        return M3uFetchResult(
          content: data,
          etag: _header(response.headers, 'etag'),
          lastModified: _header(response.headers, 'last-modified'),
          contentLength: int.tryParse(
            _header(response.headers, 'content-length') ?? '',
          ),
        );
      }
      throw Exception('Lista vazia ou resposta inválida do servidor.');
    } on DioException catch (e) {
      throw Exception(_friendlyDio(e));
    }
  }

  /// Consulta só os cabeçalhos da lista (HEAD). Usado para descobrir se o
  /// provedor trocou o arquivo desde o último download salvo.
  ///
  /// Retorna null quando o servidor não aceita HEAD ou não responde 2xx.
  Future<RemoteFileInfo?> remoteFileInfo(String url) async {
    final clean = _cleanUrl(url);
    final uri = Uri.tryParse(clean);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    try {
      final response = await dio.head<List<int>>(
        clean,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 400) return null;
      return RemoteFileInfo(
        etag: _header(response.headers, 'etag'),
        lastModified: _header(response.headers, 'last-modified'),
        contentLength: int.tryParse(
          _header(response.headers, 'content-length') ?? '',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  String? _header(Headers headers, String name) {
    final value = headers.value(name)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String _friendlyDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Tempo esgotado. Verifique a internet e tente de novo.';
      case DioExceptionType.connectionError:
        return 'Sem conexão com o servidor. Confira URL/rede.';
      case DioExceptionType.badResponse:
        return 'Servidor respondeu ${e.response?.statusCode ?? 'com erro'}. Confira a URL.';
      case DioExceptionType.cancel:
        return 'Requisição cancelada.';
      default:
        return 'Falha de rede: ${e.message ?? 'erro desconhecido'}';
    }
  }
}
