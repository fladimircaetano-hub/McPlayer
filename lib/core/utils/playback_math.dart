import '../../data/models/stream_item.dart';

/// Regras de busca de tempo e ordenação da playlist de reprodução.
///
/// Ficam fora do [PlayerScreen] para serem testáveis sem player nativo.

/// Novo alvo de seek ao avançar/retroceder [deltaSeconds].
///
/// Nunca fica negativo; quando a duração é conhecida, nunca passa do fim.
Duration clampSeekTarget(
  Duration current,
  int deltaSeconds,
  Duration duration,
) {
  var target = current + Duration(seconds: deltaSeconds);
  if (target < Duration.zero) target = Duration.zero;
  if (duration > Duration.zero && target > duration) target = duration;
  return target;
}

/// Índice do item anterior, ou null quando já está no primeiro.
int? previousIndex(int index, int length) {
  if (index <= 0 || index >= length) return null;
  return index - 1;
}

/// Índice do próximo item, ou null quando já está no último.
int? nextIndex(int index, int length) {
  if (index < 0 || index >= length - 1) return null;
  return index + 1;
}

/// Ordena a playlist de reprodução.
///
/// Séries seguem temporada e episódio, então o "próximo" ao fim da T1 é o
/// E1 da T2. Filmes e canais ao vivo mantêm a ordem original (a ordem da
/// live não pode mudar). Itens sem temporada/episódio ficam na posição em
/// que vieram (ordenação estável).
List<StreamItem> orderPlaylistForPlayback(List<StreamItem> source) {
  if (source.length < 2) return List<StreamItem>.of(source);
  final hasSeries = source.any((e) => e.streamType == StreamType.series);
  if (!hasSeries) return List<StreamItem>.of(source);

  final indexed = List<MapEntry<int, StreamItem>>.generate(
    source.length,
    (i) => MapEntry(i, source[i]),
  );
  indexed.sort((a, b) {
    final sa = a.value.seasonNumber;
    final sb = b.value.seasonNumber;
    if (sa != null && sb != null && sa != sb) return sa.compareTo(sb);
    final ea = a.value.episodeNumber;
    final eb = b.value.episodeNumber;
    if (ea != null && eb != null && ea != eb) return ea.compareTo(eb);
    return a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList(growable: false);
}

/// Formata a posição no padrão do player: 00:26 / 1:13:55.
String formatPlaybackTime(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
