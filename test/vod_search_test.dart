// Regression: com a navegação por níveis, a busca precisa furar a
// hierarquia e mostrar resultados sem exigir que o usuário escolha uma
// categoria antes. Antes, digitar na tela inicial mantinha o aviso
// "Selecione uma categoria".
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
    controller.debugLoadItems([
      _movie('m1', 'Missão Impossível', 'Filmes | Ação'),
      _movie('m2', 'Gente Grande', 'Filmes | Comédia'),
    ]);
  });

  testWidgets('TV: busca mostra resultados sem escolher categoria',
      (tester) async {
    controller.setSearchQuery('');
    tester.view.physicalSize = const Size(1280, 720);
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
    expect(find.text('Selecione uma subcategoria de filmes'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Missão');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Missão Impossível'), findsOneWidget);
    expect(find.text('Gente Grande'), findsNothing);
    expect(find.text('Selecione uma subcategoria de filmes'), findsNothing);

    controller.setSearchQuery('');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
