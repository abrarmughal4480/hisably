import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google Sign-In for Hisably (user feature, 23 Oct 2026).
///
/// Serverless by design: there is no Hisably backend. Sign-in exists
/// only so the app can (a) show the user's own Google name, email and
/// photo as their profile, and (b) write backups into the app-only
/// folder of the user's own Google Drive (drive.appdata scope —
/// nothing else in the Drive is visible to the app).
class GoogleAuth {
  static const driveAppDataScope =
      'https://www.googleapis.com/auth/drive.appdata';

  final GoogleSignIn _gsi = GoogleSignIn(
    scopes: const ['email', 'profile', driveAppDataScope],
  );

  GoogleSignInAccount? get currentUser => _gsi.currentUser;

  Stream<GoogleSignInAccount?> get onUserChanged =>
      _gsi.onCurrentUserChanged;

  Future<GoogleSignInAccount?> signIn() => _gsi.signIn();

  /// Restores an earlier sign-in without showing any UI. Safe to
  /// call on every app start and from the background backup task.
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _gsi.signInSilently();
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() => _gsi.signOut();

  /// Full sign-out: revokes the app's access grant, so no silent
  /// restore can bring the session back afterwards. Falls back
  /// to a plain sign-out if the revoke itself fails.
  Future<void> disconnect() async {
    try {
      await _gsi.disconnect();
    } catch (_) {
      await _gsi.signOut();
    }
  }

  /// Authorization headers for Drive REST calls, or null when
  /// nobody is signed in.
  Future<Map<String, String>?> authHeaders() async {
    final user = _gsi.currentUser ?? await signInSilently();
    if (user == null) return null;
    return user.authHeaders;
  }
}

final googleAuthProvider = Provider<GoogleAuth>((ref) => GoogleAuth());
