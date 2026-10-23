import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, on-device user profile and app settings.
/// Nothing leaves the phone — registration is purely local storage.
///
/// PERSISTENCE (v0.6.2): the profile lives in a JSON file in the app's
/// documents directory — the Flutter cookbook file pattern, same as the
/// PIN. SharedPreferences (used before) flushes to disk asynchronously
/// on Android, so a profile "saved" there could vanish when the app
/// was cleared from RAM before the flush landed — the app then asked
/// for setup again on the next launch. A flushed file write is durable
/// the moment it returns. Legacy prefs data is migrated on first read.
class Profile {
  const Profile({required this.name, required this.languageCode});
  final String name;
  final String languageCode; // 'en' | 'ur'

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'H';
    if (parts.length == 1) return parts.first.characters.take(2).toUpperCase().toString();
    return (parts.first.characters.take(1).toString() +
            parts.last.characters.take(1).toString())
        .toUpperCase();
  }
}

class ProfileStore {
  static const _fileName = 'hisably_profile.json';
  static const _nameKey = 'profile_name';
  static const _langKey = 'profile_language';
  static const _themeKey = 'app_theme_mode'; // system|light|dark

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<Profile?> _readFile() async {
    final f = await _file();
    if (!await f.exists()) return null;
    final raw = (await f.readAsString()).trim();
    if (raw.isEmpty) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final name = (m['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return Profile(
      name: name,
      languageCode: (m['language'] as String?) ?? 'en',
    );
  }

  Future<void> _writeFile(Profile profile) async {
    final f = await _file();
    await f.writeAsString(
      jsonEncode({'name': profile.name, 'language': profile.languageCode}),
      flush: true,
    );
  }

  Future<Profile?> loadProfile() async {
    // 1) Durable file storage.
    try {
      final fromFile = await _readFile();
      if (fromFile != null) return fromFile;
    } catch (_) {
      // Fall through to the legacy store.
    }
    // 2) Legacy SharedPreferences — migrate to the file on sight.
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_nameKey);
      if (name != null && name.trim().isNotEmpty) {
        final profile = Profile(
          name: name,
          languageCode: prefs.getString(_langKey) ?? 'en',
        );
        try {
          await _writeFile(profile);
        } catch (_) {}
        return profile;
      }
    } catch (_) {}
    return null;
  }

  /// Saves the profile durably and verifies the write landed on disk
  /// (write → read back → retry once). Never throws: setup must not
  /// trap the user, and the read-back keeps a silent failure visible
  /// to the retry instead of to the user on the next launch.
  Future<void> saveProfile(Profile profile) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _writeFile(profile);
        final check = await _readFile();
        if (check != null && check.name == profile.name) return;
      } catch (_) {
        // Retry once, then give up quietly.
      }
    }
  }

  Future<ThemeMode> loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_themeKey)) {
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
        default:
          return ThemeMode.system;
      }
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, mode.name);
    } catch (_) {}
  }
}

final profileStoreProvider = Provider((ref) => ProfileStore());

final profileProvider = StateProvider<Profile?>((ref) => null);

final languageProvider = StateProvider<String>((ref) => 'en');

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Bumped whenever the locally stored Google profile photo changes,
/// so the Home avatar re-reads the file.
final profilePhotoTickProvider = StateProvider<int>((ref) => 0);

/// Incremented to make the app re-run its start-up gate (used
/// by sign-out: after the local wipe, the app must land back on
/// the setup screen as a fresh start).
final appResetNotifier = ValueNotifier<int>(0);

/// Bumped whenever a backup completes in the UI layer, so the
/// account card re-reads and re-displays the last-backup time.
final lastBackupTickProvider = StateProvider<int>((ref) => 0);
