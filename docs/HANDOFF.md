# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md).

_Update sesi 23 Juli 2026 — commit `22601be` (SELESAI, terverifikasi): sheet
"Verifikasi Pesanan" (centang barang sebelum lanjut bayar) dihapus dari alur
transfer QR. Lanjutan langsung dari commit `d9e971a` (tombol Bayar/transfer
QR bebas/nomor nota reservasi, Item 55/56/57) dan Item 54 (`4e0fbf3`/
`8cd5110`, kategori multi-tag) yang sudah selesai sebelumnya di sesi yang
sama._

## Yang baru dikerjakan sesi ini

1. **Item 55/56/57** (`d9e971a`) — tombol "Bayar" terracotta di cart bar
   (tab meta, sejajar "Tahan", tap langsung ke `/kasir/bayar`, gerbang izin
   `terima_pembayaran` via `handoff_gate_provider.dart`
   `needsPaymentGateProvider`); transfer QR BEBAS (ikon `qr_code_2`+panah)
   di `CartSheet` utk owner/asisten/pegawai berizin (bukan cuma jalur
   handoff pegawai TANPA izin yang sudah ada); "Kosongkan" jadi ikon tempat
   sampah; nomor nota (`local_id`) direservasi SEJAK item pertama masuk
   keranjang (tabel baru `reserved_order_numbers`, `schemaVersion` 19->20,
   `reserveLocalId`/`releaseLocalId`), stabil sepanjang siklus hidup
   termasuk lewat transfer QR, ditampilkan `#<segmen terakhir>` (mis.
   `#17`); `customerId` ikut terbawa transfer QR (`PelangganId:`/`Nota:` di
   `encodeHandoff`/`parse`), auto-resolve di penerima kalau tersync lokal.
   Sekalian fix tidak terkait: sheet "Tempel Pesanan" — tombol konfirmasi
   tertutup keyboard krn `DraggableScrollableSheet.currentSize` tidak
   reaktif thd `viewInsets`, diganti pola `Padding+LayoutBuilder+
   Column(mainAxisSize.min)`.
2. **Hapus sheet "Verifikasi Pesanan"** (`22601be`, permintaan user
   langsung) — tap kartu antrian handoff pegawai via QR (`awaitingPayment`)
   dulu buka sheet centang-tiap-barang (`_VerifyOrderSheet`, Item 24b)
   sebelum boleh lanjut ke keranjang; sekarang **langsung resume**, sama
   persis seperti pesanan ditahan biasa — pengirim sudah menyusun
   barangnya sendiri, tidak perlu dicek ulang oleh penerima.
   `_VerifyOrderSheet`/`_toggle`/field `checked` di payload `held_orders`
   dihapus total sbg dead code (bukan cuma disembunyikan).

**Test baru/diubah** (semua revert-verified): `cart_bar_bayar_button_test.
dart`, `cart_sheet_transfer_icon_test.dart`, `reserve_local_id_test.dart`,
`order_parser_customer_id_test.dart` (Item 55-57); `kasir_verify_order_
test.dart` ditulis ulang (kini menguji bahwa TIDAK ADA sheet verifikasi
sama sekali, utk handoff maupun biasa) & satu test lama di
`kasir_scan_order_code_test.dart` yang menguji mekanisme `_toggle` yang
sudah dihapus turut dihapus. Migration test v7-v18 diperbarui ekspektasi
`schemaVersion` ke 20.

## Status test suite

`flutter test` PENUH sudah sukses jalan sampai selesai (2 kali) di sesi
ini: 663 lulus / 1 gagal — kegagalan itu `stock_opname_screen_test.dart`
(soal stok, TIDAK terkait perubahan sesi ini), sudah dikonfirmasi
race/flaky lingkungan sandbox (lulus bersih saat dijalankan sendirian
berulang kali). `flutter analyze` bersih (0 issue) di kedua commit.

## Gotcha baru yang ketemu sesi ini (belum sempat masuk CLAUDE.md §Gotcha)

- **Tap BADAN kartu produk di `kasir_screen.dart` TIDAK langsung menambah ke
  keranjang** — cuma buka `ItemEntrySheet` (`onTapBody`/`_openEntry`). Yang
  langsung nambah adalah ikon **"+"** (`AddControl`/`onQuickAdd`,
  `Icons.add_rounded`). Widget test yang mau menaikkan `cartProvider` via
  alur nyata (bukan seed langsung provider) WAJIB
  `tester.tap(find.byIcon(Icons.add_rounded).first)`, BUKAN
  `tester.tap(find.text(productName))` — yang terakhir cuma buka sheet lalu
  diam (tidak ada assert gagal yg jelas, cuma `find.text('Bayar')` dkk
  ketemu 0 widget krn `bottomNavigationBar` tetap `null` selama cart
  kosong).
- Build-runner Drift masih sama sekali tidak bisa jalan di sandbox ini —
  tabel baru (`ReservedOrderNumbers` dkk) harus di-hand-patch ke
  `app_database.g.dart`, ikuti pola `HeldOrders`/`AppSettings` yg sudah ada.

## Yang menggantung / belum sempat

- Tidak ada. Semua pekerjaan sesi ini sudah di-commit & push ke
  `claude/kategori-produk-qty-harga-mqjh21`.
