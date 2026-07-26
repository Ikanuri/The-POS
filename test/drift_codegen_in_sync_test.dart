import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Pengaman bug SENYAP yang sempat memakan waktu berhari-hari (17-26 Juli):
/// anotasi `@DriftDatabase(tables: [...])` di `app_database.dart` tidak lagi
/// menempel di `class AppDatabase`, karena ada `typedef` yang tersisip di
/// antara blok anotasi dan class-nya (commit `dd4bad3`). Dart menganggap ini
/// SAH — anotasi boleh dipasang di typedef — jadi `flutter analyze` tetap
/// 0 issue dan seluruh test tetap hijau. Tapi drift_dev jadi TIDAK menemukan
/// database sama sekali (`elements: []`), sehingga `build_runner` "sukses"
/// dengan ribuan output TANPA pernah memperbarui `app_database.g.dart`.
/// Akibatnya setiap penambahan tabel/kolom baru diam-diam tidak ikut
/// ter-generate, dan itu SANGAT sulit dilacak karena tidak ada satu pun
/// pesan error di mana pun.
///
/// Dua test di bawah menutup kelas bug itu dari dua sisi: bentuk sumbernya
/// (akar masalah) dan hasil generate-nya (dampaknya).
void main() {
  final source =
      File('lib/core/database/app_database.dart').readAsStringSync();

  /// Nama class tabel yang didaftarkan di dalam `@DriftDatabase(tables: [...])`.
  List<String> tablesInAnnotation() {
    final start = source.indexOf('@DriftDatabase(tables: [');
    expect(start, isNot(-1), reason: 'anotasi @DriftDatabase tidak ditemukan');
    final end = source.indexOf('\n])', start);
    expect(end, isNot(-1), reason: 'penutup anotasi "])" tidak ditemukan');
    return RegExp(r'^\s+([A-Z][A-Za-z0-9]*),$', multiLine: true)
        .allMatches(source.substring(start, end))
        .map((m) => m.group(1)!)
        .toList();
  }

  test(
      'anotasi @DriftDatabase menempel PERSIS di class AppDatabase (tidak ada '
      'deklarasi lain yang menyelinap di antaranya)', () {
    final end = source.indexOf('\n])', source.indexOf('@DriftDatabase('));
    // Deklarasi pertama setelah blok anotasi HARUS class AppDatabase.
    // Kalau ada typedef/class/enum lain lebih dulu, anotasinya nempel ke
    // situ dan drift_dev berhenti mengenali database ini.
    final after = source
        .substring(end + 3)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty);

    expect(after, startsWith('class AppDatabase'),
        reason: 'Ada deklarasi lain tepat setelah blok @DriftDatabase, jadi '
            'anotasinya menempel ke deklarasi ITU, bukan ke AppDatabase. '
            'drift_dev akan diam-diam berhenti menghasilkan '
            'app_database.g.dart (build_runner tetap lapor "Succeeded"). '
            'Pindahkan blok @DriftDatabase agar langsung di atas '
            '"class AppDatabase", dan taruh typedef/class lain di atasnya.');
  });

  test(
      'app_database.g.dart tidak basi: semua tabel di anotasi benar-benar ada '
      'di skema hasil generate', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final declared = tablesInAnnotation();
    expect(declared, hasLength(greaterThan(20)),
        reason: 'daftar tabel gagal di-parse dari anotasi');

    expect(db.allTables.length, declared.length,
        reason: 'Jumlah tabel di @DriftDatabase (${declared.length}) tidak '
            'sama dengan yang ada di app_database.g.dart '
            '(${db.allTables.length}) — file generate-nya BASI. Jalankan '
            '"dart run build_runner build --delete-conflicting-outputs", lalu '
            'commit ulang app_database.g.dart.');
  });
}
