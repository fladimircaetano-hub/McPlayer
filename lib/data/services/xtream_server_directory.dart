import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/activation/activation_config.dart';

class XtreamServerInfo {
  final String name;
  final String url;

  const XtreamServerInfo({required this.name, required this.url});
}

/// Lista de servidores Xtream usados no login por usuário/senha.
///
/// A lista oficial fica no painel (tabela `xtream_servers`) para permitir
/// trocar/adicionar servidor sem gerar APK novo. Se o painel não responder
/// (ou o SQL ainda não foi rodado), usa a lista embutida abaixo.
class XtreamServerDirectory {
  static const List<XtreamServerInfo> fallback = [
    XtreamServerInfo(name: 'Cmax Vision', url: 'http://cmaxvision.xyz'),
    XtreamServerInfo(name: 'TV Sirius', url: 'http://tvsirius.xyz'),
  ];

  Future<List<XtreamServerInfo>> load() async {
    if (!ActivationConfig.isEnabled) return fallback;

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final base = ActivationConfig.supabaseUrl.replaceAll(RegExp(r'/$'), '');
      final response = await dio.get(
        '$base/rest/v1/xtream_servers',
        queryParameters: {
          'app_name': 'eq.${ActivationConfig.appName}',
          'active': 'eq.true',
          'select': 'name,url',
          'order': 'sort_order.asc',
        },
        options: Options(
          headers: {
            'apikey': ActivationConfig.supabaseAnonKey,
            'Authorization': 'Bearer ${ActivationConfig.supabaseAnonKey}',
          },
        ),
      );

      final data = response.data;
      if (data is List) {
        final servers = <XtreamServerInfo>[];
        for (final item in data) {
          if (item is! Map) continue;
          final url = (item['url'] ?? '').toString().trim();
          if (url.isEmpty) continue;
          if (servers.any((s) => s.url == url)) continue;
          servers.add(
            XtreamServerInfo(
              name: (item['name'] ?? '').toString().trim().isEmpty
                  ? url
                  : item['name'].toString().trim(),
              url: url,
            ),
          );
        }
        if (servers.isNotEmpty) return servers;
      }
    } catch (e) {
      debugPrint('[XtreamServerDirectory] usando lista embutida: $e');
    }

    return fallback;
  }
}
