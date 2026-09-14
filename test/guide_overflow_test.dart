// Regression: guia mobile não pode estourar (BOTTOM OVERFLOWED) em
// telas pequenas, com ou sem logo nos canais.
// Parseia M3U de verdade (sem rede), injeta no controller e monta a
// ContentSectionScreen em 3 viewports. Overflow de RenderFlex é
// reportado ao FlutterError: takeException() captura.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/network/api_client.dart';
import 'package:mcplayer/core/parser/m3u_parser.dart';
import 'package:mcplayer/core/storage/storage_service.dart';
import 'package:mcplayer/data/datasources/xtream_api.dart';
import 'package:mcplayer/data/models/stream_item.dart';
import 'package:mcplayer/presentation/controllers/iptv_controller.dart';
import 'package:mcplayer/presentation/screens/content_section_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _m3u = '''
#EXTM3U
#EXTINF:-1 tvg-id="globo.br" group-title="Abertos",TV Globo HD
http://pro.exemplo.com/u/p/1001.m3u8
#EXTINF:-1 tvg-id="sbt.br" group-title="Abertos",SBT HD
http://pro.exemplo.com/u/p/1002.m3u8
#EXTINF:-1 tvg-id="espn.br" group-title="Esportes",ESPN HD
http://pro.exemplo.com/u/p/1003.m3u8
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late IptvController controller;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final apiClient = ApiClient();
    controller = IptvController(
      storageService: await StorageService.init(),
      apiClient: apiClient,
      xtreamApi: XtreamApi(apiClient.dio),
    );
    final items = await M3uParser.parseM3u(_m3u);
    assert(items.length == 3, 'parser deveria extrair 3 canais');
    controller.debugLoadItems(items);
    assert(controller.totalLiveCount == 3);
  });

  /// Monta a guia no viewport, roda as verificações COM a tela montada
  /// e só então desmonta (cancela o relógio da tela, timer periódico).
  Future<void> pumpGuide(
    WidgetTester tester,
    Size size,
    void Function() checks,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ContentSectionScreen(
          controller: controller,
          type: StreamType.live,
        ),
      ),
    );
    await tester.pumpAndSettle();
    checks();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  group('Guia mobile sem overflow', () {
    testWidgets('portrait pequeno 360x640', (tester) async {
      await pumpGuide(tester, const Size(360, 640), () {
        expect(tester.takeException(), isNull);
        expect(find.textContaining('TV Globo HD'), findsWidgets);
        expect(find.text('Assistir'), findsWidgets);
      });
    });

    testWidgets('portrait curto 360x500', (tester) async {
      await pumpGuide(tester, const Size(360, 500), () {
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('landscape 700x360', (tester) async {
      await pumpGuide(tester, const Size(700, 360), () {
        expect(tester.takeException(), isNull);
      });
    });
  });
}
