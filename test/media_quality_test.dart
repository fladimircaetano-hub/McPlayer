import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/utils/media_quality.dart';
import 'package:mcplayer/data/models/stream_item.dart';

StreamItem _item(String name, {String category = 'FILMES', String? url}) {
  return StreamItem(
    id: name,
    name: name,
    streamUrl: url ?? 'https://exemplo.com/stream/$name.mkv',
    category: category,
    streamType: StreamType.movie,
  );
}

void main() {
  group('looksLikeUhd', () {
    test('reconhece resolução 4K/UHD no nome', () {
      expect(looksLikeUhd(_item('Duna 2021 4K')), isTrue);
      expect(looksLikeUhd(_item('Duna [UHD]')), isTrue);
      expect(looksLikeUhd(_item('Duna 2160p')), isTrue);
      expect(looksLikeUhd(_item('Duna 3840x2160')), isTrue);
    });

    test('reconhece codecs de alta compressão usados no 4K', () {
      expect(looksLikeUhd(_item('Duna HEVC')), isTrue);
      expect(looksLikeUhd(_item('Duna H.265')), isTrue);
      expect(looksLikeUhd(_item('Duna x265')), isTrue);
      expect(looksLikeUhd(_item('Duna AV1')), isTrue);
    });

    test('reconhece 4K na categoria ou na URL da lista', () {
      expect(looksLikeUhd(_item('Duna', category: 'FILMES 4K')), isTrue);
      expect(
        looksLikeUhd(
          _item('Duna', url: 'https://exemplo.com/4k/duna.mkv'),
        ),
        isTrue,
      );
    });

    test('não confunde conteúdo Full HD com 4K', () {
      expect(looksLikeUhd(_item('Duna 1080p')), isFalse);
      expect(looksLikeUhd(_item('Duna H.264')), isFalse);
      expect(looksLikeUhd(_item('Canal 4Kids')), isFalse);
      expect(looksLikeUhd(_item('Hotel 2160')), isFalse);
    });
  });
}
