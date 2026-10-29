import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washa/models/channel.dart';
import 'package:washa/screens/categories_screen.dart';

void main() {
  testWidgets('category tiles do not overflow on a phone', (tester) async {
    final overflows = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) overflows.add(details);
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoriesScreen(
            premium: false,
            channels: const [
              Channel(
                id: 1,
                name: 'Azam',
                premium: false,
                imageUrl: '',
                live: true,
                category: 'Sports',
              ),
            ],
            onOpenPlayer: _noop,
            onOpenSubscription: _noopVoid,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('channeli'), findsWidgets);
    expect(overflows, isEmpty);
  });
}

void _noop(Channel _) {}

void _noopVoid() {}
