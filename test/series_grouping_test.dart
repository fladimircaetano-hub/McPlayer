// Regression: provedores M3U que entregam 1 item por TEMPORADA
// ("Zatch Bell! 1".."Zatch Bell! 2", "Fairy Tail [LEG] 1/2") devem virar
// 1 cartão por série na grade/busca (TV e celular). Temporadas e episódios
// só aparecem depois do clique. "Ben 10" sozinho NÃO pode fundir em "Ben".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/network/api_client.dart';
import 'package:mcplayer/core/storage/storage_service.dart';
import 'package:mcplayer/data/datasources/xtream_api.dart';
import 'package:mcplayer/data/models/stream_item.dart';
import 'package:mcplayer/presentation/controllers/iptv_controller.dart';
import 'package:mcplayer/presentation/screens/content_section_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

StreamItem _ep(String id, String name) => StreamItem(
      id: id,
      name: name,
      streamUrl: 'http://pro.exemplo.com/series/$id.mp4',
      category: 'ANIMES (DUB)',
      streamType: StreamType.series,
    );

final _items = [
  // Base (série completa) + 2 temporadas avulsas, 2 eps cada.
  _ep('zb0e1', 'Zatch Bell! EP01'),
  _ep('zb0e2', 'Zatch Bell! EP02'),
  _ep('zb1e1', 'Zatch Bell! 1 EP01'),
  _ep('zb1e2', 'Zatch Bell! 1 EP02'),
  _ep('zb2e1', 'Zatch Bell! 2 EP01'),
  _ep('zb2e2', 'Zatch Bell! 2 EP02'),
  // Tags [LEG] + temporadas avulsas.
  _ep('ft0e1', 'Fairy Tail [LEG] EP01'),
  _ep('ft1e1', 'Fairy Tail [LEG] 1 EP01'),
  _ep('ft2e1', 'Fairy Tail [LEG] 2 EP01'),
  // Número no nome mas é série única: não funde em "Ben".
  _ep('b10e1', 'Ben 10 EP01'),
  _ep('b10e2', 'Ben 10 EP02'),
];

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
    controller.debugLoadItems(_items);
  });

  /// Monta a tela de Séries no viewport e roda [checks] COM ela montada;
  /// depois desmonta (cancela timers da tela).
  Future<void> pumpSeries(
    WidgetTester tester,
    Size size,
    void Function() checks,
  ) async {
    controller.setSearchQuery('');
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ContentSectionScreen(
          controller: controller,
          type: StreamType.series,
        ),
      ),
    );
    await tester.pumpAndSettle();
    checks();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  group('Séries compactadas', () {
    testWidgets('celular retrato: 1 linha por série', (tester) async {
      await pumpSeries(tester, const Size(360, 640), () {
        expect(tester.takeException(), isNull);
        // 11 episódios viram 3 séries (antes: 6 cartões).
        expect(find.text('Zatch Bell'), findsOneWidget);
        expect(find.text('6 episódios'), findsOneWidget);
        expect(find.text('Fairy Tail'), findsOneWidget);
        expect(find.text('3 episódios'), findsOneWidget);
        expect(find.text('Ben 10'), findsOneWidget);
        // Nenhuma temporada avulsa na lista.
        expect(find.textContaining('Zatch Bell!'), findsNothing);
        expect(find.textContaining('[LEG]'), findsNothing);
      });

      // Busca mostra só a série (sem temporadas/episódios).
      await tester.pumpWidget(
        MaterialApp(
          home: ContentSectionScreen(
            controller: controller,
            type: StreamType.series,
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.setSearchQuery('zatch');
      await tester.pumpAndSettle();
      expect(find.text('Zatch Bell'), findsOneWidget);
      expect(find.textContaining('Zatch Bell!'), findsNothing);
      controller.setSearchQuery('');
      await tester.pumpAndSettle();

      // Clique abre temporadas, depois episódios.
      await tester.tap(find.text('Zatch Bell'));
      await tester.pumpAndSettle();
      expect(find.text('Temporada 1'), findsOneWidget);
      expect(find.text('Temporada 2'), findsOneWidget);
      await tester.tap(find.text('Temporada 2'));
      await tester.pumpAndSettle();
      expect(find.text('Zatch Bell! 2 EP01'), findsOneWidget);
      expect(find.text('Zatch Bell! 2 EP02'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('TV (grade de pôsteres): 1 cartão por série', (tester) async {
      await pumpSeries(tester, const Size(1280, 720), () {
        expect(tester.takeException(), isNull);
        expect(find.text('Zatch Bell'), findsOneWidget);
        expect(find.text('Fairy Tail'), findsOneWidget);
        expect(find.text('Ben 10'), findsOneWidget);
        expect(find.textContaining('Zatch Bell!'), findsNothing);
      });
    });
  });
}
