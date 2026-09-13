import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/data/models/stream_item.dart';
import 'package:mcplayer/presentation/widgets/stream_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StreamItem liveSample() => StreamItem(
        id: 'globo.br',
        name: 'TV Globo HD',
        streamUrl: 'http://stream.exemplo.com/live/globo.m3u8',
        category: 'Canais Abertos',
        streamType: StreamType.live,
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required VoidCallback onTap,
    required VoidCallback onToggleFavorite,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamCard(
            item: liveSample(),
            onTap: onTap,
            onToggleFavorite: onToggleFavorite,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('StreamCard', () {
    testWidgets('toque na estrela favorita SEM abrir o stream',
        (WidgetTester tester) async {
      var taps = 0;
      var favs = 0;
      await pumpCard(
        tester,
        onTap: () => taps++,
        onToggleFavorite: () => favs++,
      );

      await tester.tap(find.byIcon(Icons.star_outline_rounded));
      await tester.pump(const Duration(milliseconds: 500));

      expect(favs, 1);
      expect(taps, 0,
          reason: 'InkWell aninhado não pode propagar o tap ao card');
    });

    testWidgets('toque no corpo do card abre o stream',
        (WidgetTester tester) async {
      var taps = 0;
      var favs = 0;
      await pumpCard(
        tester,
        onTap: () => taps++,
        onToggleFavorite: () => favs++,
      );

      await tester.tap(find.text('TV Globo HD'));
      await tester.pump();

      expect(taps, 1);
      expect(favs, 0);
    });
  });
}
