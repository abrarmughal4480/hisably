import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auto_backup.dart';
import '../data/google_auth.dart';
import '../data/pin_service.dart';
import '../data/profile.dart';
import '../data/providers.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/sign_in_data_sync.dart';
import '../widgets/google_logo.dart';
import '../widgets/logo.dart';
import '../widgets/smart_import.dart';

/// First-launch setup — a 3-step wizard (final design, 22 Oct 2026):
/// Step 1: choose language (cards, no toggle) · Step 2: your name ·
/// Step 3: optional 4-digit PIN or Skip. Stored only on this device.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<RegistrationScreen> createState() =>
      _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _lang = 'en';
  int _step = 1;
  String? _error;
  GoogleSignInAccount? _googleUser;
  bool _googleBusy = false;
  bool _finishing = false;

  S get _s => S(_lang);

  /// Continue with Google, offered right beside the name field
  /// (user request, 23 Oct 2026): the Google name becomes the
  /// profile name, the photo becomes the profile picture, and the
  /// account drives the Drive auto-backup.
  Future<void> _googleSignIn() async {
    setState(() => _googleBusy = true);
    // Sign in through the SHARED auth instance (googleAuthProvider).
    // A private instance here was the root cause of the broken
    // auto-restore (23 Oct 2026): setup signed in on its own
    // instance, while the post-sign-in data sync reads the shared
    // one — whose session was still empty at that moment, so the
    // sync died silently and the device stayed at zero. The
    // manual Restore worked because by then the session had been
    // silently restored on the shared instance.
    final user = await ref.read(googleAuthProvider).signIn();
    if (!mounted) return;
    setState(() => _googleBusy = false);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_s.t('googleSignInFailed'))));
      return;
    }
    _googleUser = user;
    final dn = user.displayName;
    if (dn != null && dn.trim().isNotEmpty) {
      _nameCtrl.text = dn;
    }
    // The app's own identity record (what the UI reads) + the
    // photo stored locally — awaited, so the profile is complete
    // the moment setup finishes.
    await AutoBackup.saveIdentity(
        email: user.email, name: user.displayName, photoUrl: user.photoUrl);
    await AutoBackup.downloadPhoto(user.photoUrl);
    ref.read(profilePhotoTickProvider.notifier).state++;
    setState(() {
      _error = null;
      _step = 3;
    });
  }

  /// Ask about fingerprint unlock ONLY when the device actually
  /// has biometrics (the app decides whether the prompt applies —
  /// user request, 23 Oct 2026), and only when a PIN was set.
  Future<void> _maybeOfferFingerprint() async {
    try {
      final auth = LocalAuthentication();
      var available = false;
      try {
        final enrolled = await auth.getAvailableBiometrics().timeout(
            const Duration(seconds: 2),
            onTimeout: () => const <BiometricType>[]);
        available = enrolled.isNotEmpty;
      } catch (_) {}
      if (!available) {
        final canCheck = await auth.canCheckBiometrics
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        final supported = await auth.isDeviceSupported()
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        available = canCheck && supported;
      }
      if (!available || !mounted) return;
      final s = _s;
      final enable = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.t('fingerprintTitle')),
          content: Text(s.t('fingerprintBody')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(s.t('notNow'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(s.t('enableBtn'))),
          ],
        ),
      );
      if (enable != true) {
        await BiometricSetting.setEnabled(false);
        return;
      }
      var ok = false;
      try {
        ok = await auth.authenticate(
          localizedReason: 'Hisably',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
      } catch (_) {}
      // Persist the choice ONLY on a proven success. A failed or
      // cancelled attempt stores nothing — the setting keeps its
      // default and the lock screen's fingerprint button remains
      // available, so the user is never locked out of the
      // feature by one bad attempt (bug report, 23 Oct 2026).
      if (ok) await BiometricSetting.setEnabled(true);
    } catch (_) {}
  }

  /// First-sign-in import offer, same as the More card's: shown
  /// once when setup itself was done through Google.
  Future<void> _offerFirstImport() async {
    if (!mounted) return;
    final s = _s;
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
    await startSmartImport(context, ref);
  }

  Future<void> _finish() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() {
        _step = 2;
        _error = _s.t('nameRequired');
      });
      return;
    }
    final pin = _pinCtrl.text.trim();
    if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = _s.t('pinHint'));
      return;
    }
    final profile = Profile(name: name, languageCode: _lang);
    try {
      if (mounted) setState(() => _finishing = true);
      await ref.read(profileStoreProvider).saveProfile(profile);
    } catch (_) {
      // Local prefs failing must never trap the user in setup.
    }
    ref.read(profileProvider.notifier).state = profile;
    ref.read(languageProvider.notifier).state = _lang;
    if (pin.isNotEmpty) {
      await PinService().setPin(pin); // file-based, cannot stall
    }
    // Storage access, requested with setup as the user asked. The app
    // keeps its data in app-specific storage (no permission needed per
    // the Android docs), so the result never blocks entry.
    try {
      await Permission.storage
          .request()
          .timeout(const Duration(seconds: 3), onTimeout: () => PermissionStatus.denied);
    } catch (_) {}
    // Fingerprint offer comes after the PIN exists — and only when
    // the device actually has biometrics.
    if (pin.isNotEmpty) await _maybeOfferFingerprint();
    if (_googleUser != null) {
      await AutoBackup.markFirstSignInSeen();
      await _offerFirstImport();
      // Data sync: first backup, automatic fetch when this
      // device is empty, or a double-confirmed conflict choice
      // (user rules, 23 Oct 2026).
      if (mounted) await syncDataAfterSignIn(context, ref);
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            const Center(child: HisablyLogo(size: 78)),
            const SizedBox(height: 20),
            Text(s.t('registerTitle'),
                textAlign: TextAlign.center,
                style: headingStyle(_lang, size: 23, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(s.t('registerSub'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: HisablyColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 22),
            _StepDots(step: _step),
            const SizedBox(height: 24),
            if (_step == 1) ...[
              Text(s.t('chooseLanguage'),
                  style: const TextStyle(
                      color: HisablyColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 10),
              _LangOption(
                label: 'English',
                selected: _lang == 'en',
                onTap: () => setState(() => _lang = 'en'),
              ),
              _LangOption(
                label: 'اردو',
                selected: _lang == 'ur',
                onTap: () => setState(() => _lang = 'ur'),
              ),
              const SizedBox(height: 18),
              _PrimaryButton(
                label: s.t('continueBtn'),
                onPressed: () => setState(() => _step = 2),
              ),
            ] else if (_step == 2) ...[
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: s.t('yourName'),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(child: Divider(color: HisablyColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(s.t('orDivider'),
                        style: const TextStyle(
                            color: HisablyColors.textSecondary,
                            fontSize: 12.5)),
                  ),
                  const Expanded(child: Divider(color: HisablyColors.border)),
                ],
              ),
              const SizedBox(height: 18),
              GoogleContinueButton(
                onPressed: _googleSignIn,
                label: s.t('continueWithGoogle'),
                busy: _googleBusy,
              ),
              const SizedBox(height: 10),
              Text(s.t('googleBenefit'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: HisablyColors.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _GhostButton(
                      label: s.t('backBtn'),
                      onPressed: () => setState(() => _step = 1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _PrimaryButton(
                      label: s.t('continueBtn'),
                      onPressed: () {
                        if (_nameCtrl.text.trim().isEmpty) {
                          setState(() => _error = s.t('nameRequired'));
                          return;
                        }
                        setState(() {
                          _error = null;
                          _step = 3;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(s.t('pinOptionalTitle'),
                  style: headingStyle(_lang, size: 15)),
              const SizedBox(height: 6),
              Text(s.t('pinOptionalSub'),
                  style: const TextStyle(
                      color: HisablyColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: s.t('pinHint'),
                  counterText: '',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _GhostButton(
                      label: s.t('backBtn'),
                      onPressed: () => setState(() => _step = 2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GhostButton(
                      label: s.t('skipBtn'),
                      onPressed: () {
                        _pinCtrl.clear();
                        _finish();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _PrimaryButton(
                      label: s.t('finishBtn'),
                      onPressed: _finish,
                      busy: _finishing,
                    ),
                  ),
                ],
              ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 3; i++)
          Container(
            width: 24,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i <= step
                  ? HisablyColors.accent
                  : HisablyColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class _LangOption extends StatelessWidget {
  const _LangOption(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: selected
                ? HisablyColors.income.withValues(alpha: 0.07)
                : HisablyColors.input,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? HisablyColors.income : HisablyColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: HisablyColors.income,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium-dark primary button: white background, black text.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(
      {required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.black))
            : Text(label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: HisablyColors.elevated,
          foregroundColor: HisablyColors.text,
          side: const BorderSide(color: HisablyColors.border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
