import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional app PIN. Only a salted SHA-256 hash is stored — never the
/// PIN itself.
///
/// Storage follows Flutter's official persistence cookbook: a small
/// file in the app's documents directory via path_provider
/// (docs.flutter.dev/cookbook/persistence/reading-writing-files).
/// App-specific storage needs no permission and — unlike the platform
/// keystore used before — cannot stall on devices whose keystore
/// service hangs (the Sharp AQUOS R7 "stuck at PIN" bug, v0.6).
class PinService {
  static const _fileName = 'hisably_pin.hash';

  String _hash(String pin) =>
      sha256.convert(utf8.encode('hisably::$pin')).toString();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<String?> _read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final v = (await f.readAsString()).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isPinSet() async => (await _read()) != null;

  Future<void> setPin(String pin) async {
    try {
      final f = await _file();
      await f.writeAsString(_hash(pin), flush: true);
    } catch (_) {
      // A failed PIN save must never block the user.
    }
  }

  Future<void> removePin() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<bool> verify(String pin) async {
    final stored = await _read();
    return stored != null && stored == _hash(pin);
  }
}

/// Whether biometric (fingerprint) unlock is switched on. The
/// setup wizard asks once — only when the device actually has
/// biometrics (user request, 23 Oct 2026) — and the lock screen
/// honours the choice. Default ON preserves the behaviour of
/// installs made before the setting existed.
class BiometricSetting {
  static const _key = 'biometric_enabled';

  static Future<bool> isEnabled() async {
    // Never throws: a preferences failure must not break the
    // lock screen (on-device failure, 23 Oct 2026). Default ON.
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}
