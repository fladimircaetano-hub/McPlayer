// Regression: no celular a TV ao vivo precisa navegar em níveis
// (Categorias -> Subcategorias -> Canais), sem despejar todos os canais na
// tela inicial, com prévia ao vivo em 1/3 e navegação rolável em 2/3.
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
#EXTINF:-1 tvg-id="cartoon.br" group-title="CANAIS | INFANTIS 24H",Cartoon 24h
http://pro.exemplo.com/u/p/2001.m3u8
#EXTINF:-1 tvg-id="alt.br" group-title="CANAIS | ALT",Canal Alt
http://pro.exemplo.com/u/p/2002.m3u8
#EXTINF:-1 tvg-id="globo.br" group-title="ABERTOS",TV Globo HD
http://pro.exemplo.com/u/p/2003.m3u8
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
    controller.debugLoadItems(items);
  });

  Future<void> pumpGuide(WidgetTester tester, Size size) async {
    controller.setSearchQuery('');
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
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('retrato: categorias -> subcategorias -> canais e prévia 1/3',
      (tester) async {
    await pumpGuide(tester, const Size(360, 640));
    expect(tester.takeException(), isNull);

    // Tela inicial: só categorias, nenhum canal.
    expect(find.text('Categorias'), findsOneWidget);
    expect(find.text('CANAIS'), findsOneWidget);
    expect(find.text('ABERTOS'), findsOneWidget);
    expect(find.text('Cartoon 24h'), findsNothing);
    expect(find.text('Canal Alt'), findsNothing);

    // Prévia em cima ocupa ~1/3; navegação embaixo ~2/3.
    final previewSize =
        tester.getSize(find.byKey(const Key('live-mobile-preview')));
    final navSize = tester.getSize(find.byKey(const Key('live-mobile-nav')));
    expect(previewSize.height / navSize.height, closeTo(0.5, 0.08));

    // Categoria com hierarquia -> subcategorias (sem canais).
    await tester.tap(find.text('CANAIS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('INFANTIS 24H'), findsOneWidget);
    expect(find.text('ALT'), findsOneWidget);
    expect(find.text('Cartoon 24h'), findsNothing);
    expect(find.text('Canal Alt'), findsNothing);

    // Subcategoria -> canais daquela subcategoria.
    await tester.tap(find.text('INFANTIS 24H'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cartoon 24h'), findsOneWidget);
    expect(find.text('Canal Alt'), findsNothing);

    // Escolher o canal atualiza a prévia (sem abrir o player).
    await tester.tap(find.text('Cartoon 24h'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cartoon 24h'), findsNWidgets(2));
    expect(find.text('Assistir'), findsOneWidget);
    expect(find.text('Prévia ao vivo'), findsOneWidget);

    // Voltar: canais -> subcategorias -> categorias.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('INFANTIS 24H'), findsOneWidget);
    expect(find.text('Cartoon 24h'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Categorias'), findsOneWidget);
    expect(find.text('CANAIS'), findsOneWidget);
    expect(find.text('INFANTIS 24H'), findsNothing);

    await unmount(tester);
  });

  testWidgets('paisagem: prévia à esquerda e navegação à direita',
      (tester) async {
    await pumpGuide(tester, const Size(700, 360));
    expect(tester.takeException(), isNull);

    expect(find.text('Categorias'), findsOneWidget);
    final previewSize =
        tester.getSize(find.byKey(const Key('live-mobile-preview')));
    final navSize = tester.getSize(find.byKey(const Key('live-mobile-nav')));
    expect(previewSize.width / navSize.width, closeTo(4 / 6, 0.1));

    await tester.tap(find.text('CANAIS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('INFANTIS 24H'), findsOneWidget);

    await tester.tap(find.text('INFANTIS 24H'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cartoon 24h'), findsOneWidget);

    await unmount(tester);
  });
}
