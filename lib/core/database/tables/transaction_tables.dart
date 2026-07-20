import 'package:drift/drift.dart';

/// Status: lunas | kurang_bayar | tempo | void
class Transactions extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get localId => text().unique()(); // K1-20260611-0001
  TextColumn get kasirId => text().nullable()(); // device_code
  TextColumn get customerId => text().nullable()();

  /// Nama pembeli ad-hoc (bukan pelanggan terdaftar).
  /// customerId != null  -> pelanggan terdaftar (customerName diabaikan)
  /// customerName != null -> pembeli umum bernama, TIDAK masuk tabel customers
  /// keduanya null        -> ditampilkan sebagai "Umum"
  TextColumn get customerName => text().nullable()();

  TextColumn get status => text()();
  IntColumn get total => integer()();
  IntColumn get paid => integer()();
  IntColumn get changeAmount => integer()();
  TextColumn get paymentMethod =>
      text()(); // tunai | transfer | qris | ewallet | tempo
  TextColumn get internalNote => text().nullable()();
  TextColumn get strukNote => text().nullable()();

  /// Nama pegawai toko yang melayani / mengambilkan barang pada nota ini.
  /// Disimpan sebagai snapshot nama (denormalisasi) agar tetap akurat meski
  /// pegawai dihapus dari master. null = tidak diinput.
  TextColumn get employeeName => text().nullable()();

  IntColumn get pointsEarned => integer().withDefault(const Constant(0))();

  /// true bila kembalian sudah benar-benar diserahkan ke pembeli. Berguna
  /// untuk nota yang barangnya diambil belakangan — dicentang manual di
  /// struk agar kasir lain tidak memberikan kembalian dua kali. Murni
  /// per-perangkat (tidak ikut sync — sama seperti edit strukNote/
  /// internalNote setelah nota dibuat).
  BoolColumn get changeTaken => boolean().withDefault(const Constant(false))();

  /// ID baris `transaction_items` yang sudah dicentang "diverifikasi/
  /// diserahkan" di struk in-app — JSON array of String. null/kosong =
  /// belum ada yang dicentang. Murni per-perangkat (tidak ikut sync — sama
  /// seperti `changeTaken`/`internalNote` setelah nota dibuat).
  TextColumn get checkedItemIds => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TransactionItems extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get productId => text()();
  TextColumn get productUnitId => text()();
  RealColumn get qty => real()(); // support desimal: 0.25, 0.5 kg
  IntColumn get priceAtSale => integer()(); // harga final setelah override
  IntColumn get originalPrice => integer()(); // harga dari algoritma
  BoolColumn get priceOverridden =>
      boolean().withDefault(const Constant(false))();
  IntColumn get costAtSale => integer().withDefault(const Constant(0))();
  TextColumn get itemNote =>
      text().nullable()(); // catatan item, muncul di struk
  IntColumn get subtotal => integer()();

  /// Waktu item ditambahkan SETELAH transaksi awal selesai (fitur "tambah
  /// belanjaan"). null = item asli saat transaksi dibuat. Terisi = item susulan;
  /// dipakai struk in-app untuk memberi pembatas "Tambahan <jam>".
  DateTimeColumn get addedAt => dateTime().nullable()();

  /// Item 49g — waktu baris retur INI dibuat (nota SUDAH LUNAS). null =
  /// baris penjualan biasa (baik asli maupun susulan). Terisi = baris retur
  /// (selalu `qty` NEGATIF, item ASLI yang diretur tidak pernah dihapus/
  /// diubah) — dipakai struk utk pembatas "Retur <jam>", pola sama dgn
  /// `addedAt`/"Tambahan".
  DateTimeColumn get returnedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pembayaran bertahap untuk transaksi kurang_bayar / tempo.
class TransactionPayments extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(Transactions, #id)();
  IntColumn get amount => integer()();
  TextColumn get method => text()();
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get kasirId => text().nullable()();
  TextColumn get note => text().nullable()();

  /// Kembalian yang dihasilkan OLEH pembayaran ini secara spesifik (bukan
  /// akumulatif transaksi) — dihitung & disimpan SEKALI saat baris ini
  /// dibuat (lihat `AppDatabase._computePaymentChangeGiven`). Immutable
  /// setelahnya: fakta historis "saat itu kembaliannya segini" tidak boleh
  /// berubah walau total transaksi berubah belakangan (mis. tambah
  /// belanjaan) — beda dari `Transactions.changeAmount` yang selalu
  /// dihitung ulang dari kondisi TERKINI.
  IntColumn get changeGiven => integer().withDefault(const Constant(0))();

  /// true bila kembalian baris pembayaran INI sudah diserahkan ke pembeli.
  /// Per-pembayaran (bukan per-transaksi) — nota dengan beberapa pembayaran
  /// (tambah bayar/tambah belanjaan) bisa punya beberapa kembalian terpisah,
  /// masing-masing dengan status ambil sendiri-sendiri. Murni per-perangkat
  /// (tidak ikut sync — sama seperti `Transactions.changeTaken`).
  BoolColumn get changeTaken => boolean().withDefault(const Constant(false))();

  /// true bila pembayaran ini DIBATALKAN (fitur "Batalkan Pembayaran") —
  /// baris TETAP tersimpan sbg jejak audit (kapan pernah dibayar, lalu
  /// dibatalkan), tapi TIDAK ikut dihitung ke `Transactions.paid`/status
  /// nota. Beda dari void transaksi (`Transactions.status = 'void'`, yang
  /// membatalkan SELURUH nota + stok + poin) — ini murni membatalkan SATU
  /// baris pembayaran, item & stok tidak tersentuh.
  BoolColumn get voided => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pesanan ditahan (hold) — bisa dilanjutkan kapan saja, lokal per device.
class HeldOrders extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()(); // nama pembeli / penanda
  TextColumn get cartJson => text()(); // serialized cart state
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
