import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drum_detector/main.dart';

void main() {
  testWidgets('App launches with home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: DrumDetectorApp()),
    );
    expect(find.text('Drum Detector'), findsOneWidget);
  });
}
