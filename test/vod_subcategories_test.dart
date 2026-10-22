// Regression: provedores entregam categorias hierárquicas com "|"
// (ex.: "Filmes | Lancamentos"). A tela de Filmes/Séries no TV Box
// precisa mostrar CATEGORIAS e, ao escolher, as SUBCATEGORIAS, filtrando
// a grade. No celular a hierarquia vira duas faixas de chips.
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
  _movie('m1', 'Missão Impossível', 'Filmes | Ação'),
  _movie('m2', 'Gente Grande', 'Filmes | Comédia'),
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

  Future<void> pumpMovies(WidgetTester tester, Size size) async {
    controller.setSearchQuery('');
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: ContentSectionScreen(
          controller: controller,
          type: StreamType.movie,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets('TV: linha "Filmes" oculta, subcategorias primeiro e filtro',
      (tester) async {
    await pumpMovies(tester, const Size(1280, 720));
    expect(tester.takeException(), isNull);
    expect(find.text('CATEGORIAS'), findsOneWidget);
    // A linha "FILMES" foi removida: só resta o título da tela.
    expect(find.text('Filmes'), findsOneWidget);

    // As subcategorias já aparecem sem precisar escolher o pai "Filmes".
    expect(find.text('SUBCATEGORIAS'), findsOneWidget);
    expect(find.text('Ação'), findsOneWidget);
    expect(find.text('Comédia'), findsOneWidget);
    // Nenhum filme na grade antes de escolher a subcategoria.
    expect(find.text('Selecione uma subcategoria de filmes'), findsOneWidget);
    expect(find.text('Missão Impossível'), findsNothing);
    expect(find.text('Gente Grande'), findsNothing);

    // Escolhe "Ação" -> só o filme de ação fica.
    await tester.tap(find.text('Ação'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Missão Impossível'), findsOneWidget);
    expect(find.text('Gente Grande'), findsNothing);

    // "TODAS" libera o catálogo da categoria Filmes.
    await tester.tap(find.text('TODAS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Missão Impossível'), findsOneWidget);
    expect(find.text('Gente Grande'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Celular: navegação por níveis (Categorias -> Subcategorias -> Grade)',
      (tester) async {
    await pumpMovies(tester, const Size(360, 640));
    expect(tester.takeException(), isNull);
    // Na tela inicial, exibe as categorias como cards
    expect(find.text('Categorias'), findsOneWidget);
    expect(find.text('Filmes'), findsWidgets);

    // Toca no card "Filmes" para abrir subcategorias
    await tester.tap(find.text('Filmes').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('TODAS'), findsOneWidget);
    expect(find.text('Ação'), findsOneWidget);

    // Toca na subcategoria "Ação" para abrir o catálogo
    await tester.tap(find.text('Ação'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Missão Impossível'), findsOneWidget);
    expect(find.text('Gente Grande'), findsNothing);

    await unmount(tester);
  });
}
