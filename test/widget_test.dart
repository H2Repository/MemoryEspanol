import 'package:flutter_test/flutter_test.dart';

import 'package:memoryespanol/main.dart';

void main() {
  testWidgets('StudyScreen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MemoryEspanolApp());

    // Verify app title or widgets are present
    expect(find.text('단어학습 (집중모드)'), findsOneWidget);
  });
}
