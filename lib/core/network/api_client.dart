import 'package:dio/dio.dart';

class ApiClient {
  late final Dio dio;

  ApiClient() {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent': 'IPTVSmarters/1.0.0 (Linux; Android 12; Mobile)',
          'Accept': '*/*',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }

  Future<String> fetchM3uContent(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.host.contains('.')) {
      throw Exception('URL inválida. Use http(s)://seu-servidor/playlist.m3u8');
    }
    try {
      final response = await dio.get<String>(url.trim());
      final data = response.data;
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw Exception('Servidor respondeu HTTP ${response.statusCode}.');
      }
      if (data != null && data.trim().isNotEmpty) {
        if (!data.contains('#EXTM3U') && !data.contains('#EXTINF')) {
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
