import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DpadUtils {
  /// Verifica se a tela é de TV (TV Box, Fire TV, Smart TV) e não apenas um
  /// celular em paisagem. Um celular grande em paisagem pode chegar a 915px
  /// de largura e ~412px de altura; um TV Box 720p tem ~1280x720. Exigir
  /// altura mínima separa os dois casos sem depender de marca/modelo.
  static bool isLargeScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height &&
        size.width >= 900 &&
        size.height >= 480;
  }

  /// Mantido por compatibilidade: TVs e paisagens amplas usam o layout
  /// dividido. Hoje delega para [isLargeScreen].
  static bool isTvOrLandscape(BuildContext context) => isLargeScreen(context);

  /// Verifica se uma tecla pressionada é do D-pad ou controle de TV
  static bool isDpadOrMediaKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind;
  }
}
