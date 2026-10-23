import 'package:flutter_test/flutter_test.dart';
import 'package:hisably/data/auto_backup.dart';
import 'package:hisably/data/pin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build 2022: the Google identity is the app's own record, and
/// the biometric setting defaults safely.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('identity round-trips and clears', () async {
    expect(await AutoBackup.readIdentity(), isNull);
    await AutoBackup.saveIdentity(
        email: 'user@example.com',
        name: 'Test User',
        photoUrl: 'https://example.com/p.jpg');
    final id = await AutoBackup.readIdentity();
    expect(id?.email, 'user@example.com');
    expect(id?.name, 'Test User');
    expect(id?.photoUrl, 'https://example.com/p.jpg');
    await AutoBackup.clearIdentity();
    expect(await AutoBackup.readIdentity(), isNull);
  });

  test('identity keeps earlier fields when a refresh omits them',
      () async {
    await AutoBackup.saveIdentity(
        email: 'a@b.c', name: 'Name', photoUrl: 'https://x/y.jpg');
    await AutoBackup.saveIdentity(email: 'a@b.c');
    final id = await AutoBackup.readIdentity();
    expect(id?.name, 'Name');
    expect(id?.photoUrl, 'https://x/y.jpg');
  });

  test('biometric setting defaults ON and persists changes',
      () async {
    expect(await BiometricSetting.isEnabled(), isTrue);
    await BiometricSetting.setEnabled(false);
    expect(await BiometricSetting.isEnabled(), isFalse);
    await BiometricSetting.setEnabled(true);
    expect(await BiometricSetting.isEnabled(), isTrue);
  });
}
