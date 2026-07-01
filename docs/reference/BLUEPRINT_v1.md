# BerkahPOS v2 — Blueprint Arsitektur

> Dokumen ini adalah pedoman lengkap untuk membangun ulang BerkahPOS dari nol.
> Berisi: arsitektur, skema database, logika inti, keamanan, sinkronisasi, dan panduan UI.

---

## Konteks Bisnis

**Tipe toko:** Grosir (wholesale)
**Volume:** 37–50 transaksi/hari, avg Rp212K/transaksi
**Jam operasi:** 05:45–12:00+ (rush hour 07:00–09:00)
**SKU aktif:** 2.772 produk → 2.228 pasang produk-satuan
**Perangkat:** Beberapa HP Android, offline-first, sync lokal antar HP

---

## Stack Teknologi

```
Flutter (Dart ≥3.3.0)
├── State:      flutter_riverpod ^2.5.0 + riverpod_annotation ^2.3.0
├── Database:   drift ^2.21.0 + sqlcipher_flutter_libs ^0.5.0 (terenkripsi)
├── Router:     go_router ^14.0.0
├── Crypto:     encrypt ^5.0.0 (AES-256)
├── Scan:       mobile_scanner ^5.2.0
├── Barcode:    barcode_widget ^2.0.4
├── QR:         qr_flutter ^4.1.0
├── Printer:    print_bluetooth_thermal ^1.0.9 + esc_pos_utils_plus ^2.0.4
├── WiFi Sync:  shelf ^1.4.0 (HTTP server lokal)
├── File:       file_picker ^8.0.0
├── Fonts:      google_fonts ^6.0.0 (Inter)
└── Utils:      uuid ^4.4.0 + intl ^0.19.0 + path_provider ^2.1.0 + path ^1.9.0
```

**Tidak dipakai lagi:** `sqlite3_flutter_libs`, `bcrypt`, `supabase_flutter`

---

## Struktur Direktori

```
lib/
├── main.dart
├── core/
│   ├── database/
│   │   ├── app_database.dart          ← Drift DB, daftarkan semua tabel
│   │   ├── app_database.g.dart        ← GENERATED
│   │   └── tables/                    ← Satu file per domain
│   ├── services/
│   │   ├── crypto_service.dart        ← AES-256, PBKDF2, key derivation
│   │   ├── pairing_service.dart       ← Generate/validasi QR pairing
│   │   ├── lan_sync_service.dart      ← WiFi LAN sync (shelf server + client)
│   │   ├── db_export_service.dart     ← Export/import file .berkahpos
│   │   ├── printer_service.dart       ← BLE thermal printer
│   │   └── price_service.dart         ← Algoritma harga (tier + loyalty group)
│   ├── providers/
│   │   ├── device_provider.dart       ← Identitas device (role, nama, kode)
│   │   └── theme_provider.dart        ← Dark/light mode
│   ├── router/
│   │   └── app_router.dart            ← GoRouter, tidak ada auth redirect
│   └── theme/
│       └── app_theme.dart             ← Claude design language
├── features/
│   ├── setup/                         ← Welcome + Setup Toko Baru + Gabung Toko
│   ├── kasir/                         ← Transaksi utama
│   ├── riwayat/                       ← History + tambah bayar
│   ├── produk/                        ← CRUD produk, barcode
│   ├── pelanggan/                     ← CRUD pelanggan, poin
│   ├── laporan/                       ← Laporan (owner/asisten only)
│   └── pengaturan/                    ← Settings, sync, export, pair device
```

---

## Model Keamanan

### Tidak Ada Login — Device Identity

Sistem PIN dihapus sepenuhnya. Identitas kasir = identitas HP.

**AppSettings yang tersimpan per device:**
```
store_uuid       String  UUID unik toko
store_key        String  32-byte random, base64 — master secret
store_name       String  Nama toko
device_name      String  mis. "Kasir 1", "Owner"
device_code      String  mis. "K1", "O1"
device_role      String  owner | kasir | asisten
point_threshold  String  Rp minimum untuk 1 poin (default: "10000")
store_address    String  Alamat untuk struk
```

### Welcome Screen (First Launch)

Cek `AppSettings['store_uuid']` — jika null → tampilkan Welcome Screen.

**Dua jalur:**

```
┌─────────────────────────────────────┐
│         Selamat datang di           │
│            BerkahPOS                │
│                                     │
│  [Setup Toko Baru]  [Gabung Toko]  │
└─────────────────────────────────────┘
```

**"Setup Toko Baru" (Owner):**
1. Form: nama toko, nama device (default "Owner"), kode device (default "O1")
2. Generate `store_uuid = UUID.v4()`
3. Generate `store_key = secureRandom(32 bytes)`
4. Simpan semua ke AppSettings
5. Buka database dengan key turunan dari `store_key`
6. Langsung masuk app sebagai Owner

**"Gabung Toko" (Kasir / Asisten):**
1. Kamera scanner aktif
2. Scan QR dari HP owner
3. Parse + validasi payload (lihat format QR di bawah)
4. Cek `expires_at` — tolak jika expired
5. Simpan ke AppSettings: `store_uuid`, `store_key`, `device_role`, `device_name`, `device_code`
6. Masuk app

### Format QR Pairing

```json
{
  "store_uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "store_key": "<base64url 32 bytes>",
  "role": "kasir",
  "device_name": "Kasir 1",
  "device_code": "K1",
  "expires_at": "2026-06-11T10:05:00Z"
}
```

QR = base64url(jsonEncode(payload)) → tidak dienkripsi (hanya untuk setup, bukan transfer data).
Owner generate dari Pengaturan → "Pair Device Baru". Expired 5 menit, bisa refresh.

### Jika Kasir Iseng "Setup Toko Baru"

Dia membuat toko baru yang kosong. Database terenkripsi dengan `store_key` yang berbeda dari toko asli. Tidak bisa sync, tidak bisa lihat data toko asli. Aman.

---

## Enkripsi Menyeluruh

### 1. Database (SQLCipher)

Ganti `sqlite3_flutter_libs` → `sqlcipher_flutter_libs`.

```dart
// Di app_database.dart
Future<QueryExecutor> _openConnection() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  final file = File(path.join(dbFolder.path, 'berkah_pos.db'));
  final key = await CryptoService.getDatabaseKey(); // dari store_key di AppSettings
  return NativeDatabase.createInBackground(file, setup: (rawDb) {
    rawDb.execute("PRAGMA key='$key'");
  });
}
```

`getDatabaseKey()`: ambil `store_key` dari AppSettings → PBKDF2-SHA256 → hex string 64 char.

Database tidak bisa dibuka dengan DB browser biasa tanpa key.

### 2. WiFi Sync Payload (AES-256-CBC)

Key = PBKDF2(store_key + sync_token, iterations=10000, keyLen=32).

```dart
// Sender
final encrypted = CryptoService.encrypt(jsonEncode(payload), key: derivedKey);
await http.post(url, body: encrypted);

// Receiver
final decrypted = CryptoService.decrypt(responseBody, key: derivedKey);
final payload = jsonDecode(decrypted);
```

### 3. File Backup (.berkahpos)

Format file:
```
[8 bytes magic: 0x42455246 0x42414B50]  "BERKAHPO"
[4 bytes version: 0x00000001]
[16 bytes IV: random]
[N bytes: AES-256-CBC encrypted JSON body]
```

JSON body:
```json
{
  "exported_at": "ISO8601",
  "device_name": "Kasir 1",
  "device_code": "K1",
  "store_uuid": "...",
  "schema_version": 1,
  "transactions": [...],
  "transaction_items": [...],
  "transaction_payments": [...],
  "expenses": [...],
  "stock_ledger": [...],
  "loyalty_point_ledger": [...]
}
```

Key enkripsi file: PBKDF2(store_key + user_password, salt = store_uuid bytes).
User harus memasukkan password yang sama di semua device saat import.

---

## Skema Database (Drift Tables)

> **Prinsip:** Semua ID adalah UUID. Qty selalu double. Harga selalu int (Rupiah bulat). Hapus = void/flag, bukan DELETE.

### app_settings (Key-Value Config)

```dart
class AppSettings extends Table {
  TextColumn get key => text()();           // PK
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {key};
}
```

### products

```dart
class Products extends Table {
  TextColumn get id => text()();                              // UUID PK
  TextColumn get name => text()();
  IntColumn get productGroupId => integer().nullable()();     // FK product_groups
  TextColumn get kodeProduk => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

### product_groups

```dart
class ProductGroups extends Table {
  IntColumn get id => integer()();                  // PK (legacy ID 3–20)
  TextColumn get name => text().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

### unit_types

```dart
class UnitTypes extends Table {
  IntColumn get id => integer()();                  // PK (legacy ID 1–24)
  TextColumn get name => text()();                  // Biji, Pak, Dos, dll
  TextColumn get abbrev => text().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

### product_units

```dart
class ProductUnits extends Table {
  TextColumn get id => text()();                    // UUID PK
  TextColumn get productId => text()();             // FK products
  IntColumn get unitTypeId => integer().nullable()();
  BoolColumn get isBaseUnit => boolean().withDefault(const Constant(false))();
  RealColumn get ratioToBase => real().withDefault(const Constant(1.0))();
  BoolColumn get isNonStock => boolean().withDefault(const Constant(false))();
  @override Set<Column> get primaryKey => {id};
}
```

### product_barcodes

```dart
class ProductBarcodes extends Table {
  TextColumn get id => text()();                    // UUID PK
  TextColumn get productUnitId => text()();         // FK product_units
  TextColumn get barcode => text().unique()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  BoolColumn get isGenerated => boolean().withDefault(const Constant(false))();
  @override Set<Column> get primaryKey => {id};
}
```

### price_tiers

```dart
class PriceTiers extends Table {
  TextColumn get id => text()();                    // UUID PK
  TextColumn get productUnitId => text()();         // FK product_units
  IntColumn get minQty => integer().withDefault(const Constant(1))();
  IntColumn get price => integer()();               // Rupiah
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

### customer_groups

```dart
class CustomerGroups extends Table {
  TextColumn get id => text()();                    // UUID PK
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

### customer_group_prices

```dart
class CustomerGroupPrices extends Table {
  TextColumn get id => text()();
  TextColumn get productUnitId => text()();
  TextColumn get customerGroupId => text()();
  IntColumn get price => integer()();
  // Unique: (productUnitId, customerGroupId)
  @override Set<Column> get primaryKey => {id};
}
```

### customers

```dart
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get customerGroupId => text().nullable()();
  IntColumn get creditLimit => integer().withDefault(const Constant(0))();
  IntColumn get outstandingDebt => integer().withDefault(const Constant(0))();
  IntColumn get loyaltyPoints => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

### transactions

```dart
class Transactions extends Table {
  TextColumn get id => text()();                    // UUID PK
  TextColumn get localId => text().unique()();      // Format: K1-20260611-0001
  TextColumn get kasirId => text().nullable()();    // device_code, bukan FK ke Users
  TextColumn get customerId => text().nullable()();
  TextColumn get status => text()();                // lunas | kurang_bayar | tempo | void
  IntColumn get total => integer()();
  IntColumn get paid => integer()();
  IntColumn get changeAmount => integer()();
  TextColumn get paymentMethod => text()();         // tunai | transfer | qris | tempo
  TextColumn get internalNote => text().nullable()();
  TextColumn get strukNote => text().nullable()();
  IntColumn get pointsEarned => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

### transaction_items

```dart
class TransactionItems extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  TextColumn get productId => text()();
  TextColumn get productUnitId => text()();
  RealColumn get qty => real()();                   // Support 0.25, 0.5 kg dll
  IntColumn get priceAtSale => integer()();         // Harga setelah override
  IntColumn get originalPrice => integer()();       // Harga dari algoritma, sebelum override
  BoolColumn get priceOverridden => boolean().withDefault(const Constant(false))();
  IntColumn get costAtSale => integer().withDefault(const Constant(0))();
  IntColumn get subtotal => integer()();
  @override Set<Column> get primaryKey => {id};
}
```

### transaction_payments

```dart
class TransactionPayments extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  IntColumn get amount => integer()();
  TextColumn get method => text()();               // tunai | transfer | qris
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get kasirId => text().nullable()();   // device_code
  TextColumn get note => text().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

### stock_ledger

```dart
class StockLedger extends Table {
  TextColumn get id => text()();
  TextColumn get productUnitId => text()();
  TextColumn get type => text()();  // opening | sale | purchase | return_in | return_out | adjustment
  RealColumn get qtyChange => real()();             // Positif = masuk, Negatif = keluar
  RealColumn get stockAfter => real()();            // Running balance
  TextColumn get referenceId => text().nullable()();
  TextColumn get kasirId => text().nullable()();    // device_code
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

### expenses

```dart
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get localId => text().unique()();
  TextColumn get type => text()();  // daily_expense | owner_withdrawal | supplier_payment | change_given
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get kasirId => text().nullable()();    // device_code
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

### loyalty_point_ledger

```dart
class LoyaltyPointLedger extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get type => text()();                  // earn | redeem | adjust
  IntColumn get points => integer()();              // Positif atau negatif
  TextColumn get referenceId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

### suppliers

```dart
class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  IntColumn get outstandingDebt => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

### purchases + purchase_items

```dart
class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get localId => text().unique()();
  TextColumn get supplierId => text().nullable()();
  TextColumn get kasirId => text().nullable()();    // device_code
  TextColumn get status => text()();                // draft | received | partial
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get paid => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text()();
  TextColumn get productUnitId => text()();
  RealColumn get qty => real()();
  IntColumn get pricePerUnit => integer()();
  IntColumn get subtotal => integer()();
  @override Set<Column> get primaryKey => {id};
}
```

### kasir_permissions (key-value, bukan per-user)

```dart
class KasirPermissions extends Table {
  TextColumn get permissionKey => text()();          // PK
  BoolColumn get isEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {permissionKey};
}
```

Keys: `input_stok`, `tambah_pelanggan`, `input_pengeluaran`, `input_pembelian`, `override_harga`

---

## Logika Inti

### Algoritma Harga

Prioritas (dari tinggi ke rendah):
1. **Customer Group Price** — jika customer punya group, cek `customer_group_prices`
2. **Qty Tier** — ambil tier dengan `minQty` terbesar yang ≤ qty saat ini
3. **Fallback** — tier dengan `minQty = 1`

```dart
// price_service.dart
Future<int> resolvePrice(String productUnitId, double qty, String? customerGroupId) async {
  if (customerGroupId != null) {
    final groupPrice = await db.getCustomerGroupPrice(productUnitId, customerGroupId);
    if (groupPrice != null) return groupPrice.price;
  }
  final tiers = await db.getPriceTiers(productUnitId); // sorted by minQty DESC
  return tiers.firstWhere((t) => t.minQty <= qty, orElse: () => tiers.last).price;
}
```

Override harga: hanya jika `KasirPermissions['override_harga'] = true`. Simpan `originalPrice` + `priceOverridden = true` di `transaction_items`.

### LocalID Format

```dart
// Format: {device_code}-{YYYYMMDD}-{4digit counter}
// Contoh: K1-20260611-0001
String generateLocalId(String deviceCode) {
  final today = DateFormat('yyyyMMdd').format(DateTime.now());
  final count = await db.countTodayTransactions(deviceCode) + 1;
  return '$deviceCode-$today-${count.toString().padLeft(4, '0')}';
}
```

### Poin Loyalitas

```dart
// Earned points = floor(total / point_threshold)
int calculatePoints(int total, int threshold) => total ~/ threshold;

// Catat ke loyalty_point_ledger type='earn', referenceId=transactionId
// Update customers.loyaltyPoints += points
```

Mekanisme redeem belum dikonfirmasi klien (#28) — implementasikan saja kolom `type='redeem'` di ledger, UI redeem pending.

### Stock Ledger (Append-Only)

```dart
// Setiap penjualan → insert ke stock_ledger:
StockLedgerEntry(
  type: 'sale',
  qtyChange: -item.qty,              // negatif
  stockAfter: currentStock - item.qty,
  referenceId: transactionId,
  kasirId: deviceCode,
)

// Stok terkini = stockAfter dari entry terbaru untuk productUnitId
// ATAU = sum(qtyChange) untuk productUnitId
```

### Partial Payment (Kurang Bayar)

```dart
// Transaction.status = 'kurang_bayar' jika paid < total
// Setiap pembayaran tambahan → insert TransactionPayment
// Update Transaction.paid += amount
// Jika paid >= total → update status = 'lunas'
```

### Void Transaksi

```dart
// Jangan DELETE — set Transaction.status = 'void'
// Insert stock_ledger entries kebalikan (return_in) untuk setiap item
// Batalkan poin jika sudah diberikan (loyalty_point_ledger type='adjust')
// Hanya owner/asisten yang bisa void
```

---

## WiFi LAN Sync

### Alur

```
HP A (Sender)               HP B (Receiver)
     │                            │
     ├─ Buka "Sync WiFi" ────────►│
     │                            ├─ Tampilkan QR (IP:port + token)
     │◄──── Scan QR ─────────────┤
     │                            │
     ├─ Kumpulkan delta data ─────►│
     │  (records dengan syncedAt = null)
     │                            │
     ├─ Encrypt + POST /sync ─────►│
     │                            ├─ Decrypt, insert (ON CONFLICT IGNORE)
     │                            ├─ Kumpulkan delta dari B
     │◄──── Return delta B ───────┤
     │                            │
     ├─ Decrypt, insert ──────────►│
     │                            │
     ├─ Mark syncedAt = now() ────►│
     └────────────────────────────┘
```

### Server (shelf di HP B)

```dart
// lib/core/services/lan_sync_service.dart

void startServer() async {
  final token = _generateToken(); // 6 char random alphanumeric
  final ip = await _getLocalIP();
  
  final handler = Pipeline()
    .addMiddleware(_authMiddleware(token))
    .addHandler(_syncHandler);
    
  _server = await serve(handler, ip, 7788);
  showQR('$ip:7788?token=$token');
}

Response _syncHandler(Request req) async {
  final body = await req.readAsString();
  final token = req.url.queryParameters['token']!;
  final key = CryptoService.deriveSyncKey(storeKey, token);
  
  final incoming = jsonDecode(CryptoService.decrypt(body, key));
  await _applyDelta(incoming);
  
  final outgoing = await _collectDelta();
  return Response.ok(CryptoService.encrypt(jsonEncode(outgoing), key));
}
```

### Tabel yang Disync

| Tabel | Arah | Conflict Strategy |
|---|---|---|
| transactions | bidirectional | ON CONFLICT IGNORE (UUID unik per device) |
| transaction_items | bidirectional | ON CONFLICT IGNORE |
| transaction_payments | bidirectional | ON CONFLICT IGNORE |
| expenses | bidirectional | ON CONFLICT IGNORE |
| stock_ledger | bidirectional | ON CONFLICT IGNORE |
| loyalty_point_ledger | bidirectional | ON CONFLICT IGNORE |
| products | bidirectional | Last-Write-Wins (updatedAt) |
| customers | bidirectional | Last-Write-Wins (updatedAt) |
| price_tiers | bidirectional | Last-Write-Wins |
| purchases | bidirectional | ON CONFLICT IGNORE |

### Tracking Delta

Tambahkan kolom `syncedAt DateTime? nullable` di tabel ledger/transaksi.
Delta = records dengan `syncedAt IS NULL` atau `updatedAt > lastSyncTime`.
Setelah sync sukses → update `syncedAt = DateTime.now()`.

---

## File Sync (.berkahpos)

### Export

```dart
// lib/core/services/db_export_service.dart

Future<File> exportToFile(String password) async {
  final delta = await _collectAllUnsyncedRecords();
  final jsonBody = jsonEncode(delta);
  
  final key = CryptoService.deriveFileKey(storeKey, password, storeUuid);
  final iv = CryptoService.randomIV();
  final encrypted = CryptoService.encrypt(jsonBody, key: key, iv: iv);
  
  final magic = Uint8List.fromList([0x42,0x45,0x52,0x46,0x42,0x41,0x4B,0x50]);
  final version = Uint8List.fromList([0,0,0,1]);
  
  final file = File('${exportDir}/backup_${timestamp}.berkahpos');
  await file.writeAsBytes([...magic, ...version, ...iv.bytes, ...encrypted]);
  return file;
}
```

### Import

```dart
Future<int> importFromFile(File file, String password) async {
  final bytes = await file.readAsBytes();
  // Validasi magic bytes
  if (!_validateMagic(bytes)) throw FormatException('Bukan file .berkahpos valid');
  
  final iv = bytes.sublist(12, 28);
  final encrypted = bytes.sublist(28);
  
  final key = CryptoService.deriveFileKey(storeKey, password, storeUuid);
  final jsonBody = CryptoService.decrypt(encrypted, key: key, iv: iv);
  final data = jsonDecode(jsonBody);
  
  // Validasi store_uuid cocok
  if (data['store_uuid'] != storeUuid) throw Exception('File dari toko berbeda');
  
  return await _applyDelta(data);
}
```

---

## Routing (GoRouter)

```dart
// Tidak ada auth redirect — cukup setup check

GoRouter(
  initialLocation: '/kasir',
  redirect: (ctx, state) {
    final isSetup = ref.read(deviceProvider).isConfigured;
    if (!isSetup && state.matchedLocation != '/setup') return '/setup';
    return null;
  },
  routes: [
    GoRoute(path: '/setup', builder: (_,__) => SetupScreen()),
    GoRoute(path: '/setup/pair', builder: (_,__) => PairingScreen()),
    ShellRoute(
      builder: (ctx, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/kasir', ...),
        GoRoute(path: '/riwayat', ...),
        GoRoute(path: '/produk', ...),
        GoRoute(path: '/pelanggan', ...),
        // Hanya muncul jika device_role = owner | asisten:
        GoRoute(path: '/laporan', ...),
        GoRoute(path: '/pengaturan', ...),
      ],
    ),
  ],
)
```

MainShell menampilkan tab `/laporan` hanya jika `deviceRole == 'owner' || deviceRole == 'asisten'`.

---

## UI Design Language

### Color Scheme (Claude-Inspired)

```dart
// lib/core/theme/app_theme.dart

final lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFD97757),    // Copper/terracotta
    brightness: Brightness.light,
  ).copyWith(
    surface: const Color(0xFFFAF9F5),      // Warm off-white
    background: const Color(0xFFF5F0EB),   // Slightly darker warm bg
  ),
  textTheme: GoogleFonts.interTextTheme(),
  useMaterial3: true,
  cardTheme: const CardTheme(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      side: BorderSide(color: Color(0xFFE8E2DB), width: 0.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      minimumSize: const Size(double.infinity, 48),
    ),
  ),
);

final darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFD97757),
    brightness: Brightness.dark,
  ).copyWith(
    surface: const Color(0xFF272320),
    background: const Color(0xFF1C1917),   // Warm dark brown
  ),
  textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  useMaterial3: true,
  // card, button sama dengan light
);
```

### Design Principles

- **Padding:** 16px luar (page), 12px inner (card), 8px antar item list
- **Card:** `elevation: 0`, `borderRadius: 12`, border `0.5px` dari `colorScheme.outline`
- **Tombol utama:** `FilledButton`, lebar penuh, tinggi 48px
- **Tombol sekunder:** `OutlinedButton` — tidak ada `ElevatedButton`
- **Icon:** `outlined` style (bukan filled)
- **Typography:** Inter, gunakan `titleLarge` untuk heading halaman, `bodyMedium` untuk list item
- **Bottom nav:** label selalu tampil, icon outlined

---

## Inisialisasi Database

```dart
// Default data saat onCreate:

// AppSettings
{'store_name': 'BerkahPOS', 'store_address': '', 'point_threshold': '10000'}

// KasirPermissions (semua default OFF)
['input_stok', 'tambah_pelanggan', 'input_pengeluaran', 'input_pembelian', 'override_harga']

// UnitTypes (dari legacy CSV)
[{1: 'Biji'}, {2: 'Pak'}, {3: 'Dos'}, {4: 'Ret'}, {5: 'Sak'}, {6: 'Kg'}, ...]
// Catatan: ID 7 dan 8 di legacy = 'Biji', merge ke ID 1

// ProductGroups (nama NULL, diisi manual)
[{3: null}, {4: null}, ..., {20: null}]
```

---

## ETL Import Produk (dari CSV Sistem Lama)

Script: `scripts/etl_products.py`

```bash
python scripts/etl_products.py --csv Products.csv --db berkah_pos.db
```

**Aturan import:**
- Import SEMUA 2.772 baris (termasuk HJ=0)
- 18 duplikat dihapus
- 773 produk tanpa barcode → generate barcode via app atau pre-generate
- ID unit 7 & 8 di-merge ke 'Biji'
- Harga → `price_tiers` dengan `minQty=1`
- Harga pokok (HPP) → `cost_price` di `price_tiers`

---

## Fitur per Screen

### /setup (Welcome + Wizard)

- Welcome screen 2 tombol: "Setup Toko Baru" / "Gabung Toko"
- Setup form: nama toko, nama device, kode device
- Pairing screen: kamera scanner + field manual

### /pengaturan → "Pair Device Baru" (Owner only)

- Pilih role + nama device baru
- Tampilkan QR countdown 5 menit
- Tombol refresh QR
- Hanya tampil jika `device_role = owner`

### /kasir

- Search produk: nama, barcode (scan/ketik), kode produk
- Cart dengan qty input (support desimal: 0.25, 0.5, 1, dst)
- Harga otomatis dari `price_service.resolvePrice()`
- Override harga (jika permission ON): field edit harga inline
- Pilih pelanggan → apply loyalty price otomatis
- Pilih metode bayar
- Input bayar → hitung kembalian / status kurang_bayar
- Catatan internal + catatan struk
- Cetak struk Bluetooth setelah transaksi

### /riwayat

- List transaksi (filter: tanggal, kasir, status, pelanggan)
- Detail → reprint struk
- Tambah bayar (kurang_bayar → lunas)
- Void (owner/asisten only, konfirmasi dialog)

### /produk

- List + search (nama, barcode, kode, group)
- Filter aktif/nonaktif
- Tampilkan stok (dari `stock_ledger`)
- Form CRUD produk: nama, group, satuan, harga tier, HPP, barcode
- Generate barcode untuk produk tanpa barcode
- Print label barcode (Bluetooth)

### /pelanggan

- List + search
- Form CRUD: nama, telepon, alamat, group, credit limit
- Tampilkan poin loyalitas + histori poin
- Tampilkan piutang (warning, tidak blokir transaksi)

### /laporan (owner + asisten only)

- Penjualan: harian, per kasir, per jam, per produk
- Arus kas: pemasukan vs pengeluaran
- Pengeluaran: 4 tipe (daily_expense, owner_withdrawal, supplier_payment, change_given)
- Stok: stok terkini, produk low-stock
- Piutang pelanggan
- Poin loyalitas
- Keuntungan kotor (disclaimer jika ada cost_price = 0)

### /pengaturan

- Info toko (nama, alamat)
- Point threshold
- Toggle permission kasir (5 permission keys)
- Import produk CSV
- Export/Import file .berkahpos (sync via file)
- WiFi LAN sync
- Pair device baru (owner only)
- Printer Bluetooth: pilih + test print
- Dark/light mode toggle

---

## Catatan Pending

- **#28 Redeem Poin:** Berapa poin = berapa rupiah diskon? Konfirmasi klien sebelum implementasi UI redeem. Infrastruktur sudah ada (`type='redeem'` di ledger).

---

## Perintah Setup Development

```bash
# Install dependencies
flutter pub get

# Generate kode (Drift + Riverpod)
dart run build_runner build --delete-conflicting-outputs

# Run debug (tanpa Supabase)
flutter run

# Build APK release
flutter build apk --release

# Import produk dari CSV
python scripts/etl_products.py --csv path/to/Products.csv --db path/to/berkah_pos.db
```

---

*Dokumen ini self-contained. Untuk pertanyaan bisnis atau data: lihat `docs/POS_Grosir_Technical_Report_v6.md`.*
