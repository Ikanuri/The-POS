# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 11 Juli 2026. Backlog Item 9-22 (PLAN.md) 12/13 SELESAI
(Item 17+21 — sync — sengaja ditunda, lihat bagian "MENGGANTUNG" di bawah).
Sesi ini (11 Juli): user upload sampel CSV export Griyo POS untuk migrasi
data toko lama → ditemukan & diperbaiki bug import CSV (`63d0f2d`): parser
cuma kenal pemisah `,` (Griyo pakai `;`), alias kolom tidak cocok header asli
Griyo ("Produk"/"Kode Produk"/"Grup Produk"/"Harga Jual"/"Harga Pokok"), dan
kolom Satuan/Grup Produk berisi ID legacy MENTAH (bukan nama teks) yang
sebenarnya sudah match `_kDefaultUnitTypes`/grup 3-20 di `_seedDefaults`
(app_database.dart) tapi importer tidak pernah memakainya sebagai ID
langsung. Keputusan desain: import tetap FLAT (user pilih ini, bukan
auto-gabung baris nama-sama-satuan-beda jadi 1 produk multi-satuan) karena
CSV Griyo tidak menyertakan rasio konversi antar satuan — digabung manual
lewat Edit Produk bila perlu, dibantu counter `sameNameDifferentUnit` baru
di hasil import._
**Gotcha locale:** app TIDAK memanggil `initializeDateFormatting` — jangan
pakai `DateFormat(..., 'id')` (throw LocaleDataException). Format nama hari/
bulan Indonesia MANUAL (lihat `expenses_screen.dart` `_idDays`/`_idMonths`).

## Lingkungan sesi ini (PENTING untuk sesi lanjutan)
Flutter TIDAK terpasang default di environment ini — dipasang manual ke
`/tmp/flutter` (versi **3.24.5 stable**, samakan dengan CI `build-apk.yml`).
Jalankan `export PATH="/tmp/flutter/bin:$PATH"` tiap sesi baru, `flutter pub get`,
lalu `flutter analyze` + `flutter test`. Kalau `/tmp/flutter` sudah hilang
(container di-reclaim), unduh ulang:
`curl -sSL -o /tmp/flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz" && tar xf /tmp/flutter.tar.xz -C /tmp`.
Baseline sebelum eksekusi: 141 test hijau; setelah Item 22: 149 hijau.
Google Fonts butuh binding aktif — di test, JANGAN panggil `AppTheme.light()/dark()`
di badan `main()` (fase collection); bangun theme DI DALAM `testWidgets`
(lihat `test/chip_and_banner_color_test.dart`).
**Gotcha widget test + drift StreamProvider yang MEMUTASI db:** saat provider
di-dispose di akhir test, drift `StreamQueryStore.markAsClosed` menjadwalkan
Timer 0ms → binding lapor "Timer still pending". Fix: sebelum test selesai,
unmount eksplisit lalu drain — `await tester.pumpWidget(const SizedBox()); await
tester.pump(Duration(milliseconds: 10));` (lihat helper `drain` di
`test/payment_method_edit_delete_test.dart`).
**Overflow PRE-EXISTING (bukan bug baru):** cart bar `kasir_screen.dart:2500`
(Row, ~8.8px) & kartu antrian `:3061` (Column, ~8px) overflow pada lebar 430px
— muncul saat keranjang/panel antrian berisi. Kandidat perbaikan layout
tersendiri; test Item 18 sengaja meng-konsumsi exception ini.

---

## Di Mana Kita Sekarang

### Sesi terbaru — eksekusi backlog Item 9-22 (12 dari 13 SELESAI)
User menyetujui eksekusi seluruh saran fitur + bug + proposal (Item 9-22 di
PLAN.md) dan mendelegasikan penuh ("Anda yang lebih tahu"). Dieksekusi 12 item
berturut-turut, tiap item: kode + test berjenjang + **revert-verify** + full
suite hijau + `flutter analyze` bersih + docs, satu commit per item, push ke
`claude/project-gaps-incomplete-wpgdp8`. Baseline 141 test → **184 test hijau**.

Selesai (lihat CHANGELOG untuk hash): **22** warna chip terpilih (fix tema
sistemik `chipTheme.labelStyle` state-aware, kena 8 titik) + banner sukses
hijau/gagal merah • **10** metode bayar pelunasan hutang (dialog reusable
`debt_payment_dialog.dart`) • **20** tombol edit produk di modal kasir
(owner/asisten) • **14** edit/hapus metode bayar • **9** pengeluaran + Laba
Bersih (`ExpensesScreen`; Laba Bersih = Laba Kotor − daily_expense −
change_given) • **12** Buku Hutang (tab Laporan ke-5) • **18** beralih pesanan
tertahan auto-hold (tanpa dialog "Ganti Keranjang") • **16** atribusi varian
per-satuan (`CartItem.parentProductUnitId` + `belongsToParent`, cascade delete)
+ fix tombol minus • **19** Harga Lain/grosir → dropdown di field Harga •
**11** stok menipis (`ProductUnits.minStock`, **schemaVersion 11**) badge+filter
• **13** pengingat backup (cek saat app dibuka, `BackupReminder`) • **15**
Tutup Kasir harian (tabel `cash_closings`, **schemaVersion 12**).

**schemaVersion sekarang 12.** Migrasi baru: v11 addColumn `product_units.
min_stock` (tanpa guard `from>=X` — product_units cuma di base schema); v12
createTable `cash_closings`. Fixture migrasi test v7-v10 ditambah tabel
`product_units` minimal + assert versi akhir 12.

### ⚠️ MENGGANTUNG — Item 21+17 (sync) BELUM dikerjakan (sengaja ditunda)
Satu-satunya item backlog yang belum: **Item 21** (angkat state sync ke
provider global + banner persisten di shell + lepaskan lifecycle host dari
`SyncScreen.dispose` yang kini `stopHost()` total) & **Item 17** (persist
`_pendingQueue` in-memory ke DB agar selamat restart, lalu majukan watermark
upload). **Sengaja ditunda ke sesi fokus** karena menyentuh infrastruktur sync
multi-device yang KRITIS — bagian "majukan watermark upload" berisiko
kehilangan data diam-diam bila salah (persis yang dicegah full-dump sekarang),
dan butuh test round-trip HTTP asli (HttpOverrides escape-hatch, lihat
CLAUDE.md §Metode Test level 3). Detail lengkap masih di PLAN.md Item 17 & 21.

**Catatan lingkungan sesi ini:** binary `flutter` ada di `/tmp/flutter/bin/flutter`
di environment ini (BUKAN `/opt/flutter/bin` seperti disebut CLAUDE.md — itu
mungkin beda per environment/container, cek `which flutter`/`find` dulu kalau
command CLAUDE.md gagal). Playwright global ada di `/opt/node22/lib/node_modules`
(`NODE_PATH` perlu di-set manual), Chromium executable di
`/opt/pw-browsers/chromium-1194/chrome-linux/chrome` (bukan `chromium/chrome-linux/chrome`
seperti disebut di system prompt — versi folder berubah, cek `find /opt/pw-browsers -iname "*chrome*"`
kalau path itu gagal).

### Sesi sebelumnya (commit `50752cd`) — poles layout topbar kasir
Lihat CHANGELOG untuk detail commit. Ringkasan: lebar collapsed field cari
dihitung presisi dari lebar tombol nyata (bukan hardcode), tinggi Stack
topbar diperbesar supaya label 2 baris tidak kepepet divider, tap
"+"/badan-produk saat search aktif tidak lagi collapse field.

### Fitur eksperimental Katalog Pesanan (branch `claude/order-html-eksperimental`)
Lengkap dua fase (generate HTML → kirim WA → pelanggan pilih barang → kasir
tempel balik ke keranjang), ditambah optimasi performa sesi ini (lihat di
atas). Detail arsitektur lengkap ada di `lib/core/services/order_page_service.dart`
(generator) & `lib/core/services/order_parser_service.dart` (parser).

### Yang SENGAJA belum dibangun (deferred, bukan lupa)
- Hosting "link hidup" (GitHub Pages dkk) untuk Katalog Pesanan — user pilih
  TIDAK sekarang (kirim manual via WA).
- UX varian (arrow-tap + auto-expand-on-search) hanya ada di HTML generated,
  belum diseragamkan ke kasir utama (yang masih pakai long-press).
- Belum ada PR untuk branch `claude/order-html-eksperimental` — menunggu
  instruksi user.
- Item 8 PLAN.md (bawa UI pilih-harga ItemEntrySheet ke HTML) — masih
  diskusi kelayakan, belum ada keputusan scope.

## Ringkasan Sesi Audit Sebelumnya (masih berlaku, tidak diulang detail)
14 bug hasil audit kode menyeluruh sudah diperbaiki & dirilis sebagai
v2.1.1+3 (lihat CHANGELOG). PR #2 sudah di-merge ke `main`.

## Temuan yang SENGAJA Belum Diperbaiki (kandidat diskusi, dari audit)
- **Multi-satuan + varian bercampur**: invariant `storedQty induk = base +
  Σvarian` ambigu bila satu produk punya ≥2 baris satuan non-varian di
  keranjang. Butuh refactor atribusi varian per-baris — jangan disentuh
  tanpa keputusan user.
- Tombol minus di kartu produk (`_decrementProduct`) selalu mengurangi baris
  satuan PERTAMA bila produk ada di keranjang dengan >1 satuan.
- **Upload sync klien→host masih full-dump** (sengaja — antrian approval
  host (`_pendingQueue`) hanya di memori, hilang bila host restart sebelum
  approve; full-dump adalah pengaman agar data tak hilang permanen). Bukan
  "sync satu arah tanpa ACK" — sync SUDAH dua arah & host SUDAH punya review
  manual. Fix presisi = persist `_pendingQueue` ke DB (pola `held_orders`)
  lalu majukan watermark upload. Detail di PLAN.md Item 17.
- Fitur "hantu" yang tabel-nya ada tapi tanpa UI: `expenses` (paling layak
  dibangun — lihat saran fitur), `suppliers/purchases/purchase_items`,
  `customer_groups/customer_group_prices`.

## Saran Fitur dari Audit (menunggu keputusan user, urut prioritas)
1. Pencatatan pengeluaran (tabel/sync/izin sudah ada → laba bersih di laporan).
2. Tukar poin loyalty di layar bayar (tipe ledger `redeem` sudah disiapkan).
3. Pilih metode bayar saat pelunasan hutang (kini hardcode 'tunai' di
   Tambah Bayar & pelunasan gabung nota).
4. Peringatan stok menipis (ambang minimum per satuan).
5. Layar "Buku Hutang" terpusat (siapa berhutang, umur hutang, aksi lunasi).
6. Backup otomatis terjadwal + pengingat "backup terakhir X hari lalu".
7. Edit/hapus metode pembayaran (kini hanya tambah + on/off).
8. Rekap tutup kasir harian (uang seharusnya di laci vs fisik).

## Keputusan Penting yang Masih Berlaku
- Cart meta tab = shrink-wrap kiri, **bukan** full-width.
- Animasi scan yang dipilih = **Opsi E** (garis pulse hijau), dari 8 opsi.
- Referensi proyek tinggal di `docs/reference/` (jangan hapus) — termasuk
  `Mockup.zip` & `Contoh_Dataset.rar` yang masih ada & dipakai aktif untuk
  perencanaan migrasi data (lihat PLAN.md Item 3-5).
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.
- Katalog Pesanan (eksperimental): tanpa hosting, kasir utama tidak
  disentuh (hanya tombol baru ditambah).
- Harga Lain (`alt_prices`) TIDAK pernah dipilih otomatis oleh
  `PriceService.resolvePrice` — murni manual/tap. Urutan tampilnya sekarang
  bisa diatur user via drag-handle di form Produk (`sortOrder` kolom).
- Claude TIDAK punya akses berkelanjutan ke database toko user (offline-first,
  terenkripsi SQLCipher) — alur migrasi data dari dataset lama selalu:
  user kirim data mentah → Claude olah format → user import sendiri lewat
  fitur di app. Lihat "Konteks" di PLAN.md.

## Menggantung / Kandidat Berikutnya
- **PLAN.md Item 3** (konversi format `Products.csv` + fix rasio multi-satuan
  hilang, 31% katalog terdampak) — prioritas TINGGI, harus selesai SEBELUM
  data produk diimpor ke DB live. Menunggu user siap kirim/konfirmasi data
  final.
- **PLAN.md Item 4** (importer pelanggan + poin loyalty, fitur baru) —
  menunggu user jawab 3 pertanyaan desain (overwrite vs delta poin, kunci
  pencocokan, penanganan nama kembar).
- **PLAN.md Item 5** (import riwayat transaksi dari dataset lama) — setelah
  Item 3 selesai, dan setelah user konfirmasi cakupan tanggal file
  `Transaksi ...xlsx` yang tersedia.
- **PLAN.md Item 8** (bawa UI pilih-harga ke HTML Katalog) — menunggu
  keputusan user soal trade-off kompleksitas vs manfaat.
- Saran fitur audit di atas menunggu keputusan user.
- Belum ada PR untuk branch `claude/order-html-eksperimental`.

## Preferensi User
- Untuk fitur bervisual (mis. animasi), **usulkan beberapa opsi desain dulu**
  sebelum implementasi.
- Bahasa komunikasi & teks UI: Indonesia.
- Hati-hati agar perubahan tidak merusak logika/alur aplikasi yang sudah ada.
- Untuk perbaikan bug: laporkan dulu dengan contoh kasus + severity, tawarkan
  metode fix via poll, baru eksekusi sesuai konfirmasi.
- Untuk fitur baru berisiko/besar: diskusikan cakupan dulu (boleh
  dipersempit dari proposal awal), baru eksekusi setelah "eksekusi semua"
  atau konfirmasi serupa.
- Untuk rencana kerja yang didiskusikan tapi belum dieksekusi ("jangan
  coding dulu"): masukkan ke PLAN.md secara komprehensif, jangan cuma
  disimpan di riwayat chat.
