// Regressão do agrupamento "Adulto" e do PIN padrão (0000).
//
// Regra do produto: todos os canais/filmes/séries de categorias adultas ficam
// dentro de um único grupo "Adulto". Ao entrar nele aparecem as categorias
// originais do provedor como subcategorias. O PIN é pedido na primeira
// abertura de conteúdo adulto da sessão e, sem PIN configurado, vale 0000.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/network/api_client.dart';
import 'package:mcplayer/core/storage/storage_service.dart';
import 'package:mcplayer/core/utils/adult_content.dart';
import 'package:mcplayer/data/datasources/xtream_api.dart';
import 'package:mcplayer/data/models/stream_item.dart';
import 'package:mcplayer/presentation/controllers/iptv_controller.dart';
import 'package:mcplayer/presentation/screens/content_section/category_tree.dart';
import 'package:mcplayer/presentation/screens/content_section_screen.dart';
import 'package:mcplayer/presentation/widgets/adult_pin_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

StreamItem _item(String id, String name, String category, StreamType type) =>
    StreamItem(
      id: id,
      name: name,
      streamUrl: 'http://pro.exemplo.com/$id.mp4',
      category: category,
      streamType: type,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detecção de categoria adulta', () {
    test('reconhece os nomes usados pelos provedores', () {
      for (final name in [
        'XXX',
        'Adultos',
        'ADULTO',
        'Pornô',
        'PORNO',
        'Erótico',
        '+18',
        '18+',
        'FILMES | ADULTOS',
        'Séries | Hentai',
        'Canais adultos',
      ]) {
        expect(isAdultCategoryName(name), isTrue, reason: name);
      }
    });

    test('não marca categorias comuns como adultas', () {
      for (final name in [
        'Filmes | Ação',
        'Essex',
        'Hotel',
        'Documentários',
        'Infantil',
        'Sex Education',
        'Sex and the City',
        'Adult Swim',
        '',
      ]) {
        expect(isAdultCategoryName(name), isFalse, reason: name);
      }
    });
  });

  group('agrupamento "Adulto"', () {
    test('renomeia preservando a categoria original', () {
      expect(groupedAdultCategory('XXX'), 'Adulto | XXX');
      expect(groupedAdultCategory('  +18  '), 'Adulto | +18');
    });

    test('é idempotente e não duplica o prefixo', () {
      final once = groupedAdultCategory('XXX');
      expect(groupedAdultCategory(once), once);
      expect(isAdultCategory(once), isTrue);
      expect(categoryParent(once), 'Adulto');
    });

    test('displayCategoryName devolve o nome curto para o cartão', () {
      expect(displayCategoryName('Adulto | XXX'), 'XXX');
      expect(displayCategoryName('Filmes | Ação'), 'Filmes | Ação');
    });
  });

  group('PIN padrão', () {
    test('sem PIN configurado usa 0000', () {
      expect(adultPinOrDefault(null), '0000');
      expect(adultPinOrDefault(''), '0000');
      expect(adultPinOrDefault('   '), '0000');
      expect(adultPinOrDefault('12'), '0000');
      expect(adultPinOrDefault('abcd'), '0000');
    });

    test('PIN válido de 4 dígitos é respeitado', () {
      expect(adultPinOrDefault('1234'), '1234');
      expect(adultPinOrDefault(' 0001 '), '0001');
    });

    test('effectiveAdultPin lê do StorageService', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      expect(effectiveAdultPin(storage), '0000');
      await storage.setPin('4321');
      expect(effectiveAdultPin(storage), '4321');
    });
  });

  group('IptvController agrupa na carga', () {
    late IptvController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final apiClient = ApiClient();
      controller = IptvController(
        storageService: await StorageService.init(),
        apiClient: apiClient,
        xtreamApi: XtreamApi(apiClient.dio),
      );
      controller.debugLoadItems([
        _item('c1', 'Canal Adulto', 'XXX', StreamType.live),
        _item('c2', 'Canal Pornô', 'PORNO', StreamType.live),
        _item('c3', 'Notícias', 'Notícias', StreamType.live),
        _item('m1', 'Filme Adulto', '+18', StreamType.movie),
        _item('m2', 'Ação Total', 'Filmes | Ação', StreamType.movie),
        _item('s1', 'Série Adulta', 'Adultos', StreamType.series),
      ]);
    });

    test('TV ao vivo: categorias adultas viram "Adulto | ..."', () {
      final names = controller
          .getCategories(StreamType.live)
          .map((c) => c.name)
          .toList();
      expect(names, contains('Adulto | XXX'));
      expect(names, contains('Adulto | PORNO'));
      expect(names, contains('Notícias'));

      final tree = buildCategoryTree(controller.getCategories(StreamType.live));
      final adult = tree.where((n) => n.name == 'Adulto').toList();
      expect(adult, hasLength(1));
      expect(
        adult.first.leaves.map((l) => categorySubLabel(l.name)),
        containsAll(['XXX', 'PORNO']),
      );
    });

    test('filmes e séries seguem a mesma regra', () {
      final movies = controller
          .getCategories(StreamType.movie)
          .map((c) => c.name)
          .toList();
      expect(movies, contains('Adulto | +18'));
      expect(movies, contains('Filmes | Ação'));

      final series = controller
          .getCategories(StreamType.series)
          .map((c) => c.name)
          .toList();
      expect(series, contains('Adulto | Adultos'));

      // Os itens são reagrupados junto com a categoria (filtro por categoria
      // continua funcionando).
      final adultMovies = controller.getFilteredItems(
        StreamType.movie,
        selectedCategory: 'Adulto | +18',
      );
      expect(adultMovies.map((i) => i.id), contains('m1'));
      expect(adultMovies.map((i) => i.id), isNot(contains('m2')));
    });
  });

  testWidgets('Filmes: adulto vira grupo único e o cartão pede o PIN',
      (tester) async {
    resetAdultContentUnlocked();
    SharedPreferences.setMockInitialValues({});
    final apiClient = ApiClient();
    final controller = IptvController(
      storageService: await StorageService.init(),
      apiClient: apiClient,
      xtreamApi: XtreamApi(apiClient.dio),
    );
    controller.debugLoadItems([
      _item('m1', 'Filme Adulto', 'XXX', StreamType.movie),
      _item('m2', 'Ação Total', 'Filmes | Ação', StreamType.movie),
    ]);

    tester.view.physicalSize = const Size(1280, 720);
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

    // Um único grupo "Adulto" na coluna de categorias.
    expect(find.text('Adulto'), findsWidgets);
    expect(find.text('XXX'), findsNothing);

    await tester.tap(find.text('Adulto').first);
    await tester.pumpAndSettle();
    // Só agora a subcategoria original aparece.
    expect(find.text('XXX'), findsWidgets);

    await tester.tap(find.text('XXX').first);
    await tester.pumpAndSettle();
    expect(find.text('Filme Adulto'), findsOneWidget);

    // Abrir o filme adulto pede o PIN (padrão 0000).
    await tester.tap(find.text('Filme Adulto'));
    await tester.pumpAndSettle();
    expect(find.text('Conteúdo adulto'), findsOneWidget);
    expect(find.text('PIN padrão de fábrica: 0000'), findsOneWidget);

    // Cancelar não libera nem abre o player.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Conteúdo adulto'), findsNothing);
    expect(adultContentUnlocked, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
