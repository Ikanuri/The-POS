# Catatan Pembaruan (Patch Notes)

Ringkasan perubahan yang **dirasakan pengguna**, ditulis dalam bahasa sederhana.
Untuk catatan teknis lengkap per-commit, lihat [CHANGELOG.md](CHANGELOG.md).

> Yang dicantumkan di sini: fitur baru & perbaikan yang benar-benar terasa saat
> memakai aplikasi. Perbaikan internal/teknis tidak dicantumkan.

---

## 5 Juli 2026

### 🛠️ Perbaikan yang Terasa
- **Struk tidak lagi bisa terpotong di layar sempit.** Kalau nama perangkat
  kasir cukup panjang, baris "Kasir: ..." di struk berpotensi mendorong
  tanggal transaksi sampai terpotong dari layar. Sekarang otomatis
  menyingkat (...) agar tanggal tetap selalu terlihat penuh. Baris ringkasan
  retur untuk nota belum lunas juga diperbaiki dengan cara serupa.

### ✨ Fitur Baru
- **Retur untuk nota belum lunas (hutang) kini lebih masuk akal.** Kalau
  pelanggan mengembalikan barang dari nota yang **belum dibayar sama sekali
  atau baru dibayar sebagian**, aplikasi sekarang langsung **mengurangi
  hutangnya** — bukan lagi berpura-pura ada uang tunai yang harus
  dikembalikan. Barang yang diretur langsung hilang dari nota itu, totalnya
  otomatis berkurang. Untuk nota yang **sudah lunas**, cara retur tetap sama
  seperti sebelumnya (nota retur terpisah + uang kembali beneran), karena
  uangnya memang sudah diterima toko.

---

## 2 Juli 2026

### 🛠️ Perbaikan yang Terasa
- **Aplikasi tetap cepat dibuka meski data sudah menumpuk tahunan.** Ditemukan
  lewat uji beban: pembukaan aplikasi bisa melambat drastis (hingga hang) saat
  jumlah transaksi membesar. Sudah diperbaiki — startup tetap ringan bahkan di
  atas satu juta transaksi.
- **QRIS kini tampil sebagai kode QR sungguhan** di layar pembayaran — pembeli
  bisa langsung scan. Sebelumnya hanya muncul tulisan kode mentah yang tidak
  bisa discan.
- **Struk lebih akurat untuk produk bervarian** — bila induk (mis. Pop Ice)
  dijual bersama varian rasanya sekaligus, baris induk di struk aplikasi
  sempat tampil kosong tanpa nominal. Sekarang jumlah & harganya tampil benar.
- **Total pesanan ditahan kini akurat** — kartu "Pesanan Ditahan" sempat
  menghitung varian dua kali sehingga totalnya kelihatan lebih besar.
- Berbagai penguatan di balik layar: stok aman saat tutup buku tahunan, data
  pegawai ikut ter-backup, dan sinkronisasi antar perangkat lebih andal untuk
  cicilan / tambah belanjaan pada nota lama.

---

## 1 Juli 2026

### ✨ Fitur Baru
- **Katalog Harga** — Buat daftar harga produk dan bagikan sebagai gambar ke
  pelanggan (mis. lewat WhatsApp). Pilih produk seperti biasa di kasir, lalu
  bagikan. Daftar otomatis dikelompokkan per kategori, lengkap dengan nama toko,
  tanggal, dan kontak. Katalog bisa disimpan dan **diedit kembali** kapan saja.
- **Animasi konfirmasi scan** — Saat memindai barcode dengan kamera (mode Scan
  Berulang), garis merah pemindai berkedip hijau sesaat sebagai tanda produk
  berhasil masuk keranjang.
- **Cara baru buka keranjang** — Cukup geser (swipe) bar total belanja ke atas
  untuk melihat isi keranjang. Tombol "Lihat" dan "Bayar" di bar disederhanakan.
- **Ekspor laporan lebih lengkap** — Ekspor (PDF & Excel) kini mengikuti tab yang
  dibuka (Ringkasan / Produk / Pelanggan / Transaksi), dan PDF menyertakan grafik
  (donut & batang) persis seperti tampilan di aplikasi.

### 🛠️ Perbaikan yang Terasa
- Ekspor PDF laporan yang sebelumnya gagal/macet pada data besar kini lancar.
- Tulisan pada grafik di PDF yang tadinya sulit terbaca kini jelas.

---

## 27–28 Juni 2026

### ✨ Fitur Baru
- **Cari produk lewat SKU** dan **edit item langsung dari dalam keranjang**.
- **Getar (haptik)** saat scan barcode berhasil; scanner eksternal otomatis
  membuka keranjang setelah scan.
- **Sinkronisasi harga satu arah** antar toko dengan persetujuan per kategori.
- **Izin stok minus** untuk asisten/kasir dapat diatur.

---

## 25–26 Juni 2026

### ✨ Fitur Baru
- **Ekspor CSV produk** dan **katalog sinkron harga** dari halaman Pengaturan.
- Tambahan **5 satuan** baru: Ons, Rek, Paket, Box, Karton.

---

## 19–21 Juni 2026

### ✨ Fitur Baru
- **Tambah belanjaan** ke transaksi yang sudah ada dengan alur bayar selisih.
- **Sinkronisasi via QR code** untuk data dan harga antar perangkat.
- **Senter (torch)** dan panduan bidik pada scanner kamera.
- Pelanggan & pegawai bisa dipilih langsung di bar keranjang; tahan pesanan
  jadi lebih praktis.

---

## 16–18 Juni 2026

### ✨ Fitur Baru
- **Poin loyalitas** dengan aturan yang bisa dikonfigurasi dan poin yang bisa
  diedit.
- **Penyesuaian stok manual** dari halaman detail produk.
- **Pengaturan ukuran teks global** + penyesuaian otomatis mengikuti layar.
- **Pencatatan pegawai per nota** yang tampil di struk.
- **Sinkronisasi harga antar toko** lewat WiFi langsung maupun CSV.

### 🛠️ Perbaikan yang Terasa
- Warna navigasi sistem Android mengikuti mode gelap/terang.

---

## 13–15 Juni 2026

### ✨ Fitur Baru
- **Struk dapat dikustomisasi** — header (WhatsApp/Telegram/teks bebas), ukuran
  kertas 58/80mm, dan pilihan tampil/sembunyi tiap bagian.
- **Gabung beberapa nota** satu pelanggan menjadi satu cetakan, dengan timeline
  pembayaran.
- **Varian produk bersarang** dan **manajemen grup produk**.
- **Bagikan struk sebagai gambar** ke aplikasi lain.
- Edit nama pembeli langsung di layar struk.

---

## 11–12 Juni 2026 — Rilis Awal

### ✨ Fondasi Aplikasi
- **Kasir** — katalog grid/list, pencarian, keranjang, pesanan ditahan, dan
  metode pembayaran lengkap (tunai, transfer, QRIS, e-wallet, tempo/kasbon)
  termasuk pembayaran sebagian & kembalian.
- **Barcode scanner ganda** — kamera dan scanner hardware eksternal.
- **Multi-satuan & harga berjenjang** (harga grosir per kuantitas/grup pelanggan).
- **Pelanggan** dengan poin loyalitas & pelacakan hutang.
- **Cetak struk thermal Bluetooth** (ESC/POS).
- **Laporan** 4 tab (Ringkasan, Produk, Pelanggan, Transaksi) dengan grafik dan
  pemilih rentang tanggal; pembatalan transaksi (void) dengan reversal stok.
- **Multi-perangkat** owner + kasir via sinkronisasi WiFi LAN, izin kasir per
  peran, backup/restore, dan impor CSV.
- **Tutup buku tahunan** dengan arsip read-only.
