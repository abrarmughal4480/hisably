import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/auto_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The first-sign-in import offer must appear exactly once per
/// device (user feature, build 2019).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first-sign-in flag starts unset, then sticks', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AutoBackup.firstSignInSeen(), isFalse);
    await AutoBackup.markFirstSignInSeen();
    expect(await AutoBackup.firstSignInSeen(), isTrue);
  });
}
