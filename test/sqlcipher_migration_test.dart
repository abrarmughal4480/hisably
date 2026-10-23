import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Guards the exact SQL the app runs for its one-time
/// plaintext → SQLCipher migration (database.dart): attach with a
/// key, sqlcipher_export, then read the encrypted copy back with
/// the key — and prove it cannot be read without it.
///
/// The test environment's sqlite3 library IS the SQLCipher build
/// (pubspec hooks: source: sqlcipher), same as the shipped app.
void main() {
  test('plaintext database migrates to an encrypted copy', () {
    final dir = Directory.systemTemp.createTempSync('cipher_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plainPath = '${dir.path}/plain.db';
    final cipherPath = '${dir.path}/cipher.db';
    const key =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    // A keyless SQLCipher database is stored as plaintext SQLite.
    final plain = sqlite3.open(plainPath);
    plain.execute('CREATE TABLE t (v TEXT)');
    plain.execute("INSERT INTO t VALUES ('hisably-secret-row')");
    plain.dispose();

    final head = File(plainPath).openSync().readSync(15);
    expect(String.fromCharCodes(head), 'SQLite format 3');

    // The migration, statement for statement.
    final migrator = sqlite3.open(plainPath);
    migrator.execute(
        "ATTACH DATABASE '$cipherPath' AS encrypted KEY '$key'");
    migrator.execute("SELECT sqlcipher_export('encrypted')");
    migrator.execute('DETACH DATABASE encrypted');
    migrator.dispose();

    // The encrypted copy must NOT carry the plaintext header.
    final cipherHead = File(cipherPath).openSync().readSync(15);
    expect(String.fromCharCodes(cipherHead), isNot('SQLite format 3'));

    // Readable with the key…
    final withKey = sqlite3.open(cipherPath);
    withKey.execute("PRAGMA key = '$key'");
    final rows = withKey.select('SELECT v FROM t');
    expect(rows.single['v'], 'hisably-secret-row');
    withKey.dispose();

    // …and unreadable without it.
    final noKey = sqlite3.open(cipherPath);
    expect(() => noKey.select('SELECT v FROM t'),
        throwsA(anything));
    noKey.dispose();
  });
}
