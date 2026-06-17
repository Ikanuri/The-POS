# The POS

**Aplikasi kasir _offline-first_ untuk toko grosir & retail di Indonesia.**

The POS adalah aplikasi Point of Sale berbasis Flutter yang dirancang untuk berjalan
tanpa koneksi internet. Seluruh data tersimpan lokal dalam database terenkripsi,
mendukung banyak perangkat dalam satu toko (owner + kasir) melalui sinkronisasi LAN,
serta terintegrasi dengan printer thermal Bluetooth dan barcode scanner.

---

## Daftar Isi

- [Fitur Utama](#fitur-utama)
- [Tangkapan Arsitektur](#tangkapan-arsitektur)
- [Teknologi](#teknologi)
- [Struktur Proyek](#struktur-proyek)
- [Memulai](#memulai)
- [Build APK](#build-apk)
- [Keamanan Data](#keamanan-data)
- [Multi-Perangkat](#multi-perangkat-owner--kasir)
- [Lisensi](#lisensi)

---

## Fitur Utama

### 🧾 Kasir
- **Katalog produk** tampilan grid & list, pencarian nama, filter per grup.
- **Barcode scanner ganda** — kamera (`mobile_scanner`) maupun scanner hardware
  eksternal (USB OTG / Bluetooth HID, terdeteksi otomatis lewat timing keystroke).
- **Multi-satuan & varian** — satu produk bisa punya beberapa satuan (pcs, lusin, dus)
  dan beberapa varian dengan barcode serta harga masing-masing.
- **Keranjang** dengan stepper qty, override harga, dan catatan per item.
- **Pesanan ditahan** (_held orders_) untuk melayani beberapa pembeli sekaligus.
- **Metode pembayaran lengkap** — tunai, transfer, QRIS, e-wallet, dan tempo (kasbon),
  termasuk pembayaran sebagian (_partial payment_) dan perhitungan kembalian.

### 💰 Harga & Pelanggan
- **Harga berjenjang** — resolusi otomatis berdasarkan grup pelanggan lalu kuantitas
  (_qty tier_), dengan fallback ke harga dasar.
- **Pelanggan** terdaftar, ad-hoc (nama bebas), atau "Umum".
- **Poin loyalitas** dan **pelacakan hutang** akumulatif per pelanggan.

### 🖨️ Struk
- **Cetak thermal Bluetooth** (ESC/POS, kertas 58mm & 80mm) via `print_bluetooth_thermal`.
- Tata letak struk dapat dikonfigurasi (tampilkan/sembunyikan tanggal, nomor nota,
  pelanggan, jumlah produk, rincian bayar, status).
- **Bagikan struk sebagai gambar** lewat aplikasi lain.
- **Struk gabungan** — menggabungkan beberapa nota satu pelanggan menjadi satu cetakan.

### 📊 Laporan
- Empat tab: **Ringkasan**, **Produk**, **Pelanggan**, **Transaksi**, dengan
  pemilih rentang tanggal.
- **Grafik** (donut & bar) memakai `fl_chart`.
- **Pembatalan transaksi** (_void_) dengan reversal stok dan poin loyalitas otomatis.
- **Pra-agregasi harian** (`DailySummaries`) agar laporan tetap cepat saat data menumpuk.

### ⚙️ Pengaturan & Manajemen Data
- Informasi toko, metode pembayaran, dan **izin kasir** per peran.
- **Backup & restore** database penuh.
- **Impor produk dari CSV** dan **ekspor laporan** ke PDF / XLSX.
- **Tutup buku tahunan** dengan pengarsipan data per tahun (`archive_YYYY.db`).

---

## Tangkapan Arsitektur

```
┌──────────────────────────────────────────────────────────┐
│                     UI (Flutter / Material 3)             │
│   features/{kasir, produk, pelanggan, laporan, ...}       │
├──────────────────────────────────────────────────────────┤
│                State Management (Riverpod)                │
│            providers + router (go_router)                 │
├──────────────────────────────────────────────────────────┤
│                       Services                            │
│  crypto · pairing · price · printer · lan_sync · export   │
│  csv_import · db_export · archive · tutup_buku            │
├──────────────────────────────────────────────────────────┤
│              Database (Drift + SQLCipher)                 │
│   SQLite terenkripsi · skema v4 · pre-aggregate summaries │
└──────────────────────────────────────────────────────────┘
```

**Offline-first**: tidak ada server pusat. Identitas perangkat berbasis device
(tanpa login) — perangkat kasir bergabung ke toko dengan memindai QR pairing dari
perangkat owner. Sinkronisasi antar perangkat berjalan lewat jaringan lokal (LAN).

---

## Teknologi

| Kategori | Paket |
|---|---|
| Framework | Flutter (Dart `>=3.3.0`) |
| State | `flutter_riverpod`, `riverpod_annotation` |
| Database | `drift`, `sqlcipher_flutter_libs`, `sqlite3` |
| Routing | `go_router` |
| Kripto | `encrypt`, `crypto`, `flutter_secure_storage` |
| Barcode/QR | `mobile_scanner`, `barcode_widget`, `qr_flutter` |
| Printer | `print_bluetooth_thermal`, `esc_pos_utils_plus`, `permission_handler` |
| Sync LAN | `shelf`, `network_info_plus` |
| Ekspor | `file_picker`, `excel`, `pdf`, `printing`, `share_plus` |
| UI | `google_fonts` (Inter), `fl_chart` |

---

## Struktur Proyek

```
lib/
├── main.dart                   # Entry point + bootstrap DB
├── core/
│   ├── database/               # Drift: tabel, app_database, migrasi
│   ├── models/                 # Model domain
│   ├── providers/              # Riverpod global (device, theme, db)
│   ├── router/                 # Konfigurasi go_router
│   ├── services/               # Logika bisnis lintas-fitur
│   ├── theme/                  # Tema Material 3 (copper/terracotta)
│   ├── utils/                  # Helper (format, input formatter)
│   └── widgets/                # Widget bersama
└── features/
    ├── kasir/                  # Layar kasir, keranjang, pembayaran, struk
    ├── produk/                 # CRUD produk, varian, barcode, grup
    ├── pelanggan/              # CRUD pelanggan
    ├── laporan/               # Laporan 4-tab + grafik
    ├── ringkasan/             # Dashboard ringkasan
    ├── pengaturan/            # Pengaturan, backup, sync, arsip
    ├── setup/                 # Welcome, setup toko, pairing
    └── shell/                 # Navigation shell
```

---

## Memulai

### Prasyarat
- Flutter **3.24.5** (versi dikunci agar sesuai CI — lihat `.github/workflows/build-apk.yml`)
- Android SDK (target: Android; iOS belum dikonfigurasi)

### Instalasi

```bash
# Ambil dependensi
flutter pub get

# Generate kode Drift & Riverpod
dart run build_runner build --delete-conflicting-outputs

# Jalankan di perangkat / emulator
flutter run
```

### Analisis & Test

```bash
flutter analyze
flutter test
```

---

## Build APK

Proyek menyertakan GitHub Actions (`.github/workflows/build-apk.yml`) yang:

- **Setiap push** ke `main` atau `claude/**` → otomatis membuat **pre-release**
  berisi APK yang bisa diunduh langsung dari halaman _Releases_ (tanpa zip).
- **Push tag `v*`** → membuat **release resmi** dengan _release notes_ otomatis.

Build lokal:

```bash
flutter build apk --release --target-platform android-arm64
```

> Penandatanganan rilis dibaca dari `android/key.properties`. Bila tidak ada,
> build jatuh ke _debug signing_ agar tetap berhasil di lingkungan pengembangan.
> Di CI, keystore disuntik dari GitHub Secrets.

---

## Keamanan Data

- Database **dienkripsi penuh** dengan SQLCipher (AES-256).
- Kunci toko diturunkan via **PBKDF2-SHA256** dan disimpan di
  `flutter_secure_storage`.
- Tidak ada data yang dikirim ke server eksternal — semua tetap di perangkat.

---

## Multi-Perangkat (Owner & Kasir)

1. Perangkat **owner** membuat toko dan menghasilkan **QR pairing** (kedaluwarsa 5 menit).
2. Perangkat **kasir/asisten** memindai QR untuk bergabung.
3. Owner mengatur **izin per peran** (input stok, tambah pelanggan, override harga,
   batalkan transaksi, dll).
4. Data tersinkron antar perangkat melalui **jaringan lokal (LAN)**.

---

## Lisensi

Hak cipta © 2026. Seluruh hak dilindungi. Proyek privat — belum dirilis di bawah
lisensi sumber terbuka.

---

## Pengembangan

Aplikasi ini **dibangun dari nol (_build from scratch_)**, dengan bantuan (_assisted by_)
model **Fable 5**.
