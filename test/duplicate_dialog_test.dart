import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/utils/duplicates.dart';
import 'package:mcplayer/data/models/stream_item.dart';
import 'package:mcplayer/presentation/widgets/duplicate_report_dialog.dart';

StreamItem _item(String id) => StreamItem(
      id: id,
      name: 'Filme (2022)',
      streamUrl: 'https://exemplo.com/$id.mp4',
      category: 'TESTE',
      streamType: StreamType.movie,
      releaseDate: '2022',
    );

void main() {
  testWidgets('relatório mostra resumo, detalhes e devolve a escolha',
      (tester) async {
    final scan = scanCatalogDuplicates([
      _item('a'),
      _item('b'),
      _item('c'),
    ]);
    expect(scan.report.removedCount, 2);

    DuplicateAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDuplicateReportDialog(
                    ctx,
                    report: scan.report,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Repetidos encontrados'), findsOneWidget);
    expect(find.textContaining('2 item(ns) repetido(s)'), findsOneWidget);
    expect(find.textContaining('2 filme(s)'), findsOneWidget);

    await tester.tap(find.textContaining('Ver detalhes'));
    await tester.pumpAndSettle();
    expect(find.text('Ocultar detalhes'), findsOneWidget);
    expect(find.textContaining('remover 2 cópia'), findsWidgets);

    await tester.tap(find.text('Remover repetidos'));
    await tester.pumpAndSettle();
    expect(result, DuplicateAction.remove);
  });

  testWidgets('manter tudo devolve keep', (tester) async {
    final scan = scanCatalogDuplicates([_item('a'), _item('b')]);
    DuplicateAction? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDuplicateReportDialog(
                    ctx,
                    report: scan.report,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manter tudo'));
    await tester.pumpAndSettle();
    expect(result, DuplicateAction.keep);
  });
}
