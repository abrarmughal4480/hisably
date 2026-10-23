import 'package:flutter/material.dart';

/// The official multi-colour Google "G" (bundled brand asset —
/// user, 23 Oct 2026: the earlier hand-drawn approximation did
/// not look right).
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/google_g.png',
        width: size, height: size, fit: BoxFit.contain);
  }
}

/// The standard white Continue-with-Google button (official G +
/// label), shared by the setup wizard and the More card so the
/// sign-in entry looks identical everywhere.
class GoogleContinueButton extends StatelessWidget {
  const GoogleContinueButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.busy = false,
  });
  final VoidCallback onPressed;
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GoogleLogo(size: 20),
                  const SizedBox(width: 10),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}
