# Proposal Pengembangan Sistem Order Pelanggan
# The POS — Kasir Griyo

**Versi:** 1.0
**Tanggal:** 29 Juni 2026
**Proyek:** The POS (Kasir Griyo)
**Branch:** `claude/upbeat-newton-rhnbeo`

---

## Daftar Isi

1. [Ringkasan Eksekutif](#1-ringkasan-eksekutif)
2. [Latar Belakang](#2-latar-belakang)
3. [Arsitektur Teknis The POS](#3-arsitektur-teknis-the-pos)
4. [Perbaikan & Fitur Baru yang Telah Diterapkan](#4-perbaikan--fitur-baru-yang-telah-diterapkan)
5. [Proposal Awal: Barokah Order (Cloud-Based)](#5-proposal-awal-barokah-order-cloud-based)
6. [Analisis Kelemahan Pendekatan Cloud](#6-analisis-kelemahan-pendekatan-cloud)
7. [Proposal Final: Static HTML + WhatsApp + Paste Parser](#7-proposal-final-static-html--whatsapp--paste-parser)
8. [Rencana Implementasi](#8-rencana-implementasi)
9. [Estimasi Dampak & Biaya](#9-estimasi-dampak--biaya)
10. [Kesimpulan](#10-kesimpulan)

---

## 1. Ringkasan Eksekutif

Dokumen ini merangkum seluruh pengembangan yang telah dilakukan pada sistem The POS (Kasir Griyo) serta mengajukan proposal sistem order pelanggan yang terintegrasi.

Pengembangan terbagi dalam dua bagian besar:

**Bagian A — Peningkatan Kasir (Sudah Diterapkan)**
Serangkaian perbaikan dan fitur baru pada layar kasir: dukungan scanner barcode eksternal (HID) dengan umpan balik haptic, redesain cart bar, auto-scroll keranjang, serta perbaikan bug kritis pada field harga yang tidak bisa diketik.

**Bagian B — Sistem Order Pelanggan (Proposal)**
Evaluasi dua pendekatan untuk sistem order pelanggan:
- **Pendekatan A (Ditolak):** Barokah Order — aplikasi web terpisah dengan backend Cloudflare Workers, database D1, dan API layer.
- **Pendekatan B (Direkomendasikan):** Static HTML + WhatsApp/Telegram + Paste Parser — file HTML self-contained sebagai katalog order, dikirim via WhatsApp, dan di-paste langsung ke POS.

Pendekatan B dipilih karena mengeliminasi tiga masalah fundamental sekaligus: risiko DDoS, fake order, dan biaya server — sambil memanfaatkan infrastruktur yang sudah dipakai sehari-hari oleh pelanggan (WhatsApp).

---

## 2. Latar Belakang

### 2.1 Tentang The POS

The POS (Kasir Griyo) adalah aplikasi kasir (Point of Sale) berbasis Flutter yang dirancang khusus untuk pasar retail Indonesia. Aplikasi ini bersifat **offline-first** — seluruh data tersimpan di perangkat lokal menggunakan SQLite terenkripsi (SQLCipher), dan sinkronisasi antar perangkat dilakukan melalui WiFi LAN tanpa membutuhkan koneksi internet.

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

ID 7 dan 8 (legacy "Biji") telah di-merge ke ID 12 melalui proses ETL.

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
| Kelola harga & produk | ✓ | ✗ | ✗ |
| Lihat laporan | ✓ | ✓ | ✗ |
| Host sinkronisasi | ✓ | ✓ | ✗ |
| Setujui data sync | ✓ | ✗ | ✗ |
| Override harga | ✓ | ✓ | Jika diizinkan |
| Input stok | ✓ | ✓ | Jika diizinkan |
| Batalkan transaksi | ✓ | ✓ | Jika diizinkan |

---

## 4. Perbaikan & Fitur Baru yang Telah Diterapkan

Branch `claude/upbeat-newton-rhnbeo` mencakup **98 commit** dengan **19.013 baris ditambahkan** dan **2.089 baris dihapus** di 81 file. Bagian ini merangkum perbaikan dan fitur utama yang relevan.

### 4.1 Dukungan Scanner Barcode Eksternal (HID)

**Masalah:** Sebelumnya, barcode hanya bisa discan melalui kamera perangkat. Untuk toko dengan volume transaksi tinggi, ini lambat dan tidak ergonomis.

**Solusi:** Ditambahkan handler keyboard hardware (`HardwareKeyboard.instance.addHandler`) yang mendeteksi input dari scanner barcode eksternal (USB/Bluetooth HID).

**Cara kerja:**
1. Scanner mengirim karakter barcode sebagai event keyboard
2. Handler mem-buffer karakter satu per satu
3. Tombol Enter menandakan akhir barcode
4. Jeda antar-karakter > 500ms mengindikasikan input manusia (bukan scanner) → buffer direset
5. Barcode valid (panjang minimum terpenuhi) langsung diproses

**Guard conditions** — handler mengabaikan input saat:
- Scanner kamera sedang terbuka
- Field pencarian sedang difokuskan (mengetik manual)
- Modal/dialog lain sedang terbuka (kecuali sheet keranjang)

**File:** `lib/features/kasir/kasir_screen.dart` baris 460-500

### 4.2 Umpan Balik Haptic

**Masalah:** Kasir tidak mendapat konfirmasi sensorik saat barcode berhasil discan.

**Solusi:** `HapticFeedback.heavyImpact()` dipanggil setiap kali barcode berhasil diproses — baik dari scanner kamera (single & continuous) maupun dari scanner eksternal.

**Detail teknis:**
- Menggunakan `flutter/services.dart` → `HapticFeedback.heavyImpact()`
- Membutuhkan permission `android.permission.VIBRATE` di AndroidManifest
- Fallback silent pada perangkat yang tidak mendukung vibrasi
- Tidak ada toggle on/off — selalu aktif untuk menghindari kebingungan UI

**File:** `android/app/src/main/AndroidManifest.xml` (permission), `kasir_screen.dart` (3 titik pemanggilan)

### 4.3 Auto-Open Keranjang Saat Scan Eksternal

**Masalah:** Saat menggunakan scanner eksternal, kasir tidak mendapat konfirmasi visual bahwa produk sudah masuk keranjang.

**Solusi:** Setelah scan eksternal berhasil, sheet keranjang otomatis terbuka sebagai konfirmasi visual. Jika sheet sudah terbuka, isinya diperbarui otomatis lewat Riverpod provider tanpa membuka sheet kedua.

**Alur:**
```
Scanner scan barcode
  → Produk ditemukan di database
  → Ditambahkan ke keranjang via cartProvider
  → HapticFeedback.heavyImpact()
  → _openCartSheet(scrollToBottom: true)
  → Sheet keranjang terbuka di posisi item terbaru
```

### 4.4 Debounce Dua Tingkat

**Masalah:** Scan barcode yang sama dua kali berturut-turut dalam waktu singkat (< 1 detik) tidak diproses — scan kedua dianggap duplikat oleh debounce 1,5 detik.

**Solusi:** Debounce dipisah berdasarkan sumber scan:

| Sumber | Debounce | Alasan |
|---|---|---|
| Scanner eksternal (HID) | **300 ms** | Cukup untuk mencegah echo hardware, tapi cepat untuk scan berturut produk sama |
| Scanner kamera | **1.500 ms** | Barcode bisa terus terdeteksi selama masih terlihat di frame kamera |

**File:** `kasir_screen.dart` baris 640-645

### 4.5 Auto-Scroll Keranjang ke Bawah

**Masalah:** Saat keranjang penuh (10+ item) dan scanner eksternal menambah produk baru, sheet keranjang terbuka di posisi atas — kasir harus scroll manual untuk melihat produk yang baru ditambahkan.

**Solusi:** `CartSheet` dikonversi dari `ConsumerWidget` ke `ConsumerStatefulWidget` dengan logika auto-scroll.

**Detail implementasi:**
- Parameter `scrollToBottom` diteruskan dari `_openCartSheet()`
- Scroll dijadwalkan di dalam callback `DraggableScrollableSheet.builder`, karena `ScrollController` baru tersedia di sana
- `addPostFrameCallback` memastikan scroll terjadi setelah ListView selesai di-layout
- Dua trigger: (1) saat sheet pertama kali dibuka dari scan eksternal, (2) saat item baru ditambahkan ke keranjang yang sudah terbuka

**Bug yang ditemukan dan diperbaiki:**
Versi awal memanggil `_scrollToBottom()` di method `build()` sebelum `DraggableScrollableSheet.builder` menyediakan `ScrollController`. Controller masih `null`, sehingga scroll tidak pernah terjadi. Diperbaiki dengan memindahkan logika ke dalam builder callback.

**File:** `lib/features/kasir/widgets/cart_sheet.dart` baris 18-60

### 4.6 Redesain Cart Bar

**Masalah:** Tampilan cart bar di bagian bawah layar kasir terlalu kecil dan sulit dibaca.

**Perubahan visual:**

```
SEBELUM:                              SESUDAH:
┌──────────────────────────┐    ┌──────────────────────────┐
│ (3) Total        Lihat   │    │      (3) Total           │
│     Rp 48.000    Bayar   │    │      Rp 48.000           │
└──────────────────────────┘    │   Terakhir: Gula 1kg     │
                                │                          │
                                │  [ Lihat ]  [  Bayar  ]  │
                                └──────────────────────────┘
```

- Total diperbesar (size 16.5 → 23) dan diposisikan center
- Badge jumlah item (lingkaran) di sebelah kiri total
- Info item terakhir ditampilkan di bawah total
- Tombol "Lihat" dan "Bayar" dipindah ke baris bawah sebagai full-width row
- Tinggi tombol diperbesar (40 → 46px) untuk kemudahan tap

**File:** `kasir_screen.dart` baris 1850-1970

### 4.7 Perbaikan Bug Kritis: Field Harga Tidak Bisa Diketik

**Gejala:** Saat mengetuk produk di daftar produk tab kasir untuk membuka modal entri item, field harga menampilkan keyboard namun input yang diketik tidak masuk ke field.

**Kronologi investigasi:**

| Percobaan | Diagnosis | Hasil |
|---|---|---|
| 1 | ScrollView menghalangi input saat modal dari keranjang | ❌ Tidak memperbaiki |
| 2 | Nested navigator focus-scope conflict | ❌ Tidak memperbaiki |
| 3 | `ThousandsSeparatorFormatter` menyebabkan IME desync | ❌ Tidak memperbaiki |
| 4 | Modal bertumpuk di atas `DraggableScrollableSheet` memutus koneksi input | ❌ Tidak memperbaiki |

Keempat percobaan gagal karena **mendiagnosis alur yang salah** (alur tap dari keranjang, bukan alur tap dari daftar produk).

**Akar masalah yang sebenarnya:**

Penambahan `useRootNavigator: true` pada `showModalBottomSheet` di method `_openEntry()` menyebabkan modal muncul di root navigator, bukan di shell navigator GoRouter. Akibatnya:

1. `ModalRoute.of(context)?.isCurrent` pada KasirScreen tetap bernilai `true` — karena KasirScreen masih merupakan rute aktif di dalam shell navigator-nya, meskipun ada modal di root navigator di atasnya.

2. Handler barcode eksternal (`_onHardwareKey`) tidak melakukan bail-out — karena guard condition `!(ModalRoute.of(context)?.isCurrent ?? true)` bernilai `false`.

3. Setiap event keyboard dari software keyboard di-buffer dan **di-consume** (`return true`) oleh handler barcode — sehingga TextField pada modal tidak pernah menerima input.

```
ROOT NAVIGATOR
  └── Modal (ItemEntrySheet) ← useRootNavigator: true menaruh di sini
       └── TextField (keyboard muncul, tapi input dicuri HID handler)

SHELL NAVIGATOR
  └── KasirScreen ← ModalRoute.isCurrent tetap TRUE
       └── _onHardwareKey: tidak bail-out, menelan semua input
```

**Perbaikan:**
- Hapus `useRootNavigator: true` dari semua `showModalBottomSheet` di kasir
- Kembalikan `ThousandsSeparatorFormatter` (revert `FilteringTextInputFormatter.digitsOnly`)
- Hapus `_priceFocus` FocusNode dan listener yang tidak perlu
- Kembalikan handler `onTap` untuk select-all pada field harga

**Commit referensi:** `1917ef8` (terakhir berfungsi) → `939c07b` (perbaikan)

---

## 5. Proposal Awal: Barokah Order (Cloud-Based)

### 5.1 Konsep

Barokah Order dirancang sebagai sistem order pelanggan berbasis cloud yang terintegrasi dengan The POS:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────┐
│   Kasir Griyo    │────▶│   Cloudflare     │◀────│   Barokah    │
│   (The POS)      │     │   Workers + D1   │     │   Order      │
│                  │◀────│                  │     │   (Web App)  │
└──────────────────┘     └────────┬─────────┘     └──────────────┘
                                  │
                           ┌──────┴──────┐
                           │  Telegram   │
                           │  Bot API    │
                           └─────────────┘
```

### 5.2 Stack yang Direncanakan

| Komponen | Teknologi | Fungsi |
|---|---|---|
| **API Layer** | Cloudflare Workers (TypeScript, Hono) | REST API endpoint |
| **Database** | Cloudflare D1 (SQLite di edge) | Katalog, order, pelanggan |
| **Cache** | Cloudflare KV | Session, katalog snapshot |
| **Frontend** | Cloudflare Pages (static) | Web app order pelanggan |
| **Notifikasi** | Telegram Bot API | Alert order baru |
| **Auth POS→API** | HMAC dari store_key | Token-based |

### 5.3 Alur yang Dirancang

```
1. POS push katalog produk → Workers API → D1
2. Pelanggan buka web → pilih produk → submit order
3. Workers simpan order → kirim notif Telegram
4. POS poll antrian order → konfirmasi → masuk keranjang
5. Transaksi berjalan normal → nota digital (HTML via Workers)
```

### 5.4 Endpoint API

| Method | Path | Fungsi |
|---|---|---|
| POST | `/api/store/register` | Daftarkan toko |
| POST | `/api/katalog` | POS push katalog |
| GET | `/api/katalog/:storeId` | Pelanggan baca katalog |
| POST | `/api/order` | Pelanggan submit order |
| GET | `/api/order/antrian/:storeId` | POS poll order pending |
| PATCH | `/api/order/:id/status` | POS update status order |
| GET | `/api/nota/:orderId` | Nota digital (HTML) |

### 5.5 Skema D1

```sql
stores (id, name, address, phone, token_hash, telegram_chat_id)
products (id, store_id, product_name, unit_name, price, barcode)
orders (id, store_id, customer_name, customer_phone, status, total, note)
order_items (id, order_id, product_id, product_name, unit_name, price, qty, subtotal)
```

---

## 6. Analisis Kelemahan Pendekatan Cloud

### 6.1 Tiga Masalah Fundamental

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

### 6.2 Perbandingan Komprehensif

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

### 6.3 Mengapa WhatsApp Adalah Layer Autentikasi Terbaik

WhatsApp secara implisit menyelesaikan tiga masalah sekaligus:

1. **Anti-DDoS:** Tidak ada server yang bisa diserang. Pesan masuk ke WhatsApp pribadi kasir/owner — infrastruktur Meta yang menangani traffic.

2. **Anti-Fake Order:** Hanya kontak yang dikenal (pelanggan nyata) yang bisa mengirim pesan. Nomor WhatsApp = identitas terverifikasi. Kasir bisa langsung konfirmasi via chat jika ada keraguan.

3. **Zero Cost:** WhatsApp gratis, sudah terinstal di hampir semua smartphone di Indonesia, dan familiar bagi semua kalangan usia.

**WhatsApp bukan hanya channel komunikasi — ia adalah sistem autentikasi, anti-spam, dan delivery yang sudah jadi, gratis, dan universal.**

---

## 7. Proposal Final: Static HTML + WhatsApp + Paste Parser

### 7.1 Konsep

```
┌─────────────────────────────────────────────────────────┐
│                     ALUR ORDER                          │
│                                                         │
│  PELANGGAN                           KASIR              │
│      │                                 │                │
│      ▼                                 │                │
│   Buka HTML                            │                │
│   (link / file)                        │                │
│      │                                 │                │
│      ▼                                 │                │
│   Pilih produk                         │                │
│   Atur jumlah                          │                │
│      │                                 │                │
│      ▼                                 │                │
│   Teks order muncul                    │                │
│   di bawah kotak                       │                │
│      │                                 │                │
│      ▼                                 │                │
│   [Salin & Kirim via WA] ────────────▶ │                │
│                                        ▼                │
│                                  Terima di WA           │
│                                  Salin teks order       │
│                                        │                │
│                                        ▼                │
│                                  Buka "Paste Order"     │
│                                  di POS                 │
│                                        │                │
│                                        ▼                │
│                                  Tempel → review        │
│                                  → masuk keranjang      │
│                                        │                │
│                                        ▼                │
│                                  Bayar → Struk          │
└─────────────────────────────────────────────────────────┘
```

### 7.2 Komponen Sistem

Sistem terdiri dari **tiga komponen** — dua di sisi POS, satu file HTML statis:

#### A. Order Page Generator (di POS)

POS men-generate file HTML self-contained yang berisi seluruh katalog produk sebagai data embedded. File ini bisa di-host di Cloudflare Pages (gratis, 1 file statis) atau dikirim langsung sebagai file via WhatsApp.

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
📋 ORDER BAROKAH
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
| Header (`📋 ORDER BAROKAH`) | Identifikasi visual |
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
│  📋 Paste Order                 │
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

### 7.3 File Baru di POS

```
lib/core/services/
├── order_page_service.dart      ← Generate HTML dari katalog produk
└── order_parser_service.dart    ← Parse kode #BRK:... → CartItem[]

lib/features/kasir/
└── paste_order_screen.dart      ← UI paste + preview + confirm

lib/features/pengaturan/
└── order_link_screen.dart       ← UI generate & share link order
```

### 7.4 File yang Diubah di POS

| File | Perubahan |
|---|---|
| `lib/core/database/app_database.dart` | Tambah method `getProductByKode(String kodeProduk)` dan `getPublicCatalog()` |
| `lib/core/router/app_router.dart` | Tambah route `/kasir/paste-order` dan `/pengaturan/order-link` |
| `lib/features/kasir/kasir_screen.dart` | Tambah tombol/akses ke "Paste Order" |
| `lib/features/pengaturan/pengaturan_screen.dart` | Tambah menu "Link Order Pelanggan" |

### 7.5 Spesifikasi `order_page_service.dart`

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

### 7.6 Spesifikasi `order_parser_service.dart`

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

### 7.7 Hosting HTML

**Dua opsi (bisa keduanya sekaligus):**

| Opsi | Cara | Kelebihan |
|---|---|---|
| **Cloudflare Pages** | POS upload HTML via Wrangler CLI atau API | URL tetap, bisa dibookmark pelanggan |
| **Kirim file via WA** | POS generate HTML → share sebagai file | Offline, pelanggan simpan di HP |

Untuk fase awal, opsi "kirim file via WA" lebih praktis — tidak butuh setup Cloudflare sama sekali. Pelanggan buka file HTML langsung dari WhatsApp, pilih barang, salin teks, kirim balik via WA.

### 7.8 Keunggulan Teknis

1. **Zero backend** — Tidak ada server, tidak ada database cloud, tidak ada API. HTML statis bisa dibuka langsung di browser tanpa koneksi internet (setelah pertama kali dibuka).

2. **Sinkronisasi katalog = regenerate HTML** — Saat harga berubah, owner cukup tap "Update" → HTML baru di-generate → dikirim ulang ke pelanggan atau di-upload ke Pages.

3. **Parsing deterministik** — Format `#BRK:KODE=QTY` sangat sederhana, tidak ambigu, dan bisa divalidasi 100% secara lokal tanpa network call.

4. **Graceful degradation** — Jika kode mesin tidak ditemukan dalam teks yang di-paste, kasir masih bisa membaca daftar item secara manual dari teks yang human-readable.

5. **Kompatibel dengan alur kasir yang sudah ada** — Output parser adalah `CartItem[]` yang langsung masuk ke `cartProvider` yang sudah ada. Tidak perlu mengubah alur pembayaran, struk, atau sinkronisasi.

---

## 8. Rencana Implementasi

### 8.1 Fase & Timeline

```
FASE 1 (Minggu 1) ─── Order Parser + UI Paste Order
    File baru: order_parser_service.dart, paste_order_screen.dart
    File ubah: app_database.dart, app_router.dart, kasir_screen.dart
    Deliverable: Kasir bisa paste teks order → masuk keranjang

FASE 2 (Minggu 1-2) ─── HTML Generator
    File baru: order_page_service.dart, order_link_screen.dart
    File ubah: pengaturan_screen.dart, app_router.dart
    Deliverable: POS bisa generate HTML katalog + share via WA

FASE 3 (Opsional) ─── Hosting Cloudflare Pages
    Setup: Wrangler CLI, Cloudflare account
    Deliverable: URL tetap untuk katalog order (bisa dibookmark)
```

### 8.2 Detail Perubahan Per Fase

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

1. Setup Cloudflare Pages project
2. Tambah fitur upload HTML ke Pages dari POS (via API atau manual)
3. Pelanggan akses via URL tetap

### 8.3 Testing Checklist

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

## 9. Estimasi Dampak & Biaya

### 9.1 Perbandingan Biaya

| | Barokah Order (Cloud) | HTML + WA + Parser |
|---|---|---|
| **Setup awal** | 4-5 minggu dev | 1-2 minggu dev |
| **Server/hosting** | ~Rp 0-200k/bulan | Rp 0/bulan |
| **Domain** | ~Rp 150k/tahun | Tidak perlu |
| **Maintenance** | API + DB + Web + Bot | 0 komponen server |
| **Downtime risk** | Ada (cloud outage) | Tidak ada |
| **Skalabilitas** | Tinggi | Cukup untuk 1-5 toko |

### 9.2 Dampak Operasional

**Sebelum (manual penuh):**
```
Pelanggan kirim WA: "Pak mau pesen gula 2, minyak 1, beras 3"
  → Kasir baca
  → Cari produk satu-satu di POS
  → Input qty manual
  → ≈ 3-5 menit per order
```

**Sesudah (HTML + paste):**
```
Pelanggan buka link, pilih produk, kirim via WA
  → Kasir salin teks
  → Paste di POS
  → Review → konfirmasi
  → ≈ 30 detik per order
```

**Penghematan waktu: ~80-90% per order.**

### 9.3 Kapan Perlu Upgrade ke Cloud

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

## 10. Kesimpulan

### 10.1 Yang Sudah Dicapai

Pada branch `claude/upbeat-newton-rhnbeo`, telah diterapkan serangkaian peningkatan signifikan pada layar kasir The POS:

- **Scanner barcode eksternal (HID)** dengan deteksi otomatis, debounce dua tingkat, dan integrasi langsung ke keranjang
- **Umpan balik haptic** sebagai konfirmasi sensorik saat scan berhasil
- **Auto-scroll keranjang** ke item terbaru saat scan berturut-turut
- **Redesain cart bar** yang lebih informatif dan mudah diakses
- **Perbaikan bug kritis** pada field harga yang tidak bisa diketik, yang disebabkan oleh konflik antara `useRootNavigator` dan handler barcode HID

### 10.2 Rekomendasi Sistem Order

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

### 10.3 Langkah Selanjutnya

1. **Fase 1:** Implementasi Order Parser dan UI Paste Order di POS
2. **Fase 2:** Implementasi HTML Generator dan fitur share
3. **Evaluasi:** Setelah 1-3 bulan penggunaan, evaluasi apakah perlu upgrade ke cloud berdasarkan indikator di Bab 9.3

---

*Dokumen ini disusun berdasarkan analisis arsitektur proyek The POS, 98 commit perubahan pada branch pengembangan, serta evaluasi teknis terhadap dua pendekatan sistem order pelanggan.*
