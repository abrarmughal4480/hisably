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

  @override
  void initState() {
    super.initState();
    _tryBiometric();
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
            const Duration(seconds: 2),
            onTimeout: () => const <BiometricType>[]);
        available = enrolled.isNotEmpty;
      } catch (_) {}
      if (!available) {
        final canCheck = await _auth.canCheckBiometrics
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        final supported = await _auth.isDeviceSupported()
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
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
              TextButton.icon(
                onPressed: _tryBiometric,
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
