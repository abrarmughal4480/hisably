import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'google_auth.dart';

/// Backups in the signed-in user's own Google Drive, in the hidden
/// app-only folder (appDataFolder). The folder is invisible in the
/// Drive UI and no other app can read it; the developer has no
/// access to it either — there is no Hisably server anywhere in
/// this flow.
///
/// Exactly one rolling backup file is kept: hisably-backup.json.
class DriveBackup {
  DriveBackup(this._auth);
  final GoogleAuth _auth;

  static const fileName = 'hisably-backup.json';
  static const _filesUrl = 'https://www.googleapis.com/drive/v3/files';
  static const _uploadUrl =
      'https://www.googleapis.com/upload/drive/v3/files';

  Future<Map<String, String>> _headers() async {
    final h = await _auth.authHeaders();
    if (h == null) throw StateError('Not signed in to Google');
    return h;
  }

  /// The backup file's id + modified time, or null when no backup
  /// exists in this Google account yet.
  Future<({String id, DateTime modified})?> findBackup() async {
    final headers = await _headers();
    final uri = Uri.parse(_filesUrl).replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name = '$fileName'",
      'fields': 'files(id,name,modifiedTime)',
      'pageSize': '1',
    });
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw StateError('Drive lookup failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final files = (body['files'] as List?) ?? const [];
    if (files.isEmpty) return null;
    final f = files.first as Map<String, dynamic>;
    return (
      id: f['id'] as String,
      modified: DateTime.parse(f['modifiedTime'] as String),
    );
  }

  /// Creates the backup file, or overwrites it in place when one
  /// already exists — Drive keeps its own version history.
  Future<void> uploadBackup(String jsonText) async {
    final headers = await _headers();
    final existing = await findBackup();
    final bytes = utf8.encode(jsonText);
    if (existing != null) {
      final uri = Uri.parse('$_uploadUrl/${existing.id}')
          .replace(queryParameters: {'uploadType': 'media'});
      final res = await http.patch(uri,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: bytes);
      if (res.statusCode != 200) {
        throw StateError('Drive upload failed (${res.statusCode})');
      }
      return;
    }
    final req = http.MultipartRequest(
        'POST', Uri.parse('$_uploadUrl?uploadType=multipart'))
      ..headers.addAll(headers);
    req.files.add(http.MultipartFile.fromString(
      'metadata',
      jsonEncode({
        'name': fileName,
        'parents': ['appDataFolder'],
        'mimeType': 'application/json',
      }),
      contentType: MediaType('application', 'json'),
    ));
    req.files.add(http.MultipartFile.fromBytes('media', bytes,
        contentType: MediaType('application', 'json')));
    final streamed = await req.send();
    if (streamed.statusCode != 200) {
      throw StateError('Drive upload failed (${streamed.statusCode})');
    }
  }

  /// The backup JSON text, or null when this Google account has no
  /// backup yet.
  Future<String?> downloadBackup() async {
    final headers = await _headers();
    final existing = await findBackup();
    if (existing == null) return null;
    final uri = Uri.parse('$_filesUrl/${existing.id}')
        .replace(queryParameters: {'alt': 'media'});
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw StateError('Drive download failed (${res.statusCode})');
    }
    if (_txCount(res.body) > 0) return res.body;
    // The current copy holds no transactions — an earlier
    // overwrite may have replaced real data with an empty copy.
    // Drive keeps recent versions of the file: reach back to the
    // newest version that still holds data.
    try {
      final revsUri = Uri.parse('$_filesUrl/${existing.id}/revisions')
          .replace(queryParameters: {
        'fields': 'revisions(id,modifiedTime)',
        'pageSize': '20',
      });
      final revsRes = await http.get(revsUri, headers: headers);
      if (revsRes.statusCode == 200) {
        final decoded = jsonDecode(revsRes.body) as Map<String, dynamic>;
        final revs = (decoded['revisions'] as List? ?? [])
            .cast<Map<String, dynamic>>()
          ..sort((x, y) => (y['modifiedTime'] as String? ?? '')
              .compareTo(x['modifiedTime'] as String? ?? ''));
        var tried = 0;
        for (final rev in revs) {
          if (tried >= 4) break;
          tried++;
          final revUri =
              Uri.parse('$_filesUrl/${existing.id}/revisions/${rev['id']}')
                  .replace(queryParameters: {'alt': 'media'});
          final revRes = await http.get(revUri, headers: headers);
          if (revRes.statusCode == 200 && _txCount(revRes.body) > 0) {
            return revRes.body;
          }
        }
      }
    } catch (_) {
      // Recovery is best-effort; the current copy is returned.
    }
    return res.body;
  }

  static int _txCount(String json) {
    try {
      final m = jsonDecode(json);
      if (m is Map && m['transactions'] is List) {
        return (m['transactions'] as List).length;
      }
    } catch (_) {}
    return 0;
  }
}
