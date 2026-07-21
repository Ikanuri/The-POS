import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug nyata dilaporkan user: usulan harga/produk yang SUDAH direview &
/// diterapkan owner ("Terapkan") tetap terus muncul lagi di sync
/// berikutnya, seolah belum pernah di-apply.
///
/// Akar masalah: `applyProductProposals` menulis baris `products` APA
/// ADANYA dari payload usulan klien — termasuk `updated_at` LAMA (waktu
/// klien mengedit, jauh sebelum owner sempat approve). `dumpSince` (host→
/// klien, dipakai memutuskan data master apa yang dikirim balik ke bawah)
/// memfilter tabel `products` dengan `WHERE updated_at >= since`. Begitu
/// watermark download klien maju melewati timestamp lama itu (di sync-sync
/// berikutnya, hal yang WAJAR terjadi karena klien terus sync), baris hasil
/// approve ini tidak pernah lagi ikut terkirim balik ke klien — sehingga
/// `products.locally_modified` di device klien TIDAK PERNAH ke-reset ke
/// false, dan `dumpLocalProposals()` klien terus mengusulkan ulang
/// perubahan yang SEBENARNYA sudah diterapkan.
void main() {
  test(
      'applyProductProposals mencap updated_at ke SAAT INI, bukan '
      'mempertahankan timestamp lama dari usulan klien', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Klien mengedit produk ini 2 hari lalu (updated_at lama) — nilai ini
    // yang dikirim sbg bagian payload usulan (dumpLocalProposals dump apa
    // adanya dari tabel produk klien).
    final oldUpdatedAtSec = DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch ~/
        1000;

    final proposalRows = {
      'products': [
        {
          'id': 'p1',
          'name': 'Produk Usulan',
          'is_active': 1,
          'marked_out_of_stock': 0,
          'locally_modified': 1,
          'created_at': oldUpdatedAtSec,
          'updated_at': oldUpdatedAtSec,
        },
      ],
    };

    // Dibulatkan ke detik SEBELUM apply (sama seperti presisi penyimpanan
    // `updated_at`, unix detik) supaya perbandingan tidak flaky akibat
    // pembulatan-ke-bawah milidetik.
    final beforeApplySec =
        DateTime.now().subtract(const Duration(seconds: 1));
    await db.applyProductProposals(proposalRows, {'p1'});

    final row = await (db.select(db.products)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(row.locallyModified, isFalse,
        reason: 'host adalah sumber kebenaran baru setelah approve');
    expect(
        row.updatedAt.isAfter(beforeApplySec) ||
            row.updatedAt.isAtSameMomentAs(beforeApplySec),
        isTrue,
        reason: 'updated_at HARUS dicap ke saat approve (sekarang), bukan '
            'timestamp lama dari usulan klien — kalau tidak, baris ini jatuh '
            'di bawah watermark download klien pada sync berikutnya dan '
            'TIDAK PERNAH terkirim balik utk mereset locally_modified klien');

    // Sync berikutnya (host→klien): klien sudah maju watermark-nya melewati
    // waktu edit asli tapi SEBELUM saat approve barusan — baris HARUS tetap
    // ikut terkirim supaya locally_modified klien ter-reset.
    final sinceAfterOriginalEdit =
        DateTime.now().subtract(const Duration(hours: 1));
    final dump = await db.dumpSince(sinceAfterOriginalEdit);
    final products = dump['products'] ?? const [];
    expect(products.any((r) => r['id'] == 'p1'), isTrue,
        reason:
            'produk yang baru di-approve harus ikut dumpSince berikutnya '
            'supaya benar-benar sampai balik ke klien (tanpa ini, usulan '
            'yang sudah diterapkan akan terus muncul lagi selamanya)');
  });
}
