import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

class ApiClient {
  late final Dio dio;

  ApiClient([Dio? customDio]) {
    dio = customDio ??
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

      // Decodificação com fallback inteligente (UTF-8 -> Latin-1 -> UTF-8 tolerante)
      String data;
      try {
        data = utf8.decode(bytes);
      } on FormatException {
        try {
          data = latin1.decode(bytes);
        } catch (_) {
          data = utf8.decode(bytes, allowMalformed: true);
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
        return data;
      }
      throw Exception('Lista vazia ou resposta inválida do servidor.');
    } on DioException catch (e) {
      throw Exception(_friendlyDio(e));
    }
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
