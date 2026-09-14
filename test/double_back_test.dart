import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcplayer/presentation/widgets/double_back_to_exit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller: 1º toque avisa, 2º confirma', () {
    final c = DoubleBackController();
    expect(c.registerPress(), isFalse);
    expect(c.registerPress(), isTrue);
  });

  testWidgets('1º voltar avisa e permanece; não dá pop',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DoubleBackToExit(
          child: Scaffold(body: Text('Playlist')),
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Pressione voltar novamente para sair'),
        findsOneWidget);
    expect(find.text('Playlist'), findsOneWidget);
  });
}
