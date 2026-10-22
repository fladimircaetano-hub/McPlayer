// Regression: Filmes/Séries no TV Box (Fire TV) precisam expor a coluna
// de CATEGORIAS. O refactor de content_section removeu a barra lateral
// do VOD e a tela ia direto para o catálogo. Este teste garante que a
// categoria continua acessível (TV e celular) e que filtra a grade.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/network/api_client.dart';
import 'package:mcplayer/core/storage/storage_service.dart';
import 'package:mcplayer/data/datasources/xtream_api.dart';
import 'package:mcplayer/data/models/stream_item.dart';
import 'package:mcplayer/presentation/controllers/iptv_controller.dart';
import 'package:mcplayer/presentation/screens/content_section_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

StreamItem _movie(String id, String name, String category) => StreamItem(
      id: id,
      name: name,
      streamUrl: 'http://pro.exemplo.com/movie/$id.mp4',
      category: category,
      streamType: StreamType.movie,
    );

final _items = [
  _movie('m1', 'Missão Impossível', 'Ação'),
  _movie('m2', 'Velozes e Furiosos', 'Ação'),
  _movie('m3', 'Gente Grande', 'Comédia'),
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

  Future<void> pumpMovies(
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
          type: StreamType.movie,
        ),
      ),
    );
    await tester.pumpAndSettle();
    checks();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('TV: coluna CATEGORIAS visível e filtra a grade após seleção',
      (tester) async {
    await pumpMovies(tester, const Size(1280, 720), () {
      expect(tester.takeException(), isNull);
      // Coluna de categorias visível
      expect(find.text('CATEGORIAS'), findsOneWidget);
      expect(find.text('TODOS'), findsWidgets);
      expect(find.text('Ação'), findsWidgets);
      expect(find.text('Comédia'), findsWidgets);
      // Estado inicial orienta seleção antes de abrir o catálogo
      expect(find.text('Selecione uma categoria de filmes'), findsOneWidget);
    });

    // Filtra por Ação: a grade é exibida com apenas os filmes de Ação
    await tester.pumpWidget(
      MaterialApp(
        home: ContentSectionScreen(
          controller: controller,
          type: StreamType.movie,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ação').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Missão Impossível'), findsOneWidget);
    expect(find.text('Gente Grande'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Celular: navegação de categorias exibe cards e abre catálogo', (tester) async {
    await pumpMovies(tester, const Size(360, 640), () {
      expect(tester.takeException(), isNull);
      expect(find.text('Categorias'), findsOneWidget);
      expect(find.text('Ação'), findsOneWidget);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ContentSectionScreen(
          controller: controller,
          type: StreamType.movie,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ação'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Missão Impossível'), findsOneWidget);
    expect(find.text('Gente Grande'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
