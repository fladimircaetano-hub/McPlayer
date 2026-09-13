import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/core/theme/app_theme.dart';
import 'package:mcplayer/presentation/widgets/tv_focusable.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Color? borderColor(WidgetTester tester) {
    final container =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final decoration = container.decoration as BoxDecoration?;
    return (decoration?.border as Border?)?.top.color;
  }

  testWidgets('troca de focusNode externo reconecta o listener',
      (WidgetTester tester) async {
    final nodeA = FocusNode();
    final nodeB = FocusNode();
    addTearDown(nodeA.dispose);
    addTearDown(nodeB.dispose);

    Future<void> pumpWith(FocusNode node) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvFocusable(
              focusNode: node,
              onPressed: () {},
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWith(nodeA);
    nodeA.requestFocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(borderColor(tester), AppColors.primary);

    // Troca o nó: sem didUpdateWidget, o foco em B seria ignorado
    // (listener preso ao nó antigo) e o foco em A ainda rebuildaria.
    await pumpWith(nodeB);
    nodeB.requestFocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(borderColor(tester), AppColors.primary,
        reason: 'novo focusNode precisa comandar o highlight');

    // Nó antigo fora da árvore não pode mais comandar o highlight:
    // desfoca tudo e foca A (destacado) — a borda deve permanecer apagada.
    // Com o bug (listener preso ao nó antigo), focar A reacenderia a borda.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(borderColor(tester), Colors.transparent);
    nodeA.requestFocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(borderColor(tester), Colors.transparent,
        reason: 'nó antigo não pode mais comandar o highlight');
  });
}
