// Regression: TV ao vivo em telas grandes (TV Box/Fire TV/Smart TV) usa o
// layout dividido e navega por subcategorias, recolhendo a coluna de
// categorias. Um celular em paisagem (largura alta, altura baixa) NÃO deve
// ser confundido com TV e precisa continuar no layout mobile.
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

  testWidgets('TV 1280x720: layout dividido com categorias e canais', (
    tester,
  ) async {
    await pumpGuide(tester, const Size(1280, 720));
    expect(tester.takeException(), isNull);

    // Colunas da TV e ausência da navegação mobile.
    expect(find.text('CATEGORIAS'), findsOneWidget);
    expect(find.text('CANAIS'), findsOneWidget);
    expect(find.byKey(const Key('live-mobile-nav')), findsNothing);

    // A categoria inicial (ABERTOS, primeira em ordem alfabética) já tem
    // seus canais exibidos na coluna central.
    expect(find.text('TV Globo HD'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('TV: grupo com subcategorias recolhe categorias e abre subs', (
    tester,
  ) async {
    await pumpGuide(tester, const Size(1280, 720));
    expect(tester.takeException(), isNull);

    // "CANAIS" tem duas subcategorias.
    await tester.tap(find.text('CANAIS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('live-subcategory-col')), findsOneWidget);
    expect(
      find.byKey(const Key('live-collapsed-category-rail')),
      findsOneWidget,
    );
    expect(find.text('INFANTIS 24H'), findsOneWidget);
    expect(find.text('ALT'), findsOneWidget);

    // Subcategoria filtra os canais.
    await tester.tap(find.text('INFANTIS 24H'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cartoon 24h'), findsWidgets);
    expect(find.text('Canal Alt'), findsNothing);

    await unmount(tester);
  });

  testWidgets('TV: trilho recolhido reabre as categorias', (tester) async {
    await pumpGuide(tester, const Size(1280, 720));

    await tester.tap(find.text('CANAIS'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-subcategory-col')), findsOneWidget);

    // Clicar no trilho recolhido devolve a coluna de categorias.
    await tester.tap(find.byKey(const Key('live-collapsed-category-rail')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('live-subcategory-col')), findsNothing);
    expect(find.byKey(const Key('live-collapsed-category-rail')), findsNothing);
    expect(find.text('CATEGORIAS'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('TV: botão voltar das subcategorias reabre categorias', (
    tester,
  ) async {
    await pumpGuide(tester, const Size(1280, 720));

    await tester.tap(find.text('CANAIS'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-subcategory-col')), findsOneWidget);

    // Cabeçalho das subcategorias tem a seta de voltar.
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('live-subcategory-col')), findsNothing);
    expect(find.text('CATEGORIAS'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('celular em paisagem 915x412 mantém layout mobile', (
    tester,
  ) async {
    await pumpGuide(tester, const Size(915, 412));
    expect(tester.takeException(), isNull);

    // Largura >= 900, mas altura de celular: continua mobile.
    expect(find.byKey(const Key('live-mobile-nav')), findsOneWidget);
    expect(find.text('Categorias'), findsOneWidget);
    expect(find.byKey(const Key('live-subcategory-col')), findsNothing);
    expect(find.byKey(const Key('live-collapsed-category-rail')), findsNothing);

    await unmount(tester);
  });
}
