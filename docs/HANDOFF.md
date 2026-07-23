# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md).

_Update sesi 23 Juli 2026 — commit `d9e971a` (SELESAI, terverifikasi): tombol
Bayar di cart bar, transfer QR bebas, nomor nota reservasi. Lanjutan langsung
dari Item 54 (`4e0fbf3`/`8cd5110`, kategori multi-tag) yang sudah selesai
sebelumnya di sesi yang sama._

## Yang baru dikerjakan (Item 55/56/57 — user menyebutnya "1/2/3/4")

Diminta lewat 4 poin sekaligus, semua keputusan arah dikonfirmasi via
`AskUserQuestion` SEBELUM eksekusi (user eksplisit minta TIDAK dicatat di
PLAN.md untuk fitur ini — beda dari kebiasaan Item 54):

1. **Tombol "Bayar" di cart bar** — segmen terracotta baru di tab meta
   (sejajar "Tahan"), tap langsung `context.push('/kasir/bayar')` (TIDAK
   lewat cart sheet dulu). Muncul utk owner/asisten/pegawai berizin
   `terima_pembayaran`; gerbang dipusatkan ke `handoff_gate_provider.dart`
   (`needsPaymentGateProvider`) — dipakai jg oleh `cart_sheet.dart`,
   menghapus provider privat duplikat yg sebelumnya ada di sana.
2. **Transfer QR bebas** (bukan cuma jalur handoff pegawai tanpa izin yg
   sudah ada) — ikon `qr_code_2`+panah kecil di `CartSheet` (gantinya
   "Kosongkan" yg sekarang jadi ikon tempat sampah, dialog konfirmasi tetap
   ada). User pilih ikon ini eksplisit, BUKAN `send_to_mobile` yg
   direkomendasikan.
3. **Nomor nota stabil sejak awal** — tabel baru `reserved_order_numbers`
   (`schemaVersion` 19->20), `reserveLocalId`/`releaseLocalId` di
   `app_database.dart`. Direservasi begitu item pertama masuk keranjang
   (`_CartMetaTab._ensureReserved`, dipanggil via `addPostFrameCallback`),
   ditampilkan sbg `#<segmen terakhir>` (mis. `local_id`
   `K1-20260723-0017` → `#17`) via `CartMeta.displayOrderNumber`. Nomor ini
   IKUT lewat transfer QR (bukan reservasi baru di penerima) & dikonsumsi
   (`releaseLocalId`) begitu checkout tersimpan di `payment_screen.dart`.
4. **CustomerId ikut transfer QR** — `OrderParserService.encodeHandoff`/
   `parse` menambah baris `PelangganId:`/`Nota:`; penerima auto-resolve
   `customerId` HANYA kalau baris itu benar-benar tersync lokal (dicek ke
   `db.customers`), diam-diam fallback ke `customerName` polos kalau tidak
   ketemu (BUKAN error) — `payment_screen.dart._load()` sudah otomatis
   pre-fill `_selectedCustomer` dari `meta.customerId` (mekanisme lama,
   dipakai ulang, tidak perlu kode baru di sisi situ).

Sekalian nebeng di sesi yang sama (bug tidak terkait, dilaporkan mendadak):
**fix sheet "Tempel Pesanan"** — tombol konfirmasi tertutup keyboard krn
`DraggableScrollableSheet.currentSize` tidak reaktif thd `viewInsets`
(`ValueNotifier` diset sekali di `initialChildSize`) — diganti pola
`Padding(bottom: MediaQuery.viewInsets.bottom) + LayoutBuilder +
ConstrainedBox + Column(mainAxisSize.min)` yg sudah dipakai sheet lain di
app ini (`item_entry_sheet.dart`/`cart_meta_pickers.dart`).

**Test baru** (semua revert-verified): `cart_bar_bayar_button_test.dart`,
`cart_sheet_transfer_icon_test.dart`, `reserve_local_id_test.dart`,
`order_parser_customer_id_test.dart`. Migration test v7-v18 diperbarui
ekspektasi `schemaVersion` ke 20 (pola sama spt tiap kali `schemaVersion`
naik — cari `ver.data.values.first`).

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
- Build-runner Drift masih sama sekali tidak bisa jalan di sandbox ini
  (lihat entri sebelumnya) — `ReservedOrderNumbers` di `app_database.g.dart`
  jg di-hand-patch, ikuti pola `HeldOrders`/`AppSettings` yg sudah ada.

## Yang menggantung / belum sempat

- **Full `flutter test` (seluruh suite) belum sempat 1x clean run tuntas
  tanpa gangguan** di sesi ini — 2 percobaan penuh terganggu (proses mati
  sebelum sampai baris ringkasan akhir, kemungkinan restart
  worker/container, BUKAN kegagalan test). Yang SUDAH terverifikasi solid:
  `flutter analyze` bersih (0 issue), seluruh test file baru/terkait Item
  55-57 hijau (28+ test individual, termasuk file lama yg overlap:
  `kasir_handoff_qr_test.dart`, `kasir_scan_order_code_test.dart`), 10 file
  migration v7-v18 hijau setelah expektasi versi diperbaiki ke 20. Run
  penuh pertama (sebelum expektasi migration diperbaiki) sempat sampai
  ~280 test tanpa kegagalan BARU selain 6 kegagalan versi migration yg
  memang sudah diprediksi & sudah diperbaiki. Kalau sesi berikutnya sempat,
  jalankan `flutter test` penuh 1x lagi sbg konfirmasi akhir — TIDAK ada
  indikasi konkret ada regresi, ini murni belum sempat re-run sampai
  selesai karena keterbatasan waktu/proses sandbox.
- Dokumentasi (CHANGELOG/PATCHNOTES/HANDOFF ini) sudah diperbarui &
  di-commit terpisah setelah commit fitur `d9e971a`.
