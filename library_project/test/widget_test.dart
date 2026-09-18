import 'package:flutter_test/flutter_test.dart';
import 'package:library_project/src/library_login_page.dart';
import 'package:library_project/src/reader_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders reader start screen', (tester) async {
    await tester.pumpWidget(const ReaderApp());
    await tester.pumpAndSettle();

    expect(find.byType(LibraryLoginPage), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
  });
}
