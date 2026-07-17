import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug dilaporkan user (ketahuan saat review riwayat transaksi di device
/// tujuan "Alihkan Owner", tapi BUKAN disebabkan fitur itu — bug lama):
/// transaksi lama yang pelanggannya SUDAH DIHAPUS (soft-delete,
/// `deactivateCustomer` → `isActive=false`) menampilkan nama generik
/// "Pelanggan" di riwayat, alih-alih nama asli. `deactivateCustomer()`
/// sendiri berkomentar "riwayat historis tetap utuh", tapi
/// `getAllCustomerNamesIncludingInactive()` yang BARU ini membuktikan
/// janji itu — beda dari `searchCustomers()` yang sengaja cuma utk daftar
/// AKTIF (dropdown pilih pelanggan baru).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('mengembalikan nama pelanggan AKTIF', () async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Bu Siti'));

    final names = await db.getAllCustomerNamesIncludingInactive();
    expect(names['c1'], 'Bu Siti');
  });

  test(
      'TETAP mengembalikan nama pelanggan yang SUDAH DIHAPUS (isActive=false) '
      '— beda dari searchCustomers() yang menyaringnya', () async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Bu Siti'));
    await db.deactivateCustomer('c1');

    final viaSearch = await db.searchCustomers('');
    expect(viaSearch.where((c) => c.id == 'c1'), isEmpty,
        reason: 'searchCustomers() memang sengaja cuma daftar aktif');

    final names = await db.getAllCustomerNamesIncludingInactive();
    expect(names['c1'], 'Bu Siti',
        reason: 'riwayat transaksi historis harus tetap tahu namanya');
  });
}
