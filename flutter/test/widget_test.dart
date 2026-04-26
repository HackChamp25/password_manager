import 'package:flutter_test/flutter_test.dart';
import 'package:secure_password_manager/main.dart';

void main() {
  testWidgets('App loads login shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.textContaining('Vault'), findsWidgets);
  });
}
