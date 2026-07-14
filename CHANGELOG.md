# Changelog

Catatan teknis **1:1 dengan riwayat commit** (terbaru di atas). Setiap baris =
satu commit: `hash` — subjek commit. Ini catatan untuk developer/maintainer;
untuk ringkasan ramah-pengguna lihat [PATCHNOTES.md](PATCHNOTES.md).

> Dihasilkan dari `git log`. Saat menambah commit baru, tambahkan entri di
> bawah tanggal yang sesuai (paling atas).


## 2026-07-13

- `24097ec` — feat: katalog HTML — kontrol +/- lingkaran spt app kasir, harga read-only, font lebih besar
- `16b94b9` — fix: scan pesanan pegawai via scanner HID tertentu salah rute ke Tempel Pesanan
- `83e01dd` — fix: tombol Batalkan Pembayaran tidak muncul untuk nota lunas seketika
- `6564852` — feat: katalog HTML — modal tap-item ganti dropdown varian (pilih satuan/harga custom/catatan)
- `955ea34` — feat: bersihkan file share sementara (struk/katalog) yang menumpuk di temp dir
- `acaf2b5` — feat: modal Tambah Bayar Uang Pas pindah kiri + gate kosong, stepper lebih besar, harga produk reaktif
- `5ff92a4` — feat: struk — Bayar+Tambah Belanjaan sejajar, batalkan pembayaran, edit item, fix nota gabungan
- `a8c94ad` — feat: skema v15 — checklist struk persisten, batalkan pembayaran, edit item nota belum lunas
- `174cad7` — feat: gerbang aktivasi/lisensi offline (Item 25c) — public key developer masih placeholder, gerbang nonaktif total
- `fb8ba80` — fix: build APK utk armeabi-v7a + arm64-v8a — akar masalah crash Infinix Smart 8 TERKONFIRMASI
- `f47e67b` — docs: perbarui CHANGELOG/PATCHNOTES/HANDOFF — crash Infinix Smart 8 masih belum selesai
- `2c5ddf9` — fix: pindahkan crash log ke folder Downloads publik (Android/data terblokir File Manager) + jaring lebih awal
- `c48ec4b` — docs: perbarui CHANGELOG/PATCHNOTES/HANDOFF untuk fix tap-to-scan race + HID #PSN:
- `2ee8068` — fix: deteksi basi tap-to-scan + kode #PSN: pecah jadi beberapa scan di HID eksternal
- `26ce99c` — docs: perbarui CHANGELOG/PATCHNOTES/HANDOFF untuk fix crash Infinix Smart 8
- `e3a7b7d` — fix: cegah force-close diam-diam di HP tertentu (mis. Infinix Smart 8) + jaring pengaman crash log
- `1b6d275` — docs: perbarui CHANGELOG/PATCHNOTES/HANDOFF untuk bugfix tap-to-scan + atribusi antrian
- `c146695` — fix: scan tap-to-scan mengulang barang lama + atribusi pelanggan/pegawai tertukar di antrian
- `386b275` — docs: perbarui CHANGELOG/PATCHNOTES/HANDOFF/PLAN untuk Item 24b
- `b04e064` — feat: sheet Verifikasi Pesanan sebelum lanjut bayar antrian handoff (Item 24b)
- `610d8b6` — docs: perbarui CHANGELOG/PATCHNOTES/HANDOFF/PLAN untuk Item 24d-core
- `1f18000` — feat: gerbang pembayaran Pegawai via QR + antrian handoff (Item 24d)
- `7fa7907` — feat: catatan per-produk katalog HTML + tata letak kalkulator bayar (Item 26a/26b/26c)
- `8fa05d8` — docs: masukkan Item 26 — catatan per-produk HTML, posisi Uang Pas/keypad
- `5d65188` — docs: putuskan mekanisme kirim pesanan pegawai — QR gabung scanner kasir
- `9f9cb18` — docs: catat 2 opsi desain mekanisme kirim pesanan pegawai (Item 24d)

## 2026-07-12

- `4317c33` — feat: rename kosmetik "Kasir"→"Pegawai" di UI + izin Terima Pembayaran (Item 24d, bagian 1)
- `5a18301` — feat: tap-to-scan + redesign kapsul melayang scanner kasir (Item 24e+24f), + badge kosmetik "Habis" di kartu kasir (Item 25a — bagian kedua)
- `d9e1f2e` — feat: tanda "Stok Habis" cepat dari modal kasir (Item 25a) — inti
- `29d7400` — feat: hapus produk via swipe di tab Produk (Item 25b)
- `6285481` — feat: katalog HTML default terang + font Hanken Grotesk/Newsreader (Item 24c)
- `37ca76e` — feat: chip Uang Pas di modal Tambah Bayar/Lunasi (Item 24a)
- `a2ad03d` — fix: field harga produk tak bisa diketik setelah tap "Edit produk" dari keranjang (cart sheet salah kebuka lagi di belakang ProdukFormScreen, HID handler menelan input digit)
- `7950176` — docs: perbarui CHANGELOG/PATCHNOTES/HANDOFF untuk poin 2+3 (harga dasar & per-qty)
- `d703c0b` — feat: tampilkan harga per-qty di baris item keranjang kasir (mis. "Karung · Rp 65.000")
- `b1141f6` — feat: tampilkan harga dasar di bawah nama produk (tab Produk)
- `cd382ed` — fix: kalkulator tampilkan Kembalian palsu saat ada sisa tagihan lama (preview _change/_shortfall belum ikut existingShortfall)
- `88c8deb` — fix: hitungkan "Total yang perlu ditagih" di kalkulator, bukan kasir yang jumlah manual
- `765734e` — feat: info "+ Sisa tagihan sebelumnya" di kalkulator Tambah Belanjaan (kasir tahu Total kalkulator ≠ total yang perlu ditagih)
- `87cdaf0` — fix: "Dibayar" di Ringkasan struk tidak konsisten dgn Sisa Tagihan (Total != Dibayar+Sisa)
- `19e679d` — fix: Sisa Tagihan understated saat kembalian dipakai ulang sbg pembayaran baru (double-count di `paid`)

## 2026-07-11

- `c3e975a` — fix: centang "Pakai kembalian" di kalkulator bayar tidak merespons tap (state beku di sheet showModalBottomSheet)
- `0323d3f` — feat: cabut flag Eksperimental dari Tempel Pesanan
- `d77e81e` — feat: info kembalian terakhir + centang di kalkulator bayar Tambah Belanjaan (+ highlight nominal Total)
- `6173b57` — feat: Buku Hutang tampilkan daftar nota belum lunas per pelanggan (+ fix 2 overflow lama)
- `5759c18` — feat: Riwayat Pembayaran tampilkan kembalian per baris + centang per baris
- `399a742` — feat: kembalian per-baris pembayaran (schemaVersion 13)
- `cb87507` — feat: pindah toggle "Izinkan Stok Minus" ke halaman utama Pengaturan (dari dalam Izin Kasir)
- `9e52f61` — fix: owner selalu bisa override stok minus (sebelumnya ikut ke-block sama seperti kasir tanpa bypass khusus)
- `c8a79f1` — fix: tombol "Harga lain" di modal item kasir tampilkan nama opsi terpilih (mis. "Eceran"), bukan cuma hitungan generik
- `e4baa92` — fix: produk hasil import CSV hilang dari katalog HTML (isBaseUnit tidak pernah ditandai true, OrderPageService mensyaratkan itu tanpa fallback)
- `07fee39` — feat: pindah flag Eksperimental dari Katalog Pesanan (HTML, jadi native) ke menu baru "Import dari Griyo POS" (CsvImportScreen griyoMode)
- `63d0f2d` — fix: import CSV format Griyo POS (pemisah ";", header & satuan/grup legacy) — parser hanya kenal ",", alias kolom tidak cocok header asli Griyo, kolom Satuan/Grup berisi ID legacy mentah bukan nama teks

## 2026-07-10

- `15c50b8` — feat: Tutup Kasir harian — rekap kas sistem vs fisik + selisih + riwayat (tabel cash_closings, schemaVersion 12) — Item 15
- `56d42f1` — feat: pengingat backup (cek saat app dibuka, kartu status + toggle interval) — Item 13
- `33ecd4f` — feat: peringatan stok menipis (kolom min_stock, schemaVersion 11) — badge + filter di Produk — Item 11
- `9af9cb6` — feat: Harga Lain & tier grosir jadi dropdown menempel di field Harga (bukan chip menumpuk) — Item 19
- `4bd4d97` — fix: atribusi varian per-satuan (parentProductUnitId) + tombol minus tak menebak saat >1 satuan — Item 16
- `b48f7c2` — feat: beralih antar pesanan tertahan auto-hold keranjang aktif (tanpa dialog, tanpa kehilangan) — Item 18
- `320a0dc` — feat: Buku Hutang terpusat (tab Laporan, urut umur menunggak, lunasi langsung) — Item 12
- `b5ebaff` — feat: pencatatan pengeluaran + Laba Bersih di laporan (ExpensesScreen, unhide izin input_pengeluaran) — Item 9
- `eaa5ea6` — feat: edit metode pembayaran (reuse sheet) + hapus via swipe bila nonaktif — Item 14
- `dbdc779` — feat: tombol edit produk di modal kasir (owner/asisten saja) — Item 20
- `fd4ed1e` — feat: pilih metode bayar saat pelunasan/tambah bayar hutang (dialog reusable, ganti hardcode tunai)
- `f8f65e9` — fix: warna chip terpilih (tema, sistemik) + banner sukses hijau/gagal merah light & dark
- `b949268` — feat: reorder "Harga Lain" via drag-handle di form Produk (schemaVersion 10)
- `c1a9efe` — perf: optimasi halaman HTML Katalog Pesanan untuk HP low-end
- `3bff1b6` — fix: kunci dedup importer CSV ikut barcode/kode produk (silent data loss)
- `ea6e952` — fix: dropdown pelanggan scroll sungguhan, hapus pemotongan .take(N)
- `6f1fbc4` — fix: urutan qty/satuan di struk in-app (1 pcs x, bukan pcs 1 x)

## 2026-07-08

- `50752cd` — fix: rapikan layout topbar kasir + kecualikan tap produk dari collapse cari
- `632a836` — feat: checkbox kembalian sudah diambil, animasi expand kolom cari kasir
- `6dedc80` — feat: tombol Bayar Nanti terpisah, harga alternatif berlabel, poles Katalog Pesanan
- `ef9ab12` — feat(eksperimental): parser & UI Tempel Pesanan sisi kasir (Katalog Pesanan Fase 2)

## 2026-07-07

- `dc9c3ef` — docs: catat fitur eksperimental Katalog Pesanan (commit e422639)
- `e422639` — feat(eksperimental): katalog pesanan HTML self-contained tanpa hosting
- `1993b80` — chore: naikkan versi ke 2.1.1+3 untuk rilis perbaikan audit
- `b6fefbe` — fix: audit code review — consolidate payment logic & archive filtering (PR #2, squash dari `7ed9692`)
- `c1bafd7` — fix: audit ulang — konsolidasi pelunasan ke addPaymentToTransaction + filter arsip per-tahun
- `998a475` — docs: catat hasil audit kode — 14 bug fix + cleanup (commit 7d1fc6f, 81f1af6)
- `81f1af6` — chore: hapus kode mati hasil audit + sembunyikan izin fitur yang belum ada
- `7d1fc6f` — fix: perbaiki 12 temuan bug audit kode (sync arsip, retur multi-bank, CSV, kembalian, dll)
- `dd6f729` — docs: tambahkan metode test wajib sebelum rilis ke CLAUDE.md
- `eeb5ea1` — Rilis production v2.1.0 — deep debug, hardening, retur hutang, backup/restore fix, test suite lengkap
- `58b54bb` — docs: catat version bump 2.1.0+2 di changelog
- `3b7c305` — chore: naikkan versi ke 2.1.0+2 untuk rilis production pertama pasca deep-debug

## 2026-07-06

- `1eec864` — docs: catat Riwayat Transaksi Opsi C, optimasi pencarian, sync watermark (commit d9340b2)
- `d9340b2` — feat: Riwayat Transaksi Opsi C (auto-refresh saat sheet dibuka), optimasi pencarian produk (lepas dari volume riwayat), incremental sync watermark (arah host→klien)
- `b97ffcb` — fix(backup): perbaiki 2 bug restore (cross-device gagal password + StreamProvider tidak ter-notify)
- `a0c4c6c` — test(widget): buktikan overflow nama kasir panjang di struk sudah aman
- `5a8a49b` — docs: catat fitur Sisa/Kembali Riwayat Transaksi + feedback device Tier 4 user
- `79aa836` — feat(kasir): tampilkan sisa hutang/kembalian langsung di baris Riwayat Transaksi + fix overflow header Riwayat Transaksi

## 2026-07-05

- `f2f7829` — docs: catat harness widget-test & 2 overflow fix (changelog, patchnotes, hand-off)
- `7307740` — test(widget): bangun harness widget-test pertama + fix 2 overflow layout nyata di receipt_screen.dart
- `9991519` — refactor(chart): ekstrak clamp tinggi bar jadi pure function + test (Tier 3)
- `5a4ee57` — refactor(kasir): ekstrak alokasi diskon jadi pure function + test (Tier 3)
- `3a7ce6b` — test: Tier 2 — resolvePrice, mergeRows master-data, restoreFromDump, generateUniqueLocalId
- `9b9b3cc` — test: siklus hidup transaksi paling kritis (Tier 1) — saveTransaction, voidTransaction, addReturnTransaction, settleMergedDebt
- `0dff97e` — feat(kasir): retur nota belum lunas kini mengurangi hutang langsung

## 2026-07-02

- `61c7455` — perf(db): indeks transaction_payments(transaction_id) — cegah O(n^2) di startup (schema v7)
- `2d3dc37` — docs: catat hasil sesi deep debug (changelog, patchnotes, hand-off)
- `16ad934` — fix: deep debug — perbaikan bug lintas modul (stok, sync, backup, struk, chart, QRIS)

## 2026-07-01

- `9e16f22` — docs: add project memory files (CLAUDE.md, changelog, patchnotes, hand-off)
- `178d16a` — docs: archive original project reference files

## 2026-06-30

- `702212c` — feat(kasir): pulse animation on scan line for successful scans
- `f2d8b94` — fix(kasir,laporan): 5-item polish batch
- `a6868ce` — Katalog: fitur edit katalog tersimpan
- `e6039ff` — Laporan: ekspor per-kategori dengan grafik sesuai aplikasi + perbaiki ekspor
- `81bfe84` — Kasir: tab meta membentang penuh — hilangkan ruang kosong di samping Tahan
- `57b41c4` — Fitur katalog: buat & bagikan daftar harga sebagai gambar
- `1b292eb` — Settings, kasir, laporan & PDF export improvements

## 2026-06-29

- `7fdb65f` — Docs: revisi proposal pertimbangan Barokah Order
- `99112f9` — Docs: proposal lengkap sistem order pelanggan (HTML + WA + Paste Parser)

## 2026-06-28

- `65197cf` — Fix: scroll keranjang ke bawah — pindahkan trigger ke dalam builder
- `0d9f701` — Fix: keranjang langsung scroll ke bawah saat dibuka dari scan eksternal
- `051357b` — Kasir: debounce scanner eksternal 300ms + auto-scroll keranjang ke bawah

## 2026-06-27

- `939c07b` — Fix: field harga tidak bisa diketik — useRootNavigator membuat HID handler menelan input
- `d4911a8` — Fix: edit harga dari keranjang — tutup sheet dulu sebelum buka editor
- `e6728cd` — Fix: field harga tak bisa diketik (IME desync akibat pemisah ribuan)
- `76bcacf` — Debug: panel diagnostik field harga di modal entri item (sementara)
- `9aed569` — Fix: input harga tak terbaca saat modal item dibuka dari keranjang
- `8feaef7` — Fix: haptik scan tidak muncul + harga tak bisa diedit di modal keranjang
- `98c7ea6` — Kasir: haptik saat scan, scan eksternal buka keranjang, redesign cart bar
- `1f59836` — Sync harga satu arah, approve per kategori, izin stok minus asisten
- `b798ba8` — Kasir: cari SKU, modal edit item dari keranjang, catatan format quote

## 2026-06-26

- `1917ef8` — Fix sync mergeRows: handle local_id collision for append-only tables
- `b261027` — Fix tombol Setuju sync + pindah export katalog harga ke tab produk
- `b22c2ae` — Fix sync error Variable<Object> dan tombol Setuju tidak terlihat
- `f307ad7` — Tambah export CSV produk dan katalog sinkron harga di pengaturan
- `32b057a` — Fix mapping unit types sesuai data lama + merge ID 7,8 ke 12

## 2026-06-25

- `f4c2683` — Tambah 5 satuan baru: Ons, Rek, Paket, Box, Karton

## 2026-06-21

- `8e86e96` — Fix duplikat price tier yang menyebabkan sync harga gagal
- `4eb5a48` — Tambah logging sync harga & diagnostic duplikat tier di Pengaturan
- `033b8e2` — Fix layout antrian sync & terjemahkan nama tabel ke Indonesia
- `165b076` — Cetak tebal nama produk di label item terakhir cart bar

## 2026-06-20

- `bd2f0d6` — Fix logika sync harga: unit-aware match, varian, harga 0, layout
- `003666d` — Fix QR scan sync: strip port dari IP agar tidak dobel
- `9ddb5a9` — Fix sync error: product_units tidak punya kolom updated_at
- `ef3f769` — Penyesuaian UI catatan & laba: blockquote, toggle, riwayat
- `4c49ffb` — Laba inline di struk, catatan nota, pemisah hari riwayat, filter produk detail
- `baf0c8e` — Pelanggan/pegawai di cart bar + tahan pesanan inline
- `ff3b63d` — Tambah QR code untuk sync data dan sync harga

## 2026-06-19

- `9489b29` — Fix tambah belanjaan kedua kali tidak masuk ke struk
- `f8eb105` — Fitur tambah belanjaan: keranjang per-slot + alur bayar selisih
- `2d6a3ca` — Scanner torch + overlay panduan, fondasi tambah belanjaan

## 2026-06-18

- `9caf1c2` — Fitur sinkron harga antar toko: WiFi langsung + CSV

## 2026-06-17

- `b7916d8` — Fitur pegawai toko: dicatat per nota, tampil di struk
- `549709f` — Nota gabungan: id nota tidak bold, footer total/sisa pakai layout struk biasa
- `6d415ca` — Fix nota gabungan: hapus "Struk Gabungan", tambah alamat, perbaiki subtotal
- `266d103` — Struk: jam di samping tanggal, kode nota cukup nomor urut, jarak nama toko
- `f66117b` — Ukuran teks: pengaturan global + auto-fit layar
- `eefe8c0` — Poin loyalitas: aturan konfigurable + poin editable; + induk varian
- `c6ba690` — Kasir: perbaiki minus list view + dropdown varian inline (eksperimen)
- `56d5fba` — Fix: tombol minus, nama+alamat pelanggan di struk, catatan item
- `567037f` — docs: tulis README komprehensif
- `6ace6e7` — Kasir: tambah tombol minus di kartu produk, perbesar lingkaran qty
- `5416439` — Struk: sesuaikan format footer — total/kembali wide, bayar normal
- `979e9a1` — CI: APK langsung download tanpa zip via GitHub Release

## 2026-06-16

- `ebc7314` — Struk: perbesar footer & nama pelanggan, scanner eksternal, edit varian
- `a8c6ac0` — fix: sync izin kasir dari owner ke HP kasir
- `33bfc30` — fix: warna system navigation bar Android mengikuti dark/light mode
- `da6fe2a` — refactor: konsolidasi stok ke satuan dasar (schema v4)
- `8f9619c` — feat: penyesuaian stok manual dari detail produk
- `8fd0aa2` — fix: sync crash transaction_items, harga asli di struk in-app

## 2026-06-15

- `ef77bee` — fix: laba di struk in-app, warna pelanggan umum vs terdaftar
- `10b4bb4` — fix: donut chart contrast, profit di detail transaksi, timestamp semantik
- `6d75d13` — Gabung nota + timeline pembayaran di struk
- `a3e8799` — ci: fall back to debug signing when release keystore is absent
- `5c80c97` — ci: inject signing keystore from GitHub Secrets at build time
- `1685b85` — feat: receipt header redesign, fix customer edit UX, price padding
- `ddc9ddc` — feat: customizable receipt header (WhatsApp, Telegram, free header text)
- `3f928ae` — fix: receipt printed two timestamps
- `85a561c` — feat: inline edit buyer name on receipt screen
- `f825f74` — fix: catalog '+' uses green (not primary) when in cart
- `75edf4a` — UX: auto-select fields, clear confirm, accent color, edit customer in history
- `23cb63c` — fix: undo session variants on discard + inline banner for held orders

## 2026-06-14

- `8b74cc6` — fix: item note clearing + preserve parent base qty when mixing variants
- `a8a9f69` — fix: 8 bugs — variant/parent cart logic, transaction save, history filter, controller leaks, badge qty, CSV price parsing, COGS rounding, archive close
- `63064b1` — revert: 2 fixes that conflicted with project design intent
- `cb3ddd9` — fix: 7 bugs across kasir, produk, pengaturan, and database layers
- `8a539b5` — fix: paired devices inherited owner's device code
- `6431692` — fix: sync token length + archive read-only crash
- `6a9ad2e` — fix: sync timestamp unit mismatch + defensive customer name access
- `63abc4d` — fix: revert misguided B-5/A-5, fix C-5 non-stock false positive
- `27a8c34` — fix(A-5,C-4,A-12,C-5,B-3,B-4,B-5,B-6): apply changes to existing files
- `34dac77` — fix(A-5,C-4,A-12,C-5,B-3,B-4,B-5,B-6): resolve all deferred audit items

## 2026-06-13

- `8046596` — fix: audit P0–P3 — transaction integrity, security hardening, data integrity
- `c8e83ad` — fix: parent/variant flow, inline banner redesign, tutup buku button, printer logs
- `647035f` — fix: constrain trailing FilledButton in tutup buku ListTile
- `663d641` — feat: product group management + unsaved-changes guard on produk form
- `0872c5d` — feat: bold product names on thermal receipt, drop checkmark on print
- `5fe3c9c` — feat: add InlineBannerStateMixin and convert produk/printer screens
- `b721eda` — feat: replace all remaining SnackBars with InlineBanner in pengaturan screens
- `1ab7c7e` — fix: parent/variant cart logic — dua bug kritis
- `e0459fa` — Add InlineBanner widget + timestamp labels on charts
- `20a7ab7` — feat: variant auto-offset in cart + barcode scanner in product form
- `2c96cf5` — feat: redesign receipt format + paper size + format settings
- `7bcee82` — feat: bypass print_bluetooth_thermal with native Kotlin RFCOMM channel
- `903177d` — fix: printer writeBytes — 600ms stabilisasi RFCOMM + warm-up ESC@ sebelum data nyata
- `d928caf` — fix: printer ESC/POS — sanitasi ASCII semua string, em-dash dan non-ASCII tidak lagi crash
- `f2306fe` — feat: debug log panel printer — log setiap langkah koneksi+print dengan timing & warna

## 2026-06-12

- `180d8ba` — fix: teks vertikal di layar printer — override minimumSize FilledButton.tonal di ListTile trailing
- `26e283a` — feat: redesain keypad bayar (slide-up + ✓), warna semantik konsisten, perbaikan layar printer & toast dark mode
- `1a944df` — feat: varian produk (bersarang) + perbaikan tombol "+" katalog
- `aec8589` — fix: printer bluetooth, sticky keypad, delete pelanggan, sort A-Z, bayar nanti, kembalian
- `74d361e` — feat: tutup buku tahunan + arsip read-only
- `1286237` — feat: app icon lebih besar + format backup portable BPOSP
- `e8e953e` — Phase 3: UX + bisnis + fondasi performa database
- `1365b47` — ci: trigger Build APK on claude/** branches
- `c0aeb98` — fix: apply security & bug audit fixes across all layers
- `5f763af` — feat(produk): support multiple price tiers per unit (harga grosir)
- `34615e7` — feat: kasir item entry modal, price in catalog, counter button + fixes
- `5641cd1` — feat: add Slop unit type + seed existing DBs via beforeOpen

## 2026-06-11

- `353b80b` — design: fresh UI — Hanken Grotesk + Newsreader, warm palette, kasir topbar
- `46288de` — ci: build single arm64-v8a APK instead of split-per-abi
- `d672ca7` — fix: use named top-level function for SQLCipher isolateSetup
- `a996c43` — fix: load SQLCipher in background isolate — crash libsqlite3.so not found
- `8809788` — fix ci: pin Flutter 3.24.5 to match dev environment
- `87ae1bf` — feat: kasir UX from mockup — hold orders, tx history, keypad, share struk
- `773774f` — fix: upgrade AGP 8.1→8.3 and Kotlin 1.8→1.9 for file_picker compat
- `c406ad5` — add phase 6 HTML preview (WiFi sync, printer, backup, CSV, export, izin kasir)
- `371e583` — add GitHub Actions build workflow + peach emoji app icon
- `d186289` — enforce input_stok permission for kasir on produk form/list
- `4c5a212` — feat: implement WiFi sync, Bluetooth printer, PDF/XLSX export, backup, CSV import, kasir permissions
- `13882bd` — chore: track Flutter .metadata file
- `2a6a61d` — feat: Phase 5 — Polish: nama produk di struk + barcode screen
- `1adefac` — feat: Phase 4 — Pengaturan screens fungsional
- `15529f1` — feat: Phase 3 — Ringkasan dashboard + Laporan 4-tab
- `c60a678` — feat: Phase 2 — Kasir, Produk, Pelanggan CRUD + pembayaran
- `02f087a` — feat: Phase 1 — Flutter foundation + full DB schema + HTML preview
