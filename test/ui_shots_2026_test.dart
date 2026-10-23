/// Build 2026 documentation screenshots — the real app UI rendered
/// at full phone resolution (1080x2340 @ 3x) with sample data only.
/// No real account data appears in any shot: the signed-in card
/// uses a placeholder identity, as the documentation rules require.
///
/// Run: flutter test test/ui_shots_2026_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hisably/data/auto_backup.dart';
import 'package:hisably/data/pin_service.dart';
import 'package:hisably/screens/lock_screen.dart';
import 'package:hisably/screens/registration_screen.dart';
import 'package:hisably/theme/hisably_theme.dart';
import 'package:hisably/widgets/google_account_card.dart';

Future<void> _loadFonts() async {
  final families = <String, List<String>>{
    'Sora': ['Sora-600.ttf', 'Sora-700.ttf', 'Sora-800.ttf'],
    'Manrope': ['Manrope-600.ttf', 'Manrope-700.ttf', 'Manrope-800.ttf'],
    'Inter': ['Inter-400.ttf', 'Inter-500.ttf', 'Inter-600.ttf', 'Inter-700.ttf'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  final roboto = FontLoader('Roboto');
  roboto.addFont(Future.value(ByteData.view(File(
          '/home/hatch/flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
      .readAsBytesSync()
      .buffer)));
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(Future.value(ByteData.view(File(
          '/home/hatch/flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
      .readAsBytesSync()
      .buffer)));
  await icons.load();
}

const _shotDir = '../../reports/build-2026/shots';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
    Directory('reports/build-2026/shots').createSync(recursive: true);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: HisablyTheme.app(lang: 'en'),
          home: home,
        ),
      );

  testWidgets('shot: setup step 2 — name + Continue with Google', (tester) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(app(RegistrationScreen(onDone: () {})));
    await tester.pump();
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Continue with Google'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_shotDir/ui-setup-google.png'));
  });

  testWidgets('shot: Google card — signed out', (tester) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(app(const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: GoogleAccountCard(),
      ),
    )));
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_shotDir/ui-card-signed-out.png'));
  });

  testWidgets('shot: Google card — signed in, backup time shown',
      (tester) async {
    phone(tester);
    final backupAt = DateTime(2026, 10, 23, 16, 45);
    SharedPreferences.setMockInitialValues({
      AutoBackup.googleNameKey: 'Test User',
      AutoBackup.googleEmailKey: 'user@example.com',
      AutoBackup.lastBackupKey: backupAt.millisecondsSinceEpoch,
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(app(const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: GoogleAccountCard(),
        ),
      )));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    // The label's read restarts on each rebuild, so give it a
    // second settle cycle before asserting and capturing.
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    expect(find.textContaining('Last Drive backup'), findsOneWidget);
    expect(find.textContaining('4:45 PM'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_shotDir/ui-card-signed-in.png'));

    // The sign-out confirmation, same session.
    await tester.tap(find.text('Sign out'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sign out and reset?'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_shotDir/ui-sign-out-dialog.png'));
  });

  testWidgets('shot: lock screen', skip: true, (tester) async {
    phone(tester);
    final dir = await Directory.systemTemp.createTemp('hisably_shots_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir.path;
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => PinService().setPin('1234'));
    await tester.pumpWidget(app(LockScreen(onUnlocked: () {})));
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_shotDir/ui-lock-screen.png'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
