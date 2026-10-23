import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The SQLCipher database key (user security request, 23 Oct 2026).
///
/// A random 256-bit key, generated once and kept in Android
/// Keystore-backed secure storage. It is never written into code,
/// preferences, backups, or logs — without it the database file is
/// indistinguishable from random bytes.
class DbKey {
  static const _storageKey = 'hisably_db_key_v1';
  static const _storage = FlutterSecureStorage();

  /// Returns the existing key, or creates and stores a new one.
  static Future<String> obtain() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null && existing.length == 64) return existing;
    final key = generate();
    await _storage.write(key: _storageKey, value: key);
    return key;
  }

  /// Deletes the stored key (full local wipe on sign-out). The
  /// next database created afterwards gets a fresh key.
  static Future<void> clear() async {
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {}
  }

  /// A fresh random 256-bit key as 64 lowercase hex characters.
  static String generate() {
    final rnd = Random.secure();
    return List<int>.generate(32, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
