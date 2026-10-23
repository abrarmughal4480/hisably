import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:permission_handler/permission_handler.dart';

import '../data/pin_service.dart';
import '../data/profile.dart';
import '../l10n/strings.dart';
import '../theme/hisably_theme.dart';
import '../widgets/logo.dart';

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

  S get _s => S(_lang);

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
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
