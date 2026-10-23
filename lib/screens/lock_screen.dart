import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../data/pin_service.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/logo.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  final _auth = LocalAuthentication();
  bool _bioEnabled = true;

  @override
  void initState() {
    super.initState();
    // After the first frame, when the activity is fully resumed:
    // a biometric prompt raised during initState can be dropped
    // silently by the platform (bug report, 23 Oct 2026 — the app
    // asked only for the PIN although fingerprint was enabled).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _initBiometric());
  }

  Future<void> _initBiometric() async {
    // The setup wizard asks once whether fingerprint unlock is
    // wanted (only when the device has biometrics); honour it
    // for the automatic prompt.
    _bioEnabled = await BiometricSetting.isEnabled();
    if (mounted) setState(() {});
    if (_bioEnabled) _tryBiometric();
  }

  /// Fingerprint has priority (user request, v0.6.3): when a biometric
  /// is actually enrolled, prompt for it first and only fall back to
  /// the PIN when there is none or it fails. `biometricOnly` keeps the
  /// system from swapping the fingerprint prompt for the device PIN.
  Future<void> _tryBiometric() async {
    try {
      var available = false;
      try {
        final enrolled = await _auth.getAvailableBiometrics().timeout(
            const Duration(seconds: 6),
            onTimeout: () => const <BiometricType>[]);
        available = enrolled.isNotEmpty;
      } catch (_) {}
      if (!available) {
        final canCheck = await _auth.canCheckBiometrics
            .timeout(const Duration(seconds: 6), onTimeout: () => false);
        final supported = await _auth.isDeviceSupported()
            .timeout(const Duration(seconds: 6), onTimeout: () => false);
        available = canCheck && supported;
      }
      if (!available) return;
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Hisably',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) widget.onUnlocked();
    } catch (_) {
      // Biometrics unavailable — PIN entry remains.
    }
  }

  Future<void> _submit() async {
    final ok = await PinService().verify(_ctrl.text.trim());
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = ref.read(stringsProvider).t('wrongPin');
        _ctrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const HisablyLogo(size: 68),
              const SizedBox(height: 18),
              Text(s.t('lockedTitle'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(s.t('lockedSub'),
                  style: TextStyle(color: HisablyColors.textSecondary)),
              const SizedBox(height: 28),
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 6),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: HisablyColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Unlock', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 10),
              // The button is ALWAYS available (bug report,
              // 23 Oct 2026): the setting gates only the automatic
              // prompt. Tapping it with the setting off turns the
              // feature on and authenticates in one go — there is
              // no state in which fingerprint is unreachable.
              TextButton.icon(
                onPressed: () async {
                  if (!_bioEnabled) {
                    await BiometricSetting.setEnabled(true);
                    if (mounted) setState(() => _bioEnabled = true);
                  }
                  _tryBiometric();
                },
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(s.t('useFingerprint')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
