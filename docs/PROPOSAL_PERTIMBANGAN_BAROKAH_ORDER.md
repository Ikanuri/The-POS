# Proposal Pertimbangan Barokah Order
# The POS — Kasir Griyo

**Versi:** 1.1
**Tanggal:** 29 Juni 2026
**Proyek:** The POS (Kasir Griyo)

---

## Daftar Isi

1. [Ringkasan Eksekutif](#1-ringkasan-eksekutif)
2. [Latar Belakang](#2-latar-belakang)
3. [Arsitektur Teknis The POS](#3-arsitektur-teknis-the-pos)
4. [Proposal Awal: Barokah Order (Cloud-Based)](#4-proposal-awal-barokah-order-cloud-based)
5. [Analisis Kelemahan Pendekatan Cloud](#5-analisis-kelemahan-pendekatan-cloud)
6. [Proposal Final: Static HTML + WhatsApp + Paste Parser](#6-proposal-final-static-html--whatsapp--paste-parser)
7. [Rencana Implementasi](#7-rencana-implementasi)
8. [Estimasi Dampak & Biaya](#8-estimasi-dampak--biaya)
9. [Kesimpulan](#9-kesimpulan)
10. [TL;DR](#10-tldr)

---

## 1. Ringkasan Eksekutif

Dokumen ini mengevaluasi dua pendekatan untuk membangun sistem order pelanggan yang terintegrasi dengan The POS (Kasir Griyo):

- **Pendekatan A (Ditolak):** Barokah Order — aplikasi web terpisah dengan backend Cloudflare Workers, database D1, dan API layer.
- **Pendekatan B (Direkomendasikan):** Static HTML + WhatsApp/Telegram + Paste Parser — file HTML self-contained sebagai katalog order, dikirim via WhatsApp, dan di-paste langsung ke POS.

Pendekatan B dipilih karena mengeliminasi tiga masalah fundamental sekaligus: risiko DDoS, fake order, dan biaya server — sambil memanfaatkan infrastruktur yang sudah dipakai sehari-hari oleh pelanggan (WhatsApp).

---

## 2. Latar Belakang

### 2.1 Tentang The POS

The POS (Kasir Griyo) adalah aplikasi kasir (Point of Sale) berbasis Flutter yang dirancang khusus untuk pasar retail Indonesia. Aplikasi ini bersifat **offline-first** — seluruh data tersimpan di perangkat lokal menggunakan SQLite terenkripsi (SQLCipher), dan sinkronisasi antar perangkat dilakukan melalui WiFi LAN tanpa membutuhkan koneksi internet.

**Fitur inti yang sudah berjalan:**
- Kasir lengkap dengan multi-satuan, harga bertingkat, dan varian produk
- Scan barcode via kamera dan scanner eksternal (HID) dengan umpan balik haptic
- Sinkronisasi multi-perangkat via WiFi LAN (terenkripsi AES-256, approval-gated)
- Sistem peran (Owner / Asisten / Kasir) dengan izin granular
- Cetak struk via printer thermal Bluetooth
- Laporan penjualan, stok, pelanggan, dan keuangan
- Manajemen pelanggan dengan poin loyalti dan kredit/tempo
- Import/export data (CSV, Excel, PDF)

### 2.2 Karakteristik Pengguna

| Segmen | Profil |
|---|---|
| **Pemilik toko** | Owner, mengelola harga dan stok, biasanya 1 perangkat utama |
| **Kasir** | Operator harian, menggunakan scanner dan input manual |
| **Asisten** | Peran menengah, bisa melihat laporan namun tidak mengubah harga |
| **Pelanggan** | Beragam usia termasuk kalangan yang kurang familiar dengan teknologi |

### 2.3 Kebutuhan yang Muncul

Dalam operasional toko, muncul kebutuhan agar pelanggan bisa memesan barang sebelum datang ke toko — misalnya pelanggan langganan yang ingin memesan lewat WhatsApp. Saat ini proses ini dilakukan secara manual: pelanggan mengetik pesanan di chat, kasir membaca satu per satu, lalu menginput ke POS secara manual.

Alur yang diinginkan:

```
Pelanggan memilih barang  →  Kirim pesanan  →  Kasir terima & proses cepat
```

---

## 3. Arsitektur Teknis The POS

### 3.1 Tech Stack

| Komponen | Teknologi |
|---|---|
| **Framework** | Flutter (Dart) |
| **State Management** | Riverpod v2.5 |
| **Database** | Drift ORM + SQLCipher (SQLite terenkripsi) |
| **Routing** | GoRouter v14 (ShellRoute + nested navigator) |
| **Enkripsi** | AES-256-CBC, HMAC-SHA256, PBKDF2 |
| **Sync** | HTTP POST via Shelf framework (WiFi LAN, port 8625) |
| **Hardware** | Camera (barcode), Bluetooth (printer thermal), HID (scanner eksternal) |

### 3.2 Skema Database

Sistem menggunakan **24 tabel** yang saling berelasi. Berikut tabel-tabel utama yang relevan dengan proposal ini:

#### Tabel Produk

```
products
├── id (UUID)
├── name (TEXT)
├── kodeProduk (TEXT)          ← kode SKU, dipakai sebagai identifier order
├── productGroupId (INTEGER)
├── parentProductId (TEXT)     ← untuk relasi varian (produk anak)
├── isActive (BOOLEAN)
├── createdAt, updatedAt
│
└── product_units (1:banyak)
    ├── id (UUID)
    ├── unitTypeId → unit_types.id (Kg, Pcs, Pak, dll.)
    ├── isBaseUnit, ratioToBase
    │
    ├── price_tiers (1:banyak)      ← harga bertingkat per kuantitas
    │   ├── minQty, price, costPrice
    │
    └── product_barcodes (1:banyak)  ← multi-barcode per satuan
        ├── barcode (UNIQUE)
        └── isPrimary
```

#### Tabel Transaksi

```
transactions
├── id (UUID), localId (UNIQUE, format: K1-20260629-0001)
├── customerId, customerName
├── status: lunas | kurang_bayar | tempo | void
├── total, paid, changeAmount
├── paymentMethod: tunai | transfer | qris | ewallet | tempo
│
├── transaction_items (1:banyak)
│   ├── productId, productUnitId
│   ├── qty (REAL, mendukung desimal: 0.5 kg)
│   ├── priceAtSale, originalPrice, priceOverridden
│   └── itemNote
│
└── transaction_payments (1:banyak)   ← untuk cicilan/tempo
    ├── amount, method, paidAt
```

#### Tabel Pelanggan

```
customers
├── id (UUID), name, phone, address
├── customerGroupId → customer_groups.id
├── creditLimit, outstandingDebt, loyaltyPoints
```

#### Tabel Stok & Keuangan

```
stock_ledger (append-only)          ← jejak audit stok
├── productUnitId, type, qtyChange, stockAfter

expenses                             ← pengeluaran harian
├── type: daily_expense | owner_withdrawal | supplier_payment

loyalty_point_ledger                 ← poin loyalti pelanggan
├── customerId, type: earn | redeem | adjust, points
```

### 3.3 Satuan Produk (Unit Types)

Sistem mendukung **23 jenis satuan** yang sudah diselaraskan dengan data historis:

| ID | Nama | ID | Nama | ID | Nama |
|---|---|---|---|---|---|
| 1 | Kg | 10 | Pres | 19 | Tas |
| 2 | Pcs | 11 | Ons | 20 | Ikat |
| 4 | Pak | 12 | Biji | 22 | Roll |
| 5 | Bal | 13 | Kas | 23 | Toples |
| 6 | Sak | 14 | Dos | 24 | Paket |
| 9 | Slop | 15 | Lusin | 25 | Karton |
| | | 16 | Box | | |
| | | 17 | Rek | | |
| | | 18 | Ret | | |

### 3.4 Sinkronisasi WiFi LAN

Sinkronisasi antar perangkat menggunakan model **owner-controlled, approval-gated**:

```
                    ┌──────────────┐
                    │    Owner     │
                    │  (Host/Server)│
                    └──────┬───────┘
                           │ HTTP POST :8625/sync
                           │ AES-256 + HMAC-SHA256
                    ┌──────┴───────┐
              ┌─────┤   WiFi LAN   ├─────┐
              │     └──────────────┘     │
       ┌──────┴──────┐           ┌───────┴─────┐
       │   Kasir     │           │   Asisten   │
       │  (Client)   │           │   (Client)  │
       └─────────────┘           └─────────────┘
```

**Aturan arah data:**
- **Owner → Bawahan:** Data master (produk, harga, pelanggan, izin kasir)
- **Bawahan → Owner:** Data append-only (transaksi, stok, poin, pengeluaran)
- **Persetujuan:** Owner menyetujui per kategori data sebelum merge

**Keamanan:**
- Token autentikasi 80-bit (constant-time comparison)
- HMAC-SHA256 per request (anti-tamper)
- Nonce + timestamp (anti-replay, jendela ±5 menit)
- Rate limit: 5 kegagalan → lockout IP 5 menit
- Payload terenkripsi AES-256-CBC
- Batas ukuran payload: 50 MB

### 3.5 Struktur Proyek

```
The-POS/
├── lib/
│   ├── core/
│   │   ├── database/        ← Drift ORM, 24 tabel, 2000+ baris
│   │   ├── models/          ← CartItem, ProductWithUnits
│   │   ├── providers/       ← deviceProvider, databaseProvider, theme
│   │   ├── router/          ← GoRouter dengan ShellRoute
│   │   ├── services/        ← 12 service (sync, crypto, printer, dll.)
│   │   ├── theme/           ← AppTheme, numStyle
│   │   ├── utils/           ← ThousandsSeparatorFormatter
│   │   └── widgets/         ← Shared widgets
│   │
│   └── features/
│       ├── kasir/           ← Layar kasir, cart, payment, receipt
│       ├── laporan/         ← Laporan (ringkasan, transaksi, produk)
│       ├── pelanggan/       ← CRUD pelanggan
│       ├── pengaturan/      ← Pengaturan toko, sync, backup, printer
│       ├── produk/          ← CRUD produk, barcode, harga
│       ├── ringkasan/       ← Dashboard
│       ├── setup/           ← Setup toko baru, pairing
│       └── shell/           ← Bottom navigation shell
│
├── android/                 ← Konfigurasi Android native
├── scripts/                 ← ETL, migrasi data
└── pubspec.yaml             ← 25+ dependencies
```

### 3.6 Peran & Izin Perangkat

| | Owner | Asisten | Kasir |
|---|---|---|---|
| Kelola harga & produk | Ya | Tidak | Tidak |
| Lihat laporan | Ya | Ya | Tidak |
| Host sinkronisasi | Ya | Ya | Tidak |
| Setujui data sync | Ya | Tidak | Tidak |
| Override harga | Ya | Ya | Jika diizinkan |
| Input stok | Ya | Ya | Jika diizinkan |
| Batalkan transaksi | Ya | Ya | Jika diizinkan |

---

## 4. Proposal Awal: Barokah Order (Cloud-Based)

### 4.1 Konsep

Barokah Order dirancang sebagai sistem order pelanggan berbasis cloud yang terintegrasi dengan The POS:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────┐
│   Kasir Griyo    │────>│   Cloudflare     │<────│   Barokah    │
│   (The POS)      │     │   Workers + D1   │     │   Order      │
│                  │<────│                  │     │   (Web App)  │
└──────────────────┘     └────────┬─────────┘     └──────────────┘
                                  │
                           ┌──────┴──────┐
                           │  Telegram   │
                           │  Bot API    │
                           └─────────────┘
```

### 4.2 Stack yang Direncanakan

| Komponen | Teknologi | Fungsi |
|---|---|---|
| **API Layer** | Cloudflare Workers (TypeScript, Hono) | REST API endpoint |
| **Database** | Cloudflare D1 (SQLite di edge) | Katalog, order, pelanggan |
| **Cache** | Cloudflare KV | Session, katalog snapshot |
| **Frontend** | Cloudflare Pages (static) | Web app order pelanggan |
| **Notifikasi** | Telegram Bot API | Alert order baru |
| **Auth POS-API** | HMAC dari store_key | Token-based |

### 4.3 Alur yang Dirancang

```
1. POS push katalog produk  →  Workers API  →  D1
2. Pelanggan buka web  →  pilih produk  →  submit order
3. Workers simpan order  →  kirim notif Telegram
4. POS poll antrian order  →  konfirmasi  →  masuk keranjang
5. Transaksi berjalan normal  →  nota digital (HTML via Workers)
```

### 4.4 Endpoint API

| Method | Path | Fungsi |
|---|---|---|
| POST | `/api/store/register` | Daftarkan toko |
| POST | `/api/katalog` | POS push katalog |
| GET | `/api/katalog/:storeId` | Pelanggan baca katalog |
| POST | `/api/order` | Pelanggan submit order |
| GET | `/api/order/antrian/:storeId` | POS poll order pending |
| PATCH | `/api/order/:id/status` | POS update status order |
| GET | `/api/nota/:orderId` | Nota digital (HTML) |

### 4.5 Skema D1

```sql
stores (id, name, address, phone, token_hash, telegram_chat_id)
products (id, store_id, product_name, unit_name, price, barcode)
orders (id, store_id, customer_name, customer_phone, status, total, note)
order_items (id, order_id, product_id, product_name, unit_name, price, qty, subtotal)
```

---

## 5. Analisis Kelemahan Pendekatan Cloud

### 5.1 Tiga Masalah Fundamental

Setelah evaluasi mendalam, pendekatan Barokah Order (cloud-based) memiliki tiga masalah fundamental yang sulit dimitigasi secara bersamaan:

#### Masalah 1: Kerentanan DDoS

Setiap API endpoint yang terbuka ke publik adalah target potensial DDoS. Meskipun Cloudflare menyediakan proteksi DDoS di layer network secara gratis, layer aplikasi tetap rentan:

- Rate limiting bisa di-bypass dengan IP rotation
- Endpoint `/api/order` yang menerima POST dari publik tanpa autentikasi = vektor serangan
- Untuk toko kecil, bahkan 1.000 request/menit bisa mengganggu operasional

Mitigasi yang tersedia (rate limit, payload cap, WAF rules) menambah kompleksitas operasional yang tidak proporsional untuk skala toko kecil.

#### Masalah 2: Fake Order

Ini masalah yang **jauh lebih serius** dari DDoS. Tanpa autentikasi pelanggan, siapa saja bisa submit order palsu. Opsi mitigasi:

| Metode | Efektivitas | Masalah |
|---|---|---|
| OTP SMS | Tinggi | Biaya per SMS, UX rumit, boomers kesulitan |
| OTP WhatsApp | Tinggi | Butuh WhatsApp Business API (berbayar, setup rumit) |
| reCAPTCHA | Sedang | Membingungkan pengguna awam, bot canggih bisa bypass |
| Honeypot field | Rendah | Hanya menangkap bot primitif |
| Link unik per pelanggan | Tinggi | Butuh manajemen link, bisa dishare |
| Rate limit per nomor HP | Sedang | Nomor bisa dipalsukan |

**Tidak ada solusi yang secara bersamaan simpel, aman, dan ramah pengguna awam.** Setiap mitigasi menambah gesekan UX atau kompleksitas teknis.

#### Masalah 3: Biaya & Kompleksitas Operasional

| Komponen | Biaya | Maintenance |
|---|---|---|
| Workers | Gratis (100k req/hari) lalu berbayar | Monitoring, logging, debugging |
| D1 | Gratis (5GB) lalu berbayar | Migrasi skema, backup |
| Pages | Gratis | Deploy, update UI |
| Domain | ~Rp 150.000/tahun | Renewal, DNS |
| Telegram Bot | Gratis | Monitoring uptime |
| **Total infrastruktur** | **5 komponen** | **Semua butuh maintenance** |

Untuk toko dengan 10-50 order/hari, ini adalah **over-engineering**.

### 5.2 Perbandingan Komprehensif

```
┌────────────────────┬──────────────────┬────────────────────────────┐
│     Aspek          │  Workers + D1    │  HTML + WA + Paste Parser  │
├────────────────────┼──────────────────┼────────────────────────────┤
│ DDoS risk          │  Ada             │  Tidak ada (no server)     │
│ Fake order risk    │  Tinggi          │  Nol (WA = identitas asli) │
│ Server cost        │  Ada (scalable)  │  Nol                       │
│ Auth pelanggan     │  Harus dibangun  │  WA contact = auth         │
│ Maintenance        │  API + DB + Web  │  1 file HTML               │
│ Komponen           │  5 komponen      │  0 komponen server         │
│ Boomer-friendly    │  Perlu UX effort │  WA sudah familiar         │
│ Offline-capable    │  Tidak           │  Ya (HTML file lokal)      │
│ Realtime tracking  │  Ya              │  Tidak                     │
│ Automasi tinggi    │  Ya              │  Tidak (semi-manual)       │
│ Time to market     │  4-5 minggu      │  1-2 minggu                │
│ Risiko kegagalan   │  Sedang          │  Sangat rendah             │
└────────────────────┴──────────────────┴────────────────────────────┘
```

### 5.3 Mengapa WhatsApp Adalah Layer Autentikasi Terbaik

WhatsApp secara implisit menyelesaikan tiga masalah sekaligus:

1. **Anti-DDoS:** Tidak ada server yang bisa diserang. Pesan masuk ke WhatsApp pribadi kasir/owner — infrastruktur Meta yang menangani traffic.

2. **Anti-Fake Order:** Hanya kontak yang dikenal (pelanggan nyata) yang bisa mengirim pesan. Nomor WhatsApp = identitas terverifikasi. Kasir bisa langsung konfirmasi via chat jika ada keraguan.

3. **Zero Cost:** WhatsApp gratis, sudah terinstal di hampir semua smartphone di Indonesia, dan familiar bagi semua kalangan usia.

**WhatsApp bukan hanya channel komunikasi — ia adalah sistem autentikasi, anti-spam, dan delivery yang sudah jadi, gratis, dan universal.**

---

## 6. Proposal Final: Static HTML + WhatsApp + Paste Parser

### 6.1 Konsep

```
┌─────────────────────────────────────────────────────────┐
│                     ALUR ORDER                          │
│                                                         │
│  PELANGGAN                           KASIR              │
│      │                                 │                │
│      v                                 │                │
│   Buka HTML                            │                │
│   (link / file)                        │                │
│      │                                 │                │
│      v                                 │                │
│   Pilih produk                         │                │
│   Atur jumlah                          │                │
│      │                                 │                │
│      v                                 │                │
│   Teks order muncul                    │                │
│   di bawah kotak                       │                │
│      │                                 │                │
│      v                                 │                │
│   [Salin & Kirim via WA] ────────────> │                │
│                                        v                │
│                                  Terima di WA           │
│                                  Salin teks order       │
│                                        │                │
│                                        v                │
│                                  Buka "Paste Order"     │
│                                  di POS                 │
│                                        │                │
│                                        v                │
│                                  Tempel → review        │
│                                  → masuk keranjang      │
│                                        │                │
│                                        v                │
│                                  Bayar → Struk          │
└─────────────────────────────────────────────────────────┘
```

### 6.2 Komponen Sistem

Sistem terdiri dari **tiga komponen** — dua di sisi POS, satu file HTML statis:

#### A. Order Page Generator (di POS)

POS men-generate file HTML self-contained yang berisi seluruh katalog produk sebagai data embedded. File ini bisa di-host secara gratis (lihat opsi hosting di Bab 6.7) atau dikirim langsung sebagai file via WhatsApp.

**Kapan di-generate ulang:** Saat owner mengetuk "Update Link Order" di pengaturan (setelah harga/produk berubah).

**Isi HTML:**
- Daftar produk dalam bentuk grid/list yang responsif (mobile-first)
- Tombol +/- untuk setiap produk
- Field nama, nomor HP, dan catatan
- Output teks terformat + kode mesin di bagian bawah
- Tombol "Salin & Kirim via WhatsApp" (deep link `whatsapp://send?text=...`)

#### B. Format Output Order

HTML menghasilkan teks yang **bisa dibaca manusia DAN diparsing mesin**:

```
ORDER BAROKAH
━━━━━━━━━━━━━━━
Gula Pasir 1kg × 2
Minyak Goreng 2L × 1
Beras Pandan 5kg × 3
━━━━━━━━━━━━━━━
Nama: Pak Ahmad
HP: 08123456789
Catatan: Antar sore ya

#BRK:GP1K=2;MG2L=1;BP5K=3
```

**Anatomi format:**

| Bagian | Fungsi |
|---|---|
| Header (`ORDER BAROKAH`) | Identifikasi visual |
| Daftar item (human-readable) | Bisa dibaca kasir tanpa sistem |
| Data pelanggan | Nama, HP, catatan |
| Kode mesin (`#BRK:...`) | Untuk parsing otomatis oleh POS |

**Format kode mesin:**
```
#BRK:{kodeProduk}={qty};{kodeProduk}={qty};...
```

Menggunakan field `kodeProduk` yang sudah ada di tabel `products` sebagai identifier — pendek, unik, sudah familiar bagi pemilik toko (contoh: "GP1K" untuk "Gula Pasir 1kg").

#### C. Paste Order Parser (di POS)

Fitur baru di layar kasir yang menerima teks order dari clipboard dan mengkonversinya menjadi item keranjang.

**Alur di POS:**

```
┌─────────────────────────────────┐
│  Paste Order                    │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Tempel teks order di sini │  │
│  │                           │  │
│  │ #BRK:GP1K=2;MG2L=1       │  │
│  └───────────────────────────┘  │
│                                 │
│  [  Proses Order  ]             │
│                                 │
│  ─── Hasil ───                  │
│  ✓ Gula Pasir 1kg    ×2  20rb  │
│  ✓ Minyak Goreng 2L  ×1  28rb  │
│  ✗ XYZ (tidak ditemukan)        │
│                                 │
│  Pelanggan: Pak Ahmad           │
│  Total: Rp 48.000               │
│                                 │
│  [  Masukkan ke Keranjang  ]    │
└─────────────────────────────────┘
```

**Logika parsing:**
1. Cari pola `#BRK:` dalam teks yang ditempelkan
2. Split per `;` → pasangan `{kode}={qty}`
3. Lookup setiap `kodeProduk` di database lokal
4. Tampilkan preview (termasuk item yang tidak ditemukan)
5. Setelah konfirmasi → masukkan ke keranjang sebagai `CartItem[]`
6. Lanjut ke alur bayar normal

### 6.3 File Baru di POS

```
lib/core/services/
├── order_page_service.dart      ← Generate HTML dari katalog produk
└── order_parser_service.dart    ← Parse kode #BRK:... → CartItem[]

lib/features/kasir/
└── paste_order_screen.dart      ← UI paste + preview + confirm

lib/features/pengaturan/
└── order_link_screen.dart       ← UI generate & share link order
```

### 6.4 File yang Diubah di POS

| File | Perubahan |
|---|---|
| `lib/core/database/app_database.dart` | Tambah method `getProductByKode(String kodeProduk)` dan `getPublicCatalog()` |
| `lib/core/router/app_router.dart` | Tambah route `/kasir/paste-order` dan `/pengaturan/order-link` |
| `lib/features/kasir/kasir_screen.dart` | Tambah tombol/akses ke "Paste Order" |
| `lib/features/pengaturan/pengaturan_screen.dart` | Tambah menu "Link Order Pelanggan" |

### 6.5 Spesifikasi `order_page_service.dart`

```dart
class OrderPageService {
  final AppDatabase db;

  /// Generate HTML self-contained dari katalog produk aktif.
  /// Produk diembed sebagai JSON array di dalam <script>.
  Future<String> generateHtml({
    required String storeName,
    String? storePhone,
  }) async {
    final catalog = await db.getPublicCatalog();
    // Template HTML dengan:
    // - CSS responsive (mobile-first)
    // - JavaScript: render produk, qty +/-, format output
    // - Data produk embedded sebagai: const PRODUCTS = [...];
    // - Tombol "Salin & Kirim via WhatsApp"
    return htmlString;
  }
}
```

**Struktur data yang di-embed dalam HTML:**
```javascript
const PRODUCTS = [
  { kode: "GP1K", nama: "Gula Pasir 1kg", satuan: "Pcs", harga: 15000 },
  { kode: "MG2L", nama: "Minyak Goreng 2L", satuan: "Pcs", harga: 32000 },
  { kode: "BR5K", nama: "Beras Pandan 5kg", satuan: "Sak", harga: 65000 },
  // ...
];
```

### 6.6 Spesifikasi `order_parser_service.dart`

```dart
class OrderParserService {
  final AppDatabase db;

  /// Parse teks yang mengandung kode "#BRK:GP1K=2;MG2L=1"
  /// menjadi daftar item yang siap masuk keranjang.
  Future<ParsedOrder> parse(String text) async {
    // 1. Ekstrak kode mesin: regex #BRK:(.+)$
    // 2. Split per ";"
    // 3. Untuk setiap "KODE=QTY":
    //    - Lookup produk: db.getProductByKode(kode)
    //    - Ambil harga aktif dari price_tiers
    //    - Buat CartItem
    // 4. Ekstrak nama & HP dari teks (opsional, regex)
    // 5. Return ParsedOrder dengan items + metadata
  }
}

class ParsedOrder {
  final List<ParsedOrderItem> items;
  final List<String> notFound;    // kode yang tidak ditemukan
  final String? customerName;
  final String? customerPhone;
  final String? note;
  final int total;
}

class ParsedOrderItem {
  final CartItem cartItem;
  final String kodeProduk;        // untuk referensi
}
```

### 6.7 Opsi Hosting HTML

File HTML yang di-generate bersifat self-contained (satu file, tanpa dependency eksternal), sehingga bisa di-host di mana saja — atau bahkan tanpa hosting sama sekali:

| Opsi | Cara | Kelebihan | Kekurangan |
|---|---|---|---|
| **Kirim file via WA** | POS generate HTML → share langsung sebagai file | Tanpa hosting, offline, pelanggan simpan di HP | Harus kirim ulang tiap update harga |
| **GitHub Pages** | Push HTML ke repo GitHub → otomatis live di `username.github.io/repo` | Gratis, unlimited bandwidth, sudah punya akun GitHub | Perlu setup repo, push manual atau via API |
| **Cloudflare Pages** | Upload via Wrangler CLI atau dashboard | Gratis, CDN global, sangat cepat | Perlu akun Cloudflare, setup Wrangler |
| **Netlify** | Drag-and-drop file HTML ke dashboard | Gratis, paling mudah setup awal | Batas 100GB bandwidth/bulan (lebih dari cukup) |

**Rekomendasi untuk fase awal:** Gunakan opsi "kirim file via WA" — tanpa setup sama sekali. Pelanggan buka file HTML langsung dari WhatsApp, pilih barang, salin teks, kirim balik via WA.

**Untuk fase lanjut:** GitHub Pages adalah pilihan paling praktis karena repo GitHub sudah digunakan untuk proyek ini. Cukup push file HTML ke branch `gh-pages`, dan pelanggan bisa mengakses via URL tetap yang bisa dibookmark (misalnya `username.github.io/toko-order`).

### 6.8 Keunggulan Teknis

1. **Zero backend** — Tidak ada server, tidak ada database cloud, tidak ada API. HTML statis bisa dibuka langsung di browser tanpa koneksi internet (setelah pertama kali dibuka).

2. **Sinkronisasi katalog = regenerate HTML** — Saat harga berubah, owner cukup tap "Update" → HTML baru di-generate → dikirim ulang ke pelanggan atau di-upload ke Pages.

3. **Parsing deterministik** — Format `#BRK:KODE=QTY` sangat sederhana, tidak ambigu, dan bisa divalidasi 100% secara lokal tanpa network call.

4. **Graceful degradation** — Jika kode mesin tidak ditemukan dalam teks yang di-paste, kasir masih bisa membaca daftar item secara manual dari teks yang human-readable.

5. **Kompatibel dengan alur kasir yang sudah ada** — Output parser adalah `CartItem[]` yang langsung masuk ke `cartProvider` yang sudah ada. Tidak perlu mengubah alur pembayaran, struk, atau sinkronisasi.

---

## 7. Rencana Implementasi

### 7.1 Fase & Timeline

```
FASE 1 (Minggu 1) ─── Order Parser + UI Paste Order
    File baru: order_parser_service.dart, paste_order_screen.dart
    File ubah: app_database.dart, app_router.dart, kasir_screen.dart
    Deliverable: Kasir bisa paste teks order → masuk keranjang

FASE 2 (Minggu 1-2) ─── HTML Generator
    File baru: order_page_service.dart, order_link_screen.dart
    File ubah: pengaturan_screen.dart, app_router.dart
    Deliverable: POS bisa generate HTML katalog + share via WA

FASE 3 (Opsional) ─── Hosting Static Pages
    Setup: GitHub Pages atau Cloudflare Pages
    Deliverable: URL tetap untuk katalog order (bisa dibookmark)
```

### 7.2 Detail Perubahan Per Fase

#### Fase 1: Order Parser (Prioritas Tertinggi)

Ini adalah komponen yang memberikan value paling cepat — bahkan tanpa HTML generator, kasir sudah bisa menerima order dalam format yang disepakati dan paste langsung ke POS.

**Langkah-langkah:**

1. Tambah method `getProductByKode()` di `app_database.dart`
2. Buat `order_parser_service.dart` dengan logika parsing
3. Buat `paste_order_screen.dart` dengan UI paste + preview
4. Tambah route `/kasir/paste-order` di router
5. Tambah akses ke Paste Order dari layar kasir (tombol atau menu)

**Validasi:** Tes dengan teks format `#BRK:GP1K=2;MG2L=1` → produk ditemukan → masuk keranjang.

#### Fase 2: HTML Generator

1. Buat `order_page_service.dart` — generate HTML dari katalog
2. Buat `order_link_screen.dart` — UI generate + share
3. Tambah menu di pengaturan
4. Integrasi dengan `share_plus` untuk share file via WhatsApp

**Validasi:** Generate HTML → buka di browser HP → pilih produk → salin teks → paste di POS → keranjang terisi.

#### Fase 3: Hosting (Opsional)

1. Setup GitHub Pages (push ke branch `gh-pages`) atau Cloudflare Pages
2. Tambah fitur upload/push HTML dari POS (atau manual via desktop)
3. Pelanggan akses via URL tetap

### 7.3 Testing Checklist

- [ ] Parse teks dengan format valid → semua item masuk keranjang
- [ ] Parse teks dengan kode produk tidak dikenal → tampil peringatan, item lain tetap masuk
- [ ] Parse teks tanpa kode mesin `#BRK:` → tampil pesan error yang jelas
- [ ] Parse teks dengan qty desimal (0.5) → ditangani dengan benar
- [ ] HTML generator menghasilkan file yang bisa dibuka offline
- [ ] Tombol "Salin & Kirim via WhatsApp" berfungsi (deep link)
- [ ] HTML responsive di HP dengan layar kecil (320px width)
- [ ] Re-generate HTML setelah perubahan harga → harga terupdate
- [ ] Alur end-to-end: HTML → pilih → WA → paste → bayar → struk

---

## 8. Estimasi Dampak & Biaya

### 8.1 Perbandingan Biaya

| | Barokah Order (Cloud) | HTML + WA + Parser |
|---|---|---|
| **Setup awal** | 4-5 minggu dev | 1-2 minggu dev |
| **Server/hosting** | ~Rp 0-200k/bulan | Rp 0/bulan |
| **Domain** | ~Rp 150k/tahun | Tidak perlu |
| **Maintenance** | API + DB + Web + Bot | 0 komponen server |
| **Downtime risk** | Ada (cloud outage) | Tidak ada |
| **Skalabilitas** | Tinggi | Cukup untuk 1-5 toko |

### 8.2 Dampak Operasional

**Sebelum (manual penuh):**
```
Pelanggan kirim WA: "Pak mau pesen gula 2, minyak 1, beras 3"
  → Kasir baca
  → Cari produk satu-satu di POS
  → Input qty manual
  → ~ 3-5 menit per order
```

**Sesudah (HTML + paste):**
```
Pelanggan buka link, pilih produk, kirim via WA
  → Kasir salin teks
  → Paste di POS
  → Review → konfirmasi
  → ~ 30 detik per order
```

**Penghematan waktu: ~80-90% per order.**

### 8.3 Kapan Perlu Upgrade ke Cloud

Pendekatan HTML + WA + Parser memiliki batasan. Berikut indikator kapan perlu migrasi ke solusi cloud:

| Indikator | Threshold |
|---|---|
| Volume order | > 50 order/hari (copy-paste jadi bottleneck) |
| Jumlah toko | > 5 toko (manajemen HTML per toko tidak efisien) |
| Kebutuhan tracking | Pelanggan ingin cek status order real-time |
| Multi-channel | Order dari web, Telegram, Instagram sekaligus |
| Analitik | Butuh data order trend, pelanggan terbanyak, dll. |

Ketika indikator ini tercapai, migrasi ke Cloudflare Workers menjadi justified — dan fondasi kode (parser, format order) sudah siap digunakan kembali.

---

## 9. Kesimpulan

Setelah evaluasi menyeluruh terhadap dua pendekatan:

**Barokah Order (cloud-based) dinyatakan obsolete** untuk skala operasional saat ini, karena:
- Memperkenalkan attack surface (DDoS) yang tidak perlu ada
- Tidak bisa mengeliminasi fake order tanpa mengorbankan kemudahan pengguna
- Over-engineering untuk volume 10-50 order/hari
- 5 komponen infrastruktur yang semuanya butuh maintenance

**Static HTML + WhatsApp + Paste Parser direkomendasikan** karena:
- Zero infrastructure, zero attack surface, zero cost
- WhatsApp bertindak sebagai layer autentikasi, anti-spam, dan delivery sekaligus
- Familiar bagi semua kalangan pengguna termasuk yang awam teknologi
- Implementasi 1-2 minggu vs 4-5 minggu
- Perubahan minimal pada kode POS yang sudah ada
- Fondasi kode bisa digunakan kembali jika kelak perlu migrasi ke cloud

**Langkah selanjutnya:**

1. **Fase 1:** Implementasi Order Parser dan UI Paste Order di POS
2. **Fase 2:** Implementasi HTML Generator dan fitur share
3. **Evaluasi:** Setelah 1-3 bulan penggunaan, evaluasi apakah perlu upgrade ke cloud berdasarkan indikator di Bab 8.3

---

## 10. TL;DR

Awalnya kami mempertimbangkan untuk membangun "Barokah Order" — sebuah aplikasi web order pelanggan lengkap dengan backend di Cloudflare Workers, database D1, dan Telegram bot. Pelanggan buka web, pilih barang, submit, lalu order masuk otomatis ke sistem kasir.

Setelah dievaluasi, pendekatan itu terlalu berat untuk kebutuhan yang sebenarnya cukup sederhana. Ada tiga masalah yang sulit dipecahkan sekaligus: bagaimana mencegah serangan DDoS ke API publik, bagaimana memastikan order yang masuk bukan order palsu (tanpa bikin ribet pelanggan yang gaptek), dan siapa yang maintain 5 komponen cloud yang semuanya bisa rusak kapan saja.

Lalu muncul pertanyaan: kenapa tidak pakai WhatsApp saja?

Solusi yang kami rekomendasikan jauh lebih sederhana. POS men-generate satu file HTML yang berisi daftar produk dan harga. File itu dikirim ke pelanggan lewat WhatsApp — atau di-host gratis di GitHub Pages supaya bisa diakses via link tetap. Pelanggan buka file itu di HP, pilih barang yang mau dipesan, lalu tekan tombol "Kirim via WhatsApp". Teks pesanan otomatis terformat rapi dan siap dikirim. Di sisi kasir, tinggal salin teks pesanan itu, tempel di fitur "Paste Order" di POS, dan seluruh keranjang langsung terisi otomatis. Selesai.

WhatsApp di sini bukan cuma kanal pengiriman — ia sekaligus jadi sistem keamanan. Tidak ada server yang bisa diserang (file HTML statis, bukan API). Tidak ada fake order karena yang kirim pesan pasti orang yang nomornya dikenal. Tidak ada biaya bulanan. Dan yang paling penting: pelanggan tidak perlu belajar aplikasi baru — mereka tinggal buka link dan kirim WhatsApp seperti biasa.

Kalau suatu hari volume order sudah lebih dari 50 per hari dan copy-paste mulai jadi bottleneck, barulah upgrade ke Cloudflare Workers masuk akal. Tapi untuk saat ini, solusi yang paling baik adalah yang paling sederhana.

---

*Dokumen ini disusun berdasarkan analisis arsitektur proyek The POS dan evaluasi teknis terhadap dua pendekatan sistem order pelanggan.*
