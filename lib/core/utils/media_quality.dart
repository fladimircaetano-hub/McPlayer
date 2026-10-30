import '../../data/models/stream_item.dart';

/// Detecta conteúdo 4K/UHD pelo nome, categoria ou URL.
///
/// Usado para escolher o player: no Android o 4K vai para o player de
/// hardware (MediaCodec -> Surface), que é o único caminho que renderiza
/// corretamente em TV boxes Allwinner; 1080p e canais seguem no mpv.
///
/// `2160` só vale com o "p" (`2160p`): senão um título como "Hotel 2160"
/// mandaria um filme comum para o player de hardware sem necessidade.
final RegExp uhdPattern = RegExp(
  r'(\b4k\b|\buhd\b|\b2160p\b|\bhevc\b|h\.?265|\bx265\b|\bav1\b|3840\s*[x×]\s*2160)',
  caseSensitive: false,
);

bool looksLikeUhd(StreamItem item) =>
    uhdPattern.hasMatch('${item.name} ${item.category} ${item.streamUrl}');
