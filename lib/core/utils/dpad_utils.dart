import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DpadUtils {
  /// Verifica se o dispositivo atual tem aspecto de TV ou modo paisagem amplo
  static bool isTvOrLandscape(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height && size.width >= 900;
  }

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
