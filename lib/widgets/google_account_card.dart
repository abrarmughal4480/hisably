import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/auto_backup.dart';
import '../data/backup_service.dart';
import '../data/drive_backup.dart';
import '../data/google_auth.dart';
import '../data/profile.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import 'sign_in_data_sync.dart';
import 'smart_import.dart';
import '../theme/hisably_theme.dart';
import 'google_logo.dart';

/// Google account card on the More screen (user feature,
/// 23 Oct 2026). Signed out: a Continue-with-Google button.
/// Signed in: the Google photo, name and email (the name and photo
/// become the in-app profile, as the user asked), the last-backup
/// time, and Backup now / Restore / Sign out actions.
class GoogleAccountCard extends ConsumerStatefulWidget {
  const GoogleAccountCard({super.key});

  @override
  ConsumerState<GoogleAccountCard> createState() =>
      _GoogleAccountCardState();
}

class _GoogleAccountCardState extends ConsumerState<GoogleAccountCard> {
  // The card displays the app's OWN identity record (saved at
  // sign-in), never the live Google session alone — a failed
  // silent restore must not make a connected account look
  // signed out (user bug report, 23 Oct 2026).
  String? _email;
  String? _name;
  bool _sessionDead = false;
  String? _busyAction;
  bool get _busy => _busyAction != null;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final identity = await AutoBackup.readIdentity();
    if (mounted) {
      setState(() {
        _email = identity?.email;
        _name = identity?.name;
      });
    }
    // Refresh the record from the live session when one is
    // available; failure changes nothing on screen.
    final auth = ref.read(googleAuthProvider);
    final user = auth.currentUser ?? await auth.signInSilently();
    if (user != null) {
      await AutoBackup.saveIdentity(
          email: user.email,
          name: user.displayName,
          photoUrl: user.photoUrl);
      if (mounted) {
        setState(() {
          _email = user.email;
          _name = user.displayName;
        });
      }
    }
  }

  Future<void> _signIn() async {
    setState(() => _busyAction = 'signin');
    try {
      final auth = ref.read(googleAuthProvider);
      final user = await auth.signIn();
      if (user == null) return; // user cancelled the picker
      // Google profile becomes the app profile: name …
      final lang = ref.read(languageProvider);
      final profile = Profile(
          name: user.displayName ?? user.email, languageCode: lang);
      await ref.read(profileStoreProvider).saveProfile(profile);
      ref.read(profileProvider.notifier).state = profile;
      // … photo (stored locally for offline display) …
      await AutoBackup.downloadPhoto(user.photoUrl);
      ref.read(profilePhotoTickProvider.notifier).state++;
      // … and the app's own identity record, which is what the
      // UI reads from now on (never the live session alone).
      await AutoBackup.saveIdentity(
          email: user.email,
          name: user.displayName,
          photoUrl: user.photoUrl);
      setState(() {
        _email = user.email;
        _name = user.displayName;
        _sessionDead = false;
      });
      await AutoBackup.requestNotificationPermission();
      // First sign-in on this device: offer the old-backup import
      // BEFORE the first Drive backup, so the imported data is
      // what gets backed up (user flow, 23 Oct 2026).
      if (!await AutoBackup.firstSignInSeen()) {
        await AutoBackup.markFirstSignInSeen();
        if (mounted) await _offerFirstImport();
      }
      // Data sync: first backup, automatic fetch, or a
      // double-confirmed conflict choice (user rules, 23 Oct).
      await syncDataAfterSignIn(context, ref);
      if (mounted) setState(() {});
      return;
    } catch (e) {
      if (mounted) _snack(_clean(e));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  /// The first-sign-in offer: import a backup file from before
  /// (user request, 23 Oct 2026). Shown exactly once per device;
  /// the manual Restore in More → Backup stays available anytime.
  Future<void> _offerFirstImport() async {
    final s = ref.read(stringsProvider);
    final choice = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('firstImportTitle')),
        content: Text(s.t('firstImportBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(s.t('notNow'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(s.t('importFile'))),
        ],
      ),
    );
    if (choice != true || !mounted) return;
    // One smart entry: the app detects whether the picked file is
    // a Hisably backup or another app's data (user UX rule).
    await startSmartImport(context, ref);
  }

  Future<void> _backupNow({required bool showResult}) async {
    final s = ref.read(stringsProvider);
    try {
      final ok = await AutoBackup.run(
          ref.read(databaseProvider), ref.read(googleAuthProvider));
      // Re-read the displayed time from storage (it is not held
      // in a field — a stale field was the "always Never" bug).
      ref.read(lastBackupTickProvider.notifier).state++;
      if (mounted && !ok) setState(() => _sessionDead = true);
      if (mounted && showResult) {
        _snack(ok ? s.t('backupDone') : s.t('sessionExpired'));
      }
    } catch (_) {
      if (mounted && showResult) _snack(s.t('backupFailed'));
    }
  }

  Future<void> _restoreFromDrive() async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('restoreTitle')),
        content: Text(s.t('restoreBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('restoreFromDrive'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyAction = 'restore');
    try {
      final auth = ref.read(googleAuthProvider);
      final json = await DriveBackup(auth).downloadBackup();
      if (json == null) {
        if (mounted) _snack(s.t('noBackupFound'));
        return;
      }
      // Report WHAT came back, with counts (user rule,
      // 23 Oct 2026): an empty backup must never look like a
      // successful restore of real data.
      var counts = <String, int>{};
      try {
        counts = BackupService(ref.read(databaseProvider)).preview(json);
      } catch (_) {}
      if ((counts['transactions'] ?? 0) == 0) {
        if (mounted) _snack(s.t('syncBackupEmpty'));
        return;
      }
      await BackupService(ref.read(databaseProvider))
          .restoreFromJson(json);
      if (mounted) {
        _snack('${s.t('restoreDone')} '
            '(${counts['transactions']} ${s.t('transactions')})');
      }
    } catch (e) {
      if (mounted) _snack(_clean(e));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  /// Sign-out (user spec, 23 Oct 2026): confirm → disconnect →
  /// wipe this device's Hisably data → the app returns to the
  /// fresh setup screen. No backup is bundled into sign-out —
  /// backing up is the user's own Backup now action. The Drive
  /// backup is kept; signing in again restores from it.
  Future<void> _signOut() async {
    final s = ref.read(stringsProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('signOutTitle')),
        content: Text(s.t('signOutBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(s.t('signOutConfirm'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busyAction = 'signout');
    final auth = ref.read(googleAuthProvider);
    final db = ref.read(databaseProvider);
    // Sign-out is sign-out ONLY (user instruction, 23 Oct 2026):
    // no backup is bundled into it. Backing up is the user's own
    // explicit action — the Backup now button, which completes
    // with its notification. Sign-out itself is disconnect +
    // wipe + fresh start, and takes seconds.
    try {
      // The disconnect is STARTED but never awaited: a stalled
      // Play-services call trapped sign-out behind this spinner
      // for over a minute (device video, 23 Oct 2026). The
      // signed-out latch set below — backed by the anti-clobber
      // guard in AutoBackup.run — protects the Drive backup
      // whether or not the revoke ever completes.
      unawaited(auth.disconnect());
      await AutoBackup.wipeLocalData(db);
      // The latch is set AFTER the wipe (the wipe clears stored
      // settings by design): from here until an explicit sign-in,
      // no backup may run and no session may be silently restored
      // to overwrite the Drive copy.
      await AutoBackup.setSignedOutLatch().timeout(
          const Duration(seconds: 3), onTimeout: () {});
    } finally {
      // Re-run the start-up gate: no profile remains, so the
      // app lands on setup — a genuine fresh start.
      appResetNotifier.value++;
    }
  }

  String _clean(Object e) => e
      .toString()
      .replaceFirst(RegExp(r'^(StateError|Bad state):?\s*'), '');

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _email == null ? _signedOut(s) : _signedIn(s),
      ),
    );
  }

  Widget _signedOut(S s) {
    // A returning user who skipped Google at setup gets a plain
    // "Connect" action here; "Continue with Google" belongs to
    // the first-run wizard (user request, 23 Oct 2026).
    final hasProfile = ref.watch(profileProvider) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.t('googleAccount'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(s.t('googleBackupSub'),
            style: const TextStyle(
                color: HisablyColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 14),
        GoogleContinueButton(
          onPressed: _signIn,
          label: s.t(hasProfile ? 'connectGoogle' : 'continueWithGoogle'),
          busy: _busyAction == 'signin',
        ),
      ],
    );
  }

  Widget _signedIn(S s) {
    final email = _email ?? '';
    final name = _name ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _identityAvatar(name, email),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(email,
                      style: const TextStyle(
                          color: HisablyColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FutureBuilder<DateTime?>(
          key: ValueKey(ref.watch(lastBackupTickProvider)),
          future: AutoBackup.lastBackupAt(),
          builder: (context, snap) => Text(
            '${s.t('lastBackup')}: ${snap.data == null ? s.t('never') : DateFormat('d MMM, h:mm a').format(snap.data!)}',
            style: const TextStyle(
                color: HisablyColors.textSecondary, fontSize: 13),
          ),
        ),
        if (_sessionDead) ...[
          const SizedBox(height: 10),
          Text(s.t('sessionExpired'),
              style: const TextStyle(
                  color: HisablyColors.warning, fontSize: 13)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signIn,
            icon: _btnIcon('signin', Icons.link_rounded),
            label: Text(s.t('reconnect')),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busyAction = 'backup');
                      await _backupNow(showResult: true);
                      if (mounted) setState(() => _busyAction = null);
                    },
              icon: _btnIcon('backup', Icons.cloud_upload_rounded),
              label: Text(s.t('backupNow')),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restoreFromDrive,
              icon: _btnIcon('restore', Icons.cloud_download_rounded),
              label: Text(s.t('restoreFromDrive')),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _signOut,
              icon: _btnIcon('signout', Icons.logout_rounded),
              label: Text(s.t('signOut')),
            ),
          ],
        ),
      ],
    );
  }

  /// A button icon that becomes a spinner while ITS action runs.
  Widget _btnIcon(String action, IconData icon) => _busyAction == action
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(icon, size: 18);

  /// The account avatar from the LOCALLY stored Google photo
  /// (works offline, refreshes with the daily backup); initials
  /// when no photo is stored yet.
  Widget _identityAvatar(String name, String email) {
    ref.watch(profilePhotoTickProvider);
    return FutureBuilder<Uint8List?>(
      future: AutoBackup.storedPhotoBytes(),
      builder: (context, snap) {
        final bytes = snap.data;
        final initial = (name.isNotEmpty ? name : email)
            .characters
            .take(1)
            .toString()
            .toUpperCase();
        return CircleAvatar(
          radius: 22,
          backgroundColor: HisablyColors.accent,
          backgroundImage: bytes != null ? MemoryImage(bytes) : null,
          child: bytes == null
              ? Text(initial,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600))
              : null,
        );
      },
    );
  }
}

