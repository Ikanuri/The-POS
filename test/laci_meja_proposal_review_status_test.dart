import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/laci_meja/laci_meja_proposal_review_screen.dart';

/// Permintaan user: "apakah pre-order yang sudah dipenuhi client akan
/// muncul lagi sebagai usulan sync ke host? kalau iya, apakah itu cuma
/// riwayat sync (bukan bug)?" — jawabannya YA, itu memang riwayat sync
/// yang sah (baris berubah status -> `locally_modified` nyala lagi utk
/// dikirim ke host), TAPI layar review sebelumnya tidak menandai status
/// itu sama sekali — baris pre-order yang SUDAH "Dipenuhi" tampil identik
/// dgn pre-order BARU yang masih terbuka, bikin owner mengira ada
/// permintaan baru yang perlu ditinjau. Fix: tandai status eksplisit +
/// tampilkan baris `laci_meja_events` (riwayat "diambil sejumlah N" dkk)
/// yang sebelumnya sama sekali tidak terlihat di layar ini walau ikut
/// diterapkan.
void main() {
  Widget buildApp(PendingLaciMejaProposal proposal) => MaterialApp(
        home: LaciMejaProposalReviewScreen(proposal: proposal),
      );

  testWidgets(
      'pre-order yang SUDAH dipenuhi (fulfilled_at terisi) ditandai '
      '"Dipenuhi", bukan tampil seperti pre-order baru', (tester) async {
    final proposal = PendingLaciMejaProposal(
      id: 'p1',
      fromIp: '192.168.1.5',
      arrivedAt: DateTime.now(),
      entryCount: 1,
      rows: {
        'preorder_entries': [
          {
            'id': 'po1',
            'customer_name': 'Bu Sri',
            'qty_ordered': 5,
            'deposit_qty': 0,
            'paid': 0,
            'fulfilled_at': DateTime.now().millisecondsSinceEpoch,
            'cancelled_at': null,
          },
        ],
      },
    );

    await tester.pumpWidget(buildApp(proposal));

    expect(find.textContaining('Dipenuhi'), findsOneWidget,
        reason: 'status "Dipenuhi" harus terlihat, bukan cuma "Qty 5" '
            'polos yg terlihat seperti pesanan baru');
  });

  testWidgets(
      'pre-order yang BELUM dipenuhi (fulfilled_at & cancelled_at null) '
      'TIDAK menampilkan status apa pun', (tester) async {
    final proposal = PendingLaciMejaProposal(
      id: 'p1',
      fromIp: '192.168.1.5',
      arrivedAt: DateTime.now(),
      entryCount: 1,
      rows: {
        'preorder_entries': [
          {
            'id': 'po1',
            'customer_name': 'Bu Sri',
            'qty_ordered': 5,
            'deposit_qty': 0,
            'paid': 0,
            'fulfilled_at': null,
            'cancelled_at': null,
          },
        ],
      },
    );

    await tester.pumpWidget(buildApp(proposal));

    expect(find.textContaining('Dipenuhi'), findsNothing);
    expect(find.textContaining('Dibatalkan'), findsNothing);
  });

  testWidgets('pre-order yang DIBATALKAN ditandai "Dibatalkan"',
      (tester) async {
    final proposal = PendingLaciMejaProposal(
      id: 'p1',
      fromIp: '192.168.1.5',
      arrivedAt: DateTime.now(),
      entryCount: 1,
      rows: {
        'preorder_entries': [
          {
            'id': 'po1',
            'customer_name': 'Bu Sri',
            'qty_ordered': 5,
            'deposit_qty': 0,
            'paid': 0,
            'fulfilled_at': null,
            'cancelled_at': DateTime.now().millisecondsSinceEpoch,
          },
        ],
      },
    );

    await tester.pumpWidget(buildApp(proposal));

    expect(find.textContaining('Dibatalkan'), findsOneWidget);
  });

  testWidgets(
      'titip/ketinggalan yang SUDAH diambil (collected_at terisi) '
      'ditandai "Sudah diambil"', (tester) async {
    final proposal = PendingLaciMejaProposal(
      id: 'p1',
      fromIp: '192.168.1.5',
      arrivedAt: DateTime.now(),
      entryCount: 1,
      rows: {
        'left_behind_items': [
          {
            'id': 'l1',
            'item_name': 'Galon Aqua',
            'jenis': 'titip',
            'customer_name_text': 'Bu Ani',
            'collected_at': DateTime.now().millisecondsSinceEpoch,
          },
        ],
      },
    );

    await tester.pumpWidget(buildApp(proposal));

    expect(find.textContaining('Sudah diambil'), findsOneWidget);
  });

  testWidgets(
      'pinjaman yang SUDAH kembali semua (fully_returned_at terisi) '
      'ditandai "Sudah kembali semua"', (tester) async {
    final proposal = PendingLaciMejaProposal(
      id: 'p1',
      fromIp: '192.168.1.5',
      arrivedAt: DateTime.now(),
      entryCount: 1,
      rows: {
        'borrowed_items': [
          {
            'id': 'b1',
            'item_name': 'Tabung Gas',
            'qty': 2,
            'qty_returned': 2,
            'customer_name_text': 'Pak Budi',
            'fully_returned_at': DateTime.now().millisecondsSinceEpoch,
          },
        ],
      },
    );

    await tester.pumpWidget(buildApp(proposal));

    expect(find.textContaining('Sudah kembali semua'), findsOneWidget);
  });

  testWidgets(
      'baris "laci_meja_events" (riwayat ambil/penuhi/dll) SEKARANG '
      'ditampilkan sbg section tersendiri, sebelumnya sama sekali tak '
      'terlihat di layar ini', (tester) async {
    final proposal = PendingLaciMejaProposal(
      id: 'p1',
      fromIp: '192.168.1.5',
      arrivedAt: DateTime.now(),
      entryCount: 1,
      rows: {
        'laci_meja_events': [
          {
            'id': 'e1',
            'entity_type': 'preorder',
            'entry_id': 'po1',
            'aksi': 'penuhi',
            'qty': 5,
            'note': null,
          },
        ],
      },
    );

    await tester.pumpWidget(buildApp(proposal));

    expect(find.textContaining('Riwayat Kejadian'), findsOneWidget);
    expect(find.textContaining('Dipenuhi 5'), findsOneWidget);
  });
}
