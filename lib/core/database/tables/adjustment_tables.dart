import 'package:drift/drift.dart';

/// Jejak audit per-PRODUK untuk retur/edit item nota (4 fungsi mutasi:
/// [AppDatabase.returnUnpaidTransactionItems], [AppDatabase.editUnpaidTransactionItem],
/// [AppDatabase.returnPaidTransactionItems], [AppDatabase.editPaidTransactionItem]).
///
/// Kenapa tabel baru: 3 dari 4 fungsi itu MENGUBAH/MENGHAPUS baris
/// `transaction_items` IN PLACE (bukan menyisipkan baris baru) — begitu
/// mutasi selesai, produk/qty/harga yang diretur/diedit PERMANEN tidak bisa
/// direkonstruksi lagi dari skema lama. Baris di sini disisipkan SEKALI saat
/// momen retur/edit terjadi, sebelum data lama itu hilang — insert-only,
/// tidak pernah diupdate/dihapus setelahnya (murni jejak audit).
///
/// Satu baris = SATU produk dalam SATU momen retur/edit. [paymentId] menaut
/// ke baris "penanda momen" di `transaction_payments` (marker Rp0 utk nota
/// belum-lunas, atau baris refund sungguhan utk nota lunas) — momen dgn
/// beberapa produk sekaligus (retur multi-item) punya beberapa baris di sini
/// dgn `paymentId` yang SAMA. Dipakai kartu "Riwayat Pembayaran" in-app
/// (`receipt_screen.dart`) utk menampilkan rincian per-produk tiap momen.
class TransactionAdjustmentLines extends Table {
  TextColumn get id => text()();
  TextColumn get paymentId => text()();
  TextColumn get transactionId => text()();
  TextColumn get productId => text()();
  TextColumn get productUnitId => text()();

  /// Snapshot nama produk & satuan SAAT momen ini — bukan referensi live,
  /// supaya rincian retur/edit lama tetap benar walau produk kemudian
  /// diganti nama/dihapus.
  TextColumn get productName => text()();
  TextColumn get unitName => text()();

  RealColumn get qty => real()();
  IntColumn get priceAtSale => integer()();
  IntColumn get subtotal => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
