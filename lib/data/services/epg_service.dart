import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import '../models/stream_item.dart';

/// Programa da grade (EPG): título + janela de exibição (UTC internamente).
class EpgProgram {
  final String title;
  final DateTime start;
  final DateTime end;

  const EpgProgram({
    required this.title,
    required this.start,
    required this.end,
  });

  DateTime get startLocal => start.toLocal();
  DateTime get endLocal => end.toLocal();

  bool isLiveAt(DateTime now) {
    final utc = now.toUtc();
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  String rangeLabel() =>
      '${_hhmm(startLocal)} : ${_hhmm(endLocal)}';

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Parse pesado roda em isolate: devolve só tipos primitivos.
/// {channelKey: [{t: title, s: startMsUtc, e: endMsUtc}]}
/// Deve ser top-level para funcionar com compute().
Future<Map<String, List<Map<String, Object>>>> _parseXmltv(String raw) async {
  final result = <String, List<Map<String, Object>>>{};
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(raw);
  } catch (_) {
    return result;
  }
  for (final p in doc.findAllElements('programme')) {
    final ch = p.getAttribute('channel')?.trim();
    final title = p.getElement('title')?.innerText.trim() ?? '';
    final s = _parseXmltvDate(p.getAttribute('start'));
    final e = _parseXmltvDate(p.getAttribute('stop'));
    if (ch == null ||
        ch.isEmpty ||
        title.isEmpty ||
        s == null ||
        e == null) {
      continue;
    }
    if (!e.isAfter(s)) continue;
    result.putIfAbsent(ch, () => []).add({
      't': title,
      's': s.millisecondsSinceEpoch,
      'e': e.millisecondsSinceEpoch,
    });
  }
  for (final list in result.values) {
    list.sort((a, b) => (a['s'] as int).compareTo(b['s'] as int));
  }
  return result;
}

/// "20260914091400 -0300" ou "20260914091400" (sem offset = UTC).
/// Deve ser top-level para funcionar com compute().
DateTime? _parseXmltvDate(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^(\d{14})(?:\s*([+-])(\d{2})(\d{2}))?')
      .firstMatch(v.trim());
  if (m == null) return null;
  final d = m.group(1)!;
  try {
    var utc = DateTime.utc(
      int.parse(d.substring(0, 4)),
      int.parse(d.substring(4, 6)),
      int.parse(d.substring(6, 8)),
      int.parse(d.substring(8, 10)),
      int.parse(d.substring(10, 12)),
      int.parse(d.substring(12, 14)),
    );
    if (m.group(2) != null) {
      var offset = Duration(
        hours: int.parse(m.group(3)!),
        minutes: int.parse(m.group(4)!),
      );
      if (m.group(2) == '-') offset = -offset;
      utc = utc.subtract(offset);
    }
    return utc;
  } catch (_) {
    return null;
  }
}

/// Baixa e cruza o XMLTV.
///
/// Mapeamento: `programme@channel` == `tvg-id` do M3U (que é o `id`
/// do nosso StreamItem). Nunca lança exceção: falha retorna mapa vazio.
class EpgService {
  final Dio _dio;

  EpgService([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 2),
                headers: {
                  'User-Agent': 'IPTVSmarters/1.0.0 (Linux; Android 12)',
                  'Accept': 'application/xml, text/xml, */*',
                },
                responseType: ResponseType.plain,
                validateStatus: (s) => s != null && s < 500,
              ),
            );

  /// Via conta Xtream: `{server}/xmltv.php?username=..&password=..`
  Future<Map<String, List<EpgProgram>>> loadXtream({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    if (username.trim().isEmpty || password.trim().isEmpty) {
      debugPrint('[EPG] Missing credentials for Xtream EPG');
      return {};
    }
    final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url =
        '$base/xmltv.php?username=${Uri.encodeComponent(username.trim())}'
        '&password=${Uri.encodeComponent(password.trim())}';
    return _fetch(url);
  }

  /// Via URL M3U com usuário/senha (ex.: `get.php?username=..&password=..`):
  /// tenta o `xmltv.php` do mesmo host. Sem credenciais ou falha → vazio.
  Future<Map<String, List<EpgProgram>>> tryFromM3uUrl(String m3uUrl) async {
    try {
      final uri = Uri.parse(m3uUrl.trim());
      final user = uri.queryParameters['username'] ?? '';
      final pass = uri.queryParameters['password'] ?? '';
      if (user.isEmpty || pass.isEmpty) {
        debugPrint('[EPG] No credentials in M3U URL for EPG');
        return {};
      }
      var host = '${uri.scheme}://${uri.host}';
      if (uri.hasPort) host += ':${uri.port}';
      return await loadXtream(
          serverUrl: host, username: user, password: pass);
    } catch (e) {
      debugPrint('[EPG] Error parsing M3U URL for EPG: $e');
      return {};
    }
  }

  /// Cache em memória: channelKey (tvg-id) -> programas ordenados.
  /// Preenchido pelo controller após carregar a lista; nunca bloqueia a UI.
  Map<String, List<EpgProgram>> _cache = {};

  bool get hasData => _cache.isNotEmpty;

  void setCache(Map<String, List<EpgProgram>> data) => _cache = data;

  void clear() => _cache = {};

  /// Programa no ar agora para o canal ([StreamItem.id] == tvg-id).
  /// Síncrono sobre o cache: barato para chamar por linha de lista.
  /// Sem cache ou fora do ar retorna null.
  EpgProgram? liveNow(String channelId, DateTime now) {
    final all = _cache[channelId];
    if (all == null || all.isEmpty) return null;
    final utc = now.toUtc();
    for (final p in all) {
      if (!utc.isBefore(p.start) && utc.isBefore(p.end)) return p;
    }
    return null;
  }

  /// Programas do canal no dia local informado (00h–24h).
  /// A chave é o [StreamItem.id] (tvg-id no M3U). Nunca lança: sem cache
  /// ou sem chave retorna lista vazia. Síncrono por cima do cache, mas
  /// exposto como Future para a tela poder awaitar sem travar.
  Future<List<EpgProgram>> getPrograms(StreamItem channel,
      {required DateTime day}) async {
    final all = _cache[channel.id];
    if (all == null || all.isEmpty) return const [];
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return [
      for (final p in all)
        if (p.endLocal.isAfter(start) && p.startLocal.isBefore(end)) p,
    ];
  }

  Future<Map<String, List<EpgProgram>>> _fetch(String url) async {
    try {
      final response = await _dio.get<String>(url);
      final raw = response.data ?? '';
      if (response.statusCode != null && response.statusCode! >= 400) {
        debugPrint('[EPG] HTTP error: ${response.statusCode} for $url');
        return {};
      }
      if (!raw.contains('<tv')) {
        debugPrint('[EPG] Invalid XMLTV format from $url');
        return {};
      }
      final parsed = await compute(_parseXmltv, raw);
      final out = <String, List<EpgProgram>>{};
      parsed.forEach((key, list) {
        out[key] = [
          for (final m in list)
            EpgProgram(
              title: m['t'] as String,
              start: DateTime.fromMillisecondsSinceEpoch(m['s'] as int,
                  isUtc: true),
              end: DateTime.fromMillisecondsSinceEpoch(m['e'] as int,
                  isUtc: true),
            ),
        ];
      });
      debugPrint('[EPG] Loaded ${out.length} channels with EPG data');
      return out;
    } catch (e) {
      debugPrint('[EPG] Error fetching $url: $e');
      return {};
    }
  }
}