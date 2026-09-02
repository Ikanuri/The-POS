import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laci_meja/preorder_report.dart';

/// Susulan dashboard Laci Meja tab Pre-order (permintaan user) — tombol
/// "Salin Laporan". Test ini HANYA menguji logic murni penyusun teks
/// (`buildPreorderReportText`), terpisah dari widget tombolnya (lihat
/// `preorder_report_copy_button_test.dart` utk widget test tombol +
/// `Clipboard.setData`).
void main() {
  final now = DateTime(2026, 9, 2, 14, 35);

  PreorderEntry entry({
    required String id,
    required String productId,
    String productUnitId = 'U1',
    String? transactionId,
    String? customerId,
    required String customerName,
    required double qtyOrdered,
    double depositQty = 0,
    bool paid = false,
    required DateTime createdAt,
  }) =>
      PreorderEntry(
        id: id,
        productId: productId,
        productUnitId: productUnitId,
        transactionId: transactionId,
        customerId: customerId,
        customerName: customerName,
        qtyOrdered: qtyOrdered,
        depositQty: depositQty,
        paid: paid,
        locallyModified: false,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  const labels = {
    'U1': (productName: 'LPG', unitName: 'tabung'),
    'U2': (productName: 'Beras 25kg', unitName: 'karung'),
  };

  group('Format A — satu produk (filter aktif atau cuma 1 produk terbuka)', () {
    test('contoh persis yang disetujui user', () {
      final budi = entry(
        id: 'e1',
        productId: 'p-lpg',
        transactionId: 'tx1',
        customerId: 'c1',
        customerName: 'Budi Santoso (lama)',
        qtyOrdered: 5,
        depositQty: 5,
        paid: false,
        createdAt: DateTime(2026, 8, 28, 9, 12),
      );
      final siti = entry(
        id: 'e2',
        productId: 'p-lpg',
        transactionId: 'tx2',
        customerId: null,
        customerName: 'Siti',
        qtyOrdered: 3,
        depositQty: 3,
        paid: true,
        createdAt: DateTime(2026, 8, 30, 16, 40),
      );
      final warungJaya = entry(
        id: 'e3',
        productId: 'p-lpg',
        transactionId: 'tx3',
        customerId: 'c3',
        customerName: 'Warung Jaya',
        qtyOrdered: 4,
        depositQty: 0,
        paid: false,
        createdAt: DateTime(2026, 9, 1, 11, 5),
      );

      final text = buildPreorderReportText(
        items: [budi, siti, warungJaya],
        productFilter: 'p-lpg',
        takenQty: {'e1': 2}, // Budi dipenuhi 2 dari 5, sisa 3
        productUnitLabels: labels,
        customerNames: {'tx1': 'Budi Santoso'}, // nama TERKINI dari nota
        now: now,
      );

      const expected = 'LAPORAN PRE-ORDER — LPG\n'
          'Dicetak: 02/09/2026 14:35\n'
          'Total terbuka: 3 entri, 12 tabung, **8 jaminan**\n'
          '\n'
          '1. Budi Santoso\n'
          '   Pesan 5 LPG - Sisa 3 - 5 jaminan - Tempo\n'
          '   Dipesan 28/08/2026 09:12 (5 hari lalu) - Dipenuhi 2 dari 5\n'
          '\n'
          '2. Siti (Umum)\n'
          '   Pesan 3 LPG - Sisa 3 - 3 jaminan - Lunas\n'
          '   Dipesan 30/08/2026 16:40 (3 hari lalu)\n'
          '\n'
          '3. Warung Jaya\n'
          '   Pesan 4 LPG - Sisa 4 - Tempo\n'
          '   Dipesan 01/09/2026 11:05 (1 hari lalu)\n'
          '\n'
          '**Total jaminan: 8**';

      expect(text, expected);
    });

    test('filter "Semua Produk" tapi cuma 1 produk terbuka -> tetap Format A',
        () {
      final e = entry(
        id: 'e1',
        productId: 'p-lpg',
        customerName: 'Umum',
        qtyOrdered: 2,
        createdAt: DateTime(2026, 9, 1),
      );
      final text = buildPreorderReportText(
        items: [e],
        productFilter: null,
        takenQty: const {},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );
      expect(text, startsWith('LAPORAN PRE-ORDER — LPG\n'));
    });

    test('entri tanpa jaminan tidak menampilkan segmen "- N jaminan"', () {
      final e = entry(
        id: 'e1',
        productId: 'p-lpg',
        transactionId: 'tx1',
        customerName: 'Umum',
        qtyOrdered: 2,
        depositQty: 0,
        createdAt: DateTime(2026, 9, 1),
      );
      final text = buildPreorderReportText(
        items: [e],
        productFilter: 'p-lpg',
        takenQty: const {},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );
      expect(text, contains('Pesan 2 LPG - Sisa 2 - Tempo'));
      expect(text, isNot(contains('jaminan -')));
    });

    test('entri tanpa transactionId -> status disembunyikan (bukan error)',
        () {
      final e = entry(
        id: 'e1',
        productId: 'p-lpg',
        transactionId: null,
        customerName: 'Titip Wadah',
        qtyOrdered: 1,
        depositQty: 2,
        createdAt: DateTime(2026, 9, 1),
      );
      final text = buildPreorderReportText(
        items: [e],
        productFilter: 'p-lpg',
        takenQty: const {},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );
      expect(text, contains('Pesan 1 LPG - Sisa 1 - 2 jaminan\n'));
      expect(text, isNot(contains('Tempo')));
      expect(text, isNot(contains('Lunas')));
    });

    test('total jaminan 0 tetap ditulis dibold, tidak disembunyikan', () {
      final e = entry(
        id: 'e1',
        productId: 'p-lpg',
        customerName: 'Umum',
        qtyOrdered: 2,
        depositQty: 0,
        createdAt: DateTime(2026, 9, 1),
      );
      final text = buildPreorderReportText(
        items: [e],
        productFilter: 'p-lpg',
        takenQty: const {},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );
      expect(text, contains('**0 jaminan**'));
      expect(text, endsWith('**Total jaminan: 0**'));
    });

    test('tidak ada entri sama sekali -> laporan kosong tanpa error', () {
      final text = buildPreorderReportText(
        items: const [],
        productFilter: null,
        takenQty: const {},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );
      expect(text, contains('LAPORAN PRE-ORDER TERBUKA'));
      expect(text, contains('Total terbuka: 0 entri, **0 jaminan**'));
      expect(text, endsWith('**Total jaminan: 0**'));
    });
  });

  group('Format B — >1 produk & filter "Semua Produk"', () {
    test('contoh persis yang disetujui user', () {
      final budi = entry(
        id: 'e1',
        productId: 'p-lpg',
        transactionId: 'tx1',
        customerId: 'c1',
        customerName: 'Budi Santoso',
        qtyOrdered: 5,
        depositQty: 5,
        paid: false,
        createdAt: DateTime(2026, 8, 28, 9, 12),
      );
      final siti = entry(
        id: 'e2',
        productId: 'p-lpg',
        transactionId: 'tx2',
        customerId: null,
        customerName: 'Siti',
        qtyOrdered: 3,
        depositQty: 3,
        paid: true,
        createdAt: DateTime(2026, 8, 30, 16, 40),
      );
      final warungJaya = entry(
        id: 'e3',
        productId: 'p-beras',
        productUnitId: 'U2',
        transactionId: 'tx3',
        customerId: 'c3',
        customerName: 'Warung Jaya',
        qtyOrdered: 4,
        depositQty: 0,
        paid: false,
        createdAt: DateTime(2026, 9, 1, 11, 5),
      );

      final text = buildPreorderReportText(
        items: [budi, siti, warungJaya],
        productFilter: null,
        takenQty: {'e1': 2},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );

      const expected = 'LAPORAN PRE-ORDER TERBUKA\n'
          'Dicetak: 02/09/2026 14:35\n'
          'Total terbuka: 3 entri, **8 jaminan**\n'
          '\n'
          '=== LPG (2 pesanan, 8 tabung, 8 jaminan) ===\n'
          '1. Budi Santoso: Sisa 3 dari 5 - 5 jaminan - Tempo '
          '(dipesan 28/08, 5 hari lalu, dipenuhi 2/5)\n'
          '2. Siti (Umum): Sisa 3 - 3 jaminan - Lunas '
          '(dipesan 30/08, 3 hari lalu)\n'
          '\n'
          '=== Beras 25kg (1 pesanan) ===\n'
          '3. Warung Jaya: Sisa 4 - Tempo (dipesan 01/09, 1 hari lalu)\n'
          '\n'
          '**Total jaminan: 8**';

      expect(text, expected);
    });

    test('nomor urut BERKELANJUTAN lintas kelompok, bukan reset', () {
      final a = entry(
        id: 'a',
        productId: 'p1',
        customerName: 'A',
        qtyOrdered: 1,
        createdAt: DateTime(2026, 8, 1),
      );
      final b = entry(
        id: 'b',
        productId: 'p2',
        productUnitId: 'U2',
        customerName: 'B',
        qtyOrdered: 1,
        createdAt: DateTime(2026, 8, 2),
      );
      final c = entry(
        id: 'c',
        productId: 'p1',
        customerName: 'C',
        qtyOrdered: 1,
        createdAt: DateTime(2026, 8, 3),
      );
      final text = buildPreorderReportText(
        items: [a, b, c],
        productFilter: null,
        takenQty: const {},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );
      // Grup p1 (A, lalu C krn urutan kemunculan produk pertama kali),
      // nomor tetap lanjut 1, 2 di grup p1, lalu 3 di grup p2 — TAPI
      // urutan grup mengikuti kemunculan PERTAMA (p1 duluan krn A duluan).
      expect(text, contains('1. A'));
      expect(text, contains('2. C'));
      expect(text, contains('3. B'));
    });

    test('grup >1 entri: header tampilkan qty & jaminan agregat', () {
      final a = entry(
        id: 'a',
        productId: 'p1',
        customerName: 'A',
        qtyOrdered: 3,
        depositQty: 1,
        createdAt: DateTime(2026, 8, 1),
      );
      final b = entry(
        id: 'b',
        productId: 'p1',
        customerName: 'B',
        qtyOrdered: 2,
        depositQty: 0,
        createdAt: DateTime(2026, 8, 2),
      );
      final c = entry(
        id: 'c',
        productId: 'p2',
        productUnitId: 'U2',
        customerName: 'C',
        qtyOrdered: 1,
        createdAt: DateTime(2026, 8, 3),
      );
      final text = buildPreorderReportText(
        items: [a, b, c],
        productFilter: null,
        takenQty: const {},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );
      expect(text, contains('=== LPG (2 pesanan, 5 tabung, 1 jaminan) ==='));
    });
  });

  group('Cakupan filter produk', () {
    test('filter LPG hanya menyertakan entri LPG, bukan produk lain', () {
      final lpg = entry(
        id: 'e1',
        productId: 'p-lpg',
        customerName: 'A',
        qtyOrdered: 1,
        createdAt: DateTime(2026, 9, 1),
      );
      final beras = entry(
        id: 'e2',
        productId: 'p-beras',
        productUnitId: 'U2',
        customerName: 'B',
        qtyOrdered: 1,
        createdAt: DateTime(2026, 9, 1),
      );
      final text = buildPreorderReportText(
        items: [lpg, beras],
        productFilter: 'p-lpg',
        takenQty: const {},
        productUnitLabels: labels,
        customerNames: const {},
        now: now,
      );
      expect(text, isNot(contains('Beras')));
      expect(text, contains('Total terbuka: 1 entri'));
    });
  });
}
