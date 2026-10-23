import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auto_backup.dart';
import 'data/backup_service.dart';
import 'data/drive_backup.dart';
import 'data/google_auth.dart';
import 'data/pin_service.dart';
import 'data/profile.dart';
import 'data/providers.dart';
import 'l10n/strings.dart';
import 'screens/lock_screen.dart';
import 'screens/registration_screen.dart';
import 'shell/home_shell.dart';
import 'theme/hisably_theme.dart';
import 'widgets/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Automatic Drive backups: notifications + the daily job. Both
  // are best-effort at startup and must never block the app.
  await AutoBackup.initNotifications();
  await AutoBackup.schedule();
  runApp(const ProviderScope(child: HisablyApp()));
}

/// Startup gate: local registration first (3-step setup), then the
/// optional PIN lock, then the app shell.
///
/// LOADER FIX (v0.6): startup can never hang on this screen again —
/// every storage read has a hard timeout and a safety timer keeps the
/// gate moving even if a platform channel stalls (the v0.5 hang on
/// the Sharp AQUOS R7).
///
/// PERSISTENCE FIX (v0.6.2): the profile read no longer times out into
/// "no profile" — a slow read used to route a registered user back to
/// setup after the app was cleared from RAM. The gate now waits for
/// the real read (with retries); the safety timer only reveals a
/// Retry button, never a wrong destination.
class HisablyApp extends ConsumerStatefulWidget {
  const HisablyApp({super.key});

  @override
  ConsumerState<HisablyApp> createState() => _HisablyAppState();
}

class _HisablyAppState extends ConsumerState<HisablyApp> {
  bool _loading = true;
  bool _slow = false;
  bool _needsLock = false;
  bool _unlocked = false;
  bool _splashMinDone = false;
  Timer? _safety;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _safety = Timer(const Duration(seconds: 12), () {
      if (mounted && _loading) setState(() => _slow = true);
    });
    // Animated splash (v0.6.8): stays at least ~1.5 s so the opening
    // animation reads as an opening, not a flash.
    _splashTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _splashMinDone = true);
    });
    _init();
    appResetNotifier.addListener(_onAppReset);
  }

  /// Sign-out wiped the device: re-run the start-up gate so the
  /// app lands on setup as a fresh start.
  void _onAppReset() {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _needsLock = false;
      _slow = false;
    });
    _init();
  }

  @override
  void dispose() {
    appResetNotifier.removeListener(_onAppReset);
    _safety?.cancel();
    _splashTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    if (mounted) setState(() => _slow = false);
    // Profile: wait for the real read. A failed attempt retries — a
    // registered user must never be sent back to setup by a slow disk.
    Profile? profile;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        profile = await ref.read(profileStoreProvider).loadProfile();
        break;
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    // Publish the result UNCONDITIONALLY: after a sign-out wipe the
    // loaded profile is null, and a stale non-null value left in the
    // provider would drop the user back into the shell instead of
    // the start screen (device bug, 23 Oct 2026).
    ref.read(profileProvider.notifier).state = profile;
    if (profile != null) {
      ref.read(languageProvider.notifier).state = profile.languageCode;
    }
    try {
      _needsLock = await PinService()
          .isPinSet()
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (_) {
      _needsLock = false; // storage unavailable — never brick startup
    }
    // Startup auto-restore: a signed-in account plus an empty
    // device means the account's data simply comes back — no
    // manual trigger (user rule, 23 Oct 2026). Bounded, so the
    // network can never trap startup.
    if (profile != null) {
      try {
        await _autoRestoreIfEmpty()
            .timeout(const Duration(seconds: 8), onTimeout: () {});
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
    // Catch-up backup: signed in + last backup over 20h old (or
    // none) → back up now, in the background of normal use.
    unawaited(_catchUpBackup());
  }

  /// Fetches the Drive backup into an empty local database at
  /// startup. Best-effort and silent: on any failure the device
  /// simply starts as it was, and the manual Restore remains.
  Future<void> _autoRestoreIfEmpty() async {
    if (await AutoBackup.isSignedOutLatchSet()) return;
    final auth = ref.read(googleAuthProvider);
    final user = auth.currentUser ?? await auth.signInSilently();
    if (user == null) return;
    final db = ref.read(databaseProvider);
    if ((await db.select(db.transactions).get()).isNotEmpty) return;
    final json = await DriveBackup(auth).downloadBackup();
    if (json == null) return;
    if ((BackupService(db).preview(json)['transactions'] ?? 0) == 0) {
      return;
    }
    // Re-check immediately before replacing: nothing may have
    // been added since the first check.
    if ((await db.select(db.transactions).get()).isNotEmpty) return;
    await BackupService(db).restoreFromJson(json);
    ref.read(lastBackupTickProvider.notifier).state++;
  }

  Future<void> _catchUpBackup() async {
    try {
      final auth = ref.read(googleAuthProvider);
      if (await AutoBackup.isOverdue(auth)) {
        if (await AutoBackup.run(ref.read(databaseProvider), auth)) {
          ref.read(lastBackupTickProvider.notifier).state++;
          ref.read(profilePhotoTickProvider.notifier).state++;
        }
      }
    } catch (_) {
      // A failed catch-up is silent; the daily job will retry.
    }
  }

  Future<void> _afterRegister() async {
    // Registration's own data sync may have raced the sign-in
    // (device report, 23 Oct 2026: a fresh login landed on zeros
    // and the data only arrived after an app restart, fetched by
    // the startup restore). Give that same restore one bounded
    // chance here, before the shell shows, so the first entry
    // already carries the account's data.
    if (mounted) setState(() => _loading = true);
    try {
      await _autoRestoreIfEmpty()
          .timeout(const Duration(seconds: 8), onTimeout: () {});
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _needsLock = false; // a PIN set now applies from the next launch
      _unlocked = true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final profile = ref.watch(profileProvider);

    Widget home;
    String branch;
    if (_loading || !_splashMinDone) {
      branch = 'splash';
      home = Stack(
        key: const ValueKey('splash'),
        children: [
          SplashScreen(tagline: S(lang).t('tagline')),
          if (_slow && _loading)
            Positioned(
              left: 0,
              right: 0,
              bottom: 56,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Taking longer than usual…',
                    style: TextStyle(color: HisablyColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () {
                      setState(() => _loading = true);
                      _init();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      );
    } else if (profile == null) {
      branch = 'register';
      home = RegistrationScreen(
          key: const ValueKey('register'), onDone: _afterRegister);
    } else if (_needsLock && !_unlocked) {
      branch = 'lock';
      home = LockScreen(
          key: const ValueKey('lock'),
          onUnlocked: () => setState(() => _unlocked = true));
    } else {
      branch = 'shell';
      home = const HomeShell(key: ValueKey('shell'));
    }

    return MaterialApp(
      title: 'Hisably',
      debugShowCheckedModeBanner: false,
      theme: HisablyTheme.app(lang: lang),
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        child: KeyedSubtree(key: ValueKey(branch), child: home),
      ),
    );
  }
}
