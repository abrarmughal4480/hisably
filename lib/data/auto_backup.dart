import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'backup_service.dart';
import 'database.dart';
import 'db_key.dart';
import 'pin_service.dart';
import 'drive_backup.dart';
import 'google_auth.dart';

/// Background entry point for the daily backup task. Must be a
/// top-level function and stay annotation-marked so release
/// (obfuscated) builds keep it reachable.
@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == AutoBackup.taskName) {
      return AutoBackup.runInBackground();
    }
    return true;
  });
}

/// Automatic Google Drive backups (user feature, 23 Oct 2026):
///
/// * a daily WorkManager job that only runs with internet
///   (NetworkType.connected) — no internet means Android holds the
///   job and fires it as soon as connectivity returns, which is
///   exactly the "catch up immediately" behaviour the user asked
///   for;
/// * an app-open catch-up: if the last backup is over 20 hours old,
///   opening the app backs up right away;
/// * a local notification after every successful automatic backup.
/// What a fresh sign-in should do about Drive vs device data.
enum SyncDecision { uploadFirst, autoRestore, conflict }

class AutoBackup {
  static const taskName = 'hisably.dailyBackup';
  static const _uniqueName = 'hisably-daily-backup';
  static const lastBackupKey = 'last_backup_at_ms';
  static const googleEmailKey = 'google_email';
  static const firstSignInSeenKey = 'first_google_signin_seen';

  /// Whether the first-sign-in import offer has been shown on this
  /// device (user feature: the offer appears exactly once).
  static Future<bool> firstSignInSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(firstSignInSeenKey) ?? false;
    } catch (_) {
      return true; // never let a prefs failure break sign-in
    }
  }

  static Future<void> markFirstSignInSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(firstSignInSeenKey, true);
    } catch (_) {}
  }

  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notifReady = false;

  static Future<void> initNotifications() async {
    if (_notifReady) return;
    try {
      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_h'),
        ),
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'hisably_backup',
            'Backups',
            description: 'Shown when an automatic backup completes.',
            importance: Importance.defaultImportance,
          ));
      _notifReady = true;
    } catch (_) {
      // Notifications are a courtesy, never a blocker.
    }
  }

  static Future<void> requestNotificationPermission() async {
    await initNotifications();
    try {
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Registers the daily job. Safe to call repeatedly.
  static Future<void> schedule() async {
    try {
      await Workmanager().initialize(backupCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        taskName,
        frequency: const Duration(hours: 24),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // The app-open catch-up still covers backups if the
      // background scheduler is unavailable on a device.
    }
  }

  /// The last successful backup in THIS process. Belt and braces
  /// beside the stored value: the card's "Last Drive backup" line
  /// can never be stale in the session that took the backup.
  static DateTime? _lastRunAt;

  /// The sign-in data decision, as a pure function so every branch
  /// is testable: no Drive backup yet -> upload this device's data;
  /// backup exists and this device is empty -> restore it; both
  /// sides hold data -> ask the user (with a double confirmation).
  static SyncDecision decideSync({
    required bool driveHasBackup,
    required int localTransactions,
  }) {
    if (!driveHasBackup) return SyncDecision.uploadFirst;
    if (localTransactions == 0) return SyncDecision.autoRestore;
    return SyncDecision.conflict;
  }

  static Future<DateTime?> lastBackupAt() async {
    DateTime? stored;
    try {
      final prefs = await SharedPreferences.getInstance();
      // The daily background backup runs in its own isolate and
      // writes this value there; reload so a live foreground
      // cache can never show a stale "never" (bug, 23 Oct 2026).
      await prefs.reload();
      final ms = prefs.getInt(lastBackupKey);
      stored = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}
    final mem = _lastRunAt;
    if (mem == null) return stored;
    if (stored == null) return mem;
    return mem.isAfter(stored) ? mem : stored;
  }

  /// Signed in AND (never backed up OR last backup over 20h ago).
  /// The signed-out latch: set when the user explicitly signs
  /// out, cleared only by an explicit interactive sign-in. While
  /// it is set, NO backup may run — a background catch-up must
  /// never resurrect the session and upload over the Drive copy.
  static const signedOutLatchKey = 'hisably_signed_out_v1';

  static Future<void> setSignedOutLatch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(signedOutLatchKey, true);
    } catch (_) {}
  }

  static Future<void> clearSignedOutLatch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(signedOutLatchKey);
    } catch (_) {}
  }

  /// Whether the signed-out latch is currently set (used by the
  /// startup gate to skip its auto-restore after a sign-out).
  static Future<bool> isSignedOutLatchSet() => _signedOutLatch();

  static Future<bool> _signedOutLatch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(signedOutLatchKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// An empty local database must never overwrite a Drive backup
  /// that still holds data.
  static bool wouldClobber({required int localTx, required int? driveTx}) =>
      localTx == 0 && driveTx != null && driveTx > 0;

  static Future<bool> isOverdue(GoogleAuth auth) async {
    if (await _signedOutLatch()) return false;
    if (auth.currentUser == null && await auth.signInSilently() == null) {
      return false;
    }
    final last = await lastBackupAt();
    if (last == null) return true;
    return DateTime.now().difference(last) > const Duration(hours: 20);
  }

  /// One backup, right now. Returns false when signed out; throws
  /// on Drive/network errors so callers can report them.
  static Future<bool> run(HisablyDatabase db, GoogleAuth auth,
      {bool notify = true}) async {
    if (await _signedOutLatch()) return false;
    if (await auth.authHeaders() == null) return false;
    final json = await BackupService(db).exportToJson();
    // Anti-clobber guard: never replace real Drive data with an
    // empty device's data.
    final localTx = BackupService(db).preview(json)['transactions'] ?? 0;
    if (localTx == 0) {
      final drive = DriveBackup(auth);
      if (await drive.findBackup() != null) {
        try {
          final existing = await drive.downloadBackup();
          final driveTx = existing == null
              ? null
              : BackupService(db).preview(existing)['transactions'];
          if (wouldClobber(localTx: localTx, driveTx: driveTx)) {
            return false;
          }
        } catch (_) {
          return false; // Cannot verify — do not risk the overwrite.
        }
      }
    }
    await DriveBackup(auth).uploadBackup(json);
    _lastRunAt = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          lastBackupKey, _lastRunAt!.millisecondsSinceEpoch);
    } catch (_) {
      // The upload itself succeeded; bookkeeping must not fail it.
    }
    // The daily run also refreshes the stored Google profile
    // photo (user rule, 23 Oct 2026): a changed picture replaces
    // the local copy, and a failed download changes nothing.
    final user = auth.currentUser ?? await auth.signInSilently();
    if (user != null) {
      await saveIdentity(
          email: user.email,
          name: user.displayName,
          photoUrl: user.photoUrl);
      await downloadPhoto(user.photoUrl);
    }
    if (notify) await _showDoneNotification();
    return true;
  }

  // ── Google identity (app-owned record) ────────────────────────
  //
  // The app keeps its OWN record of the connected Google account
  // (user bug report, 23 Oct 2026): the UI reads this record, so
  // a momentary silent-sign-in failure can never make a connected
  // account look signed out or show "Continue with Google" again.
  static const googleNameKey = 'google_name';
  static const googlePhotoUrlKey = 'google_photo_url';

  static Future<void> saveIdentity({
    required String email,
    String? name,
    String? photoUrl,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(googleEmailKey, email);
      if (name != null && name.isNotEmpty) {
        await prefs.setString(googleNameKey, name);
      }
      if (photoUrl != null && photoUrl.isNotEmpty) {
        await prefs.setString(googlePhotoUrlKey, photoUrl);
      }
    } catch (_) {}
  }

  /// The stored identity, or null when no account is connected.
  static Future<({String email, String? name, String? photoUrl})?>
      readIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final email = prefs.getString(googleEmailKey);
      if (email == null || email.isEmpty) return null;
      return (
        email: email,
        name: prefs.getString(googleNameKey),
        photoUrl: prefs.getString(googlePhotoUrlKey),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(googleEmailKey);
      await prefs.remove(googleNameKey);
      await prefs.remove(googlePhotoUrlKey);
    } catch (_) {}
  }

  /// The WorkManager path: its own database + silent sign-in. A
  /// signed-out user is a successful no-op (nothing to back up to);
  /// real failures return false so WorkManager retries later.
  static Future<bool> runInBackground() async {
    WidgetsFlutterBinding.ensureInitialized();
    final auth = GoogleAuth();
    if (await auth.signInSilently() == null) return true;
    final db = HisablyDatabase();
    try {
      return await run(db, auth);
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  }

  static Future<void> _showDoneNotification() async {
    await initNotifications();
    if (!_notifReady) return;
    try {
      await _notifications.show(
        1001,
        'Hisably backup',
        'Backup complete — your data is safe in your Google Drive.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'hisably_backup',
            'Backups',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (_) {}
  }

  // ── Profile photo (from Google sign-in) ─────────────────────────

  static Future<File> photoFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'profile_photo.jpg'));
  }

  /// The stored photo, or null when absent (or when storage is
  /// unavailable, e.g. in tests) — callers show initials instead.
  static Future<File?> storedPhoto() async {
    try {
      final f = await photoFile();
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// The stored photo's bytes, for image widgets: reading the
  /// bytes (rather than a FileImage on the same path) means a
  /// refreshed photo is never hidden by the image cache.
  static Future<Uint8List?> storedPhotoBytes() async {
    final f = await storedPhoto();
    if (f == null) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Downloads the Google profile photo for offline display.
  /// The new picture is written to a temporary file first and
  /// only replaces the stored photo once it has fully arrived
  /// (user rule, 23 Oct 2026): the previous photo is never
  /// deleted or damaged by a failed refresh.
  /// Returns true when a photo is now stored locally.
  static Future<bool> downloadPhoto(String? url) async {
    if (url == null || url.isEmpty) return false;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return false;
      final target = await photoFile();
      final temp = File('${target.path}.tmp');
      await temp.writeAsBytes(res.bodyBytes, flush: true);
      await temp.rename(target.path);
      return true;
    } catch (_) {
      return false;
    }
  }
/// Full local wipe for sign-out (user flow, 23 Oct 2026):
  /// closes the database, deletes every app data file in the
  /// documents directory (database, profile, PIN, photo,
  /// exports), drops the database key, and clears preferences.
  /// The Drive backup is NOT touched — it is what a later
  /// sign-in restores from.
  static Future<void> wipeLocalData(HisablyDatabase db) async {
    // Row-level wipe (redesign, 23 Oct 2026): the old version
    // closed the database and deleted its file — and a stalled
    // close trapped sign-out behind a spinner indefinitely
    // (device video, 23 Oct 2026). Emptying every table in one
    // transaction is the same fresh start the user sees, uses
    // the mechanism restores already rely on, and cannot stall
    // on a platform call. The now-empty database file and its
    // encryption key stay in place: deleting the key while the
    // encrypted file remains would break the next open, and an
    // empty database holds nothing the key could expose.
    try {
      await db.transaction(() async {
        for (final table in db.allTables) {
          await db.delete(table).go();
        }
      }).timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {}
    _lastRunAt = null;
    try {
      await PinService()
          .removePin()
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory().timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError('timeout'));
      final entities = await dir
          .list()
          .toList()
          .timeout(const Duration(seconds: 2),
              onTimeout: () => <FileSystemEntity>[]);
      for (final entity in entities) {
        // The profile FILE must go too: since v0.6.2 the profile
        // lives in hisably_profile.json (durable file storage),
        // not in preferences — leaving it behind made the
        // startup gate find a profile and re-enter the shell
        // after sign-out instead of showing setup (device report,
        // 23 Oct 2026). Exported backup files the user saved are
        // deliberately kept: they are the user's own copies.
        final base = p.basename(entity.path);
        if (entity is File &&
            (base.startsWith('profile_photo') ||
                base == 'hisably_profile.json')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs
          .clear()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {}
  }
}
