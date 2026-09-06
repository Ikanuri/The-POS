# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md).

_Update sesi 6 September 2026 (sesi kedua puluh sembilan). Versi kerja
**2.47.0+98** (MINOR naik, PATCH reset — redesain tampilan terlihat
pengguna, walau perilaku fungsional tidak berubah). schemaVersion TETAP
40 — TIDAK ADA perubahan skema DB sesi ini._

**Sesi ini — redesain sheet "Pengaturan Struk" (ikon gear layar Struk)
SELESAI** (diminta user: ikon gear sebelumnya membuka `PopupMenuButton`
bawaan Flutter berisi 1 item "Tampilkan Laba", "terasa template"/generik).

Diganti (`lib/features/kasir/receipt_screen.dart`, method BARU
`_showReceiptSettingsSheet`) dgn bottom sheet custom mengikuti pola
visual sheet lain di app (handle bar 40×4 + `Material` rounded-top 20,
lihat `debt_payment_sheet.dart`): judul "Pengaturan Struk" ber-ikon
`receipt_long_outlined` accent terracotta, divider, lalu satu
`SwitchListTile` dgn `CircleAvatar` ikon `trending_up` (accent-tint) +
judul "Tampilkan Laba" + subtitle deskripsi singkat + `activeColor:
AppTheme.accent` (Flutter 3.24.5 di repo ini masih pakai `activeColor`,
BUKAN `activeThumbColor` yg baru ada di versi Flutter lebih baru —
dicek langsung ke source SDK sblm dipakai, supaya tidak error nama
parameter tak dikenal). Isi TETAP cuma 1 opsi (scope: redesain tampilan
saja, bukan tambah opsi baru) — perilaku (`_showProfit`, persist ke
SharedPreferences key `receipt_show_profit`) TIDAK diubah sama sekali.

Test baru `test/receipt_settings_sheet_test.dart` (2 test): sheet custom
terbuka dari ikon gear & `PopupMenuButton` sudah tidak ada di tree;
toggle berfungsi, persist ke SharedPreferences, dan bertahan saat sheet
ditutup-buka lagi. Revert-verify dibuktikan gagal dgn kode lama (pesan
gagal masuk akal: `PopupMenuButton` masih ditemukan / `SwitchListTile`
tak ditemukan) sebelum fix dikembalikan.

Full suite: **1494 lulus, 3 gagal** — ketiga kegagalan (
`proposal_unchanged_end_to_end_test.dart` x2,
`sync_status_banner_gap_and_client_wait_test.dart`) TIDAK terkait
perubahan sesi ini (tidak menyentuh sync/proposal sama sekali) dan
LULUS SEMUA saat dijalankan terisolasi (`flutter test <file>` langsung)
— pre-existing flaky/order-dependent test, bukan regresi baru. `flutter
analyze`: 0 issue.

**Sesi sebelumnya — fitur baru "kembalian sudah diambil" di Pra-Bayar
SELESAI**
(diminta user via briefing lengkap, rumus pool sudah dikonfirmasi user
sebelum eksekusi — tidak ada pertanyaan menggantung).

Masalah: baris "Kembalian" (hijau) di footer keranjang kasir dihitung
LIVE dari `prabayarTotal - cartTotal` — begitu kasir SUDAH menyerahkan
fisik kembalian itu, lalu keranjang berubah lagi (customer nambah/kurang
barang), nilai kembalian dihitung ULANG seolah uang itu masih tersedia
→ risiko diserahkan dobel.

Fix (`lib/features/kasir/cart_prabayar_provider.dart`):
- `CartPrabayarNotifier` dapat akumulator `changeTakenTotal` (int,
  BUKAN boolean — kembalian bisa muncul & diambil berkali-kali per
  sesi keranjang) + `poolAvailable = totalLocked - changeTakenTotal`.
  Persist ke SharedPreferences KEY YANG SAMA dgn entri (`cartprabayar_v1_
  <cartId>`) — payload berubah dari bare JSON list jadi objek
  `{entries, changeTakenTotal}`, format lama (bare list) tetap
  ke-parse (fallback 0). `recordChangeTaken(amount)` — dipanggil dari
  checkbox, akumulatif. `clear()`/`replaceAll(entries,
  changeTakenTotal:)` ikut reset/pulihkan bersamaan siklus hidup entri.
- `cart_sheet.dart` (`_PrabayarFooterSummary`, jadi `ConsumerWidget`):
  Sisa/Kembalian dihitung dari `pool = prabayarTotal - changeTakenTotal`
  (bukan `prabayarTotal` mentah). Baris "Kembalian" dapat `Checkbox`
  kecil (18×18, `MaterialTapTargetSize.shrinkWrap`) — tap memanggil
  `recordChangeTaken(nilai yg SEDANG tampil)`, baris langsung
  recompute (checkbox SELALU tampil `value:false`, bukan status
  permanen — kalau kembalian baru muncul lagi nanti, checkbox baru
  lagi).
- `payment_screen.dart`: `buildPrabayarCheckout` dapat param
  `changeTakenTotal` (default 0, kompatibel mundur) — pool dipakai utk
  `combinedPaid`/status/`combinedChange`, porsi yg sudah diambil
  dipotong dari entri Pra-Bayar PALING BARU dikunci (mundur) supaya
  invariant lama `Σ TransactionPayments.amount == combinedPaid` tetap
  terjaga (entri yg abis terpotong 0 tidak menghasilkan baris sama
  sekali). `_prabayarCoversTotal`/`_prabayarPool` juga pindah ke pool
  (`_lockedSum` mentah TETAP dipakai apa adanya utk label "Total
  Terkunci" — informasi faktual, bukan keputusan). Baris info
  "Kembalian sudah diambil" (read-only, tanpa checkbox — sudah
  ditentukan sebelum layar bayar ini dibuka) ditambah kalau
  `changeTakenTotal > 0`.
- Hold/resume order: `changeTakenTotal` ikut tersimpan di payload
  `cartJson` (key baru `prabayarChangeTaken`, sejajar `prabayar`) di
  KETIGA titik hold (`cart_sheet.dart` `_holdCurrent`, `kasir_screen.dart`
  `_holdCurrent`/`_autoHoldCurrentIfAny`) & dipulihkan di
  `_parseHeldPayload`/`_resumeHeld` (fallback 0 utk payload lama).

Test (semua BARU, revert-verify dibuktikan gagal dulu sebelum fix
dikembalikan — pesan gagal masuk akal, bukan error tak relevan):
- `test/cart_prabayar_change_taken_test.dart` (BARU, 5 test) — logic
  murni notifier: akumulasi, no-op utk nilai ≤0, reset via `clear()`,
  persist/reload round-trip, kompatibilitas format lama.
- `test/payment_prabayar_checkout_test.dart` (+4 test) —
  `buildPrabayarCheckout` dgn `changeTakenTotal`: pool dipakai bukan
  lockedSum mentah, potongan dari entri terbaru, entri abis terpotong
  hilang dari payments, default 0 tak berubah perilaku lama.
- `test/cart_sheet_prabayar_test.dart` (+2 test) — interaksi checkbox
  end-to-end (termasuk kembalian MUNCUL LAGI setelah qty dikurangi
  lagi, akumulasi changeTakenTotal via UI), `poolAvailable` vs
  `totalLocked` lewat notifier.
- `test/kasir_prabayar_hold_resume_test.dart` (+2 test) — hold/resume
  bawa `prabayarChangeTaken` utuh, DAN payload lama (tanpa key itu)
  tetap resume normal dgn fallback 0.

Full suite (`--concurrency=1`, serial): **1492 lulus, 1 gagal** —
`lan_sync_timeout_test.dart` (timing-sensitive, network timeout real,
TIDAK terkait Pra-Bayar — lulus normal saat dijalankan sendiri). Saat
dijalankan default (paralel) muncul gagal ekstra (port bentrok antar
file jaringan berbeda — `sync_upload_queue_device_slot_key_test.dart`
dll), juga pre-existing/tidak terkait; lulus semua saat dites
sendiri-sendiri. `flutter analyze`: 0 issue. Komit kode+test `dce7935`.

**Belum dikerjakan / cek sesi depan**: tidak ada — briefing user
tuntas dieksekusi semua poinnya (1-5), tidak ada keputusan desain yang
masih menggantung utk fitur ini.

_Update sesi 6 September 2026 (sesi kedua puluh tujuh). Versi kerja
**2.46.0+96** (MINOR naik — fitur baru terlihat user, PATCH reset 0).
schemaVersion TETAP 40 — TIDAK ADA migrasi baru (kolom kategori di
`AltPrices` sudah ada sejak Fase B, sesi ini cuma menambah JALUR MASUK
mengisinya dari Edit Produk)._

**Sesi ini — fitur "assign ke Kategori Harga langsung dari Edit Produk"
SELESAI** (item request user, komit `6ab6e5e`): sebelumnya satu-satunya
jalur assign produk ke Kategori Harga adalah dari SISI KATEGORI
(`kategori_harga_screen.dart` → "Tambah Produk"). Sekarang section
"Harga Lain (opsional)" di Edit Produk (`produk_form_screen.dart`) —
BAIK satuan produk utama MAUPUN tiap varian — punya ikon
`Icons.sell_outlined` per baris yang membuka picker Kategori Harga +
editor margin langsung dari situ.

Keputusan desain kunci (semua sudah diverifikasi via test, revert-verify
lulus):
- **Reuse, bukan duplikasi**: editor margin bidirectional
  (`_MarginEditorSheet` lama di `kategori_harga_screen.dart`) diekstrak
  jadi `PriceCategoryMarginSheet` (`lib/core/widgets/price_category_
  margin_sheet.dart`) — return hasil via `Navigator.pop`, TIDAK menulis
  DB sendiri (beda dari versi lama). `kategori_harga_screen.dart` sudah
  dipindah pakai widget ini (pemanggil di sana yang menulis DB via
  `setPriceCategoryMargin`, perilaku observable TIDAK berubah — dites).
  File yang sama juga berisi `pickPriceCategoryForRow` (pilih kategori
  existing/buat baru → buka editor margin, atau "Lepas dari Kategori").
- **Baris category-linked di Edit Produk TIDAK langsung tulis DB** — beda
  dari alur kategori_harga_screen (yang langsung `setPriceCategoryMargin`
  saat sheet ditutup). Di Edit Produk, hasil picker cuma mengubah state
  lokal (`_AltPriceEntry` utk satuan produk utama; parallel lists
  `altCategoryIds`/`altAnchors`/`altTypes`/`altValues` utk dialog
  varian) — persis pola Harga Lain manual, baru benar² tersimpan saat
  tombol Simpan (form produk ATAU dialog varian) ditekan. `createVariant`/
  `updateVariant` (`app_database.dart`) altPrices param ganti dari record
  polos `({label, price})` jadi typedef `AltPriceInput` (+4 field
  kategori nullable) supaya varian ikut mendukungnya.
- **Unassign ("Lepas dari Kategori") MEMBEKUKAN harga live-computed
  terakhir jadi manual, TIDAK mengosongkan** — konsisten dgn keputusan
  desain existing `deletePriceCategory` (massal, dokumentasi kelasnya
  di `pricing_tables.dart`) yang juga membekukan bukan menghapus data
  owner. Alasan: user baru saja lihat angka itu di layar (harga wajar),
  memaksa isi ulang dari 0 lebih mengganggu daripada berguna.
- **costPrice varian sendiri, bukan induk** dipakai sbg acuan 'Modal' —
  sudah dikonfirmasi user tidak ada kasus redundan dgn
  `followsParentPrice`/`_cascadeVariantPricesForUnit` (itu cuma
  meng-cascade tier dasar minQty=1, TIDAK PERNAH menyentuh
  AltPrices/costPrice varian). Dialog varian tidak py field costPrice
  editable (nilainya ikut costPrice induk saat dibuat, lihat
  `createVariant`) — cukup diteruskan sbg parameter baca-saja ke dialog.

Test baru (semua revert-verify lulus — gagal jelas tanpa fix, hijau
lagi dgn fix): `variant_price_category_test.dart` (DB murni,
createVariant/updateVariant persist + live-compute category fields
varian), `produk_form_price_category_assign_test.dart` (widget, assign
+ unassign satuan produk utama — WAJIB lewat router sungguhan
`MaterialApp.router`/`routerProvider`, BUKAN `pumpWithFakeApp`, krn
tombol "Simpan Produk" menutup layar via `context.pop()` go_router),
`produk_form_variant_price_category_assign_test.dart` (widget, assign
lewat dialog Tambah Varian — cukup `pumpWithFakeApp` krn dialog varian
pakai `Navigator.pop` lokal, bukan go_router).

Bug kecil ketemu & difix selama sesi ini: `FilledButton.tonal` di field
"+ Kategori Baru" (dalam `Row` tanpa `Expanded`) crash infinite-width —
gotcha `minimumSize` lebar penuh (`AppTheme`) yang sudah didokumentasikan
di CLAUDE.md, ketemu lewat widget test (bukan kelihatan dari baca kode).

Full suite: 1480 lulus, 3 gagal — SEMUA pre-existing & tidak terkait
(port 8625 "Address already in use" di 3 test LAN-sync paralel yg
memang saling rebutan port fisik, bukan regresi sesi ini — dikonfirmasi
re-run test file yang relevan (`kategori_harga_screen_test.dart`)
sendirian 100% hijau). `flutter analyze`: 0 issue.

**Belum tersentuh sesi ini (potensi kerja lanjutan kalau diminta)**:
- Belum ada cara MASSAL assign banyak produk sekaligus dari Edit Produk
  (alur ini per-baris/per-produk saja) — kalau user butuh bulk-assign,
  tetap pakai jalur lama dari `kategori_harga_screen.dart`.
- `_NewCategoryField` (bikin kategori baru inline dari picker) belum
  divalidasi nama duplikat (biarkan `addPriceCategory` — tidak ada
  constraint unique di tabel `PriceCategories`, sama dgn perilaku form
  Tambah Kategori yang sudah ada).

---

_Sesi sebelumnya (6 September 2026, sesi kedua puluh enam) — investigasi
& fix bug finance-critical Kategori Harga SELESAI:_
user melapor "override harga produk yang ada di kategori tertentu,
mengapa harga dasar masih tetap harga kategori tersebut ketika diswitch
kembali ke kategori normal?".

Hasil investigasi (reproduksi via `pumpWithFakeApp`-style widget test,
BUKAN cuma baca kode):
- `repriceCartForCategoryChange` (`cart_price_category_provider.dart`) —
  logika toggle kategori di keranjang SUDAH BENAR sejak awal. Baris
  `priceOverridden==true` konsisten dilewati; skenario "override manual
  saat kategori aktif -> toggle ke Normal -> harga tetap nilai override"
  LULUS tanpa perubahan kode sama sekali (test regresi ditambahkan
  utk mengunci ini).
- Bug SEBENARNYA ada di `item_entry_sheet.dart`: chip "Harga dasar"
  (`_priceOptions()` produk utama, & `_MiniPriceChip` varian) memakai
  `_UnitOption.basePrice`/`_VariantOption.price` — field ini SUDAH hasil
  resolve Kategori Harga aktif (dipakai jg utk pre-fill field Harga,
  benar utk itu), tapi ikut dipakai sbg acuan "harga dasar" — SALAH.
  Kasir yg tap chip "Harga dasar" bermaksud kembali ke harga normal
  malah tetap dapat harga kategori lama (chip-nya sendiri yg mislabel).

Fix: field baru `trueBasePrice` (resolve KEDUA kali TANPA
`activeCategoryId`, hanya query ekstra saat baris memang category-priced
— tidak nambah biaya di kasus umum). Chip "Harga dasar" (produk & varian)
sekarang pakai `trueBasePrice`; field `basePrice`/`price` (efektif) TIDAK
disentuh — tetap dipakai apa adanya utk pre-fill & baseline
`_priceOverridden` (perilaku lama, non-kategori, TIDAK regresi — sudah
dites eksplisit).

Test baru: `test/item_entry_sheet_price_category_true_base_test.dart`
(5 test — 2 reproduksi bug/fix, 1 skenario penuh laporan user, 2 regresi
non-kategori & non-anggota). Revert-verify: 2/5 gagal tanpa fix
("Rp 10.000 not found"), 3/5 SUDAH lulus tanpa fix (membuktikan
`repriceCartForCategoryChange` independen benar). Full suite: 1480
lulus, 0 gagal. `flutter analyze`: 0 issue. Komit `ee313e8`.

**Sesi ini**: bugfix kecil — `Badge` notif jumlah di `_CategoryIconBtn`
(ikon kategori/search/Kuota/Salin, `laci_meja_dashboard_screen.dart`)
diberi `offset: const Offset(10, -10)` supaya tidak numpuk di atas glyph
ikon yang (sejak revisi sesi sebelumnya) sudah di-tengah kotak 36×36 via
`alignment: Alignment.center`. Komit `a6e07ba`.

_Update sesi 5 September 2026 (sesi kedua puluh empat). Versi kerja
**2.45.0+92** (MINOR naik — redesain lanjutan dashboard Laci Meja +
Kategori Harga pindah lokasi, keduanya terlihat pengguna). schemaVersion
TETAP 40 — TIDAK ADA perubahan skema DB sesi ini (murni UI + logika)._

**Sesi ini** — 3 revisi kecil-menengah thd fitur yang sudah live:

1. **Baris statistik tab Pre-order Laci Meja dirapikan lagi**
   (`laci_meja_dashboard_screen.dart`): dropdown INTERNAL pemilih produk
   jaminan (di dalam chip statistik, `ProductPickerDropdown` kedua) DIHAPUS
   — fungsinya sudah diwakili dropdown filter produk UTAMA. Jaminan
   sekarang TEKS BIASA "Jaminan: N" yang ikut `effectiveProduct` (produk yg
   sedang difilter dropdown utama, ATAU produk tunggal implisit kalau cuma
   1 produk aktif — pola yg SAMA dgn garis kuota) — disembunyikan TOTAL
   kalau "Semua Produk" dipilih & ada >1 produk aktif (tidak ada satu
   produk tunggal utk dihitung). Field cari jadi SATU ikon 36×36 (persis
   `_CategoryIconBtn`), melebar via `Stack`+`AnimatedPositioned` (pola
   PERSIS `_KasirTopbar` di `kasir_screen.dart`, konstanta durasi dibuat
   ulang lokal krn private ke file asal) menimpa tombol Kuota+Salin
   Laporan yang PINDAH ke baris atas (`_PreorderTopActionBtn` baru) —
   kedua tombol itu CUMA tampil di tab Pre-order (disembunyikan total di
   Titip/Ketinggalan & Pinjaman). qty total ("Produk: N") & jumlah entri
   ("N entri") pindah ke baris dropdown filter produk. `_PreorderStatsLine`
   DIHAPUS TOTAL sbg satu widget — logikanya dipecah jadi
   `_computePreorderStats` (method static, dipakai SEKALI di `build()` lalu
   hasilnya diteruskan ke `_buildPreorderList` — satu sumber kebenaran,
   tidak dihitung ulang) + `_PreorderTopActionBtn` (tombol ikon 36×36
   reusable utk Kuota/Salin).
2. **Fix bug nyata (revisi mid-turn)**: `Container` 36×36 pembungkus ikon
   di `_CategoryIconBtn` (dan search/Kuota/Salin baru) TIDAK PUNYA
   `alignment` → ikon numpuk di POJOK KIRI-ATAS box, bukan di tengah. Fix:
   tambah `alignment: Alignment.center` ke tiap `Container` 36×36 di baris
   ini (`IconButton`-based sudah center by default, revert-verify
   membuktikan Container-based-lah yang benar2 butuh fix ini).
3. **Menu "Kategori Harga" pindah dari Pengaturan ke layar Produk** —
   `ListTile` di `pengaturan_screen.dart` dihapus, `IconButton` baru
   (`Icons.sell_outlined`, tooltip "Kategori Harga") ditambah di AppBar
   `produk_list_screen.dart` (antara "Kelola Kategori" & "Katalog"). Route
   TETAP `/pengaturan/kategori-harga` (URL internal saja, push lintas-tab
   dalam `ShellRoute` yg sama, pola sama `receipt_screen.dart` push
   `/kasir/struk/:id` dari tab lain) — sengaja TIDAK dipindah grouping,
   biar minimal-risiko.

Test baru: `laci_meja_top_row_actions_test.dart` (search 36×36, Kuota/Salin
cuma di Pre-order & ketutup search, semua ikon centered — geometri
`tester.getCenter`, bukan cuma "ada"), `kategori_harga_entry_point_test.
dart` (ListTile hilang dari Pengaturan, IconButton baru navigasi ke
`KategoriHargaScreen` via `GoRouter` nyata). Disesuaikan (bukan dihapus):
`laci_meja_dashboard_redesign_test.dart`, `laci_meja_dashboard_grouping_
test.dart` (2 test dropdown-jaminan-internal ditulis ulang jadi test
dropdown-filter-utama, 1 test marquee jaminan DIHAPUS krn fiturnya sendiri
hilang), `preorder_quota_line_test.dart` (assersi "chip nama produk"
dihapus). SEMUA revert-verify (fix dibalik → test gagal dgn pesan masuk
akal → fix dikembalikan → hijau lagi).

Full `flutter test`: **1471 lulus, 0 gagal** (termasuk
`proposal_unchanged_end_to_end_test.dart` — TIDAK flaky run ini, port 8625
tidak bentrok). `flutter analyze` bersih (0 issue). Push ke branch fitur +
merge ke `main` sudah dilakukan sesi ini.

Tidak ada item menggantung dari 3 revisi ini.

---

_Update sesi 5 September 2026 (sesi kedua puluh tiga). Versi kerja
**2.44.0+91** (MINOR naik — toggle Kategori Harga di keranjang,
terlihat pengguna). schemaVersion TETAP 40 — TIDAK ADA perubahan skema
DB sesi ini (murni logika + UI, kolom yg dipakai sudah ada dari Fase B)._

**"Kategori Harga" (Fase A + B + C) SUDAH LENGKAP/SELESAI SEMUA** — tidak
ada Fase lanjutan yang direncanakan lagi kecuali user minta sesuatu yang
baru. Fase A (diskon % di Ubah Total) & Fase B (skema `PriceCategories`
+ margin per-produk + layar kelola di Pengaturan) sudah live sebelumnya.
**Fase C (`d77117e`)** — toggle kategori AKTIF langsung di
keranjang kasir:
- Kasir pilih 1 kategori (chip "Normal"/nama kategori) di `CartSheet`
  (HANYA `kMainCartId`) — baris keranjang yang produknya terdaftar di
  kategori itu otomatis pindah ke harga kategori (live-computed dari
  margin Fase B, bukan formula baru). Chip disembunyikan total kalau
  device tak berizin `override_harga` ATAU belum ada `PriceCategories`
  sama sekali.
- **Prioritas resolusi harga** (final): manual override (`CartItem.
  priceOverridden`, di level CartItem) > kategori aktif > harga grup
  pelanggan > tier qty > harga dasar. `PriceService.resolvePrice`
  parameter baru `activeCategoryId` (source baru `PriceSource.category`,
  costPrice tetap dari tier qty berlaku spy laba akurat).
- **Manual override SELALU menang** — baris `priceOverridden==true`
  TIDAK PERNAH disentuh toggle, baik saat dinyalakan/dimatikan/ganti
  kategori. Penanda `CartItem.priceFromCategoryId` MURNI internal
  (dipakai `repriceCartForCategoryChange` di
  `cart_price_category_provider.dart`), tidak pernah mengubah
  `priceOverridden`/ikon pensil override manual — badge visualnya beda
  (`Icons.sell_outlined`, bukan `Icons.edit`).
- Item baru via `ItemEntrySheet` selagi kategori aktif → harga awal
  SUDAH harga kategori (baca `cartPriceCategoryProvider` saat
  `resolvePrice`); edit manual sebelum submit tetap melewati penanda.
- Hold/resume (`kasir_screen.dart` + `cart_sheet.dart`): kategori aktif
  ikut payload (`priceCategory`), pulih saat resume. Transfer transaksi
  via QR SENGAJA TIDAK membawa penanda kategori lintas device (di luar
  scope — device penerima terima harga apa adanya, perilaku lama).
- **Gotcha ketemu sesi ini**: daftar `PriceCategories` di `CartSheet`
  SENGAJA `FutureProvider` (`priceCategoriesForToggleProvider`), BUKAN
  `StreamProvider` reaktif — `CartSheet` dipakai puluhan test widget yg
  menutup `AppDatabase` di `tearDown` TANPA `drain()` (lihat gotcha
  `StreamProvider` di CLAUDE.md); begitu ditambah sbg `StreamProvider`,
  `cart_sheet_transfer_icon_test.dart` (dan berpotensi test `CartSheet`
  lain) langsung HANG "Timer is still pending". Kategori tidak pernah
  diedit dari alur kasir (CRUD-nya di layar Pengaturan terpisah) jadi
  tidak butuh reaktif live — fetch sekali tiap sheet dibuka sudah cukup.
- 22 test baru (semua di-revert-verify): `price_service_category_test.
  dart`, `cart_reprice_category_test.dart`,
  `kasir_price_category_hold_resume_test.dart`,
  `cart_sheet_price_category_toggle_test.dart`,
  `item_entry_sheet_price_category_test.dart`. Full `flutter test`:
  **1463 lulus, 1 gagal** (`proposal_unchanged_end_to_end_test.dart`,
  port 8625 "Address already in use" — dikonfirmasi lulus sendirian,
  pola flaky yg sama, BUKAN regresi). `flutter analyze` bersih (0 issue).

Tidak ada item menggantung dari Fase C — scope selesai persis sesuai
briefing.

---

_Update sesi 5 September 2026 (sesi kedua puluh dua, dikerjakan di git
WORKTREE terpisah dari sesi Fase B "Kategori Harga" di atas — dua agen
paralel, fitur TIDAK terkait). Versi kerja **2.43.0+90** (MINOR naik —
redesain dashboard Laci Meja, terlihat pengguna). schemaVersion TETAP
40 — TIDAK ADA perubahan skema DB sesi ini (murni redesain UI)._

**Sesi ini** — redesain dashboard Laci Meja
(`laci_meja_dashboard_screen.dart`) supaya lebih compact, 3 instruksi
persis dari mockup yang sudah disetujui user (screenshot Playwright):
1. **3 kartu ringkasan besar (`_SummaryCard`) -> 3 ikon kotak kecil**
   gaya PERSIS `_TbBtn` kasir (`kasir_screen.dart`): 36x36, radius 10,
   border 0.75 `outlineVariant`, ikon 18px berwarna aksen per-kategori,
   `Badge` Material kecil menempel utk count (gantiin angka besar
   lama). Tap ikon = fungsi ganda: pindah kategori aktif SEKALIGUS
   badge menampilkan count kategori itu. Kategori aktif ditandai latar
   (`bg`) + bingkai lebih pekat (`fg`, width 1.4) warna aksennya;
   kategori tidak aktif latar transparan + bingkai netral tipis (0.75)
   — ikon TETAP berwarna aksennya kapan pun (bukan cuma saat aktif).
2. **Warna aksen baru** di `app_theme.dart`: `pinjamanFg`/`pinjamanBg`
   (indigo/periwinkle, `#4C5FA8` light / `#AAB6E8` dark) untuk
   Pinjaman; `preorderFg`/`preorderBg` (turquoise/petrol, `#1B7A82`
   light / `#6FD3DA` dark) untuk Pre-order. Titip/Ketinggalan reuse
   `laciFg`/`laciBg` lama (dusty-rose) — sesuai izin briefing ("boleh
   dipakai lagi utk salah satu dari 3 kategori"). TIDAK reuse
   `tealFg`/`tealBg` (sudah dipakai Pengaturan -> Perangkat).
3. **Satu field cari untuk KETIGA kategori** — `LaciMejaExpandableSearch`
   (`laci_meja_expandable_search.dart`) dipromosikan jadi widget shared
   (sebelumnya privat tab Pre-order), diposisikan di samping 3 ikon
   kategori satu baris. Provider digeneralisasi:
   `_preorderSearchProvider`/`_preorderSearchExpandedProvider` ->
   `_laciMejaSearchProvider`/`_laciMejaSearchExpandedProvider` (level
   dashboard, dipakai bersama). Teks TIDAK reset saat pindah kategori.
   **Titip/Ketinggalan & Pinjaman SEBELUMNYA SAMA SEKALI tidak punya
   filter pencarian** — `_buildLeftBehindList`/`_buildBorrowedList`
   sekarang ikut menyaring nama pelanggan ATAU nama barang
   (case-insensitive `contains`, logika sama `_buildPreorderList`).
   Dropdown filter produk Pre-order (`ProductPickerDropdown`,
   `_preorderProductFilterProvider`) TETAP ADA & TETAP KHUSUS
   Pre-order (bukan bagian field cari bersama) — dipindah ke baris
   tersendiri di bawah baris ikon+cari, tampil hanya saat kategori
   Pre-order aktif & >1 produk.
4. **Container besar pembungkus baris statistik Pre-order dihapus** —
   `_PreorderStatsLine` dirender langsung (tanpa `Container` luar
   ber-`color`/`border`/`padding`), tiap atribut di dalamnya (chip
   "N entri", chip Produk/Jaminan, dropdown, tombol Kuota/Salin) sudah
   punya bingkai sendiri-sendiri (`_StatChip` & `IconButton.styleFrom`
   yang sudah ada + chip "N entri" baru dibungkus `Container` kecil
   berbingkai sendiri).

**Bug ditemukan+diperbaiki saat implementasi** (BUKAN dari briefing,
ketemu lewat widget test yg BENAR2 pindah kategori lalu buka lagi field
cari-nya): search field yang pembungkusnya berubah tipe (`Expanded`
saat status expanded, widget POLOS saat collapsed) membuat Flutter
memperlakukannya sbg elemen BEDA di slot `Row` itu tiap kali status
expanded berganti -> `LaciMejaExpandableSearch` LAMA (berikut
`TextEditingController`-nya, isi teks pencarian) DIBUANG & dibuat ulang
KOSONG begitu kategori dipindah lalu field cari dibuka lagi. Fix: field
cari SELALU dibungkus `Expanded` (collapsed cuma memberi ruang sisa,
tidak mengubah tampilan ikon kecilnya).

**Test**: `laci_meja_dashboard_redesign_test.dart` (9 kasus baru —
tap ikon pindah kategori+visual aktif, badge count sesuai seed, badge
count-0 disembunyikan, pencarian menyaring ketiga kategori [termasuk
2 yg SEBELUMNYA tidak difilter sama sekali], teks cari tidak reset
pindah kategori [termasuk revert-verify utk bug `Expanded` di atas],
tidak overflow 360dp, container besar pre-order sudah tidak ada).
Semua di-revert-verify (dikonfirmasi gagal dgn pesan masuk akal
terhadap kode `_SummaryCard` lama sebelum redesain, dikembalikan lagi).
Beberapa test LAMA lintas file lain (mis.
`laci_meja_dashboard_redesign_test.dart` bukan satu2nya — test lama di
`laci_meja_dashboard_grouping_test.dart`/`laci_meja_dashboard_redirect_
test.dart`/dll yg tap `find.text('Pinjaman')`/`find.text('Pre-order')`)
SENGAJA TIDAK diubah krn label teks itu SENGAJA dipertahankan persis di
bawah ikon (bukan dihapus total) — supaya semuanya tetap lulus TANPA
modifikasi.

Full `flutter test`: **1441 lulus, 1 gagal** —
`proposal_unchanged_end_to_end_test.dart` ("Address already in use"
port 8625, SocketException), dikonfirmasi HANYA gagal saat paralel
penuh & lulus sendirian (pola sama yg sudah didokumentasikan
sesi-sesi sebelumnya, BUKAN regresi sesi ini). `flutter analyze` bersih
(0 issue).

Tidak ada item menggantung dari sesi ini — scope selesai persis sesuai
briefing (3 instruksi mockup di atas), `riwayat_laci_meja_screen.dart`
sengaja TIDAK disentuh (di luar scope).

---

_Update sesi 5 September 2026 (sesi kedua puluh satu). Versi kerja
**2.42.0+89** (MINOR naik — layar baru Pengaturan -> Kategori Harga,
terlihat pengguna). **schemaVersion 39 -> 40** — tabel baru
`PriceCategories` + 4 kolom nullable di `AltPrices` (migrasi aditif)._

**KONTEKS PENTING utk sesi berikutnya**: sesi ini adalah **Fase B** dari
rencana besar "Kategori Harga" (Fase A = mode Diskon % di Ubah Total,
`f527c4e`, SELESAI & sudah di sesi sebelumnya — TIDAK terkait langsung).
- **Fase B (SESI INI, `143eacd` + `5f45f4a`, SELESAI)** — skema +
  kalkulasi + layar kelola kategori. Detail di bawah.
- **Fase C (BELUM DIKERJAKAN, MENYUSUL TERPISAH)** — toggle AKTIF
  kategori harga di keranjang kasir + integrasi `PriceService.
  resolvePrice`. JANGAN mulai tanpa konfirmasi user — `PriceService`/
  `resolvePrice`/logika pemilihan harga di `ItemEntrySheet` SENGAJA
  TIDAK disentuh sesi ini. Prinsip yang SUDAH disepakati utk Fase C
  nanti: **manual override selalu menang** begitu ada toggle aktif
  kategori di keranjang.

**Yang dibangun sesi ini** (lihat dok inline di tiap file utk detail
penuh, jangan re-derive dari nol):
- **Skema** (`lib/core/database/tables/pricing_tables.dart`):
  `PriceCategories` (id/name/sortOrder/createdAt — MURNI label
  pengelompokan, TIDAK ADA margin default per kategori — margin SELALU
  per-produk). `AltPrices` +4 kolom nullable: `priceCategoryId`,
  `marginAnchor` (`'modal'`|`'dasar'`), `marginType`
  (`'percent'`|`'fixed'`), `marginValue`. Baris `AltPrices` lama/manual
  tanpa kategori TIDAK berubah perilakunya sama sekali.
- **Kalkulasi murni** — `lib/core/utils/price_category_calc.dart`:
  `computeCategoryPrice`/`computeMarginValue` (bidirectional — margin
  <-> harga jual, sumber kebenaran = margin). Guard: anchor `'modal'`
  dgn `costPrice<=0` melempar `ArgumentError` (banyak produk toko nyata
  belum punya HPP — bukan kasus langka).
- **Harga LIVE (bukan beku)** — `AppDatabase.getAltPrices()`
  (`app_database.dart`) menghitung ULANG harga baris berkategori dari
  `PriceTiers` TERKINI produk itu sebelum dikembalikan (kolom `price` di
  DB cuma snapshot/fallback jika `computeCategoryPrice` gagal, mis. HPP
  dihapus belakangan). Efek samping BAGUS: chip "Harga Lain" kategori di
  `ItemEntrySheet` otomatis dinamis TANPA `ItemEntrySheet` diubah sama
  sekali (diverifikasi, bukan asumsi).
- **CRUD DB** (`app_database.dart`): `getAllPriceCategories`/
  `watchPriceCategories`/`addPriceCategory`/`renamePriceCategory`/
  `reorderPriceCategories`/`deletePriceCategory`/
  `getPriceCategoryMembers`/`setPriceCategoryMargin`/
  `removeProductFromPriceCategory`. **Keputusan hapus** (2 semantik
  BEDA, sengaja): `deletePriceCategory` (massal) melepas keterkaitan
  baris `AltPrices` anggota (jadi harga manual BEKU, TIDAK dihapus —
  bisa dipulihkan); `removeProductFromPriceCategory` (satu baris, dari
  layar detail) MENGHAPUS TOTAL baris itu (dibuat khusus lewat layar
  ini, bukan alt-price manual buatan owner sendiri).
- **UI** — `lib/features/pengaturan/kategori_harga_screen.dart`:
  `KategoriHargaScreen` (list, pola sama `PaymentMethodsScreen`) +
  `KategoriHargaDetailScreen` (anggota + tambah/keluarkan produk) +
  `_MarginEditorSheet` (bottom sheet bidirectional Margin<->Harga Jual,
  toggle Acuan/Jenis via `SegmentedButton`) + `_ProductUnitPickerScreen`
  (cari produk -> pilih satuan). Route `/pengaturan/kategori-harga`,
  entry menu di `PengaturanScreen` dekat "Metode Pembayaran".

**Test**: `price_category_calc_test.dart` (19 kasus murni),
`migration_v40_test.dart`, `price_categories_db_test.dart` (9 kasus DB:
CRUD, live-price, semantik hapus x2, upsert, guard costPrice=0),
`kategori_harga_screen_test.dart` (6 kasus widget). Semua di-revert-
verify. Test migrasi LAMA (`migration_v7..v39_test.dart`) diperbarui
assert `PRAGMA user_version` akhir dari 39 -> 40 (konsekuensi mekanis
bump schemaVersion, konvensi lama proyek — lihat commit `2e640c3`).

Full `flutter test`: **1431 lulus, 2 gagal** — KEDUANYA
`proposal_unchanged_end_to_end_test.dart` ("Address already in use" port
8625, SocketException), dikonfirmasi HANYA gagal saat paralel penuh &
lulus sendirian (pola sama yang sudah didokumentasikan sesi-sesi
sebelumnya, BUKAN regresi sesi ini). `flutter analyze` bersih (0 issue).

Item opsional yang SENGAJA TIDAK dikerjakan sesi ini (boleh dilakukan
sesi lain kalau owner minta): indikator read-only "Kategori: <nama>" di
`produk_form_screen.dart` (form Produk) utk baris alt-price yang sudah
ke-assign kategori — briefing eksplisit menandainya opsional & TIDAK
boleh mengganggu alur input alt-price manual yang sudah ada; risikonya
dinilai lebih besar dari manfaatnya utk sesi ini.

---

_Update sesi 5 September 2026 (sesi kedua puluh). Versi kerja **2.41.0+88**
(MINOR naik — mode Diskon % baru di dialog Ubah Total, terlihat pengguna).
schemaVersion TETAP 39 — TIDAK ADA tabel/skema baru disentuh sesi ini
(sengaja, lihat konteks Fase A di bawah)._

**KONTEKS PENTING utk sesi berikutnya**: sesi ini adalah **Fase A** dari
rencana besar "Kategori Harga" yang sudah didiskusikan panjang dgn user
tapi SENGAJA dipecah jadi 3 fase independen (risiko rendah dulu):
- **Fase A (SESI INI, `f527c4e`, SELESAI)** — mode "Diskon %" di dialog
  "Ubah Total" (layar bayar), murni UI + fungsi murni baru
  `applyPercentDiscount`, TANPA skema/tabel baru sama sekali.
- **Fase B (BELUM DIKERJAKAN)** — tabel Kategori Harga + margin per-produk.
  Akan didelegasikan ke sesi/agen TERPISAH nanti — JANGAN mulai di sesi
  yang menyentuh hal lain tanpa konfirmasi user lebih dulu.
- **Fase C (BELUM DIKERJAKAN)** — toggle aktif Kategori Harga di keranjang.
  Bergantung pada Fase B selesai duluan.

Kalau user menyinggung "Kategori Harga" lagi, kemungkinan besar maksudnya
lanjut ke Fase B — cek dulu apakah ada detail desain tambahan yang belum
didiskusikan (struktur tabel margin, aturan prioritas kategori, dst)
sebelum mulai coding.

**Sesi ini (`f527c4e`)**: dialog "Ubah Total" (`_editTotal`,
`payment_screen.dart`) yang SEBELUMNYA cuma 1 mode (ketik nominal langsung)
diperluas jadi 2 mode via `ChoiceChip` toggle di dalam `AlertDialog` yang
SAMA (bukan dialog terpisah) — `_EditTotalDialog` (StatefulWidget baru,
lihat file utk detail penuh):
- **Mode "Nominal"** — perilaku ASLI, sama persis, tidak diubah.
- **Mode "Diskon %"** (baru) — kasir ketik persentase, preview live
  "Diskon mentah: Rp X (Rp Y)" lalu "Hasil dibulatkan: Rp Z" tebal.
  Kontrol: `DropdownButton<int>` kelipatan (100/500/1.000/5.000, key
  `editTotal_multipleDropdown`) & 3 `ChoiceChip` arah (Turun/Terdekat/Naik,
  key `editTotal_dirDown`/`editTotal_dirNearest`/`editTotal_dirUp`).
  Preferensi kelipatan+arah TERAKHIR diingat per-device via
  `SharedPreferences` (`kasir_discount_round_multiple`/
  `kasir_discount_round_direction`, default 500/Terdekat).

Fungsi murni `applyPercentDiscount` + enum `RoundDirection`
(`discount_allocation.dart`) menghitung dari **`_cartTotal` APA ADANYA**
(param `cartTotal`, dipanggil dgn nilai itu bukan `_total` yang mungkin
sudah pernah di-override) — supaya diskon % konsisten & TIDAK menumpuk
kalau dialog dibuka berkali-kali. Hasil di-clamp ke `[0, cartTotal]`
(pembulatan Naik + kelipatan kasar + % kecil secara teori bisa lewati
cartTotal asli tanpa clamp ini). `allocateCartTotal`/`_confirm`/
`_confirmAddItems` **TIDAK disentuh sama sekali** — hasil akhir mode
manapun (Nominal atau Diskon %) tetap masuk lewat `_totalOverride` di
titik keputusan yang persis sama seperti sebelumnya.

**Test baru** (revert-verified — implementasi direvert manual via
`git checkout HEAD --`, dikonfirmasi 5 test widget baru gagal dgn pesan
masuk akal [`Method not found: applyPercentDiscount`/`Undefined name
RoundDirection` utk test DB, `Found 0 widgets with text "Diskon %"` utk
test UI], baru dikembalikan):
`discount_allocation_test.dart` (grup baru `applyPercentDiscount` — 9 test
DB murni: contoh 5% dari 317.000 kelipatan 500 turun/naik/terdekat,
kelipatan lain, `multiple<=1` tanpa pembulatan, percent 0/negatif/>100,
clamp ke `[0,cartTotal]`), `payment_screen_discount_percent_test.dart`
(widget test baru, pola `ProviderContainer` manual + `UncontrolledProviderScope`
sama seperti `payment_screen_buttons_test.dart` — **CATATAN**: seeding
cart via widget lifecycle [`_CartSeeder.build()` yg manggil
`notifier.addItem()`] SEMPAT dicoba dulu tapi Riverpod throw "Tried to
modify a provider while the widget tree was building" secara flaky [lolos
2x, gagal di test ke-3/4] — fix-nya seed cart via `ProviderContainer`
manual SEBELUM `pumpWidget`, BUKAN di dalam `build()` widget manapun. 4
test: mode Nominal regresi tetap jalan, Diskon % 5%/kelipatan500/turun,
kelipatan1000/naik, preferensi kelipatan+arah ke-restore dari
`SharedPreferences` lain kali dialog dibuka).

Full `flutter test` (1690 test) — SEMUA LULUS kecuali 2 yang GAGAL hanya
saat paralel penuh (dikonfirmasi lulus sendirian, bukan regresi dari sesi
ini — pola port-contention yang sama sudah didokumentasikan sesi
sebelumnya): `proposal_unchanged_end_to_end_test.dart` ("Address already
in use" port 8625) dan `laci_meja_proposal_unchanged_end_to_end_test.dart`
(assertion gagal krn interaksi test lain yg buka `AppDatabase` bersamaan —
lulus sendirian). `flutter analyze` bersih (0 issue).

---

_Update sesi 5 September 2026 (sesi kesembilan belas). Versi kerja
**2.40.0+87** (MINOR naik — void transaksi kini terlihat & bisa diberi
alasan, terlihat pengguna). **schemaVersion 38 -> 39** — kolom baru
`Transactions.voidedBy`/`voidReason` (nullable, migrasi aditif via
`_addColumnIfMissing`)._

**Sesi ini (`fd6fa1d`)**: fitur #3 dari 3 fitur besar sesi ini (fitur #1 &
#2 didelegasikan ke agen terpisah, TIDAK disentuh sesi ini — hindari 2 agen
menyentuh migrasi skema `transactions`/dialog void bersamaan). Latar
belakang: owner sempat bertanya kenapa transaksi void "hilang" dari
Laporan — ternyata `voidTransaction()` cuma mengubah `status` jadi
`'void'` (tidak menghapus apa pun), tapi `watchTransactions()` MEMFILTER
status void keluar sebelum sampai ke UI. `transaksi_tab.dart` SUDAH punya
kode styling `isVoid` (badge merah VOID + total dicoret di `_TxTile`) yang
tidak pernah terpicu krn datanya sudah difilter — sisa kode lama.

**Yang berubah**:
- `AppDatabase.watchTransactions()` (app_database.dart) dapat parameter
  `includeVoid` (default `false` — SEMUA pemanggil lain, mis. ekspor,
  TIDAK berubah). `transaksi_tab.dart`'s `_transaksiTabProvider` panggil
  dgn `includeVoid: true` — badge VOID yang sudah ada otomatis "hidup".
- `_showTxDetail` di `transaksi_tab.dart` (dulu sheet ringkasan tipis
  Total/Dibayar/Metode/Waktu/Kasir + tombol Void/Tambah Bayar BESPOKE
  sendiri `_confirmVoid`/`_tambahBayar`) DIGANTI jadi
  `context.push('/kasir/struk/${tx.id}')` — navigasi ke `ReceiptScreen`
  (struk asli lengkap, pola sama `tx_history_sheet.dart`). `ReceiptScreen`
  SUDAH py tombol Batalkan (`_showVoid` -> `showVoidTransactionDialog`
  bersama) & Tambah Bayar (`_showTambahBayar`) terintegrasi, jadi
  `_confirmVoid`/`_tambahBayar`/`_InfoRow`/`_methodLabel` bespoke di
  `transaksi_tab.dart` jadi DEAD CODE — DIHAPUS (diverifikasi tidak ada
  pemanggil lain).
- Kolom baru `Transactions.voidedBy`/`voidReason` (transaction_tables.dart,
  nullable) — `voidTransaction()` dapat parameter opsional `reason`, ditulis
  bareng `voidedBy: kasirId` di companion write yang sama yang menulis
  `status: 'void'`.
- `showVoidTransactionDialog()` (`tx_history_sheet.dart`, dipakai bersama
  riwayat & struk) dapat `TextField` "Alasan (opsional)" di dalam
  `AlertDialog` yang sudah ada; reason diteruskan langsung ke
  `db.voidTransaction(..., reason: ...)` DI DALAM fungsi ini sendiri (bukan
  dikembalikan ke pemanggil).
- `ReceiptScreen` — banner "Transaksi ini telah dibatalkan" (isVoid) kini
  tampilkan baris tambahan "Dibatalkan oleh: `<voidedBy>` · Alasan:
  `<voidReason>`" kalau salah satu terisi (nota void LAMA sebelum kolom
  ini ada -> null keduanya -> baris tambahan tidak tampil sama sekali,
  bukan "null · null").
- **Bug ketemu dari test UI baru sendiri** (bukan pre-existing): dispose
  `reasonCtrl` (`TextEditingController` field alasan) langsung di
  `finally` block `showVoidTransactionDialog` crash
  "TextEditingController used after being disposed" — dialog MASIH dalam
  animasi keluar (pop) saat titik itu tereksekusi, `TextField`-nya masih
  ter-build sebentar selama transisi. Fix: dispose via
  `WidgetsBinding.instance.addPostFrameCallback` (satu frame kemudian),
  bukan langsung. Revert-verified (immediate dispose -> crash reproduce;
  deferred -> hijau).

**Test baru** (semua revert-verified): `migration_v39_test.dart` (migrasi
schema v38->v39, kolom baru nullable, data lama tetap NULL),
`void_reason_test.dart` (DB murni: `voidTransaction` dgn/tanpa `reason`,
`watchTransactions` `includeVoid` true/false),
`transaksi_tab_void_test.dart` (UI: badge VOID + strikethrough tampil, tap
nota void -> `ReceiptScreen` beneran terbuka & item asli + voidedBy/
voidReason tampil — pakai `GoRouter` + `Scaffold` manual, BUKAN
`pumpWithFakeApp`, krn butuh route sungguhan ke `/kasir/struk/:txId`;
WAJIB `SharedPreferences.setMockInitialValues({})` krn `ReceiptScreen._load`
memanggil `SharedPreferences.getInstance()` — tanpa mock, hang selamanya
tanpa error jelas; produk nama tampil via `RichText`/`TextSpan`
[`_productNames[...]` dipakai sbg `text:` span] BUKAN `Text` polos ->
harus `find.textContaining(..., findRichText: true)`, `find.text` biasa
TIDAK menemukannya), `void_dialog_reason_test.dart` (UI: isi alasan di
dialog -> beneran tersimpan ke DB via `pumpWithFakeApp` + `TxHistorySheet`
sungguhan, bukan cuma cek widget dialog-nya doang).

Full `flutter test` (1383 test) — SEMUA LULUS kecuali
`proposal_unchanged_end_to_end_test.dart` yang gagal "Address already in
use" port 8625 (dikonfirmasi flaky KETIKA paralel dgn test LAN-sync lain
di full suite — lulus sendirian, BUKAN regresi, sudah didokumentasikan
sebelumnya juga). `flutter analyze` bersih (0 issue).

**Belum/tidak disentuh** (di luar cakupan brief): fitur #1 & #2 (lihat
paragraf pembuka) — akan dikerjakan agen terpisah setelah sesi ini.

---

_Update sesi 5 September 2026 (sesi kedelapan belas). Versi kerja
**2.39.0+86** (MINOR naik — perubahan tata letak UI yang terlihat pengguna,
bukan bugfix murni), schemaVersion TETAP 38 (tidak ada migrasi disentuh sesi
ini)._

**Sesi ini (`50b6cbe`)**: REVISI DESAIN UI fitur Pra-Bayar yang SUDAH ADA —
logika (`cartPrabayarProvider`/`buildPrabayarCheckout`/dll di
`payment_screen.dart`) TIDAK disentuh, murni tata letak/warna di
`cart_sheet.dart`. Detail lengkap ada di bagian **"UI (`cart_sheet.dart`)"**
di bawah — SUDAH DITIMPA supaya mencerminkan struktur BARU (bukan lagi
banner+header icon lama). Ringkas: banner full-width di atas Total dihapus
→ jadi baris kecil "Pra-Bayar Rp X" (netral) + "Sisa Rp Z"
(merah)/"Kembalian Rp Y" (hijau) di bawah nominal Total, tap tetap buka
daftar entri; tombol Pra-Bayar pindah dari ikon ke-7 di header (yg dulu
bikin overflow 360dp, makanya header dibikin scroll horizontal) ke tombol
sekunder (`IconButton.filledTonal`) di footer, sebelah tombol Bayar yang
tetap dominan. Header sekarang balik ke 6 ikon (tanpa Pra-Bayar) — blok
ikon header MASIH `SingleChildScrollView` horizontal (belum dikembalikan ke
`Row` statis, tidak wajib & berisiko kalau ikon baru ditambah lagi nanti).

**Susulan (permintaan user) setelah fitur Pra-Bayar utama, `076afe9`**:
`_HeldCard` (kartu antrian "Ditahan" di `kasir_screen.dart`) sekarang
menampilkan badge kecil "Pra-Bayar Rp X" langsung di kartu (dibaca dari
`_parseHeldPayload(order.cartJson).prabayar`) — sebelumnya nominal yang
sudah terkunci tidak tampak sama sekali sebelum kartu di-tap & keranjang
dibuka. Disembunyikan total kalau tidak ada entri Pra-Bayar.

**Sesi ini**: fitur besar baru "Pra-Bayar" — kasir bisa mengunci sebagian
pembayaran dari keranjang AKTIF (sebelum checkout beneran), keranjang tetap
100% bisa diedit bebas sesudahnya. Komit `d16c78c`.

**Provider baru**: `lib/features/kasir/cart_prabayar_provider.dart` —
`PrabayarEntry {id, amount, method, methodName, lockedAt}` +
`cartPrabayarProvider` (`StateNotifierProvider.family<CartPrabayarNotifier,
List<PrabayarEntry>, String>`, key = cartId SAMA dgn `cartProvider`/
`cartMetaProvider` — `kMainCartId`/txId tambah belanjaan, walau fitur ini
TIDAK dipakai di mode itu). Persist SharedPreferences prefix
`cartprabayar_v1_<cartId>`, pola identik `CartMetaNotifier` (termasuk
`cleanupOrphanPrabayar()`, dipanggil `main.dart` sejajar
`cleanupOrphanCarts`/`cleanupOrphanMeta`). `notifier.totalLocked` = sum
amount semua entri.

**Titik integrasi checkout (`payment_screen.dart`, BAGIAN PALING SENSITIF)**:
- Fungsi MURNI `buildPrabayarCheckout()` (di top-level file, testable tanpa
  widget) — input: `cartTotal`, `prabayarEntries`, `paidAmountNow` (pilihan
  kasir DI LAYAR INI, 0 kalau `isTempo` atau lockedSum sudah menutup total),
  `isTempo`, metode/nama "sekarang", `now`, `kasirId`, `genId`. Output
  `PrabayarCheckoutResult {combinedPaid, status, combinedChange, payments,
  displayMethodType, displayMethodName}`.
- **Keputusan kunci**: `status` = gabungan (`lockedSum + paidAmountNow`) vs
  `cartTotal` — BUKAN cuma `paidAmountNow` sendirian. `'tempo'` HANYA valid
  kalau `combinedPaid == 0` JUGA (kalau ada Pra-Bayar tapi kasir pilih
  "Bayar Nanti" utk sisanya, itu BUKAN tempo murni lagi — jatuh ke
  `kurang_bayar`/`lunas` sesuai gabungan). Ini SENGAJA diselaraskan dgn
  invariant yang SUDAH ADA di `_reconcileTransactionTotals` (status tempo
  cuma dipertahankan kalau `paid == 0`) — bukan aturan baru, cuma konsisten.
- Tiap entri Pra-Bayar → 1 baris `TransactionPayments`, `paidAt` = `lockedAt`
  ASLI (bukan waktu checkout). Kalau ada `paidAmountNow > 0` → 1 baris
  tambahan `paidAt` = sekarang. `combinedChange` (kelebihan gabungan)
  diatribusikan ke baris "sekarang" kalau ada; kalau TIDAK ada (lockedSum
  sendiri sudah menutup/melebihi total) → ke baris Pra-Bayar PALING
  TERAKHIR (bukan hilang).
- **`lockedSum >= cartTotal`** (`_prabayarCoversTotal` getter): bottom bar
  jadi SATU tombol "Selesaikan Transaksi" (bukan Row Bayar/Bayar Nanti) —
  `_tendered` dipaksa 0, auto lunas + kembalian dari kelebihan lockedSum.
  Kasir TIDAK PERNAH diminta isi keypad/pilih metode di kasus ini.
- `_prabayarEntries` getter mengembalikan `const []` kalau `_isAddMode` —
  fitur ini TIDAK aktif SAMA SEKALI di mode Tambah Belanjaan
  (`_confirmAddItems` tidak disentuh sedikit pun).
- Setelah checkout sukses: `cartPrabayarProvider(_cartId).notifier.clear()`
  sejajar `cartProvider`/`cartMetaProvider`.

**UI (`cart_sheet.dart`) — STRUKTUR SAAT INI (sesi kedelapan belas,
`50b6cbe`)**: tombol "Pra-Bayar" (ikon `lock_clock_outlined`, HANYA
`kMainCartId` + gerbang `terima_pembayaran` via `needsPaymentGateProvider` —
pola sama `canTransfer`) SEKARANG ada di baris FOOTER (bukan header lagi),
`IconButton.filledTonal` sekunder di antara Column "Total" & `Expanded`
tombol Bayar — buka `showDebtPaymentSheet` YANG SUDAH ADA (`remaining` =
total keranjang - totalLocked, clamp 0). Hasil → `PrabayarEntry` baru.
Ringkasan SEKARANG baris kecil (widget `_PrabayarFooterSummary`) DI DALAM
Column footer yang sama dgn "Total"/nominalnya (bukan banner
`primaryContainer` full-width terpisah lagi — itu SUDAH DIHAPUS): baris
"Pra-Bayar Rp X" warna NETRAL (tanpa override color, bukan `scheme.primary`
lagi), lalu SATU baris tambahan KALAU selisih != 0 — "Sisa Rp Z"
(`AppTheme.debtFg`, merah) kalau kurang, atau "Kembalian Rp Y"
(`AppTheme.changeFg`, hijau) kalau lebih; kalau PAS (selisih 0) tidak ada
baris kedua sama sekali. Tap AREA RINGKASAN (bukan "Total"-nya sendiri) →
`InkWell` yg sama membungkus seluruh Column Total, `onTap` cuma aktif kalau
`canPrabayar && prabayarEntries.isNotEmpty` → `_showPrabayarList` (sheet
daftar entri, hapus per-entri, selama belum checkout) — behavior tap ini
TIDAK berubah dari sebelumnya, cuma titiknya pindah.
**Efek samping (masih berlaku dari sesi sebelumnya)**: header sheet
SEBELUMNYA (saat Pra-Bayar masih di header) sempat 7 ikon & overflow di HP
sempit 360dp — fix-nya (blok ikon header pakai
`SingleChildScrollView(scrollDirection: horizontal, reverse: true)`) TETAP
DIPERTAHANKAN walau header sekarang balik ke 6 ikon (Pra-Bayar sudah pindah
ke footer) — tidak dikembalikan ke `Row` statis krn tidak wajib & berisiko
kalau ikon baru ditambah lagi nanti.

**Transfer QR / Tempel Pesanan (`order_parser_service.dart`)**:
`encodeHandoff`/`parse` bawa entri Pra-Bayar MENTAH (`ParsedPrabayarEntry
{amount, method, methodName, lockedAtMs}`) lewat baris meta baru
`Prabayar: <json ringkas [{a,m,n,t}]>`. Service ini SENGAJA TIDAK tahu
gerbang izin (layering core/services vs Riverpod) — `ParsedOrder.prabayar`
cuma data mentah. **Keputusan adopsi** (device penerima harus JUGA
bergerbang `terima_pembayaran`, dicek via `.future` BUKAN sync — pola yg
sama dgn fix mismatch-harga sesi lalu) ada di 2 titik: `kasir_screen.dart.
_handleOrderCode` (baik jalur merge-ke-keranjang-aktif maupun jalur
held_orders — payload dapat key `'prabayar'` baru) DAN
`paste_order_sheet.dart._addToCart`. Device TIDAK bergerbang → entri Pra-
Bayar DIBUANG SEPENUHNYA, barang tetap masuk normal (bukan sebagian).

**Held Orders**: `HeldOrders.cartJson` (`kasir_screen.dart`) dapat key baru
`'prabayar'` — `_holdCurrent`/`_autoHoldCurrentIfAny` menulisnya (dari
`cartPrabayarProvider(_cartId)`, lalu `.clear()` provider aktif — sejalan
`cartProvider`/`cartMetaProvider`), `_parseHeldPayload` mem-parsingnya
(fallback list kosong utk payload lama pra-fitur ini), `_resumeHeld`
me-restore via `.replaceAll(...)`. `cart_sheet.dart` `_holdCurrent`/
`_confirmClear` juga ikut menyertakan/membersihkan (pola sama).

**Test baru** (semua revert-verified — gagal sensible sebelum fix, hijau
sesudahnya): `payment_prabayar_checkout_test.dart` (komposisi murni
`buildPrabayarCheckout` + round-trip `AppDatabase` sungguhan — lockedSum <
total/==/>/interaksi tempo), `order_parser_prabayar_test.dart` (encode/parse
+ JSON baris Prabayar rusak), `kasir_handoff_prabayar_test.dart` (adopsi vs
buang via fake `MobileScannerPlatform` sesuai gerbang penerima),
`kasir_prabayar_hold_resume_test.dart` (hold+resume via UI —
`_askHoldLabel` dialog SENGAJA dihindari di test dgn pre-set customer,
lihat catatan test itu soal TextEditingController dispose race yg tidak
terkait fitur ini), `cart_sheet_prabayar_test.dart` (gate visibility, badge
live, hapus entri, ubah qty → Sisa berubah otomatis — pakai
`find.byType(AddControl)` utk stepper krn lingkaran utamanya menampilkan
ANGKA qty bukan ikon "+" begitu item sudah di keranjang).

Full `flutter test` (1371 test) — SEMUA LULUS (termasuk
`proposal_unchanged_end_to_end_test.dart` yg biasanya flaky paralel).
`flutter analyze` bersih (0 issue).

**Belum/tidak disentuh** (di luar cakupan brief, tidak ada indikasi
diperlukan): tampilan ringkasan Pra-Bayar di kartu `_HeldCard` (antrian) —
datanya SUDAH benar tersimpan/dipulihkan, cuma belum ada badge visual di
kartu sebelum di-resume (kasir baru lihat setelah tap resume & buka
keranjang).

---

_Update sesi 4 September 2026 (sesi keenam belas). Versi kerja
**2.36.0+83** (MINOR naik — badge peringatan baru terlihat pengguna),
schemaVersion TETAP 38 (tidak ada migrasi)._

**Sesi ini**: peringatan mismatch harga transfer transaksi antar device,
komit `b9d57c7`. Transfer Transaksi (`OrderParserService.encodeHandoff`/
`.parse`) mempercayai harga pengirim mentah-mentah (`trustPrices`) tanpa
pernah membandingkannya ke harga fresh lokal penerima — walau `parse()`
sudah SELALU resolve harga itu (variabel `resolved`/`reResolved`) utk
kebutuhan lain, hasilnya dulu dibuang begitu saja kalau flag harga ada.

Implementasi:
- `ParsedOrderItem` (`order_parser_service.dart`) dapat 2 field baru:
  `priceTrustedFromSender` (true kalau flag `p=` ADA di segmen item —
  cuma diisi kode transfer `trustPrices: true`, TIDAK PERNAH katalog HTML
  pelanggan) & `currentResolvedPrice` (harga resolve fresh LOKAL, diisi
  di KEDUA titik construction di `parse()`). `encodeHandoff` TIDAK diubah.
  `toCartItem()` dapat parameter opsional `priceMismatchLocal` (default
  null, tidak breaking call site lama).
- `CartItem` (`cart_item.dart`) dapat field baru `priceMismatchLocal`
  (nullable, EPHEMERAL — tidak pernah ditulis ke tabel manapun, hilang
  saat checkout). Ditambahkan juga ke `copyWith` (pola sentinel `_unset`
  sama seperti `itemNote`/`depositQty`) — TANPA ini, merge duplikat
  scan/qty (`cart_provider.dart` banyak pakai `copyWith(qty:...)`) akan
  diam-diam menghapus field ini tiap kali qty berubah.
- Titik keputusan tampil/tidak (`showMismatch = priceTrustedFromSender &&
  !receiverNeedsGate && price != currentResolvedPrice`) ada di DUA
  tempat: `kasir_screen.dart._handleOrderCode` (cabang `employeeName !=
  null`, baik jalur merge ke keranjang aktif maupun — TIDAK dipasang di
  jalur held_orders krn payload JSON situ tidak menyerap field ephemeral
  ini sama sekali) DAN `paste_order_sheet.dart._addToCart` — sheet ini
  SECARA UMUM dipakai "Tempel Pesanan" pelanggan biasa TAPI tidak
  membedakan kode transfer yang ditempel MANUAL (employeeName terisi),
  jadi logika yang sama wajib diterapkan di sana juga (no-op aman utk
  katalog biasa krn `priceTrustedFromSender` selalu false di jalur itu).
- **Bug ditemukan LEWAT langkah revert-verify** (bukan cuma lolos
  kebetulan): kedua titik di atas awalnya baca `ref.read(
  needsPaymentGateProvider).valueOrNull ?? false` (sync) — provider ini
  `autoDispose` & satu-satunya watcher biasa `_CartMetaTab`, yang TIDAK
  ikut ter-build saat scanner kamera terbuka (build() `KasirScreen`
  ganti total ke layar scanner). Akibatnya provider ke-dispose & reset
  ke `AsyncLoading` PERSIS saat titik ini dieksekusi dari callback scan
  → baca sync selalu jatuh ke default `false` (salah utk pegawai tak
  berizin, harusnya `true`) — BUKAN race jarang, tapi rusak sistematis
  tiap kali scan. Fix: `await ref.read(needsPaymentGateProvider.future)`
  di kedua tempat (dibungkus try/catch, fallback false kalau gagal).
- UI badge (`cart_sheet.dart`) — REUSE pola visual badge `itemNote`
  (border kiri + background tint) tapi warna `scheme.error`, taruh
  TERPISAH di bawah subtotal (bukan inline di baris "unitName · harga"
  yang sudah sesak, risiko overflow HP sempit) — isi `Text.rich` harga
  lokal dicoret (`TextDecoration.lineThrough`) → harga dipakai (tebal).

Test baru: `test/order_parser_service_test.dart` (5 skenario logic murni
`priceTrustedFromSender`/`currentResolvedPrice`, termasuk kasus baris
dobel/gabung qty) + `test/kasir_handoff_price_mismatch_test.dart` (3
skenario widget end-to-end via fake `MobileScannerPlatform`: owner
menerima dari pengirim berwenang dgn harga beda → badge tampil kedua
nominal; harga sama → tidak tampil; penerima pegawai tak berizin →
skip). Semua revert-verified (bug gate provider di atas KETEMU justru
lewat langkah ini). Full `flutter test` (1351 test) — 1 gagal, di
`proposal_unchanged_end_to_end_test.dart` (flaky pra-eksisting
terdokumentasi, port 8625 bentrok saat suite penuh paralel — dikonfirmasi
ULANG lulus 100% sendirian). `flutter analyze` bersih (0 issue).

---

_Update sesi 4 September 2026 (sesi kelima belas). Versi kerja
**2.35.0+82** (MINOR naik — fitur baru terlihat pengguna), schemaVersion
TETAP 38 (tidak ada migrasi)._

**Sesi ini**: tombol baru "Salin Kode Pesanan" di layar Struk
(`receipt_screen.dart`), komit `2f3463c` — mengisi gap: mekanisme kode
`#PSN:...` (`OrderParserService.encodeHandoff`/`.parse`, sudah dipakai
fitur Transfer Transaksi di `cart_sheet.dart`) sebelumnya HANYA bisa
dipicu dari keranjang AKTIF, tidak pernah dari nota LAMA/SUDAH SELESAI.
Sekarang kasir bisa buka nota lama pelanggan langganan, tap tombol ini,
kode pesanan tersalin ke clipboard, lalu "Tempel Pesanan" di kasir untuk
membuat ulang transaksi yang sama persis tanpa input manual satu-satu.

Detail implementasi (`_copyOrderCode` di `receipt_screen.dart`):
- Ikon `Icons.repeat` di AppBar, disembunyikan bila `tx.status == 'void'`
  (nota batal tidak valid jadi basis pesanan baru) — pola sama dgn
  gating tombol "+ Catat" yang sudah ada.
- `List<CartItem>` dibangun dari `_items` (`transaction_items`), qty
  di-NET-kan per `productUnitId` (jumlah semua baris termasuk baris
  retur qty negatif) — item yang net-nya <=0 (sudah diretur PENUH)
  DIHILANGKAN, bukan ikut disalin dgn qty asli yang sudah tidak
  relevan. Semua item net 0 → tombol tetap tampil, SnackBar "Tidak ada
  item untuk disalin" (bukan silent no-op).
- `trustPrices: false` SENGAJA di `encodeHandoff` — harga nota lama bisa
  sudah beda dari harga sekarang, jadi flag harga (`p=`/`o=`/`k=`/`v=`)
  tidak disertakan; sisi `parse()` resolve fresh dari harga TERKINI saat
  ditempel ulang.
- Atribut pre-order (`isPreorder`/`preorderPaid`/`depositQty`) SENGAJA
  tidak dibawa dari nota lama (hasil tempel adalah transaksi baru murni).
  `reservedLocalId` juga null (reservasi nomor nota baru sendiri).
- `customerName`/`customerId` ikut dibawa (dari `_customer`/`tx`) supaya
  pelanggan otomatis terisi di sisi "Tempel Pesanan".
- `employeeName` = `device.deviceName` (device SAAT INI melakukan salin,
  bukan `storeName` — beda konsep). `storeName` diisi supaya blok
  manusiawi "PESANAN — toko / daftar / Total" ikut muncul (memudahkan
  verifikasi visual sebelum ditempel) — Total di blok ini pakai harga
  `priceAtSale`/`originalPrice` nota LAMA sbg estimasi tampilan saja
  (TIDAK ikut terkirim sbg flag mesin krn `trustPrices: false`), jadi
  bisa saja beda dari harga final setelah resolve fresh di sisi
  penerima — cukup utk sekilas cek visual, bukan angka final.
- `OrderParserService`/`encodeHandoff`/`parse` **TIDAK diubah sama
  sekali** — sudah cukup generik, cukup dipanggil dgn parameter yang
  tepat.

Test baru `test/receipt_copy_order_code_test.dart` (harness
`pumpWithFakeApp`) — 4 skenario, semua revert-verified: (1) nota biasa
induk+varian → qty benar, tanpa flag harga, (2) item diretur penuh
dikecualikan (qty net, bukan qty kotor), (3) tombol hilang di nota void,
(4) semua item net 0 → SnackBar "Tidak ada item untuk disalin". Full
`flutter test` (1342 test) — 2 gagal, KEDUANYA di
`proposal_unchanged_end_to_end_test.dart` (flaky pra-eksisting sudah
terdokumentasi, port 8625 bentrok saat suite penuh paralel — dikonfirmasi
ULANG lulus 100% saat dijalankan sendirian). `flutter analyze` bersih (0
issue).

**PLAN.md — status ringkas item yang masih terbuka** (per sesi ini):
Item 47 (ekspor pengeluaran PDF/Excel, disetujui & ditahan), Item 48
(warna avatar pastel, disetujui & ditahan), Item 23 sisa ("kas sistem"
Tutup Kasir diduga overstated, belum dikonfirmasi), Item 41 B.1 (rotasi
kunci toko/cabut akses device — user minta pending; 11 sub-item P3
kerapian kode juga masih terbuka), Item 52 (dugaan bug sync harga
"Rinso cair 500" — user minta pending), Item 54 (arsitektur sync
otomatis & akses luar toko — sengaja ditunda).

**Item 59 — stok pre-order dipotong saat dipenuhi, `cd4cd34`** — bug KRITIS
dari audit sesi sebelumnya (lihat entri sesi kedua belas di bawah utk detail
temuan): pre-order TIDAK PERNAH memotong stok di seluruh siklus hidupnya
(`collectPreorderDeposit` maupun `fulfillPreorderQty`/`fulfillPreorderEntry`
tidak pernah panggil `_appendStock`). **Keputusan user (final)**: stok
dipotong SAAT barang diserahkan (fulfill), BUKAN saat DP dibayar — lebih
akurat scr fisik. Implementasi:
- `fulfillPreorderQty(id, qtyFulfilled)` — potong persis `qtyFulfilled`.
- `fulfillPreorderEntry(id)` (penuhi sisa sekaligus) — potong hanya SISA
  yang BELUM terpotong oleh pemenuhan sebagian sebelumnya (dihitung dari
  `getLaciMejaTakenQty`, pola yang SUDAH dipakai fungsi ini), supaya tidak
  dobel-potong kalau sebelumnya sudah ada `fulfillPreorderQty` parsial.
- Type `stock_ledger` baru `'preorder_fulfill'` (bukan reuse `'sale'`) —
  audit trail lebih jelas: ini realisasi fisik pre-order, bukan checkout
  baru. `referenceId` = id entri pre-order, `note` sebut nama pelanggan.
- TIDAK ada guard stok negatif baru — diverifikasi checkout normal juga
  tidak memblokir stok kurang, jadi konsisten (bukan inkonsistensi baru).
- Kedua fungsi sekarang dibungkus `transaction()` (sebelumnya tidak) —
  ledger event + potongan stok + update `preorderEntries` harus atomik.

**One-time correction pre-order lama yang sudah "Dipenuhi"**: dipilih
opsi **dokumentasi saja** (bukan koreksi otomatis/query bantuan) — stok
yang sudah kadung tidak terpotong SEBELUM fix ini TIDAK dikoreksi otomatis
oleh app (menyentuh angka stok toko tanpa sepengetahuan user itu berisiko,
apalagi kalau owner sudah sempat opname manual sendiri). `PATCHNOTES.md`
sudah eksplisit minta toko yang pernah pakai pre-order lakukan **Stok
Opname manual sekali** utk produk yang pernah "Dipenuhi". Tidak ada
mekanisme app baru utk ini — reuse layar Stok Opname (`reset_stock_screen.
dart`) yang SUDAH ADA, sesuai arahan user.

Test baru `test/preorder_fulfill_stock_deduction_test.dart` (level DB
murni, `AppDatabase(NativeDatabase.memory())`) — 4 skenario, semua
revert-verified: (1) fulfill sekaligus qty penuh, (2) `fulfillPreorderEntry`
sisa penuh, (3) 2x pemenuhan sebagian berturut tidak dobel-hitung, (4)
`fulfillPreorderEntry` SETELAH satu pemenuhan sebagian hanya potong sisa.

---

_Update sesi 3 September 2026 (sesi kedua belas — batch besar 1 instruksi
user, banyak poin). Versi kerja **2.33.10+79**, schemaVersion TETAP 38
(tidak ada migrasi — semua fix sesi ini SENGAJA tidak menambah kolom/tabel
baru, lihat rasional Item 60 di bawah)._

**PLAN.md housekeeping (Item 17/21/28/41.B1/51/53), `1615481`** —
diverifikasi ULANG ke kode langsung (bukan cuma percaya klaim user):
- **Item 17 (persist antrian approval sync) & Item 21 (sync UI global +
  status progres)**: TERKONFIRMASI SELESAI — `lan_sync_service.dart` sudah
  py `sync_upload_queue` persisten + komentar eksplisit "Item 17 Fase 2",
  `sync_state_provider.dart` sudah py `SyncState` global Riverpod + banner
  shell + `dispose()` `sync_screen.dart` TIDAK LAGI mematikan host. Dihapus
  dari PLAN.md.
- **Item 28 (pegawai lanjutkan pesanan owner lintas device)**: user KLAIM
  "sudah selesai" — **TIDAK terbukti**, grep `_isAddMode`/`addToTxId`
  cuma menunjukkan mode "Tambah Belanjaan" SATU device yang sama, TIDAK
  ADA jalur lintas-device sama sekali. **TETAP di PLAN.md, BUTUH
  KLARIFIKASI USER** — item ini belum diimplementasikan sama sekali,
  klaim sebelumnya keliru.
- **Item 41 B.1 (rotasi/un-pair storeKey)**: user klaim "sepertinya
  selesai lewat Alihkan Owner" — **TERBUKTI SALAH**. `pairing_service.dart`
  masih eksplisit "Belum ada mekanisme un-pair/rotasi". "Alihkan Owner"
  itu transfer kepemilikan PENUH toko ke identitas toko BARU (skenario
  ganti kepemilikan total) — BUKAN solusi utk mencabut SATU device (HP
  kasir hilang/pegawai keluar) tanpa mengganti seluruh identitas toko.
  Catatan pembeda diperjelas di PLAN.md, item tetap terbuka.
- **Item 51 & Item 53**: dicoret user eksplisit (keputusan bisnis murni,
  tanpa perlu verifikasi kode) — dihapus dari PLAN.md.

**Item 55 — filter produk Riwayat Transaksi, `eec6890`** — bug pola PERSIS
SAMA dgn fix filter pelanggan sesi sebelumnya (`4a331d1`): `findTxIdsWithProduct`
dipakai menyaring baris SETELAH `LIMIT 1000/100` SQL, bukan sebelum — produk
target bisa tertimbun tanpa muncul kalau rentang tanggal aktif punya >1000
transaksi total. Fix: `WHERE t.id IN (...)` dipindah ke SEBELUM `LIMIT` di
`_txHistoryProvider` (`tx_history_sheet.dart`). Test revert-verified.

**Item 60 — `voidTransaction` cascade Laci Meja, `3ba1143`** — `voidTransaction`
sebelumnya tidak menyentuh 3 tabel Laci Meja (`PreorderEntries`/
`LeftBehindItems`/`BorrowedItems`) walau baris di sana bisa merujuk transaksi
yang di-void; dashboard/pengingat cart bar tetap menampilkan entri itu.
Fix: `PreorderEntries` reuse `cancelledAt`+`cancelPreorderEntry` existing.
`LeftBehindItems`/`BorrowedItems` **SENGAJA TIDAK dapat kolom "batal" baru**
(tanpa migrasi schema) — status "batal" murni disimpulkan lewat JOIN ke
`transactions.status` di `getLaciMejaPending`/`watchLeftBehindItems`/
`watchBorrowedItems`/`watchLaciMejaOpenCount` (mode default; mode riwayat
penuh sengaja TIDAK difilter, nota tetap bukti historis). Event audit
`laci_meja_events` aksi='batal' tetap ditulis utk kedua kategori.

**Investigasi sync-void (diminta EKSPLISIT user) — hasil detail:**
- **(a) `voidTransaction` mencap `updatedAt` transaksi?** SUDAH, sejak
  sebelum sesi ini (bukan bug baru) — diverifikasi langsung di kode &
  ditegaskan lagi via assertion di test sync baru.
- **(b) Event 'batal' baru ikut mekanisme `applied_at` (Item 57)?** TIDAK
  PERLU & TIDAK relevan di sini — mekanisme `applied_at` itu utk PROPOSAL
  client→host (`applyLaciMejaProposals`). Event 'batal' Item 60 ditulis
  LANGSUNG oleh host saat host sendiri yang void (createdAt baru sudah
  cukup lolos filter delta biasa). **TEMUAN PENTING**: event ini justru
  **DIKECUALIKAN TOTAL** dari `dumpSince` host→klien oleh filter
  `excludeVoidTx` yang **SUDAH ADA SEBELUM Item 60** (`73338c8`, sesi
  audit sebelumnya) — baris Laci Meja (termasuk log event-nya) milik
  transaksi yang statusnya void sengaja tidak pernah disebar ke klien.
  Ini BUKAN regresi: audit trail cukup tersimpan di HOST (tempat void
  terjadi), dan status "batal" di dashboard klien tetap benar 100% murni
  dari sync status void transaksi itu sendiri (yang SUDAH benar sejak
  Item 62) — klien tidak perlu tahu event auditnya utk menyembunyikan
  entri dari dashboard, JOIN lokal klien ke `transactions.status` sudah
  cukup begitu baris `transactions` yang void tersinkron.
- **(c) `updated_at` LeftBehindItems/BorrowedItems dicap ulang saat
  voidTransaction menulisnya?** TIDAK ADA yang perlu dicap — desain
  SENGAJA tidak menyentuh baris tabel itu sendiri sama sekali (tidak ada
  kolom yang berubah di sana, cuma baris `laci_meja_events` baru +
  `transactions.status`/`updatedAt` yang berubah). Ini BUKAN kasus gotcha
  CLAUDE.md "lupa cap ulang updated_at" — memang tidak ada apa pun yang
  ditulis ke baris itu.

Test sync end-to-end BARU (`void_transaction_laci_meja_cascade_sync_test.dart`,
2 `AppDatabase` host+klien nyata, pola sama `transaction_updated_at_sync_
test.dart`/`laci_meja_events_applied_at_sync_test.dart`): void nota berisi
2 entri Laci Meja (titip + pinjaman) SETELAH sync pertama → sync ulang →
klien melihat status void nota, KEDUA entri tidak lagi pending (via JOIN),
audit event TIDAK ikut sync (per temuan (b) di atas, dites eksplisit BUKAN
diasumsikan), mode riwayat tetap menampilkan entri. Revert-verified.

**Item 61 — `voidPayment` reverse DP pre-order, `85c5c11`** — `voidPayment`
pada baris DP pre-order (note persis `'DP/jaminan pre-order'`) sebelumnya
membalik nominal `paid` dgn benar TAPI tidak membalik `transactionItems.
priceAtSale`/`subtotal` (tetap di harga asli, seharusnya balik Rp0) maupun
`preorderEntries.paid` (tetap `true`, seharusnya balik `false`) — desync
administratif murni (bukan kehilangan uang). Fix: guard tambahan reverse
eksplisit kebalikan persis `collectPreorderDeposit`. Tidak ada `entryId`
langsung dari pembayaran ke `preorder_entries` — dicocokkan via
`transactionId` + `paid=true` + `updatedAt` terdekat dgn `paidAt`
pembayaran (limitasi diketahui: >1 pre-order dgn DP terpisah dalam SATU
nota bisa salah pilih, kasus jarang). Test revert-verified.

**Test & versi**: `flutter analyze` 0 issue. Full `flutter test` 1332/1333
hijau — SATU gagal (`proposal_unchanged_end_to_end_test.dart`) adalah flaky
PRE-EXISTING yang sudah dikonfirmasi tidak terkait perubahan sesi ini
(kadang lolos, kadang tidak, di run terpisah tanpa perubahan kode apa pun).
PATCHNOTES.md TIDAK diupdate — Item 55/60/61 semua temuan AUDIT sesi
sebelumnya, belum pernah dirasakan/dilaporkan user secara langsung, sesuai
kriteria file (bugfix internal, bukan bug yang pernah user alami).

**Menggantung dari sesi ini**: **Item 28** butuh klarifikasi user (lihat di
atas — klaim "sudah selesai" TIDAK terbukti, TETAP di PLAN.md). Item 41
B.1 (rotasi/un-pair storeKey) masih butuh keputusan desain user. Item 23
sisa, Item 52 (verifikasi kandidat root cause), Item 54 (opsi arsitektur
masa depan) — semua tetap seperti dijelaskan di PLAN.md, tidak disentuh
sesi ini.

---

_Update sesi 3 September 2026 (sesi kesebelas). Versi kerja **2.33.7+76**,
schemaVersion TETAP 38 (tidak ada migrasi — kolom `PreorderEntries.customerId`
sudah ada sejak v35, murni ubah logic query)._

**Item 58 SELESAI (`a3b6235`)** — keputusan user sudah diambil sesi ini
(lihat sesi sebelumnya di bawah, "Item 58 masih menggantung... BELUM
diputuskan user" — sekarang sudah, dieksekusi langsung tanpa tanya ulang
desain). `getOpenPreorderRefsForCustomer` (rujukan baris item struk ke nota
pre-order asal) & `getLaciMejaPending` (pengingat cart bar) sebelumnya
mencocokkan pre-order pelanggan SELALU lewat `PreorderEntries.customerName`
persis, walau kolom `customerId` sudah ada & terisi dari checkout sejak v35
— dua pelanggan TERDAFTAR beda id yang kebetulan namanya sama bisa saling
tertaut pre-order-nya. Fix: kalau pemanggil punya `customerId` (pelanggan
terdaftar) → pencocokan MURNI lewat `customerId`, TIDAK di-OR dengan nama.
Pembeli ad-hoc (`customerId` null) tetap fallback ke `customerName` seperti
sebelumnya — tidak diubah. `receipt_screen.dart` diteruskan `customer?.id`
(variabel lokal yang sudah dimuat di `_load()`, sebelumnya tidak diteruskan
ke query); `payment_screen.dart`/`laci_meja_provider.dart` SUDAH meneruskan
`customerId` ke `getLaciMejaPending` sebelum sesi ini (tinggal ubah logic
internalnya). Test baru `preorder_match_by_customer_id_test.dart` (skenario
PERSIS nama kembar: 2 `customers` beda id nama sama "Budi", masing²
punya pre-order terbuka beda nota — panggil dgn `customerId` A harus cuma
dapat pre-order A) revert-verified. 2 test existing (`laci_meja_marks_and_
reminder_test.dart`, `cart_bar_reminder_lines_test.dart`) diperbarui —
seed `addPreorderEntry` ditambah `customerId` supaya mencerminkan alur
nyata checkout pasca-v35.

PATCHNOTES.md diupdate singkat (satu poin bugfix) — user pernah diberi
tahu risikonya secara eksplisit sesi ini (audit "nama kembar"), meski
belum ada laporan gejala nyata dari pemakaian.

Item 58 sudah dihapus dari `PLAN.md`. Tidak ada item baru menggantung dari
sesi ini.

---

_Update sesi 3 September 2026 (sesi kesepuluh). Versi kerja **2.33.6+75**,
schemaVersion **38** (naik dari 37 — migrasi baru)._

**Item 57 SELESAI (`89cfeaf`)** — keputusan user sudah diambil sesi
sebelumnya (di bawah, "Item 57/58... BELUM diputuskan user" — sekarang sudah).
`laci_meja_events` (log kejadian Laci Meja) tidak punya `updated_at`; delta
`dumpSince` host->klien murni `created_at >= since` (waktu kejadian FISIK,
sengaja tidak boleh diubah). Kalau watermark sync klien lewat `created_at`
event itu SEBELUM owner approve usulannya, event itu tidak pernah lagi lolos
ke sync klien manapun — `locally_modified` klien nyangkut selamanya, event
yang sama diusulkan ulang tiap sync (data aman, tapi payload usulan tumbuh
tak terbatas). Fix: kolom baru `appliedAt` (nullable) dicap host SAAT
`applyLaciMejaProposals` menyetujui (BUKAN `createdAt` yang tetap representasi
waktu kejadian) — dipakai filter delta TAMBAHAN di `dumpSince`
(`created_at >= since OR applied_at >= since`). `mergeRows` klien tidak perlu
sentuhan — tabel ini bukan `appendOnlyTables`, sudah otomatis lewat jalur
generic `INSERT OR REPLACE` yang membawa kolom baru tanpa kode tambahan.
Test end-to-end `laci_meja_events_applied_at_sync_test.dart` (2 `AppDatabase`
nyata host+klien) revert-verified — membuktikan skenario bug asli persis
(klien upload usulan, sync-download SEKALI LAGI sebelum host approve dgn
watermark sudah lewat `created_at`, host baru approve, sync-download ulang
harus tetap membawa event itu balik & mereset `locally_modified`).

PATCHNOTES.md TIDAK diupdate — murni bugfix internal sync (audit temuan
sesi sebelumnya, belum pernah benar-benar dirasakan/dilaporkan user secara
langsung), sesuai kriteria file itu.

Item 57 sudah dihapus dari `PLAN.md`. **Item 58 masih menggantung** (pre-order
cocokkan pelanggan lewat nama, risiko nama kembar) — BELUM diputuskan user,
perubahan perilaku terlihat user, minta persetujuan dulu sebelum eksekusi.

---

_Update sesi 2 September 2026 (sesi kesembilan hari yg sama). Versi kerja
**2.33.5+74**, schemaVersion TETAP 37 (tidak ada migrasi — murni UI)._

**Item 56 SELESAI (`e71d66d`)** — keputusan user sudah diambil (lihat sesi
sebelumnya di bawah, poin "4b" — dulu "BUTUH KEPUTUSAN USER"): "edit tidak
melebihi item produk... untuk penambahan entri produk baru, harusnya lewat
tambah pesanan/barang." Sheet "Ubah pre-order" (`_showLaciMejaEditSheet`
dipanggil dari `_editPreorderEntry`, `receipt_screen.dart`) sekarang terima
param `maxQty` opsional — kalau entri punya `transactionItemId`, qty (dan
jaminan, terikat ke qty YANG BERLAKU setelah cap) dikunci maksimal = qty
baris nota tertaut, DITOLAK dgn pesan jelas (bukan clamp diam-diam) kalau
dilanggar. Entri tanpa `transactionItemId` (lama, atau titip wadah tanpa
beli) TIDAK terpengaruh — tidak ada baris nota utk dibandingkan. 2 kategori
lain (titip/ketinggalan, pinjaman) TIDAK tersentuh, `maxQty` default null di
situ. 4 test widget baru `preorder_edit_max_qty_test.dart`, revert-verified.

Catatan test yang mungkin berguna sesi depan kalau menulis widget test baru
utk sheet ini: tapping 'Batal'/'Simpan' sesudah `tester.enterText` ke field
sheet ini bisa memicu `TextEditingController used after being disposed`
(cascading exceptions) kalau field masih fokus saat sheet ditutup — fix-nya
`FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();`
SEBELUM tap tombol penutup sheet. Bukan bug produksi (tidak terjadi di HP
asli, cuma race kondisi test binding), tapi WAJIB dipasang di test manapun
yg mengetik lalu menutup sheet ini.

Item 56 sudah dihapus dari `PLAN.md`. Item 57/58 (audit sesi sebelumnya,
catatan desain — bukan bug data) masih menggantung, BELUM diputuskan user.

---

_Update sesi 2 September 2026 (sesi kedelapan hari yg sama). Versi kerja
**2.33.4+73**, schemaVersion TETAP 37 (tidak ada migrasi — murni query/UI)._

**3 bug dilaporkan user (2 screenshot nota `A1-20260902-0014`, dibuat
device ASISTEN, dilihat dari HP OWNER) — SEMUA SELESAI (`a724aa8`)**:
1. "Kasir: Owner" padahal pembuat asisten — `receipt_screen.dart` pakai
   `device.deviceName` PENAMPIL. Fix helper `kasirLabel(tx, device)`:
   nama sendiri hanya kalau `tx.kasirId == deviceCode` (atau kosong),
   selain itu kode pembuat ("Kasir: A1"). Nama device lain memang TIDAK
   ada di DB (cuma SharedPreferences) — kalau user ingin NAMA (bukan
   kode), perlu tabel/registry device baru yang ikut sync (belum ada).
2. Label inline "· Titip N" salah kalau 1 nota punya >1 entri pre-order
   produk+satuan sama — `getPreorderDepositForTransaction` keyed
   `product|unit`, entri kedua menimpa. Sekarang keyed
   `transaction_item_id` per baris (fallback `product|unit` DIJUMLAHKAN
   utk entri lama), nilai = jaminan SISA (`sisaDeposit`). **`sisaDeposit`
   sekarang di `lib/core/utils/preorder_calc.dart`** (features file jadi
   re-export); baca peta LEWAT `preorderDepositForLine(marks, item)` —
   dipakai in-app, `_ReceiptPaper`, ESC/POS. ESC/POS TIDAK bisa dites di
   sandbox (`CapabilityProfile.load()` hang) — cek cetak fisik sekali.
3. Kartu riwayat Laci Meja di nota kini render `note` event (ringkasan
   edit "jumlah 1 -> 2, jaminan 1 -> 2" / nominal DP) + suffix kode
   device " · A1" di semua aksi. Review usulan: 'edit' -> "Diubah".

**Audit "deep debug laci meja/pre-order + sync" — hasil per poin**:
- 4a (agregasi jaminan/qty): dashboard `depositByProduct`/`_preorderTile`,
  laporan salin, kuota `preorderIdsBeyondQuota`, label inline (baru)
  SEMUA pakai sisa. Yang MENTAH & sengaja (deskripsi pesanan, sisa di
  baris terpisah): headline kartu nota, subtitle Riwayat, pengingat cart
  bar `getLaciMejaPending` — dicatat di PLAN Item 58, tidak diubah.
- 4b: edit qty entri TIDAK menyentuh baris nota; DP ditagih dari qty
  BARIS NOTA (`collectPreorderDeposit`). Bukan bug hitung, tapi jebakan
  alur — PLAN Item 56, BUTUH KEPUTUSAN USER (rekomendasi: peringatan di
  sheet edit).
- 4c-i (BUG NYATA, DIPERBAIKI): `applyLaciMejaProposals` INSERT OR
  REPLACE bisa membuka kembali entri yang sudah ditutup host (owner
  memenuhi sebelum approve usulan edit klien). `filterUnchanged...`
  TIDAK melindungi. Guard: `fulfilled_at`/`cancelled_at`/`collected_at`/
  `fully_returned_at` host dipertahankan kalau usulan null, `qty_returned`
  ambil terbesar. Test `apply_laci_meja_proposals_keep_closed_test.dart`.
  Catatan desain tersisa: approve = terima SELURUH versi klien utk kolom
  lain (qty/jaminan/nama/catatan) walau owner mengedit host lebih baru —
  inheren pada model "usulan"; layar review menampilkan nilai usulan.
- 4c-ii: id event `'$entryId-$micros'` — apply INSERT OR REPLACE by id,
  mergeRows INSERT OR IGNORE: usulan sama diterapkan 2x TIDAK dobel. Aman.
- 4c-iii: event klien `locally_modified` TIDAK PERNAH reset (tidak ada
  `updated_at`, delta by `created_at` tidak menjangkau event lama) —
  dikirim ulang tiap sync selamanya, dibuang host via `filterUnchanged`.
  Data aman, payload tumbuh — PLAN Item 57 (catatan desain).
- 4c-iv: pre-order cocokkan pelanggan lewat NAMA saja (`customerId` ada
  tapi tidak dipakai) — risiko nama kembar, PLAN Item 58, butuh
  persetujuan user sebelum diubah.
- Dikonfirmasi ulang: `addPreorderEntry` selalu baris UUID baru; hanya
  `editPreorderEntry` manual yang mengubah qty/jaminan; fulfilment nota
  lain tidak bisa menyentuh entri nota ini.

**Test**: 4 file baru (14 test), semua revert-verified dgn pesan gagal
bermakna. Full `flutter test` 1320 lolos, 1 gagal FLAKY
(`proposal_unchanged_end_to_end_test.dart`, "Address already in use,
port 8625" — dua test HTTP loopback berebut port saat paralel; lolos
saat dijalankan sendiri). `flutter analyze` 0 issue.

---

_Update sesi 2 September 2026 (sesi ketujuh hari yg sama). Versi kerja
**2.33.3+72**, schemaVersion TETAP 37 (tidak ada migrasi — murni query)._

**Bug dilaporkan user — SELESAI**: "Riwayat Transaksi" (`tx_history_sheet.
dart`) — cari SATU PELANGGAN (search box) TANPA filter tanggal dulu ("dari
awal"/lihat keseluruhan), lalu persempit ke BULAN TERTENTU -> bulan itu tidak
muncul sama sekali walau transaksinya ada. Diinvestigasi mendalam dgn 2 test
widget nyata (`AppDatabase` sungguhan, bukan mock) sebelum menyimpulkan akar
masalah — hipotesis PERTAMA (limit 1000 tanpa filter tanggal aktif krn search
aktif, LALU tetap salah setelah tanggal dipersempit) **TERBUKTI SALAH** lewat
test nyata: begitu tanggal dipersempit, query SQL baru re-run bersih & benar
(`test/tx_history_customer_search_no_date_test.dart`, awalnya ditulis sbg
repro, ternyata PASS bahkan SEBELUM fix). Akar masalah SEBENARNYA ketemu di
variasi lain: teks search (nama pelanggan/no. transaksi) difilter
CLIENT-SIDE **setelah** SQL `LIMIT 1000`/`100` diterapkan — kalau rentang
tanggal yg dipilih (bulan tertentu) SENDIRI sudah punya >1000 transaksi dari
SEMUA pelanggan (toko cukup ramai), transaksi pelanggan target yang lebih
"tua" di dalam rentang itu tertindih transaksi pelanggan LAIN yang lebih
baru SEBELUM sempat difilter namanya — sama sekali tidak muncul. Dibuktikan
GAGAL dulu (revert-verified) via
`test/tx_history_busy_month_search_limit_test.dart`. Fix: filter nama
pelanggan/no. transaksi dipindah jadi bagian SQL `WHERE` (LEFT JOIN ke
`customers` utk pelanggan terdaftar + cek `customerName` snapshot + `localId`
langsung di query, field baru `_HistoryQuery.search`) — sama pola dgn kenapa
`getCustomerTransactions` (statistik pelanggan) tidak pernah kena bug ini
(SUDAH `WHERE customer_id = ?` di SQL). Filter produk (`_HistoryQuery.
product`) punya POLA BUG YANG SAMA (`productTxIds` difilter SETELAH limit
juga) — **BELUM diperbaiki di sesi ini** (di luar lingkup laporan user, yg
spesifik soal pelanggan+tanggal) — dicatat di PLAN.md sbg follow-up.

**Pekerjaan 1 (PRIORITAS, bug finansial/administrasi serius) — SELESAI**:
tabel `transactions` tidak punya `updated_at` sama sekali, `dumpSince`
memperlakukannya append-only murni (`created_at >= since`), `mergeRows`
SKIP baris yang PK-nya sudah ada. Begitu nota sudah pernah tersinkron
sekali, perubahan SETELAH itu ke baris `transactions` itu sendiri (status
void, ganti pelanggan, poin loyalitas) tidak pernah terkirim lagi ke device
lain. Fix: kolom `updatedAt` nullable baru (migrasi v36→v37), dicap ulang
eksplisit di SEMUA titik `update(transactions)` yang genuinely butuh
propagasi lintas-device — `voidTransaction`, `changeTransactionCustomer`
(2 titik), `awardLoyaltyPointsIfEligible`, `_reconcileTransactionTotals`,
`addPaymentToTransaction`, `settleMergedDebt`, 2 titik "lunas setelah
retur/edit item". **`checkedItemIds` SENGAJA TIDAK dicap** — field itu
sendiri sudah terdokumentasi "murni per-perangkat, tidak ikut sync" (sama
seperti `changeTaken`) — kalau ke depan ada yang ingin field itu ikut sync,
itu perubahan desain baru, bukan bagian dari fix ini. `dumpSince` dapat
case khusus `'transactions'` (`OR updated_at >= since`). `mergeRows` dapat
case khusus: baris `transactions` yang PK-nya sudah ada di-UPDATE
(last-write-wins by `updated_at`, kolom status/customer_id/customer_name/
points_earned) alih-alih di-skip total. Test `transaction_updated_at_sync_
test.dart` (DB nyata, `dumpSince`+`mergeRows` host→klien: void & ganti nama
pelanggan setelah sync pertama) — revert-verified. **Konsekuensi rutin**:
17 file `migration_vX_test.dart` yang hardcode `schemaVersion=36` diupdate
ke 37 (pola SELALU terjadi tiap migrasi baru — cek ini lebih dulu kalau
migration test tiba-tiba merah tanpa perubahan logic terkait).

**Pekerjaan 2 — SELESAI**: `buildPreorderReportText` (`preorder_report.
dart`) memakai `depositQty` MENTAH utk "N jaminan" — tidak berkurang
seiring pre-order dipenuhi sebagian, beda dari dashboard yang sudah benar
(`sisaDeposit = depositQty - taken`, 1:1 dgn qty diambil). Komentar lama di
file itu yang mengklaim ini "keputusan disetujui user" **SALAH** — itu
kebetulan dari contoh dummy sesi sebelumnya yang tidak menunjukkan kasus
dipenuhi sebagian, bukan keputusan desain user sungguhan. Fix: logic
`sisaDeposit` diekstrak ke `lib/features/laci_meja/preorder_calc.dart`,
dipakai BERSAMA oleh dashboard (`_preorderTile`, `depositByProduct` di
`laci_meja_dashboard_screen.dart`) dan laporan salin-teks — **kalau ke
depan mengubah rumus jaminan sisa, cukup ubah di SATU tempat itu**. Audit
tambahan diminta user (bandingkan `preorder_report.dart` vs dashboard satu
per satu) — semua SUDAH diverifikasi konsisten, tidak ada perbedaan lain
selain jaminan: `sisaOf` (qty, bukan deposit) sudah sama; status Tempo/
Lunas sama-sama pakai `e.paid`; resolusi nama pelanggan (live via
`laciMejaCustomerNamesProvider` keyed `transactionId`, fallback ke salinan
beku, lalu "Umum") sama persis; cakupan filter sama-sama dari
`watchPreorderEntries()` default (`includeClosed=false`, hanya entri
terbuka); urutan FIFO sama-sama `orderBy created_at asc` di level query DB.
`preorder_report_test.dart` diperbarui (2 contoh "disetujui user" lama
sekarang salah — recompute manual dgn `sisaDeposit`, revert-verified).

---

_Update sesi 2 September 2026 (sesi kelima hari yg sama, dikerjakan via agen
background PARALEL dgn agen lain di branch yg sama — session ini ADALAH
sesi "tombol salin laporan pre-order" yg berlanjut mengerjakan tugas UI
susulan dari coordinator di tengah sesi yg sama; sesi "reorder metode
pembayaran" di blok bawah adalah agen LAIN yg berjalan paralel & sempat
push+merge duluan — REBASE manual dilakukan saat commit, lihat catatan
"⚠️ konflik multi-agen" di bawah). Tugas "expandable search + dropdown
filter produk" (2 layar Laci Meja) SUDAH DISELESAIKAN. Versi kerja
**2.33.1+70**, schemaVersion TETAP 36 (tidak ada migrasi — murni UI)._

**Diimplementasikan (`952382f`)**: 2 widget reusable baru di
`lib/features/laci_meja/`:
- `LaciMejaExpandableSearch` (`laci_meja_expandable_search.dart`) — field
  cari collapsed (ikon)/expanded (TextField penuh), PERILAKU (bukan
  implementasi teknis — lihat komentar di file) direplikasi dari
  `_KasirTopbar` yg sudah ada di `kasir_screen.dart`. Controlled component:
  status `expanded` dipegang PEMANGGIL (StateProvider di dashboard, field
  `State` biasa di Riwayat — SENGAJA beda krn dashboard sudah pakai
  Riverpod utk state serupa, Riwayat sudah `ConsumerStatefulWidget` dgn
  field lokal — konsisten dgn pola tiap layar, bukan dipaksa seragam).
  Dipakai ULANG di 2 layar (dashboard tab Pre-order + Riwayat), TIDAK
  diduplikasi.
- `ProductPickerDropdown` (`product_picker_dropdown.dart`) — diekstrak dari
  `_ProductPickerChip`/`_ProductPickerMenuRow` yg SUDAH ADA (dulu cuma
  dipakai pemilih jaminan) jadi widget publik reusable, dipakai skrg di 3
  tempat: pemilih jaminan dashboard (badge "N jaminan"), filter produk
  dashboard (badge "maks N" dari kuota, plus opsi "Semua Produk"), filter
  produk tab Pre-order Riwayat (tanpa badge, plus opsi "Semua Produk").
  MENGGANTIKAN TOTAL baris chip `ChoiceChip` horizontal yg dulu dipakai
  filter produk (permintaan user eksplisit: satu pola dropdown, bukan
  gaya beda-beda per tempat).

**Bug ditemukan & diperbaiki (BUKAN dari task asli, ketemu sendiri via
widget test)**: `PopupMenuButton<T>` Flutter menganggap hasil rute `null`
sbg "dibatalkan" (`onCanceled`, bukan `onSelected`) — opsi "Semua Produk"
yg tadinya `PopupMenuItem<String?>(value: null)` TIDAK PERNAH terpilih.
Fix: sentinel string `_allSentinel` dipetakan balik ke `null` sebelum
diteruskan ke `onSelected` milik pemanggil. **Kalau ke depan ada widget
lain yg butuh PopupMenuButton dgn opsi "kosongkan pilihan"/null, JANGAN
pasang `value: null` langsung — pakai pola sentinel yg sama.**

**Filter tanggal Riwayat** DICEK sesuai instruksi tugas — SUDAH satu
chip/tombol tunggal sejak awal dibuat (tap buka date-range picker, tombol
hapus muncul saat aktif). TIDAK diubah, dikonfirmasi sudah sesuai.

**Test**: 18 test baru/diperbarui — `laci_meja_expandable_search_test.dart`
& `product_picker_dropdown_test.dart` (widget test MURNI, tanpa DB/router,
utk 2 widget baru) + 3 file test existing (`laci_meja_dashboard_grouping_
test.dart`, `preorder_quota_line_test.dart`, `laci_meja_partial_and_log_
test.dart`) diperbaiki krn reference widget lama (`ChoiceChip`,
`_ProductPickerChip`, `TextField` full-width) yg sudah tidak ada — SEMUA
revert-verified. **Ditemukan saat debug**: `PopupMenuButton` butuh DUA
`pump(300ms)` (bukan satu) sebelum tap ke item menu-nya di widget test —
satu pump belum genap menyelesaikan animasi masuk `_kMenuDuration` (300ms),
tap ke koordinat menu yg masih mid-animasi bisa meleset (dikonfirmasi via
debug `RenderBox.localToGlobal`, BUKAN bug UI sungguhan — begitu animasi
selesai, posisi menu selalu tepat sejajar tombol, tidak pernah render di
luar layar). `flutter analyze` bersih. Seluruh `flutter test` (1303 test)
lolos TERMASUK `proposal_unchanged_end_to_end_test.dart` (flaky
pre-existing, kebetulan hijau di run ini).

**⚠️ Konflik multi-agen (info penting utk sesi berikutnya)**: sesi ini
berjalan PARALEL dgn agen lain (worktree terpisah) yg mengerjakan "reorder
metode pembayaran" di BRANCH YANG SAMA. Agen itu push+merge LEBIH DULU
(`326e39d`+`1599f90`, versi 2.33.0+69) SAAT sesi ini masih bekerja — akibatnya
index/HEAD lokal sesi ini sempat DESYNC (working tree commit lama, HEAD
sudah maju krn shared git dir), yg KALAU LANGSUNG commit akan MEREVERT
pekerjaan agen lain itu tanpa sengaja. Ditangani manual: `git checkout
HEAD -- <file-file tak terkait>` utk file yg BUKAN bagian tugas sesi ini,
`git reset HEAD --` utk unstage index basi, versi di-rebase ke baseline
HEAD terkini (2.33.0+69 → 2.33.1+70, BUKAN 2.32.0+68 → 2.32.1+69 spt
rencana awal) SEBELUM commit. **Pelajaran utk sesi mendatang yg jalan
paralel di branch sama**: SELALU `git status`+`git log --oneline -5`
dulu SESAAT SEBELUM commit (bukan cuma di awal sesi) — HEAD bisa sudah
maju di tengah jalan tanpa sesi ini melakukan apa pun.

**Tidak ada item pending dari tugas UI sesi ini.**

---

_Update sesi 2 September 2026 (sesi keempat hari yg sama, dikerjakan via agen
background, PARALEL dgn agen lain di branch yg sama — cek konflik saat
push/merge) — tugas "reorder metode pembayaran" (owner minta bisa ubah
urutan metode bayar) SUDAH DISELESAIKAN. Versi kerja **2.33.0+69**,
schemaVersion TETAP 36 (tidak ada migrasi baru — kolom `sortOrder` di
`PaymentMethods` SUDAH ADA sebelumnya, tinggal ditambah UI)._

**Diimplementasikan (`326e39d`)**: `PaymentMethodsScreen` (`lib/features/
pengaturan/payment_methods_screen.dart`) diganti dari `ListView.separated`
jadi `ReorderableListView.builder` — drag-handle IKON TERPISAH (`Icons.
drag_handle` + `ReorderableDragStartListener`), BUKAN seluruh baris, supaya
tidak bentrok dgn gestur swipe-to-delete `Dismissible` yang sudah ada di tile
yang sama. `onReorder` tulis ulang `sortOrder` via helper baru `AppDatabase.
reorderPaymentMethods` (`lib/core/database/app_database.dart`, transaksi,
pola identik `reorderProductGroups` Item 54 kategori Kasir). "Tunai" TIDAK
diberi posisi khusus/terkunci — diputuskan sendiri (tidak ada indikasi di
kode/komentar lama yang mewajibkan ia selalu pertama), bebas direorder spt
metode lain.

**Audit query `paymentMethods`** (diminta eksplisit di tugas) — 2 tempat
BELUM `orderBy(sortOrder)` ditemukan & diperbaiki: `_activeQrisMethod`
(`receipt_screen.dart`) & `_activeQrisMethodForPreview` (`cart_sheet.dart`,
sekaligus butuh import `drift` baru karena file itu sebelumnya tidak
mengimpornya). Tempat lain (payment_screen, debt_payment_sheet, layar
Pengaturan sendiri) SUDAH orderBy sebelumnya — tidak disentuh. Sekalian fix
bug laten: metode pembayaran baru yang ditambah manual via sheet tambah
SEBELUMNYA selalu insert `sortOrder` default 0 (tie dgn baris lain → urutan
tak konsisten setelah >1 metode ditambah) — helper baru `AppDatabase.
paymentMethodsMaxSortOrder` dipakai supaya metode baru selalu masuk ke
posisi PALING BAWAH.

**Test**: 3 test baru — `test/payment_methods_reorder_db_test.dart` (2 test
DB murni: `reorderPaymentMethods` menulis ulang sortOrder & query lain ikut
terurut; `paymentMethodsMaxSortOrder`), `test/
payment_methods_screen_reorder_test.dart` (1 widget test drag-handle,
`tester.startGesture`/`moveBy` step-kecil, pola sama `produk_form_
reorder_alt_price_test.dart`) — SEMUA revert-verified (fix di-stash
sementara, terbukti gagal dgn pesan masuk akal — compile error method belum
ada / 0 drag-handle ditemukan — baru dikembalikan). `flutter analyze`
bersih. Seluruh `flutter test` (1289 test) lolos kecuali
`proposal_unchanged_end_to_end_test.dart` (flaky pre-existing, TIDAK terkait
perubahan sesi ini).

**Tidak ada item pending dari tugas ini.** PLAN.md tidak disentuh (tugas ini
datang langsung dari user, bukan dari item PLAN.md).

---

_Update sesi 2 September 2026 (lanjutan, sesi ketiga hari yg sama, dikerjakan
via agen background) — item pending "tombol copy laporan pre-order" (lihat
blok sesi sebelumnya di bawah) SUDAH DISELESAIKAN, plus 1 tugas susulan yg
disisipkan coordinator di tengah sesi. Versi kerja **2.32.0+68**,
schemaVersion TETAP 36 (tidak ada migrasi baru)._

**Tugas 1 (DIIMPLEMENTASIKAN, `2e6bd69`) — tombol "Salin Laporan" pre-order**:
format teks (Format A satu-produk / Format B multi-produk) SUDAH DISETUJUI
user lewat draft sesi sebelumnya (lihat blok lama di bawah utk isi draftnya),
tidak didesain ulang. Logic murni ada di `lib/features/laci_meja/
preorder_report.dart` (`buildPreorderReportText`), dipanggil dari tombol
ikon baru "Salin Laporan" (`_PreorderStatsLine`, sebelah tombol Kuota) di
`laci_meja_dashboard_screen.dart` → `Clipboard.setData` + SnackBar.

**Keputusan yang diambil sendiri saat implementasi (spek user ada
ambiguitas/kontradiksi kecil dgn kode nyata — sesi berjalan otomatis di
background, diputuskan sendiri, dicatat di sini + komentar kode
`preorder_report.dart`)**:
- **Status Tempo/Lunas**: spek awal minta ambil dari `transactions.status`
  via `transactionId`. Ternyata dashboard nyata (`_preorderTile`) SUDAH
  PAKAI `e.paid` (field yg SENGAJA diperbaiki dari bug lama yg salah pakai
  `depositQty > 0`, lihat komentar existing di `laci_meja_dashboard_screen.
  dart` baris ~1030). Diputuskan REUSE `e.paid` (bukan query baru ke
  `transactions.status`) — sesuai prinsip CLAUDE.md "reuse logic yg sudah
  teruji, jangan hitung ulang dari sumber lain". Guard "sembunyikan kalau
  `transactionId` null" dari spek awal TETAP dipakai (kasus titip wadah
  tanpa nota rujukan — `e.paid` tidak bermakna di situ).
- **"N jaminan" per-entri & total header pakai `depositQty` MENTAH**, BUKAN
  versi "sisa" (dikurangi asumsi konsumsi 1:1 dgn qty yg sudah diambil) yg
  dipakai `_preorderTile` dashboard. Contoh yg disetujui user eksplisit:
  entri "Dipenuhi 2 dari 5" tetap tampil "5 jaminan" (bukan "3"). Beda
  metrik dari "Sisa" per-entri yg memang menampilkan sisa qty.
- **Header grup `=== Produk (...) ===` di Format B**: token qty/jaminan
  agregat HANYA muncul kalau grup itu >1 entri (contoh disetujui user:
  grup 1-entri "Beras 25kg (1 pesanan)" TANPA angka qty/jaminan sama
  sekali) — disimpulkan dari pola contoh, tidak dinyatakan eksplisit di
  prosa spek.
- **Nama pelanggan ad-hoc** (`customerId` null) diberi akhiran " (Umum)"
  supaya laporan teks (tanpa ikon pembeda spt dashboard) tetap bisa
  membedakan terdaftar vs ad-hoc — kecuali kalau namanya sendiri sudah
  "Umum" (tidak jadi "Umum (Umum)").
- **"N hari lalu" pakai selisih HARI KALENDER**, bukan `Duration.inDays`
  literal — lihat Tugas 2 di bawah (ditemukan SAAT verifikasi manual
  terhadap contoh yg disetujui user: Siti 30/08 16:40 vs "Dicetak" 02/09
  14:35 harus "3 hari lalu", tapi `inDays` mentah cuma kasih 2).

Cakupan laporan mengikuti **filter produk** dashboard (bukan kata kunci
pencarian) — sesuai spek eksplisit.

**Tugas 2 (DIIMPLEMENTASIKAN, sama commit `2e6bd69`) — susulan coordinator
di tengah sesi**: SEMUA perhitungan "N hari lalu" fitur Laci Meja (yg
sebelumnya 3 salinan logic berbeda: `_daysSince` di
`laci_meja_dashboard_screen.dart`, inline di `riwayat_laci_meja_screen.
dart`, dan yg baru ditulis di `preorder_report.dart`) disatukan jadi SATU
helper `calendarDaysSince` di file baru `lib/features/laci_meja/
laci_meja_date_utils.dart`. Bug yg diperbaiki: versi lama pakai
`DateTime.now().difference(x).inDays` — selisih LITERAL 24 jam, salah utk
kasus lewat tengah malam (entri kemarin 23:50, dilihat hari ini 00:10 →
harusnya "1 hari lalu", `inDays` mentah bilang "0"). Fix: normalisasi
kedua tanggal ke tengah malam (buang jam/menit/detik) SEBELUM
diselisihkan. `laci_meja_reminder.dart` DICEK juga (disebut coordinator)
tapi TIDAK menghitung hari sendiri — cuma menyebut konsep di komentar,
tidak ada perubahan di file itu.

**Test**: 18 test baru (14 kasus `buildPreorderReportText` di
`preorder_report_test.dart`, 1 widget test tombol di
`preorder_report_copy_button_test.dart`, 4 kasus `calendarDaysSince` di
`laci_meja_calendar_days_test.dart` termasuk kasus lewat-tengah-malam
eksplisit) — SEMUA revert-verified (logic sengaja dirusak dulu, terbukti
gagal dgn pesan masuk akal, baru dikembalikan). `flutter analyze` bersih.
Seluruh `flutter test` (1285 test) lolos kecuali
`proposal_unchanged_end_to_end_test.dart` (flaky pre-existing, TIDAK
terkait perubahan sesi ini — sudah dikonfirmasi sebelumnya juga flaky
tanpa perubahan apa pun).

**Tidak ada item menggantung baru dari sesi ini.**

---

_Update sesi 2 September 2026 (lanjutan, sesi kedua hari yg sama) —
2 tugas terpisah dikerjakan berurutan sesuai instruksi user via agen
background. Versi kerja **2.31.0+67**, schemaVersion TETAP 36 (tidak
ada migrasi baru sesi ini)._

**Tugas 1 (draft, TIDAK ada kode ditulis, SESUAI permintaan eksplisit
user)**: format teks laporan copy pre-order (item pending #1 sesi
sebelumnya) — 3 alternatif draft (A ringkas per-pelanggan, B
dikelompokkan per-produk utk kasus filter "semua produk", C paling
ringkas/mode kirim-cepat) ditulis di
`/tmp/claude-0/-home-user-The-POS/fa93a3de-572e-5f25-9ccc-a6f3364b3c34/scratchpad/draft_copy_laporan_preorder.md`
DAN dikutip penuh di laporan akhir sesi ke user (chat, bukan file
repo) — user (via agen pemanggil) yang akan mereview & memilih.
**TETAP MENGGANTUNG**: fitur copy-nya sendiri (tombol + logic clipboard)
BELUM diimplementasikan sama sekali — nunggu user pilih salah satu
draft (atau minta variasi lain) dulu.

**Tugas 2 (DIIMPLEMENTASIKAN, `302167e`)**: layar `RiwayatLaciMejaScreen`
baru (`lib/features/laci_meja/riwayat_laci_meja_screen.dart`), route
`/kasir/laci-meja/riwayat`. Ini MENGGANTIKAN TOTAL toggle inline "Riwayat"
lama di dashboard (`_showLogProvider`/`_buildEventLog`, log gabungan 3
kategori tanpa pemisah/pencarian/filter — SUDAH DIHAPUS dari
`laci_meja_dashboard_screen.dart`, ikon "Riwayat" di app bar sekarang
`context.push` ke route baru). Detail lihat entri CHANGELOG `302167e`.
**Keputusan desain yg diambil sendiri (tidak ada preseden eksak, tidak
bisa tanya balik — sesi berjalan otomatis di background)**:
- TIDAK ada query DB baru — param `includeCollected`/
  `includeFullyReturned`/`includeClosed` di `AppDatabase.
  watchLeftBehindItems`/`watchBorrowedItems`/`watchPreorderEntries`
  TERNYATA SUDAH ADA sejak lama (sudah tertes di `laci_meja_db_test.
  dart`) tapi belum pernah dipakai UI manapun — cukup pasang provider
  baru yg memanggilnya dgn `includeX: true` + filter cari/tanggal/
  produk di sisi Dart (pola sama persis `_buildPreorderList` dashboard
  yg sudah lebih dulu begini).
- Search+filter tanggal SATU set kontrol di atas TabBarView (bukan
  per-tab terpisah) — brief user tidak spesifik per-tab/global, satu
  set lebih sederhana & cukup jelas krn filternya cuma berlaku ke tab
  yg sedang aktif.
- Chip filter produk (tab Pre-order) TIDAK bawa info kuota (beda dari
  `_PreorderProductFilter` dashboard yg tampilkan "maks N") — kuota
  cuma relevan utk antrian AKTIF, tidak relevan di arsip riwayat.
- Kartu riwayat (`_RiwayatCard`) SENGAJA lebih flat/tanpa grouping
  per-nota (beda dari kartu dashboard `_buildLeftBehindList` dkk. yg
  mengelompokkan per transaksi) — riwayat mencampur entri terbuka+
  selesai, grouping per-nota jadi kurang relevan drpd melihat status
  tiap baris langsung.
- Test lama grup "Layar Riwayat (poin 5)" di
  `test/laci_meja_partial_and_log_test.dart` DITULIS ULANG total (bukan
  ditambah di sebelah test lama) krn perilaku lama (toggle inline)
  SUDAH TIDAK ADA lagi — 9 test baru, semua revert-verified (screen
  disingkirkan sementara -> compile error -> bukti test genuinely
  bergantung ke fitur -> dikembalikan -> hijau).

**Item pending SISA dari sesi sebelumnya**:
- Pertanyaan self-hosting sudah DIJAWAB tuntas di chat sesi sebelumnya
  (diskusi, bukan komitmen fitur) — tidak ada tindak lanjut kode yg
  diperlukan, dihapus dari daftar pending.

---

_Update sesi 2 September 2026 — fitur "kumpulkan DP/jaminan pre-order"
diimplementasikan (gap yang dicatat sesi sebelumnya sbg "belum
ditindaklanjuti", user approve eksplisit). Versi kerja **2.30.0+66**,
schemaVersion **35→36**. Ada 3 permintaan susulan BARU dari user
(copy laporan pre-order, riwayat Laci Meja dgn search/filter, tanya
self-hosting) yang MASIH MENGGANTUNG — lihat bawah._

**Fitur baru** (`d579c86`): pre-order dgn DP/jaminan terkunci Rp 0 saat
checkout sekarang BISA ditagih begitu dipenuhi, walau nota sudah
"Lunas" utk item lain. Skema v36 nambah `PreorderEntries.
transactionItemId` (tautan presisi ke baris nota, diisi
`payment_screen.dart` saat checkout) — dipakai
`getPreorderDepositOwed`/`collectPreorderDeposit` (app_database.dart)
yang REUSE `_reconcileTransactionTotals` (mekanisme sama yg dipakai
"Tambah Belanjaan" utk buka-lagi status lunas) + `addPaymentToTransaction`
(muncul di Riwayat Pembayaran) + `recordLaciMejaEvent(aksi:'bayar')`
(muncul di kartu riwayat pre-order struk & layar review usulan sync).
Tombol "Penuhi" di dashboard Laci Meja (`laci_meja_dashboard_screen.
dart`) otomatis menawarkan `showDebtPaymentSheet` kalau ada DP
tertunda. **Kenapa TIDAK reuse `editPaidTransactionItem`**: method itu
SENGAJA menolak semua kenaikan nilai (`if (newSubtotal > item.subtotal)
return`) — constraint benar utk edit manual biasa, tapi menutup jalur
ini; makanya dibuatkan method DB baru yang sengaja bypass constraint
itu utk SATU kasus legitimate ini saja.

**Ripple wajib skemaVersion naik (pola sudah didokumentasikan di sesi²
lalu, terulang lagi)**: 17 file `test/migration_vX_test.dart` hardcode
`expect(ver.data.values.first, 35)` — semua diupdate ke `36`. **Kalau
nambah migrasi lagi nanti, WAJIB grep
`expect(ver.data.values.first,` di seluruh `test/` dulu sebelum
menganggap full suite akan hijau.**

**MENGGANGGUNG — 3 permintaan baru dari user, belum satupun dieksekusi**:
1. **Tombol copy laporan pre-order** (di halaman/kartu Laci Meja
   pre-order) — copy ke clipboard laporan ringkas-tapi-informatif
   (timestamp + atribut penting) sesuai FILTER PRODUK yang sedang aktif
   di dashboard. User eksplisit minta **format teksnya direview dulu**
   sebelum ditulis kodenya — JANGAN langsung implementasi, kirim draft
   format teks laporan dulu.
2. **Riwayat Laci Meja dipisah per 3 kategori** (titip/pinjaman/
   pre-order) + fitur pencarian + filter tanggal, DAN pre-order dapat
   filter per produk tambahan. **Catatan penting**: saat ini TIDAK ADA
   layar "Riwayat Laci Meja" tersendiri sama sekali di
   `lib/features/laci_meja/` — baru ada dashboard (kartu entri AKTIF)
   & `LaciMejaProposalReviewScreen` (review usulan sync, BUKAN riwayat
   utk kasir/owner). Kalau user maksud "riwayat" = daftar entri yg
   SUDAH selesai (dipenuhi/diambil/dikembalikan/dibatalkan), ini
   kemungkinan besar layar BARU yang perlu dirancang dulu (tanya/
   tawarkan UI-UX sblm coding, pola yg sama dgn Reset Stok kemarin) —
   BELUM ditanyakan ke user scope persisnya.
3. **Pertanyaan murni** (TIDAK perlu eksekusi kode, sudah dikonfirmasi
   user): app ini bisa dibuat self-hosted utk fungsi online? Sudah
   dijawab di chat (lihat riwayat percakapan) — inti: app ini offline-
   first by design (SQLCipher lokal, sync LAN/QR, TANPA backend cloud
   sama sekali, lihat §Ringkasan Proyek di CLAUDE.md); "self-hosting utk
   fungsi online" scr teknis MUNGKIN (mis. device jadi server HTTP
   lokal yg bisa diekspos lewat reverse-tunnel/VPN utk akses dari luar
   LAN toko) TAPI itu perubahan arsitektur besar (autentikasi jarak
   jauh, enkripsi transport publik, dsb) yang BUKAN arah desain app
   ini saat ini — dijawab sbg diskusi, bukan komitmen fitur.

---

_Update sesi 1 September 2026 (lanjutan lagi — fix restore backup lintas-
versi-app + jawab 2 pertanyaan user: pembayaran pre-order jaminan
belum-bayar, & re-sync setelah host fulfill langsung). Versi kerja
**2.29.2+65**._

**Fix** (`5eeb7f1`): user kirim screenshot error `SqliteException`
mentah saat restore backup dari HP kasir (app lebih baru) ke HP
pribadi owner (app lebih lama, skema DB blm migrasi ke kolom
`method_name`). Payload backup (`exportPortable`/`exportOwnerTransfer`)
sekarang bawa `schemaVersion`; `DbExportService.restore()` cek ini
SEBELUM `restoreFromDump`, tolak dgn pesan jelas kalau backup dari app
lebih baru. **Kalau nanti nemu bug schema-mismatch serupa di jalur
LAIN** (mis. WiFi sync `mergeRows` — itu SUDAH difilter via `PRAGMA
table_info` fisik, aman; tapi kalau ada jalur raw-SQL baru yang
menyusun kolom dari data eksternal, cek pola ini dulu).

**Pertanyaan user #1 — BELUM ditindaklanjuti, catatan gap nyata**:
pre-order dgn jaminan wadah TAPI DP-nya belum dibayar (`_effectivePrice
= 0` di `item_entry_sheet.dart` saat `_isPreorder && !_dpPaid`) —
nota bisa "Lunas" krn barang LAIN di keranjang menutup total, sementara
baris LPG itu sendiri tetap `paid=false` (`preorderEntries.paid`,
ditampilkan sbg "Tempo" di kartu dashboard). SAAT pre-order itu
dipenuhi ("Penuhi" di dashboard, `fulfillPreorderQty`), TIDAK ADA
mekanisme mengumpulkan pembayaran sama sekali — aksi itu PURE
qty/status Laci Meja, tidak menyentuh transaksi finansial apa pun.
Workaround yang ADA: edit manual harga baris item di nota (yg sudah
lunas) via `editPaidTransactionItem` (re-buka status jadi tempo utk
selisihnya, alur pelunasan normal jalan) — TAPI ini TIDAK mengubah
`preorderEntries.paid` sama sekali (`editPreorderEntry` TIDAK PUNYA
param `paid`), jadi kartu dashboard tetap salah bilang "Tempo" walau
sudah benar-benar dibayar via workaround itu. **Ini gap fitur nyata,
belum diminta user utk difix — kalau diminta nanti, dua hal yang perlu
disambungkan: (1) titik "Penuhi" perlu jalur kumpulkan bayar (spt debt-
payment), (2) `editPreorderEntry` perlu param `paid` biar bisa
disinkronkan manual dari alur manapun.**

**Pertanyaan user #2 — sudah dijawab, TIDAK perlu fix**: "kalau host
fulfill preorder langsung, apakah nanti client re-sync ngirim balik yg
'belum fulfilled'?" — TIDAK, karena `fulfillPreorderQty` restamp
`updated_at` + `locallyModified=false` (default saat dipanggil owner),
lalu `dumpSince`/`mergeRows` (host->client, last-write-wins by
`updated_at`) menimpa baris client dgn versi host TERMASUK
`locally_modified=0` — jadi `dumpLaciMejaProposals` client (yg cuma
kirim `WHERE locally_modified=1`) otomatis tidak lagi menyertakan baris
itu. **Satu-satunya celah**: race condition kalau CLIENT juga edit baris
YANG SAMA sekitar waktu bersamaan dgn `updated_at` client LEBIH BARU —
`mergeRows` skip menimpa (client menang), baris tetap
`locally_modified=1` di client & akan ke-propose lagi. Ini genuine
conflict scenario (dua device ubah baris sama), bukan bug biasa —
belum ada resolusi otomatis utknya di app ini.

---

_Update sesi 1 September 2026 (lanjutan lagi — jawab pertanyaan user
soal pre-order "muncul lagi" di sync, ternyata cuma masalah TAMPILAN
di layar approval, bukan bug data). Versi kerja **2.29.1+64**._

**Pertanyaan user**: "apakah pre-order yang sudah dipenuhi client akan
muncul lagi sbg usulan sync ke host? kalau iya, apakah itu cuma riwayat
sync (bukan bug)?" — YA, itu memang perilaku BENAR (bukan bug): begitu
status entri Laci Meja berubah di klien, `locally_modified` nyala lagi
supaya perubahan itu tersinkron ke host (`filterUnchangedLaciMejaProposals`
sudah dokumentasikan ini sejak sebelumnya). Akar kebingungan user: layar
`LaciMejaProposalReviewScreen` menampilkan baris yang SUDAH selesai
(dipenuhi/diambil/dikembalikan) SAMA PERSIS dgn baris BARU yang masih
terbuka — tanpa penanda status apa pun.

**Fix** (`481b92d`, murni tampilan — TIDAK ADA perubahan data/logic
sync): subtitle tiap baris sekarang menandai status eksplisit
("· Dipenuhi"/"· Dibatalkan" utk pre-order, "· Sudah diambil" utk
titip/ketinggalan, "· Sudah kembali semua"/"· Dikembalikan sebagian
(N)" utk pinjaman). Juga ditemukan gap terpisah saat investigasi:
baris `laci_meja_events` (log "diambil N" dkk) SEBELUMNYA ikut
dikirim & DITERAPKAN sbg usulan tapi TIDAK PERNAH ditampilkan di layar
ini sama sekali — owner menyetujui baris yang tak terlihat. Sekarang
tampil sbg section "Riwayat Kejadian" terpisah, label manusiawi
("Diambil 3", "Dipenuhi 5") + keterangan eksplisit "bukan permintaan
baru".

Tidak ada pekerjaan menggantung dari sesi ini.

---

_Update sesi 1 September 2026 (lanjutan lagi — penanda "Titip N" pre-
order ikut ke print/share struk; persingkat teks disclaimer Pratinjau
Keranjang). Versi kerja **2.29.0+63**._

**Fitur baru** (`369697c`): pre-order dgn jaminan dititip ("· Titip N",
sudah ada di struk in-app sejak lama) sekarang ikut ditandai di struk
GAMBAR (share, `_ReceiptPaper` — param baru `preorderDeposit`) DAN cetak
ESC/POS (`printer_service.dart` — param sama, tapi dicetak "- Titip N"
ASCII polos, bukan "·", krn printer thermal tidak dijamin dukung
non-ASCII).

**Gap testing yang PENTING utk sesi mendatang**: mencoba menguji
`printer_service.dart` di level byte ESC/POS (seam `debugBuildBytes`,
sudah DIHAPUS lagi) — `CapabilityProfile.load()` dari paket
`esc_pos_utils_plus` HANG TANPA BATAS (`TimeoutException` 10 menit)
di sandbox test lingkungan REMOTE ini. Tidak ada satu pun test di
seluruh repo yang pernah memanggil jalur `_buildBytes`/`printReceipt`
utk alasan yang sama — kalau nanti mau menguji perubahan
`printer_service.dart` secara otomatis, JANGAN ulangi pendekatan ini;
verifikasi manual (baca kode, bandingkan dgn jalur `_ReceiptPaper` yg
sepadan & sudah teruji) adalah satu-satunya cara yang terbukti aman di
sini sejauh ini.

**Polish kecil** (`28349d0`): teks disclaimer "Harga & total masih bisa
berubah..." di struk Pratinjau Keranjang dipersingkat — buang
parenthetical "(mis. diskon, stok, atau item ditambah/dikurangi)"
(permintaan user).

Tidak ada pekerjaan menggantung dari sesi ini.

---

_Update sesi 1 September 2026 (lanjutan lagi — fitur "Reset Stok",
proposal UI/UX di-review & disetujui user sebelum coding). Versi kerja
**2.28.0+62**._

**Fitur baru** (`ca1590d`): "Reset Stok" — timpa stok seluruh/kategori
produk jadi 0 sekaligus (`lib/features/produk/reset_stock_screen.dart`,
`ResetStockScreen`). **Keputusan arsitektur penting**: TIDAK menulis
jalur DB baru — numpang `AppDatabase.commitOpname` yang sudah ada
(Stock Opname, Item 36), karena "reset ke 0" secara konsep adalah kasus
KHUSUS opname (hitung fisik = 0 utk semua produk terpilih). Otomatis
dapat gratis: atomic write per sesi, jejak audit `stock_ledger`, DAN
muncul di layar "Riwayat Opname" yang sudah ada TANPA perlu layar
riwayat baru — `AppDatabase.buildOpnameNote` dapat param `isReset`
(note TETAP diawali `"Opname "` supaya lolos filter `getOpnameSessions`,
scope-nya ditandai `"Reset ke 0 - ..."` biar bisa dibedakan saat
ditinjau).

**Kalau nanti ada fitur serupa** ("terapkan X ke semua/sebagian
produk sekaligus") — cek dulu apa itu bisa dimodelkan sbg kasus khusus
mekanisme existing (opname, proposal produk, dst) sebelum bikin jalur
data baru; pola ini baru kepakai 2x (aksen pelanggan reuse marquee,
sekarang reset-stok reuse opname) & terbukti hemat kode + otomatis
dapat infrastruktur (audit trail, riwayat) yang sudah teruji.

Alur: pilih cakupan (chip kategori/"Semua", reuse pola Stock Opname
persis) → LANGSUNG ke review (BEDA dari opname biasa: tidak ada tahap
hitung buta, karena target akhir SELALU 0) menampilkan Sistem vs Baru=0
per produk → tombol "Reset ke 0" (styling merah/error) → dialog wajib
ketik "RESET" (case-sensitive) sebelum tombol commit aktif → commit.
Produk yang stoknya SUDAH 0 otomatis disaring dari daftar & hitungan
(tidak ada selisih, tidak perlu ditulis ke ledger).

**Gerbang akses**: ikon "Reset Stok" baru di app bar Cek Stok,
OWNER-ONLY (`device.isOwner` — LEBIH KETAT dari `canSeeReports` yg
mengizinkan asisten juga) — blast radius-nya store-wide/kategori
sekaligus, jauh lebih destruktif drpd opname biasa yang cuma mengoreksi
ke hasil hitung wajar. Kalau user minta perluas akses ke asisten
nanti, ini titik yang perlu diubah.

Tidak ada pekerjaan menggantung dari sesi ini.

---

_Update sesi 1 September 2026 (lanjutan lagi — alamat pelanggan di
kartu Laci Meja + ganti ikon Bagikan Pratinjau; ada juga diskusi
QRIS auto-detect, TIDAK diimplementasi). Versi kerja **2.27.0+61**._

**Fitur baru** (`3be9a9e`): alamat pelanggan TERDAFTAR ditampilkan sbg
baris kecil di bawah nama di SEMUA 3 jenis kartu Laci Meja (permintaan
user: cegah nama kembar-tapi-beda-alamat tertukar). `_cardHeader`
dapat param baru `address`/`isDark`; alamat diambil via provider baru
`laciMejaCustomerAddressProvider` (keyed `customerId`, BEDA dari
`laciMejaCustomerNamesProvider` yang keyed `transactionId` — alamat
menempel ke pelanggan, bukan ke nota tertentu). Pelanggan ad-hoc
(customerId null) otomatis tidak dapat alamat sama sekali — tidak
punya record `Customers`.

**Fix kecil**: ikon tombol "Bagikan Pratinjau" (fitur sesi sebelumnya)
diganti `Icons.ios_share` → `Icons.share_outlined`, disamakan dgn ikon
"Bagikan Struk" yang sudah ada di receipt_screen.dart — user menegur
saya tidak punya alasan kuat pakai `ios_share`, jadi konsistensi
menang.

**Ditanya tapi TIDAK diimplementasi** — user tanya apakah app bisa
otomatis tahu QRIS sudah dibayar, mengingat app ini offline/tanpa
backend. Jawaban yang diberikan: TIDAK bisa reliable tanpa salah satu
dari (a) API/webhook payment gateway (perlu backend cloud — bertentangan
dgn desain app ini), atau (b) `NotificationListenerService` Android yg
membaca notifikasi pembayaran bank/e-wallet di HP yang sama (fragile,
sensitif privasi, butuh permission berat) — direkomendasikan TETAP
konfirmasi manual (kasir tap "sudah dibayar" setelah lihat notifikasi
sendiri). Kalau user minta dieksplorasi lebih lanjut nanti, ini
titik mulainya.

**Skip (bukan menggantung)**: user sempat minta referensi UI ordering
dari `esborder.qs.esb.co.id` via Playwright — situsnya di belakang
Cloudflare bot-challenge, screenshot otomatis tidak bisa (percobaan
`net::ERR_CONNECTION_RESET`/403 lewat curl & Playwright, terverifikasi
itu memang proteksi Cloudflare bukan masalah proxy sesi ini). User
memilih skip, bukan minta cara lain — jangan diulang tanpa diminta.

**MENGGANTUNG — user eksplisit minta "Tawarkan UI UX nya dulu"**: opsi
reset stok (seluruh produk ATAU grup produk tertentu) jadi 0 sekaligus.
BELUM ada proposal desain yang diajukan ke user di sesi ini — item
berikutnya yang harus dikerjakan begitu sesi lanjut.

---

_Update sesi 1 September 2026 (lanjutan — polish tombol Kuota + marquee
jaminan). Versi kerja **2.26.1+60**._

**Perbaikan** (`0d08b26`), dari screenshot user atas dashboard Laci
Meja → Pre-order: baris statistik ("Produk: N" / "Jaminan: N" / tombol
Kuota) kepotong di layar sempit. (1) Tombol "Kuota" (`OutlinedButton.
icon` berlabel) diringkas jadi `IconButton` simbol saja (tooltip tetap
ada) — membebaskan lebar tetap yang sebelumnya dipakai labelnya. (2)
Nama produk di `_ProductPickerChip` (chip pemilih jaminan) sekarang
dibatasi lebar (96px) & BERJALAN (marquee) kalau kepanjangan, alih-alih
melebar tak terbatas & mendorong chip lain keluar jangkauan scroll
horizontal.

**Refactor penting**: widget marquee (`_MarqueeText`, animasi teks
berjalan) SEBELUMNYA privat di `kasir_screen.dart` (dipakai cart bar
utk nama pelanggan) — diekstrak jadi `MarqueeText` PUBLIK di
`lib/core/widgets/marquee_text.dart` supaya bisa dipakai bareng
Laci Meja tanpa duplikasi logic animasi/pengukuran overflow yang sudah
teruji (termasuk 2 gotcha halus yang didokumentasikan di kelasnya:
`textScaler` global & `DefaultTextStyle` ambient wajib diikutkan saat
mengukur overflow, kalau tidak marquee salah simpul "muat" & teks
kepotong permanen). **Kalau nambah teks yang berpotensi kepanjangan di
layar lain, cek dulu `MarqueeText` ini sebelum bikin solusi baru** —
sudah teruji & battery-conscious (animasi dibatasi per putaran-nyala +
istirahat, bukan `repeat()` abadi).

**Ketemu saat refactor**: 1 test (`cart_bar_customer_accent_test.dart`)
mencari widget lewat `runtimeType.toString() == '_MarqueeText'` (nama
class lama) — diperbaiki ke `'MarqueeText'`. Kalau nanti ada test lain
yang gagal aneh dgn pesan "No element" setelah refactor serupa
(rename/pindah widget privat->publik), cek dulu apakah ada test yang
mencocokkan lewat string nama class mentah spt ini.

---

_Update sesi 1 September 2026 — fitur "Pratinjau Keranjang"
diimplementasikan (mockup sesi sebelumnya sudah di-approve user lewat
"continue"). Versi kerja **2.26.0+59**._

**Fitur baru selesai** (`e3bf02e`): tombol "Bagikan Pratinjau" di
header `CartSheet` → sheet share struk `CartPreviewPaper`
(`lib/features/kasir/widgets/cart_preview_paper.dart`), widget TERPISAH
TOTAL dari `_ReceiptPaper` (bukan dipakai-ulang dgn parameter
kondisional — supaya logic status lunas/tempo nota ASLI tidak pernah
kecampur dgn kondisi "belum checkout"). Visual sengaja tidak mungkin
disalahartikan struk resmi (banner terracotta, watermark diagonal,
tanpa nomor nota, label "Estimasi Total", disclaimer). QR QRIS dinamis
opsional (toggle terpisah dari toggle struk asli, key SharedPreferences
`cart_preview_show_qr`/`cart_preview_qr_dynamic`) pakai modul
`resolveQrisPayload`/`QrisQrBox` yang sudah ada (dipakai bareng
checkout & pelunasan hutang) — tidak ada kode QRIS baru, murni reuse.

**Ketemu & diperbaiki saat implementasi** (bukan bug lama, murni akibat
tombol baru): baris header `CartSheet` sudah padat 5 IconButton
(Tahan/Tempel/Pengaturan/Transfer QR/Kosongkan); nambah yang ke-6
("Bagikan Pratinjau") OVERFLOW 33px di lebar 360dp (dibuktikan test
`cart_sheet_header_overflow_test.dart` SEBELUM fix). Fix: baris itu
sekarang dibungkus `IconButtonTheme` lokal (padding 4,
`VisualDensity.compact`, minimumSize 36×36) — kalau nambah tombol lagi
ke baris ini di masa depan, otomatis ikut sempit, TIDAK PERLU sentuh
tiap `IconButton` satu-satu. **Kalau baris ini masih terasa padat ke
depannya (mis. nambah tombol lagi), pertimbangkan pindah sebagian ke
dalam dialog "Pengaturan Keranjang" yang sudah ada, bukan nambah ikon
lagi selamanya.**

Tidak ada pekerjaan menggantung dari sesi ini — task #10 (Pratinjau
Keranjang) selesai & di-merge.

---

_Update sesi 31 Agustus 2026 (lanjutan lagi x8 — bug tempo hilang saat
ada kembalian; mockup "Pratinjau Keranjang" menunggu approval). Versi
kerja **2.25.1+58**._

**Bug diperbaiki** (`3afab62`): baris "Kembali"/"Sisa" di 3 tempat
(cetak ESC/POS tunggal, nota gabungan — `printer_service.dart`; struk
share `_ReceiptPaper` — `receipt_screen.dart`) pakai if/else-if,
padahal keduanya BUKAN saling meniadakan — nota bisa kurang_bayar/
tempo LAGI setelah sempat lunas+kembalian (tambah belanjaan naikkan
total lagi). Ringkasan on-screen sudah benar dari awal (2 `if`
independen); disamakan.

**MENGGANTUNG — nunggu jawaban user**: mockup HTML "Struk Pratinjau
Keranjang" (fitur baru: share preview+estimasi total dari KERANJANG,
sebelum checkout — beda tampilan dari struk lunas/tempo asli, coba
sertakan QR QRIS dinamis krn app ini sudah bisa menyisipkan nominal ke
payload QRIS statis MURNI OFFLINE tanpa perlu transaksi tercatat dulu,
lihat `lib/core/utils/qris_dynamic.dart`) sudah dikirim ke user via
screenshot (`/tmp/.../scratchpad/cart_share_mockup/`), BELUM
diimplementasi — tunggu approval/revisi desain dulu sebelum coding.
Rencana implementasi kalau approve: tombol baru di keranjang, widget
struk BARU terpisah dari `_ReceiptPaper` (supaya tidak kecampur logic
status lunas/tempo nota sungguhan), opsi toggle QRIS di Pengaturan.

---

_Update sesi 31 Agustus 2026 (lanjutan lagi x7 — dropdown custom-desain
+ fix angka jaminan dinamis + aksen teks pelanggan diperluas ke SEMUA
tempat). Versi kerja **2.25.0+57**._

**3 permintaan susulan cepat** dari user setelah iterasi dropdown
jaminan sebelumnya:
1. Dropdown-nya diminta desain sendiri ("bukan default flutter") —
   `_ProductPickerChip`/`_ProductPickerMenuRow` baru, tetap pakai
   mekanisme `PopupMenuButton` (cuma tampilan yg di-custom total lewat
   `shape`/`color`/`elevation`+child custom, BUKAN dibangun ulang dari
   nol pakai `OverlayEntry` manual — pertimbangan risiko: posisi/
   dismiss/keyboard `PopupMenuButton` sudah teruji Flutter sendiri).
2. Bug ketauan dari feedback: angka "Jaminan: N" ternyata SELALU total
   semua produk, BUKAN produk yg sedang dipilih di dropdown — padahal
   itu justru inti permintaan sebelumnya. Fix: `_StatChip` "Jaminan: N"
   dipisah dari `_ProductPickerChip` (pemilih nama), angkanya diambil
   langsung dari `depositByProduct[selectedId]`.
3. Aksen pelanggan terdaftar (dari sesi sebelumnya) DIPERLUAS: bukan
   cuma ikon, TEKS nama-nya juga ikut terracotta — di cart bar, SEMUA
   3 kartu Laci Meja (dashboard), dan header nota. **Jebakan penting
   yg ketemu**: `scheme.primary` di tema app ini SAMA PERSIS dgn
   `AppTheme.accent` (`primary: accent` di app_theme.dart) — kalau ada
   kode LAIN yang pakai `scheme.primary` utk "menonjolkan" sesuatu yg
   BUKAN soal pelanggan-terdaftar (mis. nama ad-hoc yg cuma terisi),
   itu akan ikut ke-render terracotta juga tanpa disengaja. Sudah
   kena di header nota (diperbaiki, ganti `scheme.onSurface`) — kalau
   nambah aksen serupa di tempat lain, WAJIB cek dulu apa warna yg
   dipakai utk kasus "bukan target aksen" itu benar2 beda hex dari
   `AppTheme.accent`, jangan asumsi `scheme.primary`/`onSurface`/dkk
   otomatis netral.

---

_Update sesi 31 Agustus 2026 (lanjutan lagi x6 — chip jaminan bisa
ganti produk lewat dropdown). Versi kerja **2.24.0+56**._

Iterasi KETIGA (terakhir sejauh ini) atas statistik pre-order. Chip
"Jaminan" yang tadinya cuma tampilkan TOTAL (+ tooltip rincian per
produk) sekarang menampilkan SATU produk langsung (default: produk
pertama berjaminan terbuka — urutan sama dgn FIFO `createdAt`),
diganti via dropdown `PopupMenuButton` yang cuma muncul kalau memang
ada >1 produk berjaminan. Total keseluruhan pindah jadi teks polos di
LUAR chip, gaya sama dgn "N entri" yang duluan ada di sebelah chip
"Produk". Provider `_preorderJaminanDisplayProvider` (baru) menyimpan
pilihan per productId (BUKAN nama — lihat komentar di kode kenapa),
fallback ke produk pertama kalau produk yang dipilih sudah tidak lagi
punya jaminan terbuka (mis. sudah dipenuhi semua).

**Kalau ada permintaan serupa lagi di elemen dashboard lain** (mis.
kategori Titip/Pinjaman juga minta rincian per-X yang bisa dipilih):
pola dropdown-tetap-di-satu-baris ini (bukan expand-ke-multi-baris)
sudah terbukti dipakai berkali-kali, pertimbangkan dulu sebelum desain
baru dari nol — lihat riwayat 3 iterasi statistik pre-order di entri
sebelumnya (kartu besar → teks polos → chip gradasi → chip+dropdown)
utk pelajaran soal apa yang disukai/tidak disukai user tiap iterasi.

Iterasi KEDUA atas redesain statistik pre-order. Riwayat percobaan
(supaya tidak diulang lagi kalau ada feedback lanjutan):
1. Kartu besar (`_PreorderStats`/`_StatTile`, Container tinggi dgn
   Column label/value/sub) — user: "terlalu besar, asal tempel".
2. Teks polos satu baris ("N entri · X produk · Y jaminan") — user:
   "terlalu ringkas", gradasi visual (label normal + angka BOLD) yang
   disukai dari versi kartu justru hilang.
3. **Solusi yang dipakai sekarang** (`_PreorderStatsLine`/`_StatChip`
   baru): chip mini per angka — border+bg tipis (identitas "kartu"
   dipertahankan) TAPI satu baris `Text.rich` (bukan Container
   tinggi). Ini yang benar: kecil (memenuhi keluhan #1) SEKALIGUS
   pertahankan gradasi bold/normal (memenuhi keluhan #2).

**Pelajaran utk kasus serupa ke depan**: kalau user bilang sesuatu
"terlalu besar", jangan langsung lompat ke "hapus visual/ganti teks
polos" — tanya/pertimbangkan dulu APA yang disukai dari desain lama
(di sini: gradasi bold), lalu pangkas cuma bagian yang benar-benar
makan tempat (di sini: padding Container + Column multi-baris), bukan
seluruh identitas visualnya.

Rincian jaminan per produk tetap di `Tooltip` (tap-triggered) lewat
ikon info kecil, tidak berubah dari iterasi sebelumnya.

---

_Update sesi 31 Agustus 2026 (lanjutan lagi x3 — audit cakupan sync +
redesain tata letak filter/statistik pre-order). Versi kerja
**2.23.0+53**._

**Audit sync (permintaan user)**: ditemukan 2 gap nyata, keduanya
sudah diperbaiki (`723b292`):
1. `preorder_quota_thresholds` belum ada di `syncableSettingKeys` —
   ditambahkan (kebijakan toko, bukan scratchpad lokal spt
   `saved_catalogs`).
2. **Bug LEBIH LUAS**: `setSetting` (satu-satunya jalur tulis
   `app_settings`) tidak menstempel `updatedAt` eksplisit saat
   UPDATE — persis gotcha yang sudah didokumentasikan utk
   master-data lain di CLAUDE.md, TERNYATA berlaku juga di sini.
   Efeknya: MENGUBAH setting yang sudah pernah tersinkron sebelumnya
   (owner setel ulang kuota, ganti nama toko, dll) tidak akan lolos
   filter `dumpSince` lagi — bug ini SUDAH ADA dari awal utk seluruh
   isi `syncableSettingKeys`, cuma baru ketahuan sekarang krn kuota
   pre-order wajar diubah berkali-kali (setting lain jarang diubah
   setelah setup awal, jadi gejalanya nyaris tidak pernah muncul).
   **Kalau nanti nambah key baru ke `syncableSettingKeys`, cek juga
   apakah nilainya akan sering di-UPDATE setelah pertama kali dibuat
   — kalau ya, fix ini (updatedAt eksplisit) sudah menutupnya, tidak
   perlu fix baru lagi.**
5 kolom Laci Meja lain (`last_edited_at` x3, `pinned`, `customer_id`)
diverifikasi SUDAH terikut otomatis lewat `SELECT *` — tidak disentuh.

**Redesain tata letak** (`b3262e2`, permintaan user "jangan asal
taruh"): filter chip + kartu statistik pre-order dibungkus jadi satu
panel dgn border+padding seragam, tombol kuota dapat label. **Jebakan
test baru**: panel yang lebih tinggi mendorong entri ListView keluar
viewport test default (800×600) — WAJIB `setSurfaceSize` generus di
test manapun yang merender `LaciMejaDashboardScreen` langsung (bukan
lewat harness `pumpWithFakeApp` yang sudah otomatis generus). Juga:
tap ke widget di dalam `SingleChildScrollView` horizontal yang
mungkin ter-clip (chip di luar viewport awal) WAJIB `ensureVisible`
dulu — tanpa itu tap jatuh ke koordinat yang sama tapi kebetulan
ditempati widget LAIN (kejadian nyata: tap chip malah membuka sheet
kuota krn tombol "Kuota" ada di koordinat yang sama dgn chip yg
ter-clip).

---

_Update sesi 31 Agustus 2026 (lanjutan lagi x2 — 3 penyesuaian fitur
kuota pre-order dari feedback screenshot user). Versi kerja
**2.22.2+52**._

**Feedback user via screenshot setelah kuota dirilis**: (1) "Abdul
Ghani tidak naik, setelah satu jaminan milik orang lain terpenuhi" —
maksudnya entri YANG DIPENUHI SEBAGIAN (progress "Dipenuhi 4 dari 5")
tetap membebani kuota dgn `qtyOrdered` PENUH (5), bukan sisanya (1) —
`preorderIdsBeyondQuota` diperbaiki pakai parameter `takenQty` baru,
kumulatif sekarang `qtyOrdered - taken`. (2) ganti garis solid+kuning
jadi putus-putus (`_DashedLine`, `CustomPaint` manual) + abu-abu
netral, buang kata "normal" dari label. (3) "berikan update sisa
terakhir... card total pinjaman juga sinkronkan" — baris kartu
pre-order & 2 kartu statistik atas ("Total produk"/"Total jaminan")
sekarang menampilkan SISA (bukan angka pesanan awal yang basi begitu
ada pemenuhan sebagian). **Asumsi baru yang perlu diketahui**: jaminan
diasumsikan konsumsi 1:1 dgn item (tabung kosong ditukar isi) —
`sisaDeposit = depositQty - taken` pakai `taken` yang SAMA dgn qty
item, BUKAN akumulator terpisah. Kalau nanti ada kasus toko yang rasio
jaminan≠item, ini perlu didesain ulang (belum ada laporan seperti itu
sejauh ini).

---

_Update sesi 31 Agustus 2026 (lanjutan — 4 penyesuaian Laci Meja +
aksen pelanggan tetap vs ad-hoc). Versi kerja **2.22.0+50**,
schemaVersion **34→35**._

**Alur sesi ini**: user mengusulkan 4 hal sekaligus (kuota antrian
pre-order, semua atribut Laci Meja jadi editable, filter produk, pin
kartu pinjaman), minta **diusulkan dulu logikanya** ("jangan coding
dulu"), lalu bertanya soal pembedaan pelanggan tetap vs ad-hoc di
kartu Laci Meja / cart bar / nota. Setelah usul disetujui: dicatat ke
task manager (#6–#9), dieksekusi, di-merge ke `main`.

**Keputusan desain yang masih berlaku:**

1. **Garis pembatas kuota pre-order DIHITUNG ULANG tiap render**, tidak
   pernah disimpan sbg posisi. Ini permintaan eksplisit user: "jika
   ada pre-order terbaru tiba-tiba dipenuhi untuk alasan tertentu,
   padahal set line jumlah sudah ditetapkan, itu tetap menyesuaikan
   dengan antrian". Karena `preorderIdsBeyondQuota` murni turunan dari
   daftar entri TERBUKA (yang dipenuhi/dibatalkan otomatis hilang),
   garisnya bergeser sendiri tanpa logika antre-ulang. **Jangan
   diubah jadi kolom/snapshot** — itu membatalkan seluruh sifatnya.
   Ambangnya sendiri disimpan sbg blob JSON di tabel settings (key
   `preorder_quota_thresholds`), bukan kolom DB — konfigurasi
   operasional, bukan data transaksi.
2. **`last_edited_at` SENGAJA terpisah dari `updated_at`**.
   `updated_at` ikut tersentuh aksi operasional & sync, jadi tidak
   bisa menjawab "kapan isinya terakhir diubah orang". Toggle `pinned`
   juga TIDAK menstempelnya (menyematkan bukan mengubah isi).
3. **Edit entri Laci Meja tidak boleh menurunkan qty di bawah yang
   sudah tercatat di log** (`_laciMejaTakenQty`) — kalau tidak, sisa
   entri jadi negatif & ledger barang fisiknya ngawur. Tiap edit
   menulis baris log `aksi = 'edit'` (qty 0) berisi ringkasan
   perubahan — alasan fitur ini ada justru menjaga audit tetap jujur.
   Produk/satuan/nota SENGAJA tidak bisa diedit (setara hapus-buat-
   ulang, persis yang dihindari).
4. **Pin pinjaman disimpan per BARIS tapi di-toggle per GRUP
   pelanggan** — kartu dashboard dikelompokkan per pelanggan, kalau
   per baris kartunya bisa "setengah tersemat" & urutannya tidak bisa
   dijelaskan ke user.
5. **Pembeda pelanggan terdaftar vs ad-hoc = `customerId` (null =
   ad-hoc)**, ikon terisi + `AppTheme.accent` vs ikon garis + warna
   netral. Ikon dipakai sbg pembeda utama, bukan warna saja.
   `preorder_entries.customer_id` ditambahkan di v35 (kolom ini sudah
   lama ada di 2 tabel Laci Meja lain). User **menolak** tambahan
   snackbar/badge yang memberi tahu saat QR handoff menjatuhkan
   `customerId` karena pelanggannya belum tersinkron di penerima —
   "cukup visual saja"; downgrade-nya sudah otomatis terlihat dari
   warna ikon di perangkat penerima.

**Catatan test**: `Future.delayed` di dalam `testWidgets` TIDAK PERNAH
selesai (fake clock) → test menggantung sampai timeout 10 menit. Untuk
menyiapkan urutan `createdAt`, tulis kolomnya EKSPLISIT lewat
`Companion.insert`, jangan mengandalkan jeda antar insert. Selain itu:
di layar ber-`StreamProvider`, `drain()` harus dijalankan SEBELUM
assert (simpan hasil finder ke variabel dulu) — kalau assert gagal
duluan, `tearDown` menutup DB saat widget masih mounted dan test
menggantung tanpa batas.

---

_Update sesi 31 Agustus 2026 — user minta review menyeluruh logika
retur/kembalian ("terutama retur - tambah pembelian berkali-kali"),
lalu 2 fitur laci-meja tambahan didiskusikan & dieksekusi sekaligus.
Commit `49985ff`/`31a7376`/`73338c8`, versi kerja **2.21.0+49**, sudah
di-push & di-merge ke `main`. **Konvensi versioning baru mulai
diterapkan sesi ini** (lihat entri sebelumnya) — MINOR naik krn ada
fitur baru (poin 3 di bawah).

**Metodologi sesi ini, penting utk pola serupa ke depan**: user minta
"catat itu ke task manager anda dulu, bukan di plan.md" — temuan dari
review kode (bug + fitur yang didiskusikan) dicatat via `TaskCreate`
(bukan `PLAN.md`) selama masih tahap diskusi/menunggu keputusan user,
baru dieksekusi satu-satu setelah user bilang "boleh, eksekusi". Semua
5 task sudah `completed`, tidak ada lagi yang menggantung di task
manager terkait sesi ini.

**Temuan 1 (bug, FINANSIAL) — `49985ff`**: tombol "Batalkan Pembayaran"
& `AppDatabase.voidPayment` sebelumnya tidak membedakan pembayaran
NORMAL vs baris REFUND RETUR (`returnPaidTransactionItems`/
`editPaidTransactionItem`, `amount` negatif — uang fisik & stok SUDAH
permanen berubah lewat retur) atau marker retur nota belum-lunas
(`method` 'retur'/'edit'). Membatalkan baris refund itu bikin `paid`
naik lagi TANPA `total`/item ikut balik → kembalian HANTU (sistem
menghitung seolah harus diserahkan lagi, padahal sudah pernah) —
dialognya bahkan salah bilang "barang & stok TIDAK berubah". **Fix 2
lapis**: sembunyikan tombol UI (`_isReturLinkedPayment`, cek
`amount<0 || method in ('retur','edit')`) + guard IDENTIK langsung di
`voidPayment` (defense-in-depth, supaya caller lain di masa depan
tidak kena bug yang sama meski lewat jalur lain, bukan cuma UI).

**Temuan 2 (bug, UX) — `49985ff`**: sheet retur (`remainingFor` di
`receipt_screen.dart`) salah hitung sisa returnable saat produk yang
sama ada di >1 baris nota (baris asli + baris "Tambahan" dari sesi
Tambah Belanjaan) — skenario PERSIS yang ditanya user ("retur - tambah
pembelian berkali-kali"). Versi lama mengurangi retur SEBELUMNYA dari
qty MASING-MASING baris secara independen (bukan pool bersama) —
totalnya jadi lebih kecil dari sisa sebenarnya, kasir harus buka-tutup
sheet berkali-kali. **Bukan bug uang** — DB (`returnPaidTransactionItems`)
sendiri sudah benar. Fix: pool bersama per `productUnitId` yang
menyusut dinamis antar baris (dikurangi qty yang SUDAH dipilih di
baris lain dalam sesi sheet yang sama), diklem-ulang otomatis kalau
baris lain menyusutkan pool sesudah baris ini terisi.

**Fitur baru "Jadikan Pre-order" — `49985ff`**: skenario nyata dari
user — kasir lupa input pre-order saat checkout (LPG lupa dicek stok),
nota keburu lunas/tempo. Long-press baris item di struk in-app → menu
aksi baru (selain "Edit Catatan" yang sudah ada) → "Jadikan Pre-order"
→ dialog qty (default = sisa qty baris yang belum pernah ditandai,
dihitung dari SEMUA `PreorderEntries` unit yang sama di nota ini,
cegah dobel-tandai) + catatan opsional → insert `PreorderEntries` baru
bertaut `transactionId` LANGSUNG ke nota ini (field sudah ada &
nullable, TIDAK perlu migrasi), `paid: true` (uang sudah tercatat
lunas/tempo via nota ini sendiri, beda dari pre-order normal yg `paid`
bisa false). **TIDAK menyentuh** `transaction_items`/total/paid nota
sama sekali — murni catatan tambahan. Otomatis muncul di kartu
"Pre-order" struk (`_buildPreorderCard` sudah query by `transactionId`,
tidak perlu kerja tambahan) & dashboard Laci Meja. **Keputusan user**:
boleh di nota tempo (bukan cuma lunas), TIDAK perlu gerbang izin utk
sementara.

**Fix susulan — `31a7376`**: toggle "Pre-order?"/"DP?" di
`item_entry_sheet.dart` ternyata TIDAK PERNAH prefill dari cart line
yang sudah ada (`_load()` cuma prefill qty/harga/catatan, lupa 3 field
pre-order) — reopen item yg SUDAH pre-order di cart selalu tampil
toggle "Tidak" walau datanya masih "Ya". User klarifikasi: LOGIKA-nya
sendiri (data tetap pre-order selama sheet belum di-save ulang) SUDAH
BENAR & diinginkan — yang salah murni tampilan toggle yang membingungkan,
DAN kalau kasir tetap tap "Tambah ke Keranjang" tanpa sadar toggle
salah, status pre-order ASLI beneran hilang. Fix: prefill 3 field itu
sama seperti field lain yang sudah benar.

**Fix susulan lain — `73338c8`**: diminta user — atribut Laci Meja
(titip/pinjaman/pre-order) milik transaksi yang SUDAH di-void TIDAK
BOLEH ikut tersinkron ke host lagi. `voidTransaction` sengaja tidak
menghapus baris-baris itu (jejak audit, pola soft-delete konsisten di
app ini), jadi fixnya di titik KELUAR data (`dumpSince`, filter thd
status transaksi induk via subquery), BUKAN hapus data lokal — user
pilih ini eksplisit setelah ditanya "opsi mana yang lebih aman"
(alasan: reversibel, tidak ada mekanisme delete-propagation utk tabel
laci-meja jadi hapus lokal berisiko device lain tidak ikut tahu).
`laci_meja_events` (log kejadian, `entry_id` polimorfik ke 3 tabel
laci-meja) ikut difilter biar tidak jadi log yatim. **Gap yang
disepakati diterima**: data yang SUDAH kadung tersinkron ke host
SEBELUM notanya di-void tidak ikut terhapus balik (di luar cakupan,
laci-meja belum punya mekanisme retract/tombstone).

15 test baru total (2 DB voidPayment + 1 widget cancel-button-hidden +
1 widget pool-bersama-retur + 3 widget jadikan-preorder + 1 widget
prefill-toggle + 3 DB dumpSince-void-laci-meja + beberapa DB tambahan)
— SEMUA revert-verified satu-satu. Full suite 1206 lolos SEMUA (bukan
cuma "flaky pre-existing lolos", kali ini genuinely 0 gagal),
`flutter analyze` 0 issue.

_Update sesi 30 Agustus 2026 (lanjutan lagi — 3 penyesuaian susulan
langsung dari fitur nama metode pembayaran & chart tap-to-pin sesi
sebelumnya), commit `e3216f9`/`ddaa631`, versi kerja **2.19.22+47**,
sudah di-push (belum di-merge ke `main`).

**1. Chart "Penjualan Harian" (screenshot user) diganti ke garis**
(`e3216f9`): user tunjukkan chart bar-per-hari tumpuk labelnya di
hari-hari akhir bulan — SAMA PERSIS akar masalah yang sudah pernah
diperbaiki di `StatsTrendChart` (chart "Tren penjualan" produk, lihat
dok panjang di `stats_common.dart`). Fix: `_DailyChart`
(`ringkasan_tab.dart`) sekarang murni convert `Map<DateTime,int>` jadi
`List<TrendPoint>` lalu DELEGASI ke `StatsTrendChart` yang sudah ada —
BUKAN reimplementasi baru. **Pola penting utk sesi depan**: kalau ada
chart baru yang butuh render tren tanggal, cek dulu apakah
`StatsTrendChart` bisa dipakai ulang sebelum menulis chart baru dari
nol — sudah 2x dipakai ulang (produk, lalu Penjualan Harian).

**2. Label nominal PUNCAK permanen** (`e3216f9`, sama commit):
`StatsTrendChart` dapat `ExtraLinesData(horizontalLines: [...])` — garis
putus-putus + label di level `maxY` DATA MENTAH (bukan `maxY` chart yg
sudah dikasih headroom 15%), pakai `HorizontalLineLabel` bawaan
fl_chart (`alignment: Alignment.topLeft` default). Berlaku OTOMATIS di
KEDUA pemakai widget ini (Penjualan Harian & Tren Penjualan produk) —
tidak perlu ubah kedua caller-nya sama sekali, cukup ubah widget
bersama.

**3. Filter Riwayat Transaksi by metode pembayaran** (`ddaa631`):
`tx_history_sheet.dart` (`_HistoryQuery`) dapat field `method` baru,
difilter di level query DB (`t.paymentMethod.equals(...)`), UI chip
`InputChip` + picker `showModalBottomSheet` sederhana (pola sama
seperti chip filter tanggal yang sudah ada). **Keputusan desain**:
filter pakai KATEGORI (`Transactions.paymentMethod`: tunai/bank/qris/
ewallet/tempo), BUKAN nama spesifik (`methodName`, fitur susulan sesi
sebelumnya) — banyak nota lama `methodName`-nya null, & filter
per-kategori lebih masuk akal utk analisis semacam "semua transaksi
QRIS bulan ini". Kalau user nanti minta filter by nama spesifik jg
("filter GoPay doang, bukan semua E-Wallet"), perlu query tambahan yg
JOIN/filter `methodName` dgn fallback ke kategori kalau null.

Test baru: 1 di `stats_trend_chart_test.dart` (garis+label puncak,
posisi & nilai benar) + 1 di `ringkasan_tab_daily_chart_test.dart`
(LineChart menggantikan bar chart lama) + 2 di
`tx_history_method_filter_test.dart` (filter aktif menyembunyikan nota
lain, lepas filter menampilkan semua lagi) — SEMUA revert-verified.
Full suite 1194 lolos / 1 gagal (flaky pre-existing —
`proposal_unchanged_end_to_end_test.dart`), `flutter analyze` 0 issue.

_Update sesi 30 Agustus 2026 — 3 penyesuaian yang user minta jawaban
dulu sebelum coding ("Jawab dulu, jangan coding dulu"), lalu semuanya
dieksekusi sekaligus ("Kerjakan semua"). Commit `6a5444f`/`4cfebd5`/
`ba3c9b1`, versi kerja **2.19.21+46**, sudah di-push (belum di-merge ke
`main` — cek instruksi user sesi berikutnya).

**1. Chart Penjualan Per Jam (Ringkasan) — tap-to-pin** (`6a5444f`):
rincian per-jam sekarang dibuka via TAP (bukan tekan-tahan `Tooltip`
bawaan yang otomatis hilang), permanen sampai tap bar lain/tap area
lain/scroll. State di `_pinnedHourProvider` (provider-level, BUKAN
`setState` lokal) krn kedua pemicu "tutup" berasal dari widget leluhur
`_HourlyChart` (`RingkasanScreen`/`_RingkasanBody`), bukan dari
`_HourlyChart` sendiri — lihat dok di file itu kalau mau paham
kenapa arsitekturnya begini. Tiap bar dapat `ValueKey('hour_bar_$h')`
murni utk testability.

**2. Toggle auto-disconnect printer setelah cetak** (`4cfebd5`):
`PrinterSettings.autoDisconnectAfterPrint` baru, default **FALSE**
(perilaku lama "tetap tersambung" dipertahankan — user EKSPLISIT minta
kedua perilaku tetap bisa dipilih, bukan diganti paksa, krn tidak semua
toko pakai >1 device BT). Toggle di Pengaturan > Printer Bluetooth >
seksi baru "Koneksi Printer". Ketiga fungsi cetak lewat helper bersama
`PrinterService._writeBytes`. **Tidak ada test otomatis** utk fitur ini
(wiring native `disconnect()` yang sudah ada, percabangan trivial) —
kalau user lapor toggle tidak berfungsi, cek dulu urutan
write→disconnect di `_writeBytes`, bukan asumsikan test yang hilang.

**3. Nama SPESIFIK metode pembayaran** (`ba3c9b1`, schemaVersion
33→34): `Transactions.methodName`/`TransactionPayments.methodName`
(nullable, snapshot `PaymentMethods.name` mis. "GoPay"/"BCA" — nota
lama tetap null, fallback ke label generik di SEMUA tempat tampilan).
Ditulis dari checkout, tambah bayar tempo (4 caller
`addPaymentToTransaction`), lunasi gabungan (`settleMergedDebt`), refund
(`returnPaidTransactionItems`). Ditampilkan di cetak struk
(`printer_service.dart`), share struk & struk in-app
(`receipt_screen.dart`). **Ripple wajib tiap kali schemaVersion naik**:
17 test migrasi lama (literal `schemaVersion=33` hardcoded) + 8 fixture
kurang stub tabel `transactions`/`transaction_payments` (migrasi v34
`ALTER TABLE` keduanya) — semua sudah diperbaiki, tapi **INGAT pola ini
utk migrasi berikutnya**: cek dulu apakah kolom baru nempel ke tabel
yang belum tentu ada di fixture versi lama sebelum menganggap migrasi
"pasti aman".

**Laporan (transaksi_tab.dart/hutang_tab.dart) TIDAK diberi tampilan
nama spesifik** — hanya call-site fix minimal (`methodName:` diteruskan
ke `addPaymentToTransaction`) supaya kompilasi tidak pecah akibat
perubahan `showDebtPaymentSheet`. User cuma minta cetak/share/in-app,
laporan di luar scope literal permintaan — kalau user minta konsistensi
ke situ juga nanti, cari switch generik di
`transaksi_tab.dart:241`/`ringkasan_tab.dart:191`/
`arus_kas_tab.dart:36`/`report_export.dart:582`.

Full suite 1189 lolos / 2 gagal (flaky pre-existing —
`proposal_unchanged_end_to_end_test.dart`, `SocketException: Address
already in use` port 8625, bukan regresi), `flutter analyze` 0 issue.

_Update sesi 29 Agustus 2026 (lanjutan lagi x5 — hapus panel debug
binding device, DIKONFIRMASI user), commit `bbbd4f4`, di-push &
di-merge ke `main`. **Insiden device produksi user (entri x4 di bawah)
SUDAH SELESAI & DIKONFIRMASI**: user update ke build fix, masukkan
ulang kode aktivasi yang sama, device terbuka normal — tidak perlu
tindak lanjut lagi.

Panel debug "Debug — Binding Device" (tampil ANDROID_ID + tombol
"Simulasikan Device Lain"/"Reset") sudah dihapus total dari
`device_license_screen.dart`, sesuai janji sesi sebelumnya. Method
`LicenseNotifier.debugSimulateDeviceMismatch()`/
`debugResetDeviceBinding()` ikut dihapus. **Logic inti fitur binding
device TETAP AKTIF & TIDAK berubah** — `computeDeviceMismatch`,
`rebindDeviceId`, `_checkDeviceBinding` semua masih ada persis seperti
sebelumnya, cuma UI/method debug sementaranya yang hilang. Test
permanen (`license_service_test.dart`/
`license_device_binding_load_test.dart`) tetap menutupi logic inti ini
tanpa perlu panel debug. Full suite 1183 lolos / 0 gagal, `flutter
analyze` 0 issue.

_Update sesi 29 Agustus 2026 (lanjutan lagi x4 — fix BUG PRODUKSI:
reaktivasi valid tidak membuka device ter-flag deviceMismatch), commit
`d2f3c6b`, versi kerja **2.19.20+45**.

**Kronologi insiden (device PRODUKSI user, data riil, bukan testing)**:
user test panel debug binding device (entri di bawah) → device benar
terkunci (`deviceMismatch=true`, sesuai harapan). User coba pulihkan
lewat "Hapus Data" di Setelan HP, tapi ternyata TIDAK mereset
`license_fingerprint` (atau user belum coba fingerprint baru) — jadi
coba reaktivasi pakai kode LAMA yang masih sama fingerprint-nya. Kode
diterima secara kriptografis TAPI device tetap ke-redirect ke layar
Aktivasi berulang-ulang — user (tepat) curiga ini bug, bukan expected
behavior.

**Root cause**: `activate()` (sebelum fix ini) sama sekali tidak
menyentuh `deviceMismatch`/baseline `license_android_id` — cuma urus
`revoked`/`exp`/`lastSeen`/`activatedAt`. Sekali `deviceMismatch=true`
(dari `_checkDeviceBinding` di `load()`), TIDAK ADA jalan normal utk
membersihkannya lagi selain lewat tombol debug yang (ironisnya) TIDAK
BISA dijangkau begitu app sudah terkunci (layar Aktivasi tidak py link
ke Pengaturan). Kalau ini kejadian ke pelanggan JUJUR (skenario paling
realistis: ANDROID_ID BISA berubah krn update OS besar/factory reset
resmi di beberapa OEM, BUKAN cuma krn clone) — mereka terkunci PERMANEN
tanpa jalan keluar dari dalam app sama sekali. Bug ini murni akibat sesi
sebelumnya lupa memikirkan "bagaimana cara device yang sudah ter-flag
bisa pulih lewat jalur normal" saat merancang fitur binding-nya.

**Fix**: `LicenseNotifier.rebindDeviceId(prefs)` (method baru, PUBLIC +
`@visibleForTesting` — bukan private, krn `activate()` sendiri TIDAK
BISA ditest end-to-end tanpa private key produksi asli yg memang
sengaja tidak pernah ada di repo, jadi logic-nya diekstrak keluar
supaya testable terpisah) dipanggil dari `activate()` SETELAH kode
terverifikasi valid & lolos cek revoked — merekam ULANG baseline
ANDROID_ID ke device yang SEDANG dipakai & set `deviceMismatch=false`.
Fail-open kalau gagal baca ANDROID_ID (pertahankan status lama, bukan
diasumsikan aman).

**Trade-off yang disadari & disampaikan eksplisit ke user**: device
hasil clone SEKARANG bisa membuka diri lagi asalkan pemegangnya JUGA
punya kode aktivasi yang masih valid (belum revoked/expired) — user
menerima ini krn beda kelas ancaman dari yang jadi concern awal
("clone diam-diam TANPA jejak apa pun, developer tidak pernah tahu").
Reaktivasi tetap butuh langkah aktif & kode sah, masih ada sinyal.

**Yang belum diselesaikan di sesi ini (menunggu tindak lanjut user)**:
device produksi user MASIH terkunci saat commit ini ditulis — user
perlu update ke build baru (versi kerja di atas) lalu masukkan ULANG
kode aktivasi yang SAMA yang sudah mereka punya (fingerprint tidak
berubah krn tidak di-uninstall) — dengan fix ini, seharusnya langsung
terbuka tanpa perlu Hapus Data/kode baru sama sekali. **Verifikasi ini
BELUM dikonfirmasi user** — cek respons user sesi berikutnya.

Test baru (2, revert-verified) di `license_device_binding_load_test.
dart` menguji `rebindDeviceId` langsung (bukan lewat `activate()` yg
butuh private key produksi). Full suite 1183 lolos / 0 gagal (kebetulan
tidak kena flaky pre-existing sesi ini), `flutter analyze` 0 issue.

_Update sesi 29 Agustus 2026 (lanjutan lagi x3 — panel DEBUG sementara
utk verifikasi manual binding ANDROID_ID di HP asli, user tidak punya
laptop/adb), commit `f18c8db`. **PENTING
UTK SESI DEPAN: kalau user bilang hasil test SUDAH dikonfirmasi
berhasil, WAJIB hapus panel debug ini** — jangan biarkan menumpuk di
`main`, itu janji eksplisit yang dibuat ke user sebelum eksekusi.

Yang ditambahkan (murni utk 1x pemakaian test manual, BUKAN fitur
rilis): `device_license_screen.dart` dapat seksi baru "Debug — Binding
Device (hapus setelah test)" — tampil ANDROID_ID yang berhasil dibaca
`DeviceIdService.getAndroidId()` + 2 tombol: "Simulasikan Device Lain"
(timpa `license_android_id` tersimpan dgn nilai palsu lalu paksa
`load()` ulang — persis efek clone data ke device fisik lain, tanpa
perlu HP kedua/adb) dan "Reset" (hapus baseline simulasi, `load()`
berikutnya rekam ulang device asli sbg baseline sah). 2 method baru di
`LicenseNotifier`: `debugSimulateDeviceMismatch()`/
`debugResetDeviceBinding()`, ditandai jelas blok komentar "DEBUG
SEMENTARA ... HAPUS setelah dikonfirmasi". TIDAK ditambahkan test
permanen (kodenya sendiri memang mau dihapus lagi) — dicoba smoke test
manual sekali lewat widget test throwaway (tidak disimpan ke repo),
sempat ke-interrupt di tengah jalan tapi logic-nya trivial (cuma
`prefs.setString`/`prefs.remove` + panggil `load()` yang SUDAH
teruji lengkap di `license_device_binding_load_test.dart`) — risiko
rendah. Tidak bump versi (bukan rilis, murni alat bantu test
sementara). `flutter analyze` 0 issue, `device_license_screen_test.dart`
tetap lolos (4/4, tidak ada assersi count yang kena panel baru ini).

_Update sesi 29 Agustus 2026 (lanjutan lagi x2 — 2 lapis deteksi baru
gerbang lisensi: manipulasi jam base-offset + clone device fisik),
commit `a539f0b`, versi kerja **2.19.19+44**, di-push & di-merge ke
`main`.

**Konteks**: susulan diskusi keamanan lisensi sesi ini (lihat entri di
bawah utk diskusi awalnya) — user minta eksekusi 2 mitigasi yang
sebelumnya cuma dianalisis/dirancang (sengaja TIDAK masuk `PLAN.md`,
langsung diminta eksekusi).

**1. Manipulasi jam (base-offset)**: `LicenseNotifier._fetchLiveStatus`
(gabungan `_fetchRevokedStatus` lama, SATU request yang sama, tidak
nambah beban) sekarang juga baca header `Date` respons `revoked.json`
sbg jam server tepercaya, dibandingkan ke jam device
(`computeClockManipulated`, toleransi 24 jam, null/fail-open kalau
header hilang/gagal parse/offline). Field baru `LicenseState.
clockManipulated`, dicek di `_checkRevocation()` rutin (BUKAN di jalur
`activate()` — sengaja dibatasi scope spt diminta user).

**2. Clone device fisik**: `Settings.Secure.ANDROID_ID` (channel native
baru `com.thepos/device_id` di `MainActivity.kt`, wrapper Dart
`DeviceIdService`) direkam sbg baseline SEKALI saat `load()` pertama
kali melihat fingerprint (fresh install MAUPUN update dari versi app
LAMA sebelum fitur ini ada — keduanya "adopt baseline baru", BUKAN
mismatch, krn belum ada apa pun utk dibandingkan). `load()` berikutnya
bandingkan ANDROID_ID sekarang vs baseline (`computeDeviceMismatch`) —
beda → `deviceMismatch=true`, menutup `isLocked`. Fail-open total kalau
channel gagal (bukan Android/error) — TIDAK PERNAH mengunci krn
ketidaktahuan.

**Keputusan desain penting**: `AktivasiScreen` TIDAK disentuh — layar
itu SUDAH sengaja pakai pesan generik utk SEMUA alasan terkunci (dok
di file itu: "tidak membocorkan mekanisme, tidak terkesan menuduh"),
jadi 2 kondisi baru otomatis ikut pola yang sama tanpa kerja tambahan.
`LicenseState` dapat method `copyWith` baru (dipakai `_touchLastSeen`/
`activate`/`_checkRevocation`) supaya field baru tidak gampang
kelupaan ditulis ulang di reconstruction manual yang sebelumnya
berulang di 4 tempat.

**Test**: 9 pure-logic baru (`computeClockManipulated` 5 skenario incl.
device lebih maju/header rusak, `computeDeviceMismatch` 4 skenario,
`isLocked` 3 skenario) di `license_service_test.dart` — semua
revert-verified. 4 test integrasi baru `license_device_binding_load_
test.dart` (mock `MethodChannel('com.thepos/device_id')` +
`SharedPreferences.setMockInitialValues`): fresh-install adopt-baseline,
match, mismatch (+ `isLocked` ikut true), channel-error fail-open — 2
skenario terakhir revert-verified. **Channel native (Kotlin) TIDAK bisa
diverifikasi otomatis** di sesi ini — butuh device Android asli (sama
spt fitur printer Bluetooth lain), cuma tervalidasi lewat compile
Kotlin (implisit via `flutter analyze`/build) + fail-open Dart-side
sudah teruji kalau channel belum ada. Tidak ada entri PATCHNOTES.md
(pola konsisten dgn internal lisensi lain — revoked-check awal juga
tidak pernah masuk situ, murni plumbing keamanan bukan fitur yg
dirasakan pengguna normal). Full suite 1181 lolos / 1 gagal (flaky
pre-existing `proposal_unchanged_end_to_end_test.dart`, lolos
terisolasi), `flutter analyze` 0 issue.

_Update sesi 29 Agustus 2026 (lanjutan lagi — buang fitur scan kamera
+ tambah opsi input manual di tab Data Pelanggan), commit `d3299d4`.

**Scan kamera dibuang**: fitur scan QR sidik jari via `BarcodeDetector`
("Scan Serial dari HP Pelanggan") dibuang total dari
`scripts/license-generator.html` — dilaporkan user sudah tidak
berfungsi. Ketik manual fingerprint (field yang sudah ada) tidak
terpengaruh, tetap jalan normal.

**Input manual Data Pelanggan**: tombol "+ Tambah Manual" di tab Data
Pelanggan — form catat pelanggan LANGSUNG (nama wajib, device/
fingerprint/masa-berlaku/catatan semua opsional) TANPA lewat alur
generate kode aktivasi. Alasan: user sudah punya pelanggan yang
aktivasi SEBELUM fitur pencatatan ada, tidak mau/perlu generate ulang
serial cuma utk masuk daftar. `addCustomerRecord` diperluas terima
`catatan` opsional (dipakai bareng oleh alur generate maupun manual).

_Update sesi 29 Agustus 2026 (lanjutan — tab Data Pelanggan di alat
license generator), commit `4a49037`.

**Konteks diskusi**: user tanya soal celah keamanan gerbang lisensi
(uninstall+reaktivasi serial sama utk akali expired). Diklarifikasi:
fingerprint acak 128-bit dibuat ulang tiap fresh-install & terikat
kriptografis ke kode (`license_service.dart:116`), jadi vektor itu
SUDAH gagal dgn sendirinya (bukan celah nyata). Dua celah residual yg
lebih valid didiskusikan (freeze jam via base offset 1x-set, clone
data app via tool bawaan pabrikan OEM) — BELUM dieksekusi (baru
sebatas analisis, user pending review sebelum masuk `PLAN.md`).

**Yang DIEKSEKUSI sesi ini**: ide lain user — manfaatkan
`scripts/license-generator.html` (alat offline terpisah, TIDAK
disentuh app) sbg tempat catat siapa saja yg sudah aktivasi, supaya
developer tidak cuma mengandalkan ingatan/reminder manual utk lupa
revoke. Tab baru "Data Pelanggan": form generate dapat 2 field baru
(Nama Pelanggan/Toko + Nama Device opsional, device dipisah krn 1
pelanggan bisa sah pakai >1 HP), tiap kode dibuat otomatis tercatat 1
baris (localStorage key `thepos_license_customers_v1`), status Aktif/
H-7/Lewat dihitung ulang tiap render dari `exp` (bukan disimpan),
"Revoked" bisa ditandai manual (PENANDA LOKAL saja, TIDAK auto-nulis
`revoked.json` — itu tetap manual terpisah), tombol Hapus per baris,
cari/filter, ekspor CSV. Backup disatukan ke file cadangan kunci
privat yg SUDAH ADA (field `customers` baru di JSON, backward-compat
dgn backup lama tanpa field itu). Banner "cadangan tidak sinkron"
muncul kalau ada perubahan sejak backup terakhir.

**Cara diverifikasi**: file ini TIDAK masuk suite `flutter test` (HTML/
JS statis di luar app) — dites manual via Playwright headless
(`chromium` di `/opt/pw-browsers`, plus symlink `node_modules/
playwright` krn `playwright` cuma terpasang global di node22, bukan
lewat npm project lokal): generate keypair → isi nama/device/
fingerprint → buat kode → baris otomatis muncul di tab → unduh
cadangan (cek JSON ada `customers`) → toggle revoked → unduh cadangan
lagi (`revoked:true` ikut) → impor di halaman fresh (`localStorage`
dikosongkan) → data pelanggan pulih utuh, `revoked` ikut benar. Nol
console/page error di semua langkah. Tidak bump `pubspec.yaml` (alat
ini di luar build APK, tidak ikut versi rilis app).

_Update sesi 29 Agustus 2026 — statistik detail produk kini konversi
qty ke satuan dasar utk produk >1 satuan, commit `1b6dd8b`, versi kerja
**2.19.18+43**.

**Konteks**: user tanya "kalau produk >1 satuan (mis. Indomie pcs/dus),
gimana tampilnya di laporan tren penjualan produk?" — jawaban investigasi:
`getProductStatsSummary`/`getProductDailySales` (`app_database.dart`)
cuma `SUM(ti.qty)` mentah digabung lintas SEMUA satuan tanpa konversi
(2 dus + 20 pcs = "22", padahal 1 dus bisa puluhan pcs) — bukan bug yg
dilaporkan sebelumnya, murni ditemukan pas baca kode. User lalu minta
fix: total dikonversi ke satuan DASAR, plus keterangan satuan lain yg
ikut terjual.

**Fix**: `qtySold` (ringkasan & tiap titik tren harian) dikonversi ke
satuan dasar (`ti.qty * ratioToBase`, via `LEFT JOIN product_units`,
fallback ratio 1.0 kalau `product_unit_id` tak ketemu/`ratioToBase`
tak valid). `ProductStatsSummary` dapat 2 field baru: `unitName`
(nama satuan dasar, helper baru `_baseUnitNameOf`) & `unitBreakdown`
(List satuan NON-dasar yg ikut terjual, qty MENTAH apa adanya dlm
satuan itu sendiri — BUKAN dikonversi, ini yg jadi "keterangan"-nya).
UI (`product_stats_screen.dart`) tampilkan value StatTile jadi "100 pcs"
+ `caption` baru "dari itu: 3 dus" kalau `unitBreakdown` tidak kosong;
label tooltip tren ikut sertakan nama satuan. `StatTile` (`stats_common
.dart`) dapat parameter `caption` opsional (baris kecil di bawah value).

**Gotcha ditemukan saat nulis test**: `AppDatabase.beforeOpen` SUDAH
seed `unit_types` default (`_kDefaultUnitTypes`, id 2="Pcs", id 14=
"Dos", dkk) di SETIAP instance baru termasuk `NativeDatabase.memory()`
test — insert `unit_types` baru dgn id manual (mis. id 1/2 sendiri)
akan BENTROK PK dgn seed itu. Fix test: pakai `unitTypeId` yg SUDAH ada
dari seed (2/14), jangan insert `unit_types` baru sama sekali.

Test baru `detail_stats_query_test.dart` (2, revert-verified: assersi
gagal tepat sasaran — 22 bukan 100, 1 bukan 40 — saat konversi
dikembalikan ke SUM mentah sementara). `detail_stats_screen_test.dart`
diperbarui (assersi `find.text('3')` → `find.text('3 satuan')`, krn
produk uji di situ tak punya baris `product_units` sama sekali →
fallback nama satuan "satuan"). **Kecelakaan proses sesi ini**: sempat
salah jalankan `git checkout -- app_database.dart` utk membatalkan
eksperimen revert-verify SEMENTARA (sengaja balikin ke SUM mentah utk
buktikan test gagal) — perintah itu ikut membuang SEMUA perubahan fitur
asli di file yg sama (bukan cuma eksperimen sementara), harus ditulis
ulang dari awal. **Pelajaran: JANGAN pakai `git checkout --` utk
undo eksperimen revert-verify kalau ada perubahan LAIN yg belum
di-commit di file yang sama — edit manual balik (atau `git stash`)
lebih aman.** Full suite 1165 lolos / 1 gagal (flaky pre-existing
`proposal_unchanged_end_to_end_test.dart`, lolos terisolasi saat
diverifikasi ulang), `flutter analyze` 0 issue.

_Update sesi 23 Agustus 2026 (lanjutan lagi x8 — dropdown saran
pelanggan struk MASIH tidak bisa discroll, putaran ke-2), commit
`2ab6a29`, versi kerja **2.19.17+42**, sudah di-push & di-merge ke
`main`.

**Akar SEBENARNYA** (fix sebelumnya `fffa8d0` cuma menyelesaikan
SEBAGIAN): `_onCustQueryChanged` (`receipt_screen.dart`) memotong hasil
pencarian `.take(5)` — pelanggan ke-6+ yang cocok TIDAK PERNAH masuk
`_custSuggestions` sama sekali, jadi widget-nya boleh saja SUDAH
genuinely scrollable (fix putaran 1 benar), tapi dari sudut pandang
user efeknya tetap identik "tidak bisa discroll" — scroll tidak akan
pernah memunculkan data yang memang sudah dibuang sebelum sempat
dirender. Fix: cap dibuang total, samakan dgn `payment_screen.dart::
_searchCustomers` yang SUDAH BENAR sejak awal (tanpa potongan sama
sekali, murni mengandalkan scroll).

**Pelajaran metodologis (penting utk sesi depan)**: kalau user lapor
bug "masih terjadi" SETELAH fix sebelumnya sudah di-merge, JANGAN
asumsikan fix sebelumnya salah/tidak jalan — cek dulu apakah ada
SUMBER LAIN yang menghasilkan gejala PERSIS SAMA dari sudut pandang
user. Di sini widget scroll-nya sendiri 100% benar (test putaran 1
masih lolos semua), akar masalah kedua ini di lapisan yang SAMA SEKALI
BEDA (data-fetching, bukan rendering) — keduanya kebetulan
menghasilkan keluhan yang terdengar identik ("tidak bisa discroll").
Bandingkan implementasi dgn fitur SERUPA yang sudah established
(`payment_screen.dart`) baris-per-baris, bukan cuma pola widget-nya.

Test `receipt_customer_dropdown_scroll_test.dart` diperbarui (seed 8
pelanggan, bukan berhenti di 5) + 1 test baru "pelanggan ke-6+ harus
bisa dijangkau via scroll" — revert-verified. Full suite 1162 lolos /
1 gagal (flaky pre-existing, lolos terisolasi), `flutter analyze` 0
issue.

_Update sesi 23 Agustus 2026 (lanjutan lagi x7 — fix dropdown saran
pelanggan di struk in-app tidak bisa discroll, putaran 1), commit
`fffa8d0`, versi kerja **2.19.16+41**, sudah di-push & di-merge ke
`main`.

**Bug**: user lapor field inline edit "Pelanggan" di struk in-app
(`_buildCustomerEditor`, `receipt_screen.dart`) — dropdown sarannya
tidak bisa discroll sama sekali. Akar: dropdown dirender `Column` polos
(TIDAK PUNYA mekanisme scroll SAMA SEKALI), beda dari dropdown
pelanggan checkout (`payment_screen.dart`) yang SUDAH BENAR pakai
`ListView.builder` dibungkus `maxHeight`. Fix menyamakan pola: `Container
(constraints: BoxConstraints(maxHeight: 240)) > ListView.builder
(shrinkWrap: true)`, plus `Scrollable.ensureVisible` via `GlobalKey`
(`_scrollCustIntoView`, disalin dari `_scrollCustIntoView` milik
`payment_screen.dart`) supaya field+dropdown ikut naik di atas keyboard.

**Gotcha test BARU yang ditemukan sesi ini**: cap saran dibatasi 5
(`_onCustQueryChanged`), dan tiap baris (nama+alamat, 2 baris teks)
TERNYATA muat nyaman di bawah 240px pada ukuran font DEFAULT — widget
test dgn 8 pelanggan seed awalnya gagal membuktikan drag benar-benar
menggeser scroll (`maxScrollExtent` = 0, konten belum overflow sama
sekali). Fix test: paksa `textScaler: TextScaler.linear(2.2)` via
`MediaQuery` custom (BUKAN `pumpWithFakeApp` biasa) supaya overflow
terjadi SCR DETERMINISTIK, baru drag+assert posisi scroll berubah.
**Kalau nanti test serupa (butuh membuktikan sesuatu genuinely
overflow/discroll) terasa flaky/pas-pasan lolos di font default,
paksa textScaler besar dulu — jangan nebak-nebak jumlah item/panjang
teks sampai "kebetulan" pas melebihi viewport.**

Test baru `receipt_customer_dropdown_scroll_test.dart` (2) —
revert-verified (assersi `maxHeight`/`ListView` gagal tepat sasaran
saat `Column` polos dikembalikan). Full suite 1161 lolos / 1 gagal
(flaky pre-existing, lolos terisolasi), `flutter analyze` 0 issue.

_Update sesi 23 Agustus 2026 (lanjutan lagi x6 — pre-order bisa dirujuk
dari transaksi lain, usulan user langsung dari laporan bug Tempo/Lunas
di update sebelumnya), commit `53bb405`, sudah di-push & di-merge ke
`main`. Versi kerja **2.19.15+40**.

**Fitur**: pelanggan pre-order tanpa DP, lalu belanja lagi di nota
BERBEDA — sekarang ada link ke nota ASLI tempat pre-order dicatat, di
2 titik (dikonfirmasi lewat `AskUserQuestion` sebelum eksekusi):
1. **Cart bar** — pemicu begitu nama pelanggan DIPILIH (bukan menunggu
   produk yang sama masuk keranjang). Kalau pelanggan py >1 pre-order,
   SEMUA ditampilkan (bukan cuma yang paling relevan), kasir pilih
   sendiri mana yang mau dibuka.
2. **Struk in-app** — nama item yang produknya cocok dgn pre-order
   TERBUKA milik pelanggan nota ini (di NOTA LAIN) jadi bisa diklik.

**Keputusan desain penting**: pencocokan "pelanggan yang sama" TETAP
lewat `PreorderEntries.customerName` (text match, sama seperti
`getLaciMejaPending` yang sudah ada) — SENGAJA TIDAK memakai resolusi
identitas "live" via `transactions.customerId` (pola fix "nama ikut
nota" sesi sebelumnya) krn pre-order MEMANG dari awal cuma py
`customerName` sbg identitas, menambah mekanisme baru di sini cuma
inkonsisten tanpa manfaat nyata.

**Detail teknis yang perlu diingat**:
- `PreorderPendingLine` dapat 2 field baru (`id`, `transactionId`) —
  SEMUA literal record yang mengonstruksinya (termasuk di test) WAJIB
  ikut diperbarui, Dart record tidak punya field opsional/default.
- Cart bar: `LaciMejaReminder.bar` berubah signature dari
  `(context, List<String> lines)` jadi `(context, LaciMejaPending?
  pending)` — HANYA 1 caller (`_CartBar` di `kasir_screen.dart`), aman
  diubah. Baris pre-order dirender `Wrap` dari `InkWell` (bukan
  `TapGestureRecognizer` manual) krn `LaciMejaReminder` widget statis/
  stateless — `InkWell` beres sendiri lewat siklus widget biasa, tidak
  perlu field State utk dispose spt recognizer.
- Struk in-app: SEBALIKNYA, `TapGestureRecognizer` DIPAKAI (bukan
  `InkWell`) krn span ini menempel di `Text.rich` yang sudah ada
  (menyatu dgn nama item, pola "Dititip"/"Titip [qty]" yang sudah ada
  duluan) — `InkWell` butuh widget tree terpisah, tidak bisa menyatu ke
  text-run yang sama. Recognizer DIPAKAI ULANG per `item.id`
  (`Map<String, TapGestureRecognizer>` field State, didispose di
  `dispose()`) — bikin baru tiap build tanpa dispose = bocor, pola sama
  `_linkRecognizer` di `inline_banner.dart`.
- `cart_bar_reminder_lines_test.dart` (test LAMA, bukan yang baru sesi
  ini) ikut pecah krn baris pre-order sekarang beberapa widget terpisah
  (`Wrap`), bukan 1 `Text` utuh — `find.text(...)` string gabungan
  persis tidak lagi match, diganti `find.textContaining` per fragmen.

Test baru `preorder_refer_previous_tx_test.dart` (11) — 3 skenario
revert-verified (guard exclude-self, span struk, link cart bar). Full
suite 1159 lolos / 1 gagal (flaky pre-existing, lolos terisolasi),
`flutter analyze` 0 issue.

_Update sesi 23 Agustus 2026 (lanjutan lagi x5 — fix bug status Tempo/
Lunas pakai kolom SALAH, SEMUA pre-order tampil "Lunas"), commit
`34a0424` — **JUGA masih hanya commit LOKAL, belum di-push/merge**
(instruksi user eksplisit "jangan commit ke github dulu, commit di
lokal saja sebentar lagi" — jangan push/merge sampai user minta
lanjut). Versi
kerja **2.19.14+39**.

**Bug**: user lapor "kenapa semua transaksi preorder tampil di card
sebagai lunas?". Akar: status Tempo/Lunas (baru ditambahkan sesi ini
juga, lihat update di bawah) salah pakai `depositQty` (jaminan WADAH
FISIK, mis. tabung kosong LPG) sbg penanda "sudah bayar". Ternyata
`item_entry_sheet.dart` (~baris 480-482) OTOMATIS mengisi
`depositQty = qty` penuh begitu toggle pre-order dinyalakan utk unit
`requiresDeposit` — TERLEPAS dari apakah DP (uang) benar-benar dibayar.
Hampir semua pre-order kebetulan py `depositQty > 0` → selalu "Lunas".

**Fix**: pakai `e.paid` (kolom `PreorderEntries.paid`, diisi dari
toggle "DP sudah dibayar" di form — `_dpPaid`/`preorderPaid` di
`item_entry_sheet.dart`, yang MENGENDALIKAN `_effectivePrice`: harga
jadi 0 kalau belum bayar). **Klarifikasi user yang PENTING utk desain
ini**: nota bisa berstatus "lunas" krn barang LAIN di keranjang yang
sama (pelanggan beli banyak barang), tapi baris pre-order itu SENDIRI
harus tetap "Tempo" kalau DP-nya belum masuk — jangan pernah dibaca
dari status nota (`transactions.status`), harus dari `paid` milik
entri pre-order itu sendiri.

**Pelajaran desain**: `depositQty` (jaminan wadah) dan `paid` (DP
uang) adalah DUA KONSEP TOTAL BERBEDA yang kebetulan sama-sama ada di
`PreorderEntries` — jangan pernah pakai salah satu sbg proxy yang lain
lagi ke depan, walau namanya sama-sama terasa "soal pembayaran".

Test lama (3, ditulis sesi sebelumnya dgn asumsi salah) ditulis ulang
total, termasuk 1 test regresi baru yang PERSIS mereproduksi laporan
user (jaminan wadah ada tapi belum bayar → harus tetap Tempo) —
revert-verified. Full suite 1148 lolos / 1 gagal (flaky pre-existing,
lolos terisolasi), `flutter analyze` 0 issue.

**Usulan fitur baru dari user (BELUM dianalisis/didesain, sesi
terputus di titik ini)**: link/referensi dari nota BERIKUTNYA (beda
nota) ke nota ASLI tempat pre-order-nya dibuat — skenario: pelanggan
dgn pre-order tanpa DP datang lagi, nama diinput di cart bar kasir,
sistem tawarkan opsi (hyperlink atau desain lain) merujuk ke nota lama
tempat pre-order itu dicatat, supaya kasir/owner bisa cek momen
transaksi asli. Perlu didesain: titik pemicu (saat nama pelanggan
dipilih di cart bar mana?), bagaimana mencocokkan "produk serupa" ke
pre-order yang masih terbuka milik pelanggan itu, dan bentuk UI-nya.

_Update sesi 23 Agustus 2026 (lanjutan lagi lagi lagi lagi — 2
penyesuaian status Tempo/Lunas Pre-order), commit `edafd77`, versi
kerja **2.19.13+38**. Susulan LANGSUNG dari update di bawah ini
(status Tempo/Lunas baru saja ditambahkan):
1. Keterangan "sudah bayar" (`e.paid`) DIHAPUS dari kartu — user bilang
   fungsinya sudah digantikan status Tempo/Lunas, dua-duanya
   berdampingan jadi redundan.
2. Posisi label dipindah dari ujung kanan baris (dulu `Row` terpisah)
   jadi menempel LANGSUNG setelah kata "jaminan" — `line2` dikembalikan
   ke `Text.rich` tunggal (desain SEBELUM percobaan `Row` di update
   sebelumnya). Kalau tidak ada jaminan sama sekali, menempel setelah
   nama produk (tidak ada kata "jaminan" utk ditempeli).

**Pelajaran kecil**: percobaan `Row` (ujung kanan) di update
sebelumnya ternyata bukan posisi yang diinginkan user — sekali lagi
bukti kalau ragu soal PENEMPATAN elemen baru (bukan cuma logikanya),
lebih aman tanya/tunggu konfirmasi daripada menebak tata letak "yang
masuk akal".

Test 2 di antaranya ditulis ulang total (posisi & isi teks berubah).
Full suite 1148 lolos SEMUA, `flutter analyze` 0 issue.

_Update sesi 23 Agustus 2026 (lanjutan lagi lagi lagi — status "Tempo"/
"Lunas" di kartu Pre-order + jawab pertanyaan soal transaksi void),
commit `570e3b5`, versi kerja **2.19.12+37**.

**Pertanyaan user (dijawab, tidak ada eksekusi diminta)**: apakah data
Laci Meja tetap ada & tersinkron kalau transaksi induknya dibatalkan
(void)? Jawaban: YA — `voidTransaction` (`app_database.dart:3069`)
HANYA mengubah `status` jadi `'void'`, TIDAK PERNAH menghapus baris
`transactions`. Ketiga tabel Laci Meja FK ke `transactions.id` TANPA
cascade, jadi baris Laci Meja tetap utuh & sync-nya berjalan independen
(last-write-wins by `updated_at`, tidak peduli status transaksi induk
sama sekali).

**Temuan sampingan yang DILAPORKAN ke user, BELUM diminta perbaiki**:
dashboard Laci Meja (`watchLeftBehindItems`/`watchBorrowedItems`/
`watchPreorderEntries`) TIDAK mengecualikan entri yang transaksinya
sudah void — query-nya cuma filter status selesai
(`collectedAt`/`fullyReturnedAt`/`fulfilledAt`), tidak join ke status
transaksi. Jadi nota yang dibatalkan tapi Laci Meja-nya belum
"selesai" tetap muncul menggantung di dashboard. **Kalau user minta
ini diperbaiki nanti**: perlu join/filter tambahan ke `transactions.
status != 'void'` di ketiga query watch, plus keputusan UX (apakah
entri Laci Meja milik nota void otomatis ditutup, atau cuma disaring
dari tampilan tanpa mengubah datanya).

**Perubahan kecil**: kartu Pre-order dashboard sekarang menampilkan
status "Tempo" (merah, `debtFg`) kalau TANPA jaminan/DP, atau "Lunas"
(hijau, `changeFg`) kalau ADA jaminan — di samping baris produk (H2).
`_preorderTile` line2 diubah dari `Text.rich` polos jadi `Row` (produk
`Expanded` + label status di ujung kanan). Sinyal ini independen dari
`e.paid` (checkbox manual "sudah bayar" di form pre-order) — keduanya
sengaja tampil berdampingan.

Test baru (2, revert-verified). Full suite 1147 lolos / 1 gagal (flaky
pre-existing, lolos terisolasi), `flutter analyze` 0 issue.

_Update sesi 23 Agustus 2026 (lanjutan lagi lagi — hapus tombol Batal
di kartu Pre-order dashboard), commit `1ffe791`, versi kerja
**2.19.11+36**. Permintaan user singkat: tombol "Batal" (ikon X,
`cancelPreorderEntry`) di kartu Pre-order `laci_meja_dashboard_screen.
dart` dihapus, hanya "Penuhi" tersisa. `cancelPreorderEntry` & aksi log
`'batal'` (PLAN.md Item 54) TIDAK dihapus dari DB — masih ada jalur
lain yang mungkin memakainya (sync/riwayat), cuma pemicu UI dari kartu
ini yang dicabut. **Tidak ada route khusus** utk aksi ini (dicek
`app_router.dart`, kosong) — murni `onPressed` inline, jadi tidak ada
yang perlu dibongkar di router. Full suite 1144 lolos / 2 gagal
(`proposal_unchanged_end_to_end_test.dart` flaky yang sudah lama
dikenal + `CryptoService decrypt dengan key salah gagal` yang JUGA
ternyata flaky, keduanya lolos sendiri terisolasi, tidak terkait
perubahan sesi ini), `flutter analyze` 0 issue.

_Update sesi 23 Agustus 2026 (lanjutan lagi — field "Nama barang" di
luar nota dukung multi-baris), commit `25f7090`, versi kerja
**2.19.10+35**. Perubahan kecil: `TextField` di `_showLeftBehindDialog`
(`receipt_screen.dart`) diberi `minLines:1, maxLines:null,
keyboardType: multiline, textInputAction: newline` supaya Enter bikin
baris baru (bukan submit/tutup keyboard) — user mau catat beberapa
barang sekaligus dipisah per baris. HANYA field ini yang diubah (qty,
nama pelanggan, field sejenis di dialog Pinjaman TIDAK disentuh).
Full suite 1146 lolos, `flutter analyze` 0 issue.

_Update sesi 23 Agustus 2026 (lanjutan — Laci Meja poin 1/2/5: ambil
parsial + riwayat per-nota + log global), commit `39c6e7f`, versi
kerja **2.19.9+34**. **KELIMA usulan Laci Meja user SELESAI SEMUA**
(poin 3 & 4 di blok berikutnya di bawah). PLAN.md Item 54 dihapus.

**Arsitektur (jangan didesain ulang)**: tabel BARU `laci_meja_events` —
satu baris per kejadian (`ambil`/`kembali`/`penuhi`/`batal`), TIDAK
PERNAH di-update. Sisa = `qty − Σ log`. Alasannya ada di dok tabelnya:
3 tabel Laci Meja itu master-data *last-write-wins*, jadi kalau "ambil
3 dari 5" ditulis sbg read-modify-write pada kolom qty, dua device yang
mengambil sebelum sync SALING MENIMPA dan satu pengambilan hilang
diam-diam. **Sinkronisasi tetap lewat antrian persetujuan owner**
(keputusan eksplisit user) — append-only di sini soal BENTUK data,
BUKAN jalur sync-nya. schemaVersion **33**.

**Keputusan turunan yang penting**:
- `borrowedItems.qtyReturned` DIPERTAHANKAN tapi jadi CACHE murni:
  `returnBorrowedItemQty` sekarang menghitung ulang dari log, bukan
  `+= delta`. Titip & pre-order SENGAJA tidak diberi kolom akumulator
  sejenis (dihitung on-the-fly lewat `getLaciMejaTakenQty`) supaya
  tidak ada cache kedua yang bisa menyimpang.
- Semua metode "tutup" lama (`markLeftBehindCollected`,
  `fulfillPreorderEntry`, `cancelPreorderEntry`) sekarang JUGA menulis
  baris log — kalau tidak, riwayatnya bolong. `fulfillPreorderEntry`
  mencatat SISA-nya saja (bukan qty penuh) supaya tidak dobel.
- `cancelPreorderEntry` menulis log qty **0**: pembatalan menutup sisa
  TANPA barang berpindah, jadi tidak boleh terhitung sbg "dipenuhi".
- Semua metode menerima `eventId` opsional — dipakai test (dan sync)
  untuk membuat baris log yang deterministik/identik antar device.

**Jebakan yang SUDAH ditangani (jangan dibuka lagi tanpa sadar)**:
- **Tutup Buku**: baris log dihapus DULUAN sebelum 3 tabel induknya.
  `entry_id` polimorfik → BUKAN FK fisik → SQLite tidak membersihkan
  sendiri; kalau induknya dihapus lebih dulu, log jadi yatim PERMANEN
  dan menumpuk tiap tutup buku. Ada testnya (revert-verified).
- **`applyLaciMejaProposals` dulu SELALU mencap `updated_at`** walau
  tabelnya tidak punya kolom itu — `laci_meja_events` memang tidak
  punya (delta-nya by `created_at`). Sekarang dicek `localColumns`
  dulu. Ini bug laten yang baru muncul begitu ada tabel usulan tanpa
  `updated_at`.
- **`dumpSince`** dapat cabang ketiga khusus tabel ini (`created_at`
  saja) — TIDAK boleh full-dump, isinya tumbuh terus seiring waktu.
- **Backfill migrasi v33**: `qty_returned` pinjaman lama jadi 1 baris
  log historis, id deterministik `bf-<id>`. Tanpa ini riwayat entri
  lama tampak kosong padahal qty sudah berkurang.

**Test superseded yang perlu diketahui**:
`laci_meja_proposal_unchanged_end_to_end_test.dart` — premis "host &
klien PERSIS sama" TIDAK lagi otomatis benar, karena "Dipenuhi" kini
juga menulis baris log; kedua sisi harus dikasih `eventId` yang SAMA
supaya benar-benar identik. Plus 16 `migration_v*_test.dart` ikut naik
ke 33 (ripple yang selalu terjadi tiap schemaVersion naik).

Full suite **1145 lolos SEMUA** (termasuk pasangan flaky
`proposal_unchanged`/`laci_meja_proposal_unchanged` — ikut hijau run
ini, JANGAN dianggap fixed permanen). `flutter analyze` 0 issue.

_Update sesi 23 Agustus 2026 (lanjutan — Laci Meja: nama ikut nota +
redesain kartu), commit `32713aa`, di atas versi kerja **2.19.7+32**.
Bagian dari **5 usulan fitur Laci Meja** yang user ajukan sekaligus.
Analisis + mockup Playwright sudah diberikan utk KELIMA poin; user
memilih dikerjakan **BERTAHAP — poin 3 & 4 dulu** (murah, tanpa migrasi
DB). **Poin 1, 2, 5 BELUM dikerjakan** (lihat blok "MENGGANTUNG" di
bawah).

**Poin 3 (bug) — nama pelanggan tidak ikut saat nota diubah.** Akar:
ketiga tabel Laci Meja simpan nama sbg SALINAN BEKU
(`customerNameText`, dan `PreorderEntries.customerName` yang bahkan
TIDAK punya `customerId` sama sekali), tidak pernah dicap ulang saat
nota berubah. **Keputusan desain penting**: TIDAK menambah jalur "cap
ulang" — utk device kasir itu berarti mutasi master-data → masuk
antrian persetujuan owner (lihat `dumpLaciMejaProposals`), padahal ini
cuma soal tampilan. Nama DIBACA HIDUP dari nota di sisi render:
`AppDatabase.getCustomerNamesForTransactions` (1 query utk ketiga
kategori) + `laciMejaCustomerNamesProvider`. Urutan fallback:
nama nota → salinan beku → "Umum". Konsekuensi bagus: entri LAMA yang
sudah terlanjur salah ikut terkoreksi, tanpa migrasi & tanpa backfill.

**Poin 4 — kartu 3 tingkat**: baris 1 nama pelanggan (H1 w800, jadi
HEADER kartu, tidak diulang per baris), baris 2 barang+qty (H2 w700;
pinjaman pakai "Sisa x dari y"), baris 3 timestamp `dd/MM/yyyy HH:mm`
(disamakan PERSIS dgn `receipt_screen.dart::_formatDateTime`) + umur
relatif berwarna yang lama TETAP dipertahankan. `ListTile` diganti
`_EntryRow` (kelas terpisah supaya widget test bisa menghitung baris
per kartu — pola `_MetaTabDivider`/`_VariantRow`). Grouping SENGAJA
tidak diubah (titip/pre-order per-nota, pinjaman per-pelanggan) supaya
pembagian grup tidak ikut bergeser.

**INSIDEN — kegagalan test terlewat di rilis sebelumnya.** Penghapusan
fitur Griyo/Cek Duplikat dilaporkan "1111 lolos + 1 gagal (flaky)",
PADAHAL ada 2 gagal: `laporan_pengaturan_accent_color_test.dart` masih
menuntut kartu seksi "Eksperimental" (amber) yang seksinya ikut
terhapus. Terlewat karena saat memeriksa hasil full-suite saya cuma
mencocokkan nama test yang sudah dicurigai (`proposal_unchanged`),
bukan MENDAFTAR SEMUA kegagalan. **Pelajaran: selalu ekstrak daftar
lengkap nama test gagal** (mis. `grep -oE "--plain-name '[^']*'"` atas
log, lalu `sort -u`) sebelum menyimpulkan "cuma flaky" — jangan
mencocokkan satu nama lalu berhenti. Sudah diperbaiki di commit ini.

**MENGGANTUNG — poin 1, 2, 5 (sudah dianalisis & disetujui arahnya,
belum dieksekusi).** Keputusan arsitektur yang SUDAH diambil user:
- **Pencatatan pengambilan = TABEL LOG APPEND-ONLY** (`laci_meja_events`
  atau sejenisnya), BUKAN mengurangi kolom qty. Sisa = `qty − Σ log`.
  Alasan: ketiga tabel Laci Meja itu master-data last-write-wins, jadi
  read-modify-write pada qty bikin dua pengambilan bersamaan (owner &
  kasir) SALING MENIMPA — salah satu hilang diam-diam di ledger barang
  fisik. Baris log tidak pernah bentrok. Sekaligus langsung memenuhi
  poin 2 (riwayat per-nota) & 5 (log global) dari tabel yang sama.
  Polanya = `transaction_payments`.
- **Sinkronisasi log TETAP lewat antrian persetujuan owner** (pilihan
  eksplisit user — BUKAN auto-merge append-only spt `transactions`).
  Tetap kompatibel: baris log tidak saling menimpa, hanya tampilan di
  HP owner yang baru berubah setelah di-approve.
- Poin 1 detail: `markLeftBehindCollected` & `fulfillPreorderEntry`
  saat ini semua-atau-tidak; **pinjaman SUDAH parsial**
  (`returnBorrowedItemQty` akumulasi `qtyReturned`) tapi tanpa jejak.
- Poin 2 detail: kartu per-nota utk titipan & pinjaman SUDAH ADA di
  `receipt_screen.dart` (`_buildLeftBehindOtherCard` ~3002,
  `_buildBorrowedCard` ~2964) tapi TANPA timestamp; **pre-order belum
  punya kartu sama sekali** di nota (cuma penanda inline "· Titip n").
- **Jebakan yang WAJIB diingat saat mengeksekusi**:
  `tutup_buku_service.dart` (~240-254) menghapus baris Laci Meja
  bersama notanya saat arsip — baris log baru WAJIB ikut dihapus di
  situ, kalau tidak jadi orphan permanen. Juga: `dumpLaciMejaProposals`
  pakai `SELECT *` dan `filterUnchangedLaciMejaProposals` membandingkan
  per-kolom, keduanya harus ikut disesuaikan. Dan data pinjaman lama
  (`qtyReturned` sudah terisi) perlu di-backfill jadi 1 baris log
  historis saat migrasi, kalau tidak riwayatnya tampak kosong padahal
  qty sudah berkurang.
- Estimasi storage log: ~150 byte/baris, 20 pengambilan/hari ≈ 1 MB/
  tahun — tidak signifikan.

_Update sesi 23 Agustus 2026 (lanjutan lagi lagi — avatar produk kasir
dibuat dark-aware), commit `971f647`, di atas versi kerja **2.19.6+31**
(akan di-bump lagi sebelum merge ke `main`). Susulan langsung dari
update di bawah ini (opsi B tint lembut) — user minta warnanya JUGA
dicek kompatibilitasnya di mode gelap. Ternyata palet light dipakai
APA ADANYA di dark: bg pastel terang (mis. `#F5E4DC`) di atas panel
gelap (`_dPanel #211E1C`) jadi tempelan mencolok, bukan "lembut" lagi
seperti maksud desainnya.

Fix: `_kAvatarPaletteDark` baru (`kasir_screen.dart`) — bg jadi warna fg
yang sama dengan alpha ~20% (`0x33RRGGBB`, dioper di atas panel gelap,
bukan solid), fg dicerahkan (mis. terracotta `#C96442`→`#E0916B`).
Mengikuti PERSIS pola pasangan warna dark-aware yang SUDAH ada di
`app_theme.dart` (`scanFg`/`scanBg`, `tealFg`/`tealBg`, dst — Item 33) —
bukan skema baru. `_avatarColorsFor` sekarang `(String name, bool
isDark)`, dipanggil dgn `Theme.of(context).brightness == Brightness.
dark` di kedua situs pemakaian (`_ProductCard`/`_ProductListTileState`).
Light mode TIDAK berubah sama sekali. Didahului mockup Playwright
(simulasi latar panel gelap sungguhan `#211E1C`, bukan cuma
"dark-mode-ish" hitam polos) yang dikirim & disetujui user sebelum
eksekusi.

`flutter analyze` 0 issue, full suite 1111 lolos + 1 gagal (flaky
pre-existing yang sama, bukan regresi).

_Update sesi 23 Agustus 2026 (lanjutan lagi — avatar produk kasir
dilembutkan + hapus 2 fitur: Import Griyo POS & Cek Duplikat Data),
commit `c0a570a`/`1740d68`, versi kerja **2.19.5+30** (akan di-bump lagi
di akhir sesi ini sebelum merge ke `main`).

**Avatar produk kasir** (`_ProductCard`/`_ProductListTileState`,
`kasir_screen.dart`): user minta warna dikurangi intensitasnya lewat
mockup Playwright 3 opsi (A: gradient -45% pastel huruf putih, B: tint
lembut ala chip bg muda+huruf solid, C: gradient -25% minim). User pilih
**opsi B** — `_kAvatarGradients`/`_gradFor` (2-warna gradient solid+huruf
putih) diganti `_kAvatarPalette`/`_avatarColorsFor` (record `{bg, fg}`,
bg tint sangat muda, fg warna solid aslinya, huruf TIDAK lagi putih).

**2 fitur dihapus** (permintaan user langsung, tanpa diskusi lebih
lanjut):
1. Settings > Eksperimental > Import dari Griyo POS — tile+route
   dihapus dari `pengaturan_screen.dart`/`app_router.dart`. Screen-nya
   (`csv_import_screen.dart`) DIPAKAI BERSAMA fitur "Import Produk CSV"
   biasa via flag `griyoMode` — flag & kedua cabang kondisionalnya
   dilucuti, sisa file jadi HANYA varian generik. `CsvImportService`
   TIDAK disentuh (parser tetap otomatis kenali skema legacy Griyo di
   balik layar, cuma UI-nya yang hilang).
2. Settings > Diagnostik > Cek Duplikat Data — tile+route+screen
   dihapus total (`duplicate_data_screen.dart` di-`rm`). Method DB
   eksklusifnya, `AppDatabase.findMasterDataDuplicates()` + class
   `MasterDataDuplicate` (`app_database.dart`), ikut dihapus karena
   dipakai HANYA oleh screen ini.

**Test dihapus** (bukan cuma trim): `csv_import_griyo_test.dart`,
`duplicate_data_screen_test.dart`, `experimental_flags_test.dart`
(seluruhnya soal flag Griyo yang sudah tidak ada lagi),
`master_data_duplicate_detection_test.dart` (menguji langsung
`findMasterDataDuplicates` yang baru dihapus — **catatan penting**:
agent Explore sempat salah menandai file ini sebagai "tidak terkait",
ternyata SALAH — selalu cek isi file test yang disebut ambigu, jangan
percaya begitu saja hasil grep judul/deskripsi).

`flutter analyze` 0 issue. Full suite 1111 lolos + 1 gagal (flaky
pre-existing `proposal_unchanged_end_to_end_test.dart`/
`laci_meja_proposal_unchanged_end_to_end_test.dart`, bukan regresi dari
perubahan sesi ini).

_Update sesi 23 Agustus 2026 — redesain lanjutan stepper +/- (lingkaran
solid dihilangkan saat di keranjang, ikon "+" idle dikecilkan), commit
`c0397ba`, di atas versi kerja **2.19.4+29** (belum di-bump lebih lanjut
di titik ini — tunggu akhir sesi). Didahului mockup Playwright (4
alternatif bentuk dikirim dulu — pill menyatu/chip lembut/kotak
membulat/minimal — SEMUANYA DITOLAK user, minta arah lain sama sekali)
lalu instruksi presisi user sendiri (3 poin), dieksekusi PERSIS sesuai
itu tanpa iterasi ulang mockup krn instruksinya sudah sangat spesifik.

**Perubahan bentuk (`add_control.dart`)**:
1. Idle (`qty==0`): bentuk & cakupan sentuh SAMA PERSIS, cuma ikon "+"
   dikecilkan (`circleSize * 0.5`, sblmnya `0.6`).
2. Di keranjang (`qty>0`): lingkaran solid (hijau di kanan/qty-plus,
   merah di kiri/minus) DIHILANGKAN TOTAL — `AnimatedContainer`/
   `Container` berdekorasi warna diganti `SizedBox` transparan
   (cakupan sentuh, via `circleSize`/`minusSize`, TIDAK ikut mengecil).
3. Warna kini melekat pada SISI (kanan="+"=hijau `AppTheme.changeFg`,
   kiri="-"=merah `AppTheme.debtFg`), BUKAN pada jenis konten (ikon vs
   angka) — konsekuensinya saat qty "pindah sisi" (perilaku `_qtyOnLeft`
   lama, TIDAK diubah sama sekali: tap "+" → angka pindah ke slot minus/
   kiri, tap "-" → kembali ke kanan), warnanya ikut berpindah bersama
   angka (jadi merah di kiri, hijau di kanan — bukan menempel ke "jenis
   konten qty" spt sebelumnya kesannya).

**Efek berantai yg perlu diingat**: logic lama `mainFg` (dark-mode
kontras teks putih vs teks gelap thd fill hijau muda mode gelap, dari
"Item 6" sesi jauh sebelumnya) jadi TIDAK RELEVAN LAGI krn fill-nya
sendiri sudah tidak ada — dihapus total, diganti langsung `AppTheme.
changeFg(isDark)`/`debtFg(isDark)` (keduanya sudah dirancang sbg
pasangan warna teks-aman utk kedua mode, TIDAK butuh pasangan fg/bg lagi
krn tidak ada background yg perlu dikontraskan).

**Test lama yang SUPERSEDED (bukan bug, memang sengaja dibalik)**:
`add_control_dark_fg_and_no_debounce_test.dart` (assersi warna putih vs
`0xFF0A3D28` diganti `changeFg(isDark)` di kedua mode) dan
`add_control_idle_flat_style_test.dart` (assersi "lingkaran KEMBALI
solid saat qty>0" DIBALIK jadi "TETAP tidak ada fill" — beda dari
desain ASLI 2 sesi lalu yg justru sengaja mengembalikan fill solid
begitu masuk keranjang; itu sekarang sudah tidak berlaku). Revert-
verified (kedua file gagal sensibel — `AnimatedContainer` masih
ketemu, warna masih lama — saat widget fix di-revert sementara).
Diverifikasi juga via render widget sungguhan (`RepaintBoundary.
toImage`) — ikon "+" idle kelihatan lebih kecil, tidak ada lingkaran
berwarna di state manapun.

Full suite 1127 lolos SEMUA (tidak ada kegagalan flaky kali ini),
`flutter analyze` 0 issue.

_Update sesi 22 Agustus 2026 (lanjutan lagi x4 — fix Ringkasan/Laporan
tidak auto-refresh setelah sync), commit `09ce02e`, versi kerja **2.19.3+
28** (belum di-bump lebih lanjut — tunggu akhir sesi), SUDAH di-merge ke
`main`. Juga catatan penting: **Flutter SDK di environment ini SEMPAT
HILANG TOTAL** di tengah sesi (`/tmp/flutter` kosong, kemungkinan `/tmp`
di-reset environment) — harus di-clone ulang. **WAJIB pin ke versi PERSIS
yang dipakai CI** (`.github/workflows/*.yml` → `flutter-action` →
`flutter-version: '3.24.5'`, BUKAN branch `stable` biasa — sempat salah
clone `-b stable` dulu yg ternyata jauh lebih baru [3.47.1] dan
memunculkan 87 warning deprecare + 1 error baru yg sama sekali tidak
terkait kode kita, murni krn API Flutter berubah). `git clone --depth 1 -b
3.24.5 https://github.com/flutter/flutter.git` ke `/tmp/flutter` beres.
**Efek samping jangan lupa dibersihkan**: `flutter pub get` pertama (pakai
SDK salah/3.47.1) menimpa `pubspec.lock` (25 dependensi bergeser versi)
DAN `analysis_options.yaml` (nambah blok `analyzer: exclude:` sendiri) —
KEDUANYA di-`git checkout --` sebelum commit supaya tidak ikut ke-commit
sbg noise tak disengaja. **Kalau flutter SDK hilang lagi di sesi
mendatang, ulangi resep ini: clone persis `3.24.5`, verifikasi
`git diff --stat pubspec.lock`/`analysis_options.yaml` kosong setelah
`pub get` pertama sebelum lanjut kerja.**

**Bug sync yang diperbaiki**: user lapor total pendapatan hari ini di
Ringkasan KLIEN tidak bertambah setelah klien sync dari host (skenario:
host sync dgn klien 1, beberapa transaksi lewat, host sync ke klien 2 —
di klien 2 angkanya "macet"). Diinvestigasi via agent Explore dulu (bukan
langsung nebak) — awalnya dicurigai gotcha lama `customStatement` tanpa
param `updates:` (sudah didokumentasikan CLAUDE.md), TERNYATA BUKAN itu:
`mergeRows` (`app_database.dart`) SUDAH benar kasih `updates: {table}` di
semua cabang. Akar SEBENARNYA: `_ringkasanProvider` (ringkasan_screen.
dart) & TUJUH provider tab Laporan lain (stok/arus_kas/hutang/pelanggan/
pengeluaran/produk/ringkasan_tab) semuanya `FutureProvider` BIASA — sengaja
dipilih krn query agregat berat (rentang tanggal, JOIN multi-tabel), tapi
konsekuensinya TIDAK PERNAH `.watch()` tabel apa pun, jadi TIDAK PERNAH
otomatis re-fetch kecuali dibuka pertama kali/refresh manual/ganti rentang
tanggal. `transaksi_tab.dart` (satu-satunya yg sudah `StreamProvider`)
TIDAK kena bug ini.

Fix: `dataSyncedTickProvider` (baru, `core/providers/data_refresh_provider.
dart`) — `StateProvider<int>` yg di-bump `SyncStateNotifier`
(`sync_state_provider.dart`) di DUA titik: `sync()` (klien menerima data
dari host) dan `approveSync()` (host menerima approve dari klien),
KEDUANYA hanya kalau `received > 0`. Kedelapan provider tsb sekarang
`ref.watch(dataSyncedTickProvider)` di baris PALING ATAS — pola ini
GENERIK, kalau nanti ada provider Ringkasan/Laporan baru yg juga
`FutureProvider` non-reaktif, tinggal tambahkan baris yg sama, TIDAK perlu
bikin mekanisme invalidasi baru lagi.

**Gotcha test BARU**: `pumpWithFakeApp` (helper umum) TIDAK mengekspos
`ProviderContainer`-nya (bikin `ProviderScope` sendiri di dalam), jadi
test yg perlu bump provider dari LUAR (spt `dataSyncedTickProvider`) WAJIB
bikin `ProviderContainer`+`UncontrolledProviderScope` sendiri (pola sama
dgn `cart_meta_index_tabs_test.dart`), BUKAN pakai `pumpWithFakeApp`. Lihat
`ringkasan_sync_refresh_test.dart`.

_Update sesi 22 Agustus 2026 (lanjutan lagi lagi lagi — logo QRIS cetak
dikecilkan LAGI, 35% -> 25%), commit `f878d90`, versi kerja **2.19.2+27**
(belum di-bump lebih lanjut — tunggu akhir sesi), SUDAH di-merge ke `main`.
User masih bilang "kecilin dikit" setelah pengecilan sebelumnya (55%->35%).
**Rasio ini MURNI pendekatan visual, bukan hasil kalkulasi presisi** (lihat
penjelasan lengkap di update sebelumnya persis di bawah ini) — kalau user
lapor lagi masih kurang pas, TURUNKAN LAGI rasionya, jangan cari "angka
yang benar" krn memang tidak ada cara menghitung lebar QR sungguhan dari
Dart. Test regresi kelipatan-8 (`printer_qris_logo_test.dart`) SENGAJA
sudah dilepas dari ketergantungan pada rasio spesifik (pakai lebar ganjil
generik 130px, bukan angka turunan `paperDots * rasio`) tepatnya supaya
tidak perlu diedit lagi tiap kali rasio ini disesuaikan ke depan — kalau
nanti diminta ubah lagi, CUKUP ubah angka `0.25` di `printer_service.dart`
tanpa perlu sentuh test sama sekali.

_Update sesi 22 Agustus 2026 (lanjutan lagi lagi — tab meta cart bar
disederhanakan jadi FLAT + logo QRIS cetak dikecilkan), commit
`e1db726`/`49a529f`, versi kerja **2.19.1+26** (belum di-bump lagi lebih
lanjut sesi ini — tunggu akhir sesi utk push+merge), SUDAH di-merge ke
`main`.

**Tab meta cart bar (`_CartMetaTab`) DIROMBAK LAGI** — kali ini bukan
sekadar koreksi geometri, tapi PENYEDERHANAAN TOTAL. Kronologi: desain
awal (single trapesium) -> "tab folder menumpuk" v1 (`2569a27`, arah
miring & urutan tumpuk salah) -> "tab folder menumpuk" v2 (`75a049c`,
sudah diukur presisi dari piksel referensi, arah & urutan BENAR) -> user
tetap bilang "masih belum sesuai ekspektasi" dan mengirim contoh KONKRET
utk ditiru PERSIS. Contoh itu ternyata JAUH lebih sederhana dari 2 versi
sebelumnya: EMPAT segmen RATA/DATAR dlm SATU baris (tanpa kemiringan
apa pun, tanpa efek "menumpuk"), dipisah garis vertikal tipis, sudut ATAS
baris membulat sbg SATU GRUP (bukan per-segmen). **Pelajaran utk sesi
depan**: kalau iterasi ke-2 berbasis pengukuran piksel presisi MASIH
ditolak user, jangan asumsikan butuh iterasi ke-3 yg makin canggih/rumit —
tanya/tunggu user kirim contoh konkret dulu, karena bisa jadi solusinya
justru JAUH LEBIH SEDERHANA dari yg sedang dikerjakan, bukan lebih rumit.

Implementasi baru: `_IndexTab`/`_IndexTabPainter` (`CustomPainter` jajar-
genjang + bayangan manual) DIHAPUS TOTAL. Diganti `Container` biasa
(`clipBehavior: Clip.antiAlias`, `borderRadius` cuma top-only, `border`
top+left+right, TANPA bottom — menyatu dgn garis atas `_CartBar` di
bawahnya persis pola lama) + `Row` + `_MetaTabDivider` (widget kecil baru,
cuma `Container(width:1)`, dibuat kelas terpisah SEMATA supaya test bisa
menghitungnya via `runtimeType.toString()`, pola yg sama dipakai
`_IndexTabPainter` sebelumnya). Segmen "Bayar" dapat `ColoredBox` lokal
(accent solid) — sudut kanan-atasnya OTOMATIS ikut membulat karena
`clipBehavior` induk, tidak perlu radius terpisah.

Diverifikasi visual via render widget SUNGGUHAN (`flutter test` +
`RepaintBoundary.toImage`, BUKAN mockup HTML) dibandingkan LANGSUNG dgn
contoh yg dikirim user (side-by-side crop) — cocok persis: baris flat,
divider tipis, sudut membulat sbg grup, Bayar solid di ujung kanan.

**Logo QRIS di struk cetak DIKECILKAN** (55% -> 35% lebar kertas) —
dilaporkan user "terlalu besar", target kira-kira seukuran kode QR
di bawahnya. **Catatan penting**: lebar QR sungguhan TIDAK BISA dihitung
persis dari kode Dart manapun di app ini — `gen.qrcode()` (esc_pos_utils_
plus) cuma kirim teks mentah + ukuran modul (4 dot/modul) ke command QR
NATIF printer (`GS ( k`), jumlah modul akhir (makin banyak makin lebar)
ditentukan printer sendiri dari panjang payload + level koreksi, bukan
dihitung di sisi app. Rasio 35% murni pendekatan berdasar feedback
visual user, BUKAN hasil kalkulasi presisi — kalau user lapor lagi masih
kurang pas (terlalu besar/kecil), sesuaikan rasio ini lagi, jangan cari
formula "benar" yg sebenarnya tidak bisa dihitung dari sini.

Test: `cart_meta_index_tabs_test.dart` — `countIndexTabs` diganti
`countMetaDividers` (jumlah segmen = jumlah divider + 1), assersi warna
Bayar/Tahan & no-crash marquee tidak berubah. `printer_qris_logo_test.dart`
— angka target lebar disesuaikan (384*0.35≈134, 576*0.35≈202), test
regresi kelipatan-8 dari fix sebelumnya (lihat update di bawah) TIDAK
berubah logikanya. Full suite 1126 lolos, `flutter analyze` 0 issue.

_Update sesi 22 Agustus 2026 (lanjutan lagi — koreksi bentuk tab indeks +
fix bug cetak QR gagal total), commit `75a049c`/`e6b215e`, di atas versi
kerja **2.19.0+25** (belum di-bump lagi, masih dianggap bagian rilis yang
sama — BELUM di-merge ke `main` di titik penulisan ini, tunggu akhir sesi).

**Bug printer WAJIB diketahui**: user lapor "printer terhubung, lampu
indikator nyala, tapi kertas tidak pernah keluar" — ternyata regresi
LANGSUNG dari fitur logo QRIS cetak yang baru ditambahkan sesi sebelumnya
(`1e56dd0`). Akar: `Generator._toRasterFormat` (esc_pos_utils_plus)
MEWAJIBKAN lebar bitmap kelipatan 8, kalau tidak cabang paddingnya sendiri
melempar `Unsupported operation: Cannot add to a fixed-length list`. Lebar
logo yg dihitung `_buildBytes` (55% lebar kertas: 384*0.55≈211 @58mm,
576*0.55≈317 @80mm) TIDAK PERNAH kebetulan kelipatan 8 — SELALU meledak
begitu toggle "Tampilkan QR Pelunasan" aktif, exception terjadi SEBELUM
byte apa pun terkirim ke channel native (tidak ada try/catch di
`printReceipt`), jadi TIDAK ADA snackbar error sama sekali — printer cuma
"diam" tanpa jejak kesalahan di UI. Fix: `_qrisLogo` membulatkan lebar
target ke kelipatan 8 terdekat (ke bawah) sebelum resize.
**Kalau nanti nambah gambar raster lain ke cetak ESC/POS (logo toko
custom, dll.) — WAJIB pastikan lebar akhir kelipatan 8 dulu, jangan
asumsikan `Generator.imageRaster` menangani sendiri.**

**Gotcha tooling BARU**: `testWidgets()` + `CapabilityProfile.load()`
(esc_pos_utils_plus, dipanggil test yg ingin memanggil `Generator` ASLI)
TERBUKTI HANG TANPA BATAS di environment ini (timeout 10 menit tercapai,
padahal step lain sebelum/sesudahnya sukses instan) — direproduksi manual
2x. Test yg butuh `CapabilityProfile.load()` WAJIB pakai `test()` biasa
(bukan `testWidgets()`), `TestWidgetsFlutterBinding.ensureInitialized()`
tetap dipanggil di `main()` kalau juga butuh `rootBundle` (itu sendiri
AMAN dipakai baik di `test()` maupun `testWidgets()` — bukan biang hang-nya).

**Koreksi bentuk tab indeks** (`_CartMetaTab`/`_IndexTabPainter`,
`kasir_screen.dart`): redesain sesi SEBELUMNYA (`2569a27`, "tab indeks
folder") ternyata **meleset jauh** dari referensi user meski sudah lewat
proses mockup — dicek ulang dgn membaca PIKSEL file referensi langsung
(bukan menerka dari ingatan/deskripsi), ternyata SALAH di 4 hal sekaligus:
tinggi tab (harusnya seragam, bukan staircase), urutan tumpuk (kanan
paling depan, BUKAN kiri), bentuk (jajar-genjang dua sisi sejajar miring,
BUKAN trapesium sisi kanan lurus), & arah kemiringan (bawah geser ke
KANAN relatif atas, sebelumnya kebalikannya — 2 iterasi mockup sempat
salah arah dulu sebelum ketemu yang benar). **Pelajaran metodologis**:
setelah 2x revisi mockup based-on-description tetap meleset, baru
efektif setelah baca file referensi via Python/PIL langsung (sampling
piksel boundary antar-warna di beberapa baris y) utk menentukan
geometri sebenarnya — jangan ulangi siklus tebak-revisi-tebak kalau
sudah 2x gagal, langsung analisis piksel.

Warna DIKEMBALIKAN ke default (`cs.surface`, sama dgn badan cart) utk
semua tab non-Bayar (revert dari soft-terracotta 0.07/0.12/0.17 sesi
sebelumnya) — permintaan user eksplisit ("warna ubah ke default sebelum
perubahan saja"), fokus koreksi memang murni bentuk. Sudut ATAS tiap tab
dibulatkan tipis (radius 3.5, `quadraticBezierTo`) — permintaan tambahan
user setelah bentuk disetujui. Bayangan seam antar-tab pakai linear
gradient manual di dalam `clipPath` (BUKAN `filter: box-shadow`/drop-
shadow CSS — waktu bikin mockup HTML, `filter:drop-shadow` TERBUKTI TIDAK
RENDER sama sekali kalau dikombinasikan dgn `clip-path` di headless
Chromium versi environment ini, diverifikasi via sampling piksel; solusi
paralel dipakai juga di Flutter: gradient manual, bukan efek shadow
bawaan).

**1 regresi test ditemukan & diperbaiki sebelum commit** (bukan dibiarkan
lolos): percobaan pertama menaikkan padding horizontal `_IndexTab` (utk
"center-kan teks", permintaan user) dari (8,4) ke (10,8) MENGGESER ambang
"muat/tidak" `_MarqueeText` sampai `cart_bar_bayar_button_test.dart` gagal
("Buk Khotimah" yg SEHARUSNYA baseline muat tanpa ambient-widening jadi
overflow duluan krn ruang kurang 6px). Padding dikembalikan ke (8,4)
semula — pusat teks sudah cukup ditangani `Center()` saja, tidak perlu
padding ekstra.

Test: `cart_meta_index_tabs_test.dart` comment diperbarui (bukan lagi
gradasi warna), assersi struktural TETAP tidak berubah. `printer_qris_
logo_test.dart` +2 test regresi (lebar dibulatkan kelipatan 8; panggilan
`Generator.imageRaster` ASLI tanpa exception) — keduanya revert-verified
(exception PERSIS `Unsupported operation: Cannot add to a fixed-length
list` muncul saat fix di-revert sementara). Full suite 1126 lolos SEMUA
(termasuk `proposal_unchanged_end_to_end_test.dart` yg biasa flaky — ikut
hijau run ini, jangan dianggap sudah fixed permanen tanpa bukti lebih
lanjut), `flutter analyze` 0 issue.

_Update sesi 22 Agustus 2026 — 3 permintaan sekaligus (stepper idle jadi
garis vertikal, redesain tab meta cart bar [KEMUDIAN DIKOREKSI LAGI —
lihat update di atas], logo QRIS di struk [KEMUDIAN ditemukan bug fatal —
lihat update di atas]),
versi kerja **2.19.0+25**, commit `2569a27`/`a68dc39`/`1e56dd0`, SUDAH
di-merge ke `main`. Semua didahului analisis + preview mockup sebelum
eksekusi (permintaan user eksplisit "Berikan analisa dulu... setelah
disetujui, berikan preview mockupnya").

**Poin 1 — ring putus-putus idle stepper dinilai masih terlalu tegas**
(susulan dari desain sesi sebelumnya). Diganti SATU garis putus-putus
VERTIKAL di kiri tombol "+" (`_DashedVLinePainter`, `add_control.dart`),
warna `outlineVariant` (bukan `onSurfaceVariant` yang setara teks —
`outlineVariant` adalah token pembatas paling samar yang sudah dipakai
di tempat lain di app ini). `_DashedCirclePainter` (ring melingkar)
DIHAPUS TOTAL, bukan disembunyikan.

**Poin 2 — redesain `_CartMetaTab`** (header cart-bar-shrunk: Pelanggan/
Pegawai/Tahan/Bayar) dari SATU tab trapesium tunggal jadi EMPAT tab
terpisah model "indeks folder" (mengacu contoh map folder yang user
kirim) — `_IndexTab`/`_IndexTabPainter`, tiap tab menjorok sedikit ke
tab di kirinya (diagonal negatif, `CustomPaint` tidak clip) supaya
saling mengunci tanpa celah segitiga. Warna terracotta SANGAT LEMBUT
(opacity 0.07/0.12/0.17, menguat ke kanan) KECUALI tab "Bayar" — sengaja
dikecualikan, tetap pekat + teks putih, supaya tidak kehilangan
penekanan sbg CTA di antara tab lain yang kini ikut berwarna (keputusan
eksplisit user: "Tombol bayar usahakan aksen lebih tegas, mungkin sama
seperti sekarang").

**2 bug NYATA ketemu & diperbaiki lewat render preview widget
SUNGGUHAN** (bukan cuma dibaca kodenya — mockup dibangun via
`flutter test` + `RepaintBoundary.toImage`, screenshot hasil beneran,
BUKAN mockup HTML seperti sesi sebelumnya):
1. Versi pertama pakai `IntrinsicHeight` utk menyamakan tinggi 4 tab —
   meledak "LayoutBuilder does not support returning intrinsic
   dimensions" krn `_MetaChip` mengandung `_MarqueeText` berbasis
   `LayoutBuilder`. Fix: tinggi tab dihitung EKSPLISIT dari skala teks
   sistem (`MediaQuery.textScalerOf`), bukan query intrinsik.
2. Padding vertikal GANDA (`_IndexTab` + `_MetaChip` sendiri) memotong
   teks nama pegawai/pelanggan — kelihatan jelas di screenshot preview
   ("Rina" terpotong). Fix: padding vertikal `_IndexTab` DIHAPUS TOTAL
   (cuma padding horizontal), tinggi sudah dipatok pemanggil & isi
   dirata-tengah `Center`.

**Poin 3 — logo QRIS resmi** (aset dikirim user via upload file, BUKAN
paste inline chat — paste inline TIDAK tersimpan sbg file yang bisa
diakses tool, harus attach sungguhan; ketahuan setelah investigasi
`/root/.claude/uploads/<session>/`). `assets/qris/qris_logo.png`
(1350x512, transparan, wordmark hitam solid — dipilih user dari opsi
resolusi zonalogo.com). Paket `image` naik dari transitif jadi
dependensi langsung.

**Bug nyata WAJIB diingat kalau nanti nambah gambar lain ke cetak
ESC/POS**: `Generator._toRasterFormat` (esc_pos_utils_plus, dipanggil
`imageRaster`) HANYA membaca kanal RGB via `grayscale()`+`invert()`,
TIDAK PERNAH melihat alpha. PNG dgn latar TRANSPARAN yang kebetulan RGB
(0,0,0) — sama seperti wordmark hitamnya sendiri — akan tercetak sbg
SATU BLOK PADAT kalau langsung di-raster tanpa komposit ke kanvas putih
solid dulu (alpha diabaikan total, tidak ada kontras RGB murni utk
dibedakan pipeline b/w-nya). `PrinterService._qrisLogo` sekarang WAJIB
`img.fill` (putih) + `img.compositeImage` sebelum `imageRaster` —
dibuktikan via revert-verification (skip komposit → test kontras gagal
sensibel: Expected >200, Actual 0). **Kalau nanti ada fitur cetak gambar
lain (logo toko custom, dll.) — cek komposit-ke-putih ini DULU sebelum
dianggap "tinggal print", jangan asumsikan alpha PNG otomatis
ditangani.**

Perbedaan disengaja poin 3 antara struk **share** (gambar) vs **cetak
thermal**: share pakai `Image.asset` biasa di `_ReceiptPaper` (widget
tree/RepaintBoundary menghormati alpha PNG apa adanya, TIDAK perlu
komposit manual); cetak pakai `_qrisLogo` yg komposit manual (krn masuk
pipeline raster ESC/POS yang alpha-blind). User TOLAK opsi "cukup teks
QRIS polos di cetak" (lebih aman/simpel) — insisten logo asli harus
works di kedua jalur.

Test baru: `printer_qris_logo_test.dart` (3) + `cart_meta_index_tabs_
test.dart` (4) + `add_control_idle_flat_style_test.dart` diupdate (ring
→ garis) + 1 assersi baru di `receipt_screen_qr_toggle_test.dart` (logo
di atas QR) — semua revert-verified. Regresi: 33 file test receipt/
printer + suite kasir/cart terkait tetap lolos. Full suite 1123 lolos +
1 gagal (`proposal_unchanged_end_to_end_test.dart`, flaky pre-existing,
lolos sendiri terisolasi), `flutter analyze` 0 issue.

**Insiden kecil (bukan bug kode)**: `add_control_press_scale_test.dart`
sempat gagal di full-suite run — BUKAN regresi app, murni artefak test
(`AddControl` idle sekarang lebih lebar krn ada garis vertikal baru;
test lama tap TITIK TENGAH widget yang jatuh di `ListView` dgn
constraint tight, titik tengah bergeser ke ruang kosong). Fix: tap ikon
"+" langsung, bukan titik tengah widget.

_Update sesi 20 Agustus 2026 (lanjutan lagi lagi lagi — REVERT perluasan
konfirmasi getar stepper ke tombol "+", `98ce883`/`4cd7f0c`), versi
kerja **2.18.0+24**, SUDAH di-merge ke `main`. Fitur "perluas konfirmasi
getar ke tombol +" (sempat dibangun & di-merge ke `main`, lihat riwayat
CHANGELOG) DIBATALKAN user setelah dipertimbangkan lagi — dikerjakan via
`git revert` (BUKAN reset/force-push, krn sudah terlanjur di-push &
merge sebelumnya), bersih tanpa konflik. Perilaku stepper baris
keranjang balik seperti semula: toggle "Konfirmasi sebelum kurangi qty"
HANYA menggerbang
tombol minus, tombol "+" selalu langsung menambah tanpa gerbang apa
pun. **Kalau nanti user minta lagi fitur serupa, jangan asumsikan
otomatis "sudah pernah dikerjakan tinggal reapply"** — user sempat
setuju lalu berubah pikiran, jadi tanyakan dulu apakah memang mau versi
yang SAMA persis atau ada penyesuaian.

_Update sesi 20 Agustus 2026 (lanjutan lagi lagi — stepper "+" idle jadi
ring putus-putus netral + flat, `008958d`), versi kerja **TETAP
2.18.0+24**. User: "stepper state idle di halaman kasir itu secara UI
terlalu over" — lingkaran solid terracotta+shadow di SETIAP kartu grid
sekaligus dianggap menyaingi info produk. User usul sendiri: hilangkan
lingkaran, sisakan "+" polos + aksen garis sobekan kertas di
sampingnya. **Saya negasikan** usul itu (bukan langsung eksekusi) —
alasan: menghilangkan lingkaran = menghilangkan afordansi tap, padahal
SESI SEBELUMNYA baru saja memperbesar stepper demi mengurangi missclick
— berisiko regresi. Diskusi berlanjut 3 putaran ("Lainnya?"/"Alternatif
lain?"), total 9 alternatif diajukan (ghost outline, chip bertinta,
pill gabung, badge sudut, netral->berwarna, dashed ring SEBAGAI stroke
tombol itu sendiri [bukan elemen terpisah — ini yang menjawab kritik
awal saya], flat tanpa shadow, dll). User pilih kombinasi **Alt.7
(netral idle -> berwarna begitu di keranjang) + Alt.4 (dashed ring,
bukan elemen dekoratif terpisah) + Alt.9 (flat, shadow dihapus total)**
— setelah saya kirim **mockup .jpg** (dibangun via Playwright/Chromium
headless yg sudah pre-installed di environment ini, render HTML lokal
lalu screenshot langsung ke JPEG — `page.screenshot({type:'jpeg'})`,
BUKAN convert PNG->JPG krn `ffmpeg` di environment ini dibuild TANPA
PNG decoder, cuma encoder) yang membandingkan 1 kartu (idle/di-keranjang,
sebelum/sesudah) DAN simulasi grid 6 kartu penuh — grid penuh inilah
yang paling meyakinkan (kepadatan visual idle vs sesudah baru kelihatan
jelas bedanya di situ, bukan di 1 kartu saja).

**Detail teknis yang perlu diingat**: `_DashedCirclePainter` (baru,
`add_control.dart`) menggambar ring via `Canvas.drawArc` berulang —
Flutter TIDAK punya border dashed bawaan. Jumlah segmen DIHITUNG dari
keliling lingkaran (`circumference / targetSegment`), BUKAN angka tetap
— supaya pola dashed menutup 360° tanpa "jahitan" di titik pertemuan,
dan tetap proporsional di semua ukuran stepper (32-52px, beda-beda per
grid/list/varian/keranjang sejak sesi stepper-resize sebelumnya). Warna
idle = `Theme.of(context).colorScheme.onSurfaceVariant` (netral,
konsisten dgn token yang sudah dipakai luas di app utk teks/ikon
sekunder). `boxShadow` DIHAPUS TOTAL dari `mainCircle` (bukan cuma saat
idle) — kesan "solid tapi flat" di state di-keranjang juga bagian dari
keputusan desain, bukan cuma efek samping.

Test baru `add_control_idle_flat_style_test.dart` (2) — revert-verified.
Full suite 1117 lolos SEMUA (kebetulan `proposal_unchanged_end_to_end_
test.dart` yg biasa flaky ikut hijau run ini — jangan dianggap sudah
fixed permanen), `flutter analyze` 0 issue. **Insiden testing kecil**:
sempat menjalankan `flutter test` foreground (visual check manual, file
sementara `_tmp_visual_check.dart`, sudah dihapus lagi — bukan bagian
commit) BERSAMAAN dengan full-suite run di background — gotcha CPU-
contention yang sudah didokumentasikan (lihat entri 14 Agustus di
bawah) — full-suite run PERTAMA (b2ppefxqz) karenanya tidak dipakai
sbg bukti, ditunggu sampai semua proses `flutter_tester` benar2 kosong
lalu diverifikasi ulang manual (hasil 1117 lolos semua di atas adalah
dari run itu, BUKAN dari run yang overlap).

_Update sesi 20 Agustus 2026 (lanjutan lagi — perbesar stepper +/- di
Kasir grid/list/varian, `c1d14f6`), versi kerja **TETAP 2.18.0+24** (fix
kecil, bagian rilis yang sama). User tanya "apakah stepper di tab kasir
juga ikut besar?" (jawaban: belum, cuma baris keranjang) — lalu minta
diterapkan juga krn keluhan missclick yang sama berlaku di sana.

Delta +14 YANG SAMA dgn stepper keranjang (bukan rasio baru) dipakai lagi
supaya konsisten: kartu grid 32->46, baris list 34->48, baris varian
28->42. `mainAxisExtent` grid (138->152) ikut ditambah +14 persis
(kartu grid TINGGI TETAP, beda dari baris list/varian yang mengikuti
isi) — kalau lupa, kartu grid overflow begitu stepper diperbesar lagi
di masa depan. Test baru `kasir_stepper_size_test.dart` (3, revert-
verified). Full suite 1113 lolos + 2 gagal (`proposal_unchanged_end_
to_end_test.dart`, flaky pre-existing, lolos sendiri terisolasi),
`flutter analyze` 0 issue.

Topik missclick stepper INI SENDIRI masih menunggu diskusi lebih dalam
(root cause / desain alternatif) sesuai permintaan user sebelumnya —
kedua perbesaran (keranjang + kasir) sama-sama masih mitigasi cepat,
BUKAN solusi final yang sudah didiskusikan.

_Update sesi 20 Agustus 2026 (lanjutan — fix swipe-turun macet di sheet
QRIS statis/toggle QR nota, `fb1e317`), versi kerja **TETAP 2.18.0+24**
(fix kecil, tidak bump baru), sudah di-merge ke `main`.
User lapor: sheet bayar tempo (state QRIS statis) & sheet Bagikan Struk
(QR pelunasan dinyalakan) TIDAK BISA ditutup via swipe turun, padahal
state lain di sheet yang sama bisa. Ditanya dulu apakah bisa diperbaiki
TANPA mengorbankan jarak keypad->tombol permanen (hasil Item 62)
sebelum eksekusi — user jawab "Eksekusi".

**Akar (temuan penting, dokumentasikan untuk sheet BARU nanti)**:
`showModalBottomSheet` bawaan cuma menghubungkan swipe-turun ke
`Navigator.pop` kalau isi TIDAK scrollable. Begitu `SingleChildScrollView`
di dalamnya beneran overflow (QR+keypad; struk gambar+QR di layar
pendek), gesture arena SELALU dimenangkan scrollable itu — dismiss-drag
bawaan tidak pernah kebagian giliran, TERLEPAS dari posisi scroll
(bukan cuma "pas lagi di tengah konten"). Ini limitasi umum
`showModalBottomSheet`+`SingleChildScrollView` polos (beda dari
`DraggableScrollableSheet` yang punya wiring internal sendiri) — **kalau
nanti ada sheet lain yang isinya scrollable & lapor swipe-close macet,
INI akar masalahnya, bukan bug baru.**

Fix: `NotificationListener<ScrollNotification>` membungkus tiap
`SingleChildScrollView` (`debt_payment_sheet.dart`,
`receipt_screen.dart::_showShareSheet`), mengakumulasi
`OverscrollNotification` (tetap terkirim walau `ClampingScrollPhysics` —
posisi tidak bergerak tapi notifikasi overscroll tetap dikirim) SELAMA
satu gesture drag; tarikan ke bawah melewati ambang -60px →
`Navigator.maybePop()` manual, reset saat `ScrollEndNotification`.
Meniru wiring internal `DraggableScrollableSheet` TANPA mengubah
struktur layout sama sekali — jarak keypad->tombol permanen TETAP utuh.

Test baru di `debt_payment_sheet_test.dart` + `receipt_screen_qr_toggle_
test.dart` — masuk ke state overflow, drag turun pada
`SingleChildScrollView`, assert sheet ter-pop — revert-verified 2x
(ambang dinaikkan mustahil tercapai → kedua test gagal sensibel). Full
suite 1111 lolos + 1 gagal (`proposal_unchanged_end_to_end_test.dart`,
flaky pre-existing, lolos sendiri terisolasi), `flutter analyze` 0 issue.

_Update sesi 20 Agustus 2026 — QR pelunasan di nota share & cetak
(`198518f`), versi kerja **2.18.0+24**, sudah di-merge ke `main`. Poin
ke-2 dari 4 permintaan susulan user (poin 1/3/4 di update sebelumnya di
bawah ini). Sheet "Bagikan Struk" (`receipt_screen.dart`) dapat toggle
"Tampilkan QR Pelunasan" -- HANYA muncul utk nota `tempo`/`kurang_bayar`
dgn metode QRIS aktif terkonfigurasi (`_eligibleForShareQr`); nota lunas/
void/retur: toggle sama sekali tidak ditawarkan. Menyalakannya
menampilkan toggle kedua "QR Dinamis" (default ON); QR dirender di
`_ReceiptPaper` di atas footer, TANPA nominal terpisah (beda dari
`_QrisDisplay` checkout, nominal sudah ada di baris "Sisa" nota itu
sendiri). **Nominal QR dinamis = SISA TAGIHAN (`netRemainingOwed`), BUKAN
total nota** — dikonfirmasi eksplisit user, jangan dibalik. Caption
"Mohon konfirmasi setelah membayar." di bawah QR baik di gambar struk
maupun cetak thermal. Kedua toggle persisten via SharedPreferences
(`receipt_show_qr`, `receipt_qr_dynamic`) — preferensi TAMPILAN milik
device, bukan data transaksi, tidak ikut sync — dan dipakai SAMA baik di
share-sheet (live, `StatefulBuilder`) maupun cetak thermal
(`_resolvePrintQrData`, dipanggil `_printReceipt`). `PrinterService.
printReceipt`/`_buildBytes` dapat param baru `qrData`, dicetak native via
`Generator.qrcode` (ESC/POS `GS ( k`).

**Belum diverifikasi**: printer murah kadang mengabaikan command QR
native — sudah diperingatkan ke user, belum ada laporan hasil cetak
nyata dari sesi ini atau sesudahnya. Kalau ada laporan QR tidak muncul di
struk cetak (bukan struk share/gambar), ini kandidat pertama yang dicek.

Nota GABUNGAN (`printMergedReceipt`) SENGAJA TIDAK dapat opsi ini —
dikonfirmasi user: pelunasan tempo cukup lewat Laporan > Hutang, nota
gabungan murni info total belanja yang SUDAH lunas. Reuse
`resolveQrisPayload`/`QrisQrBox` dari `payment_qris_view.dart` (dibangun
sesi sebelumnya) — tidak ada logika QRIS baru diketik ulang.

Test baru `receipt_screen_qr_toggle_test.dart` (4) — revert-verified 2x.
49 test struk terkait lain (regresi) tetap lolos. Full suite 1109 lolos +
1 gagal (`proposal_unchanged_end_to_end_test.dart`, flaky pre-existing,
lolos sendiri terisolasi), `flutter analyze` 0 issue.

**Dengan ini SELURUH 4 poin permintaan susulan user (toggle tema
aktivasi, QR nota share/cetak, layout kalkulator bayar tempo permanen,
label switch QR destinasi-bukan-state) + stepper diperbesar sudah
selesai & di-merge ke `main` sbg satu rilis** (bersama commit
`d9b3a31`/`6697931`/`29e8ea0` di bawah).

_Update sesi 18 Agustus 2026 (lanjutan lagi — toggle tema aktivasi, rapikan
sheet bayar tempo, perbesar stepper), versi kerja **2.17.0+23**, sudah
di-merge ke `main` (lihat update di atas utk kelanjutan poin QR nota).
4 permintaan sekaligus:

1. **Toggle terang/gelap di layar aktivasi (serial key)** — layar ini
   muncul SEBELUM `/setup`/DB bisa dibuka, jadi Pengaturan (tempat mode
   gelap biasa diatur) belum terjangkau. Ikon/tooltip menyebut TUJUAN
   (bulan = "ke gelap"), bukan keadaan sekarang.

   **Bug PRE-EXISTING ditemukan saat menguji tombol ini** (dibuktikan via
   probe: gagal juga kalau tema diganti langsung lewat provider, TANPA
   menyentuh tombol sama sekali) — akarnya di **`QrImageView` (qr_flutter
   4.1.0)**: melempar assert framework `'debugSize == size'`
   (text_painter.dart) kalau tema berganti selagi QR terlihat. Selama ini
   tak pernah terjangkau krn dari layar aktivasi memang belum ada cara
   ganti tema — tombol baru inilah yang membukanya. Dikunci pakai `key`
   yang ikut brightness, ditaruh di `QrisQrBox` (SEMUA QR app ikut aman,
   bukan cuma layar aktivasi) + `KeyedSubtree` di seluruh body layar
   aktivasi (`Text`/`SelectableText` di situ JUGA kena bug sejenis).
   **Kalau nanti nemu assert serupa di layar LAIN yang punya QR + tema
   bisa berganti selagi terlihat, ini akar masalahnya — bukan bug baru.**

2. **Sheet bayar nota tempo** (`debt_payment_sheet.dart`, dibangun sesi
   sebelumnya) dirapikan 2 hal: (a) jarak keypad->baris tombol kini
   PERMANEN — diganti dari `DraggableScrollableSheet` (pecahan tetap
   layar) ke `Column(mainAxisSize.min)` + `Flexible`+scroll (tinggi
   ikut isi, tombol mengalir tepat di bawah keypad, persis pola
   kalkulator checkout); (b) label tombol switch QR dibalik — sekarang
   menyebut TUJUAN bukan keadaan sekarang (state di statis -> tertulis
   "Nominal"). Toggle QR checkout (`Switch`) TIDAK ikut diubah — widget
   itu memang lazimnya menyatakan keadaan sekarang.

3. **Stepper +/- baris keranjang diperbesar** 30->44px (+~45%) — keluhan
   missclick. **User eksplisit ingin diskusi lebih dalam soal ini nanti**
   (root cause / desain alternatif) — perubahan sesi ini murni mitigasi
   cepat sementara, BUKAN solusi final. Jangan anggap topik ini selesai.
   Stepper produk grid/list/varian (`kasir_screen.dart`) SENGAJA tidak
   ikut diperbesar (beda konteks: nambah item baru, bukan ubah qty
   transaksi).

**Flaky family meluas**: `proposal_unchanged_end_to_end_test.dart` yang
biasa flaky ternyata punya saudara `laci_meja_proposal_unchanged_end_to_
end_test.dart` (pola sync proposal serupa) yang JUGA flaky pas dijalankan
bareng — keduanya lolos sendiri terisolasi, tidak terkait perubahan sesi
ini (subsistem beda total: sync proposal vs UI stepper). Kalau full-suite
nunjukkin salah satu/kedua gagal, cek dulu terisolasi sebelum curiga
regresi.

Poin QR nota tempo/share yang sebelumnya menggantung di sini SUDAH
selesai dikerjakan — lihat update `198518f` paling atas file ini.

_Update sesi 18 Agustus 2026 (lanjutan lagi — fix bucket metode Transfer
Bank), versi kerja TETAP **2.17.0+23** (user minta merge tanpa bump versi
baru, dianggap bagian rilis yang sama dgn sheet pelunasan hutang di
atas). Bug yang sudah diketahui dari audit tab Ringkasan sesi ini
(`AppDatabase._paymentBucket` cocok string 'transfer' yang tidak pernah
ada di data nyata — nilai asli 'bank') akhirnya diperbaiki: user sempat
lupa lalu minta "sekalian perbaiki" sambil menambahkan permintaan sheet
pelunasan hutang. Fix di 5 lokasi yg switch pada RAW `paymentMethod`
(`_paymentBucket`, `receipt_screen.dart` 2x, `transaksi_tab.dart`,
`printer_service.dart`) + 1 lokasi BARU yang ketemu saat re-audit sebelum
fix (`arus_kas_tab.dart` `_methodLabels`, key lokal ke
`getCashInByMethod` yang GROUP BY raw `method` juga) — TIDAK ketemu di
audit awal krn sumber datanya beda (query langsung ke `transaction_payments`,
bukan lewat `daily_summaries`). `ringkasan_tab.dart`/`report_export.dart`
SENGAJA tidak disentuh — key `'transfer'` di sana nama bucket internal,
sudah benar otomatis begitu sumbernya (`_paymentBucket`) diperbaiki.

Keputusan soal Tempo (pertanyaan yg saya ajukan ke user, tidak pernah
dijawab eksplisit): TERNYATA sudah dijawab sendiri oleh desain existing —
komentar tabel `DailySummaries` sudah eksplisit bilang e-wallet & tempo
sengaja masuk bucket "Lainnya" (cuma 4 bucket, bukan tabel baru). Jadi
tidak perlu tanya ulang, cukup dikonfirmasi & didokumentasikan ulang di
komentar kode + di sini.

Test baru `payment_bucket_transfer_bank_test.dart` (DB murni, 5 metode
sekaligus) — revert-verified. Full suite 1100 lolos SEMUA (termasuk yg
biasanya flaky `proposal_unchanged_end_to_end_test.dart` — kebetulan ikut
hijau run ini, JANGAN dianggap sudah fixed permanen tanpa bukti lebih
lanjut). `flutter analyze` 0 issue. Sudah di-merge ke `main`.

_Update sesi 18 Agustus 2026 (lanjutan lagi — sheet pelunasan hutang gaya
kalkulator checkout), versi kerja **2.17.0+23**, sudah di-merge ke `main`.
Dirancang bareng user lewat diskusi desain PANJANG sebelum eksekusi (user
menawarkan 2 opsi, saya sarankan opsi ketiga; salah paham saya soal scope
`hutang_tab` justru memunculkan insight yang user akui perlu — pelanggan
bayar 3 nota sekaligus besar kemungkinan pakai QRIS).

`debt_payment_dialog.dart` DIHAPUS, diganti `debt_payment_sheet.dart`,
dipakai di SELURUH 4 pemanggil (`receipt_screen`, `tx_history_sheet`,
`transaksi_tab`, `hutang_tab`) — bukan ditambah berdampingan, supaya
tidak ada 2 UI berbeda utk aksi identik.

**Keputusan desain yang PENTING diingat (jangan dibalik tanpa sadar):**
- QRIS di sheet ini default **STATIS**, beda dari checkout. Alasannya di
  pelunasan nominalnya justru yang belum diketahui — kasir mengetik dulu
  di mode statis (keypad tersedia), baru geser ke "Nominal" supaya angka
  itu terpatri di QR. Di checkout kebalikannya (total sudah pasti).
- Perilaku checkout "QRIS Nominal → lewati kalkulator, langsung lunas"
  SENGAJA TIDAK dibawa ke sini. Kalau ikut terbawa, cicilan sebagian via
  QRIS jadi mustahil — itu regresi nyata (kemampuan cicilan non-tunai
  sudah dikonfirmasi penting di awal sesi ini).
- Chip **Tunai tidak pernah meng-collapse** chip lain: ia gerbang masuk ke
  metode lain & tak punya metadata utk ditonjolkan.
- Geser ke dinamis SEBELUM mengetik apa pun → QR & nota pakai sisa penuh
  (`_qrAmount`). Keputusan saya sendiri, disetujui user di muka: QR
  bernominal nol tidak sah.
- Nominal TIDAK tereset saat toggle bolak-balik (permintaan eksplisit:
  salah pencet harus aman).

**Yang di-share vs yang sengaja TIDAK**: `payment_qris_view.dart` berisi
`resolveQrisPayload`/`QrisQrBox`/label-ikon-salin — dipakai bersama
checkout supaya tidak menyimpang diam-diam. TATA LETAK sengaja tetap
lokal di masing-masing layar (di checkout QR+toggle menyatu satu Card; di
sheet QR berpindah posisi & toggle tinggal di baris tombol bawah) —
memaksakan satu widget layout justru bikin parameter kondisional lebih
ruwet daripada manfaatnya.

**Gotcha test baru (2, kena keduanya di sesi ini)**:
1. `find.byType(OutlinedButton)` TIDAK match `OutlinedButton.icon` —
   `.icon` menghasilkan subclass privat. Pakai OutlinedButton polos + Row
   kalau tombolnya perlu ditemukan widget test.
2. `setSurfaceSize` TIDAK BOLEH dipanggil dari `setUp` grup (assert
   `inTest`), harus di dalam `testWidgets`. Dan surface default
   flutter_test (800x600) LEBIH PENDEK dari HP sungguhan — QR + keypad
   tidak muat, keypad ter-render di luar viewport & `tap` gagal
   "off-screen". Helper `pumpSheet` di `debt_payment_sheet_test.dart`
   sekarang selalu set 400x900.

**PR/utang teknis yang MASIH menggantung (belum dikerjakan, sudah
disetujui user utk dikerjakan)**: bug bucket metode pembayaran —
`_paymentBucket` (`app_database.dart:4423`) mencocokkan string
`'transfer'` yang TIDAK PERNAH ada di data nyata (nilai `type` yang
tersimpan adalah `'bank'`), sehingga Transfer Bank + E-Wallet + Tempo
SEMUANYA jatuh ke bucket "lainnya" dan `pembayaranTransfer` selalu 0.
Kena di 6 tempat (`ringkasan_tab`, `report_export`, `receipt_screen`,
`transaksi_tab`, `printer_service` yang malah cetak string mentah
"bank"). User sudah bilang "oke perbaiki" SEBELUM menyisipkan permintaan
sheet ini — jadi ini pekerjaan berikutnya. Masih perlu keputusan user:
apakah Tempo ikut dihitung di breakdown "Metode Pembayaran" (definisi
sekarang: omzet ditag per metode, Tempo ikut walau kasnya belum masuk)
atau dipisah/dikecualikan.

_Update sesi 18 Agustus 2026 (lanjutan lagi — QRIS nominal jadi fitur
TETAP + toggle Statis/Nominal + mode Nominal lewati kalkulator), versi
kerja **2.16.0+22**, sudah di-merge ke `main`. **User sudah menguji bayar SUNGGUHAN** lewat fitur
QRIS-nominal di bawah dan dana masuk normal ke NMID yang sama —
kesimpulan analisis sesi ini terbukti benar di lapangan, bukan cuma di
test. Konsekuensinya: label "Eksperimental" dibuang, caption kartu QR
diringkas jadi info operasional saja (peringatan "bukan server resmi /
tanpa kedaluwarsa" dipindah ke dok kode `qris_dynamic.dart`, tidak lagi
dipajang ke kasir tiap transaksi). Ditambah toggle `Switch` Statis ↔
Nominal di POJOK KANAN ATAS kartu QR.

**Keputusan desain yang saya ambil sendiri (user bilang "kerjakan" tanpa
merinci, jadi ini bisa direvisi kalau tidak cocok)**: pilihan toggle
disimpan PERSISTEN di setting `qris_dynamic_enabled` (default ON kalau
belum pernah diisi), BUKAN state layar sesaat — alasannya kasir tidak
perlu menggeser tiap transaksi, dan krn `app_settings` masuk kategori
sync masterData 'Pengaturan Toko', pilihan owner otomatis menyebar ke HP
kasir. Tanpa migrasi DB (key-value).

Permintaan user poin 3 ("app dipakai banyak toko, acuan pola dinamis =
value QR statis yang diinputkan") ternyata SUDAH terpenuhi sejak
implementasi awal — `injectQrisAmount` cuma menyentuh tag `01`/`54`/`63`,
identitas merchant (`26`/`51`/`59`/`60`/`61`) diteruskan apa adanya,
tidak pernah di-hardcode. Sekarang dibuktikan eksplisit lewat test
payload merchant BERBEDA (Warung Melati/SURABAYA, acquirer & NMID beda
total).

**Pelajaran berulang (2x kejadian di sesi ini)**: bikin fixture payload
QRIS dgn mengetik panjang TLV MANUAL selalu salah hitung → payload rusak
& test menguji hal yang salah (parser-nya benar, fixture-nya yang
bohong). Selalu bangun fixture lewat helper yang MENGHITUNG panjang
(lihat `tlv()` di `qris_dynamic_test.dart`).

**Celah nominal-QR-vs-ketikan-kasir SUDAH TERTUTUP** (dulu 2x saya angkat
sbg pertanyaan menggantung — sekarang terjawab oleh permintaan user
berikutnya, bukan oleh asumsi saya): di QRIS mode **Nominal**,
`_onBayarPressed` sekarang LANGSUNG `_confirm()` dgn `_tendered = _total`
TANPA membuka kalkulator sama sekali (`_isQrisNominalLocked`) — persis
perilaku non-tunai sebelum Item 62. Alasannya: jumlahnya sudah dipatri di
QR & pelanggan tidak bisa menguranginya saat scan, jadi kalkulator cuma
langkah tambahan tanpa guna sekaligus sumber ketidaksinkronan. QRIS mode
**Statis** TETAP lewat kalkulator (pelanggan ketik sendiri, bisa tidak
penuh). Metode non-tunai lain (bank/e-wallet) TIDAK ikut berubah — di
sana nominal tidak pernah terkunci di mana pun, jadi kalkulator tetap
wajib.

_Update sesi 18 Agustus 2026 (lanjutan — QR QRIS sisipkan nominal
otomatis, saat itu masih EKSPERIMENTAL), versi kerja **2.14.0+20**. Setelah fitur
kalkulator-non-tunai (di bawah) selesai, user tanya soal QR QRIS statis
vs dinamis (kirim 3 screenshot GoPay merchant tools: QR statis + 2 QR
dinamis dgn nominal terkunci Rp17rb/Rp20rb) — apakah pola dinamis bisa
"diakali" sesuai nominal belanja. **Penting: analisis awal SENGAJA tanpa
generate QR sungguhan** (`Bash` sempat diblokir classifier keamanan
sandbox saat mencoba benar2 generate file QR, walau cuma nominal Rp1000
milik toko sendiri utk testing — dihormati, tidak dicoba jalan memutar,
dijelaskan ke user). Analisis matematis murni (CRC-16/CCITT-FALSE +
struktur TLV EMVCo) dilakukan dulu pakai Python di scratchpad
(`qris_dynamic.py`, DILUAR repo) sblm user kirim 3 payload QRIS TEKS asli
dari HP-nya (1 statis + 2 dinamis, toko nyata "Toko Berkah, BNY NYR") —
dipakai memvalidasi analisisnya SEBELUM implementasi. Terbukti: beda
statis→dinamis PERSIS 3 tag (`01`:`11`→`12`, `54`:nominal disisipkan
stlh tag `53`, `63`:CRC ulang) — field lain byte-identik. Tag `62`
sub-`50` (token+timestamp proprietary GoPay) di luar spek EMVCo standar,
tidak direplikasi.

Implementasi: `lib/core/utils/qris_dynamic.dart` (CRC16 + parser/builder
TLV + `injectQrisAmount`, Dart murni, tervalidasi thd check value baku +
3 payload asli sbg fixture test). `_QrisDisplay` (`payment_screen.dart`)
coba sisipkan `_total` ke QR, sukses → badge "Eksperimental" + nominal +
caption peringatan (bukan resmi, tanpa verifikasi otomatis/kedaluwarsa);
gagal (`QrisTlvException`) → fallback diam2 ke QR statis polos (checkout
tidak boleh gagal krn fitur eksperimental). Test: `qris_dynamic_test.dart`
(6, fixture payload asli) + `payment_screen_qris_dynamic_test.dart` (2,
termasuk fallback payload rusak) — revert-verified 2x (CRC poly salah;
wiring `_QrisDisplay` dimatikan). **Catatan utk sesi depan**: cara test
teraman yg disarankan ke user = scan QR sampai layar konfirmasi nominal
di app e-wallet, LALU BATALKAN tanpa bayar — kalau nominal/nama toko
tampil benar, payload sudah pasti valid struktural tanpa perlu transfer
uang sungguhan. Belum ditanya: nominal QR yg dipakai saat kasir bayar
SEBAGIAN (partial via kalkulator non-tunai) — QR di-render SEBELUM
keypad dibuka jadi masih pakai `_total` penuh, belum ada refresh setelah
nominal di keypad beda dari `_total` (pertanyaan desain yg pernah
diajukan ke user, belum dijawab — jangan diasumsikan "sudah beres").

_Update sesi 18 Agustus 2026 — kalkulator bayar dipakai sama utk metode
non-tunai + tampilkan metadata rekening/akun (`1596283`), versi kerja
**2.13.0+19**. Sesi diawali 4 pertanyaan analisis user (dijawab dulu via
riset codebase langsung, TANPA kode, sesuai instruksi eksplisit "Analisis
dulu, jangan code"): (1) metode bayar BISA dihapus tapi digated —
`Tunai` tidak pernah bisa, lainnya wajib dinonaktifkan dulu; aman krn
`paymentMethod` di transaksi string mandiri, bukan FK; (2) non-tunai
DULU selalu dipaksa lunas exact hanya krn efek samping UI checkout (tidak
ada keypad utk non-tunai) — bukan validasi eksplisit; cicilan non-tunai
sudah lama bisa lewat "Tambah Bayar" pada nota existing, TIDAK bisa di
checkout awal; (3) "Alihkan Owner" = restore file backup terenkripsi
(BPOT1) penuh + rekey SQLCipher, BUKAN QR+LAN live; nomor nota tetap
koheren (deviceCode baru WAJIB dipilih manual saat import, historical
local_id ikut utuh dari dump); TIDAK ADA registry device sentral & TIDAK
ADA mekanisme un-pair/rotasi storeKey (gap yang sudah didokumentasikan
sendiri di PLAN.md item B.1) — risiko akumulasi deviceCode dobel/basi
kalau device hilang lalu reinstall pakai kode baru itu VALID & belum
ditangani, workaround resmi skrg cuma "Alihkan Owner ke identitas toko
baru"; (4) `PaymentMethods.data` (no. rekening/HP) sudah lama tersimpan
di skema TAPI tidak pernah ditampilkan ke kasir sama sekali (dikonfirmasi
lewat grep `payment_screen.dart` — cuma `qrValue` yang dibaca, `data`
sama sekali tidak direferensikan).

Setelah dikonfirmasi, user minta eksekusi poin (2)+(4) sekaligus: reuse
`_CashKeypadSheet` (sebelumnya cuma dipakai tunai) utk SEMUA metode
selain tempo — `_paid` disederhanakan dari `_selectedMethodType ==
'tunai' ? _tendered : _total` jadi murni `_tendered` (tempo tetap 0 via
guard `isTempo` terpisah, tidak disentuh). Kalkulator dapat badge
"Metode: <nama>" + ikon gembok (permintaan eksplisit "UI penanda ...
pembayaran apa yang dilock") krn sheet sekarang dipakai bergantian utk
semua metode. Widget baru `_PaymentMetadataDisplay` (pola sama
`_QrisDisplay`) menampilkan `PaymentMethods.data` + tombol salin saat
metode `bank`/`ewallet` dipilih di layar checkout. Ganti metode via chip
sekarang mereset `_tendered = 0` (bug laten yang baru kelihatan setelah
keypad dipakai bersama — nominal tunai lama bisa nyasar ke metode baru
kalau tidak direset).

Test baru `payment_screen_noncash_keypad_test.dart` (2: metadata metode
bank tampil di checkout; kalkulator non-tunai buka dgn badge kunci &
terima nominal kurang → status `kurang_bayar`) — revert-verified (`_paid`
dikembalikan ke formula lama, assersi status gagal sensibel `lunas` vs
`kurang_bayar`). **Catatan test**: surface size 400×900 SEMPAT dicoba dulu
lalu dilepas krn overflow RenderFlex di baris tombol bawah sheet
("Uang Pas" + "Catat Hutang Rp X") pada lebar sesempit itu — belum
ditelusuri apakah ini overflow nyata yang perlu diperbaiki di layar
sungguhan pada HP sempit (mirip gotcha `OutlinedButton`/`FilledButton`
lebar-penuh yang sudah didokumentasikan di CLAUDE.md) atau cuma teks
"Catat Hutang" yang memang panjang wajar dipotong `ellipsis`— PR/sesi
depan sebaiknya cek manual di HP sungguhan kalau nominal shortfall besar
(misal jutaan rupiah, teksnya makin panjang). Full suite 1077, `flutter
analyze` 0 issue.

_Update sesi 14 Agustus 2026 (lanjutan lagi — dialog Tahan Pesanan pakai
dropdown pelanggan, `d805143`) — versi kerja **2.12.0+17** (belum
dinaikkan lagi sesi ini). Permintaan user susulan dari tombol Tahan
Pesanan yang baru ditambah: dialog isi label (saat belum ada pelanggan
terpilih) HARUS "persis dropdown cart bar shrinked" — bukan dialog polos
terpisah. Diselesaikan dgn REUSE langsung `showCustomerPickerSheet`
(`cart_meta_pickers.dart`, sheet yang sama dipakai `_CartMetaTab` di
kasir_screen.dart) — bukan menulis ulang tampilannya. Konsekuensi bagus
yang TIDAK diminta eksplisit tapi logis: pelanggan TERDAFTAR yang dipilih
sekarang ikut disematkan ke `cartMetaProvider` (`setCustomer`), bukan
cuma dipakai sbg string label — payload `held_order` (`cartJson`) jadi
bawa `customerId` sungguhan, sama seperti nota yang checkout normal
(sebelumnya cuma nama, walau user pilih dari pelanggan terdaftar).
`_HoldLabelDialog` (StatefulWidget yang baru dibuat SESI SEBELUMNYA
persis utk menghindari bug dispose-timing) DIHAPUS TOTAL lagi — jadi
"berumur" cuma satu sesi, digantikan reuse yang lebih sederhana &
sekalian menutup gap fungsional (customerId). Pelajaran: kalau ada
permintaan susulan yang mengarah ke "pakai ulang komponen yang sudah
ada" SEBELUM menulis komponen custom baru, sebaiknya digali dulu di awal
— tapi dlm kasus ini permintaan awal user ("Tahan Pesanan") memang belum
menyebut soal dropdown pelanggan sama sekali, itu baru muncul di
permintaan susulan terpisah.

**Insiden testing (bukan bug kode, murni infra)**: 2 percobaan full-suite
berturut-turut menunjukkan kegagalan 15-21 test yang TIDAK PERNAH terlihat
sebelumnya — investigasi menemukan akarnya BUKAN regresi kode sama sekali,
melainkan DUA proses `flutter test` penuh (1071+ test masing-masing)
berjalan BERSAMAAN tanpa disadari (sisa proses background dari percobaan
sebelumnya yang gagal terdeteksi selesai + proses baru), berebut CPU
sampai banyak widget test yang sensitif timing/animasi gagal random.
Setelah dipastikan HANYA SATU proses `flutter test` berjalan (`ps aux |
grep flutter_tester` harus 0 sebelum memulai proses baru), full suite
kembali normal: 1073 total, 2 gagal (`proposal_unchanged_end_to_end_test.
dart`, flaky pre-existing lama, dikonfirmasi lolos sendiri terisolasi).
**Pelajaran utk sesi depan**: SELALU cek `ps aux | grep flutter_tester`
kosong dulu sebelum memulai full-suite run baru — kalau ada sisa proses
background dari percobaan sebelumnya (mis. karena command sebelumnya
di-background lewat `&` shell biasa yang lalu "hilang" dari tracking,
bukan lewat mekanisme background resmi tool), jumlah kegagalan yang
dilaporkan TIDAK BISA dipercaya sampai dijalankan ulang sendirian.

Test `cart_sheet_hold_button_test.dart` (8, ditambah revisi dari 6) —
revert-verified. `flutter analyze` 0 issue.

_Update sesi 14 Agustus 2026 (lanjutan — tombol Tahan Pesanan, `aa814d6`)
— versi kerja **2.11.0+16**. Permintaan user: tombol "Tahan Pesanan" di
header sheet Keranjang (`CartSheet`), di kiri "Tempel Pesanan" —
sebelumnya cuma bisa lewat tab folder `_CartMetaTab` di `kasir_screen.
dart` yang tersembunyi begitu sheet keranjang dibuka. Gerbang tampil
SAMA PERSIS dgn `_CartMetaTab`: cuma `kMainCartId` (mode Katalog bukan
transaksi sungguhan, mode Tambah Belanjaan ikut transaksi asli — tidak
ada konsep "tahan" terpisah utknya). Logikanya (`_holdCurrent`/
`_askHoldLabel`) SENGAJA DISALIN ke `cart_sheet.dart`, BUKAN dibagi lewat
fungsi bersama dgn versi `kasir_screen.dart` — versi lama terikat erat ke
state layar itu sendiri (`_heldPanelOpen`, banner kustom `_showBanner`),
menyatukannya lewat abstraksi baru berisiko mengubah perilaku yang sudah
berjalan tanpa ada yang memintanya (prinsip dipegang sepanjang sesi ini:
jangan refactor di luar yang diminta).

**Gotcha BARU (perlu diingat kalau bikin dialog lain yang dibuka dari
dalam bottom sheet)**: pola lama "buat `TextEditingController` di fungsi,
`showDialog`, lalu `ctrl.dispose()` di `finally` setelah Future resolve"
— PERSIS pola yang dipakai `_askHoldLabel` versi `kasir_screen.dart` —
KETANGKAP widget test baru (`cart_sheet_hold_button_test.dart`) sbg bug
nyata: "TextEditingController was used after being disposed". Akar:
dispose manual di `finally` bisa lebih cepat dari animasi TUTUP dialog
yang masih berjalan (`TextField` masih ter-render selama transisi
keluar) — KHUSUSNYA saat dialog dibuka dari dalam `DraggableScrollableSheet`
(dipakai `CartSheet`), yang punya lapisan animasi/rebuild sendiri saat
bottom sheet ikut menyesuaikan ukuran. Fix: pindah ke `StatefulWidget`
`_HoldLabelDialog` dgn `dispose()` sendiri (tied ke lifecycle Element
sungguhan, bukan timing resolve Future) — pola SAMA dgn
`debt_payment_dialog.dart` yang SUDAH benar sejak awal. **Versi
`kasir_screen.dart` (`_askHoldLabel` lama) TIDAK ikut diperbaiki** —
scope sesi ini cuma nambah tombol baru, bukan audit ulang dialog lama;
kalau nanti ada laporan bug serupa dari tab folder `_CartMetaTab`, ini
akar penyebabnya & fix-nya sudah ada contoh jadi (`_HoldLabelDialog`).

Test `cart_sheet_hold_button_test.dart` (6, widget) — revert-verified.
Full suite 1071 (2 gagal `proposal_unchanged_end_to_end_test.dart` — flaky
pre-existing, dikonfirmasi lolos sendiri kalau dijalankan terisolasi,
tidak terkait perubahan ini), `flutter analyze` 0 issue.

_Update sesi 14 Agustus 2026 — QR Transfer Transaksi diperkecil, Copy/
Share tetap lengkap (`0419df5`). Pertimbangan user (dijawab dulu via
analisis sebelum eksekusi, sesuai kebiasaan sesi ini): QR menumpuk/padat
& sulit di-scan kamera. Investigasi: gambar QR, tombol Salin, dan Share
di `_HandoffQrSheet` (`cart_sheet.dart`) semuanya SEBELUMNYA memakai satu
string identik dari `OrderParserService.encodeHandoff()` — termasuk blok
manusiawi "PESANAN — toko / daftar produk / Total" (digerbang param
`storeName`, fitur lama Item 54) yang TERNYATA **tidak pernah ikut
di-parse balik** — `OrderParserService.parse()` cuma baca baris
`#PSN:...` + baris meta (`Pegawai:`/`Nama:`/`PelangganId:`/`Nota:`) lewat
regex per-baris, `multiLine: true`, baris lain diabaikan total. Jadi blok
itu MURNI beban modul QR tanpa manfaat fungsional — utk keranjang banyak
baris/catatan, blok inilah kontributor terbesar panjang teks. Fix (risiko
rendah krn tidak ada perubahan format wire sama sekali): pisah jadi 2
string dari fungsi yang SAMA — `_showHandoffQr` sekarang panggil
`encodeHandoff` DUA KALI, sekali `storeName: null` (buat `QrImageView`,
kecil/modul rendah), sekali `storeName: device.storeName` (buat tombol
Salin/Share, tetap teks lengkap enak dibaca manusia di WhatsApp/Telegram).
Sisi scan/parse (`_handleOrderCode`, HID merge, `PasteOrderSheet`) SAMA
SEKALI TIDAK disentuh — behaviornya identik krn bagian yang dibuang dari
QR memang sudah lama tidak pernah dibaca.

Test `kasir_handoff_qr_test.dart` diperbarui: assersi lama "Copy = isi QR
persis sama" (sudah tidak berlaku, isinya sekarang beda) diganti "Copy
tetap lengkap, beda dari QR yang diperkecil" + assersi baru clipboard
mengandung blok "PESANAN — <toko>" secara eksplisit — revert-verified.
Coverage "storeName: null → header hilang total" sudah lama ada di
`order_parser_service_test.dart` group "Item 54" (tidak perlu test baru,
`_showHandoffQr` cuma komposisi ulang primitif yang sudah teruji). Full
suite 1067 hijau, `flutter analyze` 0 issue.

**Catatan desain yang perlu diingat kalau ada fitur QR/handoff baru**:
ada 2 sistem QR TERPISAH di app ini — QR order/cart handoff
(`OrderParserService`, prefix `#PSN:`, dibahas di atas) vs QR pairing
sync LAN (`qr_sync_widgets.dart`, payload JSON `{ip, key}`, dipakai
`pairing_screen.dart`/`pair_device_screen.dart`) — JANGAN dicampur.
`QrImageView` (paket `qr_flutter`) TIDAK punya getter publik utk data-nya
— widget test tidak bisa memverifikasi isi QR langsung lewat widget tree,
harus dibuktikan tidak langsung (bandingkan dgn `encodeHandoff()` yang
dipanggil manual, atau uji primitif penyusunnya secara terpisah).

_Update sesi 13 Agustus 2026 — Riwayat Pembayaran: rincian per-produk
retur/edit + Sisa per sesi bayar (`5c46846`), schemaVersion **32**
(naik dari 31). Permintaan user: kartu "Riwayat Pembayaran" in-app WAJIB
menampilkan (1) rincian per-produk tiap momen retur/edit — nama +
`qty satuan x harga  total` (keduanya bold), beberapa produk dalam satu
momen tampil berurutan; (2) baris "Sisa" per sesi bayar pada nota
tempo/kurang_bayar (pola sama "Kembalian" tapi TANPA centang); (3)
kembalian/sisa yang berlaku PERSIS pada momen retur/edit itu SENDIRI
(klarifikasi user eksplisit: "poin 3 'tersebut' refer ke poin 1", bukan
poin 2). **Scope eksplisit user: HANYA in-app** — nota share
(`_ReceiptPaper`) & cetak (`printer_service.dart`) TIDAK disentuh sama
sekali.

Dua keputusan desain lewat `AskUserQuestion` (kedua "Recommended" dipilih):
kembalian/sisa historis harus per-momen (bukan cuma kondisi terkini), dan
boleh bikin tabel audit baru. Implementasi AKHIRNYA jauh lebih sederhana
dari rencana awal (draft sempat merencanakan "rekonstruksi mundur dari
total terkini" — DIBATALKAN, tidak jadi dipakai): karena `changeGiven`
sudah lama disimpan IMMUTABLE per baris `transaction_payments` saat baris
itu dibuat, cukup tambah kolom SIMETRIS `sisaAfter` yang dihitung &
disimpan permanen dgn pola SAMA persis (`_computePaymentDelta`,
menggantikan `_computePaymentChangeGiven` lama) — tidak perlu rekonstruksi
apa pun belakangan. **Gotcha BARU yang sempat lolos ke test** (perlu
diwaspadai kalau ada formula simetris serupa di masa depan): `sisaAfter`
WAJIB dihitung dari `thisChange` (SUDAH dikurangi `priorChangeSum`), BUKAN
`aggregateChange` mentah — kembalian lama yang dipakai ulang sbg
pembayaran baru (mis. tambah belanjaan) harus dinetkan di KEDUA sisi
formula, sama alasannya dgn kenapa `changeGiven` sendiri sudah lama
mengurangi `priorChangeSum`. Bug ini lolos ke `flutter analyze` + semua
test BARU (yg kebetulan tidak menyentuh skenario kembalian-dipakai-ulang)
tapi ketangkap `receipt_sisa_tagihan_net_test.dart` (test LAMA) di full
suite — pelajaran: full suite WAJIB dijalankan sebelum yakin selesai,
tidak cukup test file baru saja.

Rincian per-produk: tabel BARU insert-only `transaction_adjustment_lines`
(snapshot nama produk/satuan, supaya tetap benar walau produk diedit/
dihapus belakangan), ditaut ke `transaction_payments` via `paymentId`.
Diisi di titik yang TEPAT di 4 fungsi mutasi (`returnUnpaidTransactionItems`/
`editUnpaidTransactionItem`/`returnPaidTransactionItems`/
`editPaidTransactionItem`) — utk 2 fungsi retur nilainya EKSAK langsung
dari data yg ada, utk 2 fungsi edit (qty & harga BISA berubah bersamaan
dlm 1 aksi) dipakai formula derivasi supaya `qty×harga≈subtotal` tetap
konsisten (subtotal-nya sendiri selalu eksak, cuma pemecahan qty/harga
per-baris yg didekati). Edit yg CUMA ubah catatan (qty & harga persis
sama) sengaja TIDAK menghasilkan baris rincian (dicek eksplisit,
revert-verified).

Sync LAN: tabel baru + kolom baru diwire penuh ke 3 tempat
(`lan_sync_service.dart`: `appendOnlyTables`/`syncCategories`/
`childTables`/`_collectTxIds`/label; `app_database.dart`: `_allTables`/
`dumpSince` appendOnly list) — kalau lupa salah satu, gejalanya BUKAN
error nyata, cuma data diam-diam tidak pernah nyampai device lain (pola
gotcha lama di CLAUDE.md).

Test `adjustment_lines_sisa_test.dart` (8, DB murni — 4 fungsi mutasi +
`addPaymentToTransaction` + `settleMergedDebt`) — revert-verified 2x.
16 test migrasi lama (v7 s/d v31) diperbarui: SEMUANYA sekarang
diupgrade sampai schemaVersion terkini (32) krn migrasi v32 tanpa syarat
versi awal (`m.addColumn(transactionPayments, ...)`) — 9 fixture yg
sebelumnya tidak pernah membuat tabel `transaction_payments` sama sekali
(tidak dibutuhkan migrasi manapun sebelum ini) sekarang WAJIB
menyertakannya, assersi `PRAGMA user_version` akhir dinaikkan 31→32 di
semua 16 file. Full suite 1066 hijau, `flutter analyze` 0 issue.

**Tercatat di task manager (belum dikerjakan)**: tidak ada baru sesi ini.
Item lama yang masih SENGAJA ditunda user ("tidak perlu dulu"):
rotasi/pemangkasan `CrashLogService` & `HeldOrders` tanpa kedaluwarsa.

_Update sesi 11 Agustus 2026 (lanjutan lagi — chart interaktif,
`5115832`) — user kirim screenshot: statistik produk dgn rentang
setahun (~365 titik harian) label sumbu-X-nya PECAH jadi tumpukan
karakter vertikal. Akar: `StatsDailyBarChart` (dibuat sesi ini juga,
lihat poin 3 di bawah) me-layout satu `Expanded` per titik — dgn 365
titik, tiap kolom lebih sempit dari satu karakter. **Ganti total** ke
`StatsTrendChart` berbasis fl_chart `LineChart` (dependency sudah ada,
sebelumnya cuma dipakai `PieChart`) — label sumbu pakai `interval`
fl_chart (dihitung dari skala X sungguhan, BUKAN dibagi rata per titik
spt versi lama), jadi jumlah label tetap terbatas berapa pun jumlah
titiknya. `trend_aggregation.dart` baru (fungsi murni, testable tanpa
widget) mengelompokkan harian->mingguan->bulanan begitu >60 titik.
Sekalian interaktif ala trading sesuai permintaan user: `LineTouchData`
bawaan fl_chart, tap/drag di garis -> tooltip tanggal+nilai + indikator
titik mengikuti sentuhan. **Scope SENGAJA cuma `StatsTrendChart`**
(satu-satunya pemakai: `ProductStatsScreen`) — chart pengeluaran/
ringkasan/arus kas TIDAK disentuh (belum dikonfirmasi kena bug yang
sama, kalau ada laporan serupa cek dulu apakah rentangnya juga bisa
sepanjang itu). Test `trend_aggregation_test.dart` (8) +
`stats_trend_chart_test.dart` (6, termasuk replay persis skenario 365
titik) — revert-verified. Full suite 1058 hijau (kali ini TERMASUK
`proposal_unchanged_end_to_end_test.dart` yg biasanya flaky — kebetulan
lolos, bukan berarti sudah pasti stabil permanen).

_Update sesi 11 Agustus 2026 (lanjutan — batch 6 pekerjaan, SESI SELESAI)
— versi kerja tetap **2.10.0+15**, schemaVersion **31** (naik 29→30 audit
storage, lalu 30→31 tabel kamus `product_aliases`).

User minta audit fitur & efisiensi storage, lalu menyetujui eksekusi 6
task sekaligus. SEMUA SELESAI & di-push (urut commit):

1. **`d7420b2`** — retur/hapus item nota BELUM LUNAS yang melebihi sisa
   hutang: kelebihan bayar kini jadi kembalian NYATA. Akar: kelebihannya
   terhitung tapi cuma mendarat di `transactions.changeAmount` — kolom
   yang TIDAK PERNAH dirender (struk membaca `changeGiven` pembayaran
   TERAKHIR). Keputusan user: "samakan dgn UI/UX kembalian yang sudah
   ada" — jadi ditulis sbg `changeGiven` di baris penanda, BUKAN bikin
   konsep deposit/kredit pelanggan baru.
2. **`c1f639f`** — nilai rupiah selisih di riwayat Stock Opname (dari
   HPP tier `min_qty=1`). Keterbatasan disengaja: HPP dibaca SAAT QUERY,
   bukan snapshot — ubah HPP ikut mengubah nilai riwayat lama.
3. **`352911b`** — statistik detail produk & pelanggan. Tab Produk &
   Pelanggan di Laporan dulu BUNTU (`onTap` nihil). Statistik pelanggan
   punya DUA pintu masuk (Laporan + detail pelanggan) memakai layar &
   query yang SAMA. Pelanggan ad-hoc DIABAIKAN (keputusan user).
4. **`7c89ca1`** — tab Arus Kas. Sumber kas masuk = `transaction_payments`
   (`paid_at`), bukan `transactions` — menutup 2 cacat "Selisih Kas
   Operasional" (nota tempo belum dibayar ikut terhitung; pelunasan
   nota lama jatuh di tanggal salah).
5. **`ba0a6fc`** — Penerimaan Barang via tempel teks + kamus tersinkron
   (schemaVersion 31). **PENTING**: ini PENERIMAAN (qty MENAMBAH stok),
   BUKAN opname (MENIMPA) — user semula menyebut "stok opname", setelah
   contoh file HTML-nya ditinjau ternyata maksudnya barang datang.
   Pencocokan PERSIS saja, TIDAK ada fuzzy (keputusan user eksplisit,
   konsisten larangan Levenshtein di CLAUDE.md). Kamus tersinkron DUA
   ARAH lewat konsep BARU `LanSyncService.sharedTables`.
6. **`d300b16`** — sync setting toko/metode bayar/pegawai. `app_settings`
   pakai ALLOWLIST `AppDatabase.syncableSettingKeys`, disaring di DUA
   sisi. **JANGAN PERNAH** dump `app_settings` bulat-bulat — bercampur
   identitas/state device (`store_key`/`device_code`/watermark); tanpa
   guard penerima, `store_key` benar² ikut tertulis (terbukti di
   revert-verification).

Semua revert-verified, `flutter analyze` 0 issue, full suite 1042 hijau
(1-2 kegagalan `proposal_unchanged_end_to_end_test.dart` — flaky
pre-existing, tidak terkait).

**Konsep sync sekarang ada 3 kategori** (dulu 2) — penting dipahami
sebelum menambah tabel baru: `appendOnly` (2 arah, INSERT OR IGNORE),
`masterData` (SATU arah host→klien, LWW), dan **`shared`** (2 arah, LWW
— baru, sejauh ini cuma `product_aliases`).

**Tercatat di task manager (belum dikerjakan)**: tidak ada — 6 task yang
dibuat sesi ini semuanya selesai. Temuan storage yang SENGAJA ditunda
user ("tidak perlu dulu"): rotasi/pemangkasan `CrashLogService` (log
crash tumbuh tanpa batas, dipicu juga oleh kegagalan sync berulang) &
`HeldOrders` tanpa kedaluwarsa.

_Update sesi 11 Agustus 2026 — versi kerja tetap **2.10.0+15**,
schemaVersion **30** (naik dari 29 — indeks baru, lihat poin 2 di
bawah). User minta "audit efisiensi data penyimpanan" (audit-only
dulu, baru "perbaiki semua, metode paling efisien & ampuh menurut
saya" di giliran berikutnya). 4 temuan, semua di-fix commit `49b2834`:

1. **KRITIS — Tutup Buku bisa gagal total.** `TutupBukuService.execute`
   menghapus `transactions` dalam periode yang diarsipkan, TAPI tidak
   pernah menyentuh `left_behind_items`/`borrowed_items`/
   `preorder_entries` (Laci Meja) sama sekali — ketiganya FK ke
   `transactions` TANPA cascade, `PRAGMA foreign_keys = ON` aktif. Kalau
   ADA nota dalam periode itu yang masih punya baris Laci Meja (bahkan
   yang sudah SELESAI sekalipun — baris itu tidak pernah dihapus
   seumur hidup DB), `DELETE FROM transactions` menabrak "FOREIGN KEY
   constraint failed" dan SELURUH Tutup Buku rollback/gagal. Tidak ada
   test lama yang menyentuh kombinasi ini sama sekali. Fix: guard baru
   di awal `execute()` — BLOKIR (`TutupBukuException`, pesan jelas)
   kalau ada baris Laci Meja BELUM SELESAI (titip/pinjaman/pre-order
   aktif — jangan diam-diam buang tugas operasional aktif); hapus baris
   yang SUDAH SELESAI bersama notanya di langkah delete (riwayatnya
   tetap ada di `archive_YYYY.db` yang sudah disalin duluan).
2. Indeks baru (schemaVersion 30) utk 5 tabel yang sebelumnya tidak
   terindeks sama sekali (`product_units.product_id`, `price_tiers.
   product_unit_id`, `alt_prices.product_unit_id`, `product_barcodes.
   product_unit_id`, `loyalty_point_ledger.customer_id`) + `transaction_id`
   di 3 tabel Laci Meja (dipakai guard poin 1). Migrasinya
   (`_createIndexesIfTableExists`) SENGAJA defensif thd tabel/kolom
   belum ada — 14 dari 15 fixture test migrasi lama (`migration_v7`
   s/d `v26`) TIDAK replika skema penuh (cuma tabel relevan ke migrasi
   yang diuji), jadi kalau step-nya tidak defensif, hampir semua
   fixture lama gagal "no such table"/"no such column". Di DB PRODUKSI
   nyata semua tabel targetnya sudah ada sejak v1, jadi ini tidak
   pernah skip apa pun di real world.
3. `PRAGMA auto_vacuum = INCREMENTAL` (sebelumnya `NONE`) — ruang bekas
   baris terhapus di luar Tutup Buku (void transaksi, dst.) sebelumnya
   tidak pernah dikembalikan ke OS di luar `VACUUM` manual (setahun
   sekali). DB baru langsung aktif; DB lama aktif otomatis setelah
   `VACUUM` berikutnya (Tutup Buku tahunan) — SQLite mensyaratkan itu,
   tidak ada tindakan tambahan yang perlu dilakukan.
4. `CatalogStore.add()` dibatasi 30 katalog tersimpan TERBARU — blob
   JSON `saved_catalogs` (AppSettings) sebelumnya tidak punya batas
   jumlah sama sekali.

Test baru: `tutup_buku_laci_meja_guard_test.dart` (5),
`migration_v30_indexes_test.dart` (1), `catalog_store_cap_test.dart`
(2) — semua revert-verified. 15 test migrasi lama (`migration_v7`..
`v26`) diupdate assersi `PRAGMA user_version` 29→30 (bump schemaVersion
rutin, pola sama tiap kali ada migrasi baru). Full suite hijau (1
kegagalan `proposal_unchanged_end_to_end_test.dart` — flaky
pre-existing, tidak terkait), `flutter analyze` 0 issue. Sudah
di-push. **Temuan sekunder dari audit yang TIDAK di-fix (dianggap
cukup aman/rendah-risiko utk dibiarkan)**: tidak ada — 4 temuan di
atas mencakup SEMUA yang dilaporkan di audit. Tidak ada pekerjaan
menggantung dari sesi ini.

_Update sesi 9 Agustus 2026 — versi kerja tetap **2.10.0+15**,
schemaVersion tetap **29**. User laporkan (screenshot) nota
`A1-20260809-0030`: "Sisa" di Riwayat Transaksi (`-Rp 300`) beda dari
"Sisa Tagihan" di struk (`Rp 6.600`) untuk nota yang SAMA. Root cause
sama persis dgn Item 56 (Buku Hutang) yg sudah diperbaiki sesi
sebelumnya, tapi di lokasi lain yg belum kena: `tx_history_sheet.dart`
pakai `total - paid` MENTAH, bukan net dari `change_given`. **Fix
(`0becd9c`)**: `AppDatabase.getNetSisaForTxIds` baru (pola SQL sama
`getDebtBook`, batched) dipakai di SEMUA titik `tx_history_sheet.dart`
— ringkasan multi-pilih, baris daftar, detail baris, dan `_lunasi`
(fetch fresh dari DB langsung, bukan provider yg bisa basi/race, krn
jumlah ini yg tercatat sbg pembayaran). Test baru
`tx_history_net_sisa_test.dart` (6 test: 4 DB + 2 widget) —
revert-verified.

**Susulan langsung, sesi sama**: user tanya balik soal bug Item 55
("Tempel Pesanan pegawai") — ternyata SUDAH TIDAK TERJADI LAGI menurut
user, walau belum sempat dibuka log diagnostiknya (tidak ada error
yg tertangkap). Investigasi: diff commit `0919f0d` dibaca ulang —
SEMUA perubahannya cuma `OrderParseDiagnostics.add(...)` pasif, TIDAK
menyentuh logic/urutan eksekusi sama sekali, jadi logging itu sendiri
BUKAN penyebab hilangnya bug. Titik gagal yg diinstrumentasi (`unitId`
tak ketemu di `product_units`, atau produk induk tak ketemu/nonaktif)
justru menunjuk ke masalah KETERSEDIAAN DATA (produk baru owner belum
sampai ke DB lokal pegawai), bukan bug logika parser — sejalan dgn 4
ronde investigasi kode statis sebelumnya yg sudah menyingkirkan hipotesis
parser. Dugaan kuat (TIDAK terkonfirmasi via log runtime): tertutup
sbg efek samping salah satu fix sync KRITIS di sesi yg sama — kandidat
paling plausibel Item 58 (union queue upload, cegah kehilangan batch),
Item 61.1 (reset watermark download yg bisa macet), atau Item 60
(loyalty points ketimpa LWW, pola bug serupa). **Ditanya ke user**
mau instrumentasi dicabut sekarang atau disimpan dulu — user pilih
**cabut sekarang** (`19c635e`): `OrderParseDiagnostics`, titik `.add()`
di `parse()`, `ParseDiagnosticsScreen`, tombol bug_report di
`PasteOrderSheet`, dan `order_parse_diagnostics_test.dart` — dihapus
total. Full suite hijau (1 kegagalan `proposal_unchanged_end_to_end_test.
dart` — flaky pre-existing, sama seperti sesi-sesi sebelumnya, tidak
terkait perubahan ini), `flutter analyze` 0 issue.

Kedua perubahan sudah di-push. **Item 55 PLAN.md kini bisa dianggap
selesai** (walau root cause pastinya tidak pernah terkonfirmasi via
log — cuma penalaran dari pola gejala + kebetulan waktu). Tidak ada
pekerjaan menggantung dari sesi ini.

_Update sesi 8 Agustus 2026 (lanjutan 9, SESI SELESAI) — versi kerja
tetap **2.10.0+15**, schemaVersion **29** (naik dari 28 — Item 61.5
nambah `Expenses.deletedAt`). User minta kerjakan semua temuan sync
sesi lalu (PLAN.md Item 56-61 + 54/55) sesuai urutan prioritas,
kecualikan backlog lama (47/48/23/17/21/28/41/51). Urutan disepakati:
**58, 59, 60, 56, 57, 61, 55, 54** — **SEMUA 8 SELESAI dikerjakan**
(7 dieksekusi tuntas, 1 — Item 55 — infrastrukturnya terpasang tapi
fix sebenarnya menunggu data dari user).

**SELESAI (commit, ringkas — urut sesi)**:
- Item 58 (KRITIS, `8897298`) — sync kedua client tidak lagi hapus
  permanen batch upload lama yg belum di-approve (union, bukan
  replace, di `enqueueSyncUpload`/`_handleRequest`).
- Item 59 (KRITIS, `3de2358`) — Tutup Buku selalu carry-forward saldo
  stok, dulu dilewati kalau unit masih punya sisa riwayat →
  `rebuildStockAfterForUnits` pasca-sync jadi salah.
- Item 60 (KRITIS, `219bf7f`) — `rebuildLoyaltyPointsForCustomers`
  baru, poin loyalti tidak lagi bisa ketimpa LWW `customers`.
- Item 56 (`5b2029f`) — Buku Hutang pakai net `change_given`
  (`netRemainingOwed`), bukan `total-paid` mentah.
- Item 57 (`b76b923`) — hitung kategori sync dari SEMUA tabel
  (`computeAvailableSyncCategories`), bukan cuma tabel pertama.
- Item 61 (`b3d1588`) — 5 temuan menengah: reset watermark download
  (baru, disatukan ke "Sync Ulang Penuh"), guard `reconcileTransactionsByIds`
  thd item kosong pasca-sync (SCOPED ke path sync saja — sempat blanket
  & merusak `returnUnpaidTransactionItems`, sudah dikoreksi), tie-break
  `rowid` `rebuildStockAfterForUnits`, checkbox "Stok" wajib ikut
  "Transaksi" di dialog approve, `Expenses.deletedAt` (migrasi v29)
  + soft-delete penuh (dumpSince/mergeRows khusus expenses).
- Item 54 (`fb0acd5`) — QR Share handoff bawa keterangan item + Total
  (format sama `buildOrderText()` katalog HTML), lewat param baru
  `encodeHandoff(storeName:)`. Parser TIDAK perlu diubah (sudah
  tolerir baris tambahan).
- **Item 55 (`0919f0d`) — SETENGAH JALAN, PERLU TINDAK LANJUT.**
  Logging diagnostik in-app TERPASANG (`OrderParseDiagnostics`
  in-memory maks 200 entry + titik `.add()` di `OrderParserService.
  parse()` + `ParseDiagnosticsScreen` via tombol bug_report sementara
  di `PasteOrderSheet`), tapi bug aslinya ("Tempel Pesanan" pegawai
  non `terima_pembayaran` tidak dapat produk dari QR/teks owner)
  BELUM diperbaiki — 4 ronde investigasi kode statis mentok, butuh
  bukti runtime. **Langkah selanjutnya**: minta user build APK debug,
  reproduksi bug (owner buat produk baru → share → pegawai tempel,
  gagal lagi), buka halaman debug (ikon bug_report di
  `PasteOrderSheet`) di device pegawai, salin & kirim balik isinya.
  Dari situ baru bisa fix akar masalahnya. **WAJIB** cabut total
  instrumentasi (daftar file lengkap di PLAN.md Item 55) begitu fix
  itu dieksekusi.

Semua commit di atas sudah di-push ke
`claude/kategori-produk-qty-harga-mqjh21`. `flutter analyze` bersih +
full `flutter test` hijau di tiap commit (revert-verified tiap fix).
Tidak ada lagi item PLAN.md yang "siap eksekusi" tersisa — cuma
Item 55 yang menggantung menunggu user.

_Update sesi 6 Agustus 2026 (lanjutan 2) — versi kerja tetap **2.10.0+15**,
schemaVersion tetap 28. User tanya susulan: "bug titipan pre-order yang
masih terikut sync meski sudah dipenuhi — apakah sudah diperbaiki?" —
DICEK, TERNYATA BELUM (beda dari fix `81f3b66` yang cuma soal tampilan
struk). **fix (`f0c5ea5`) — SEKARANG SUDAH**: `dumpLaciMejaProposals`
(client->host) cuma filter `locally_modified=1`, TANPA banding ke data
host — flag itu cuma reset kalau baris resmi host ter-merge BALIK ke
klien (lihat dok `AppDatabase.dumpLaciMejaProposals`), jadi sebelum itu
kejadian (owner belum sempat approve, atau klien sync lagi duluan),
baris pre-order/titip/pinjaman yang SUDAH SELESAI terus dikirim ulang
sbg "usulan baru" — pola bug SAMA PERSIS dgn produk Item 40 yang sudah
diperbaiki `filterUnchangedProposals`, tapi Laci Meja tidak pernah dapat
perbaikan setara. Fix: `filterUnchangedLaciMejaProposals` (pola sama,
lebih sederhana — record datar tanpa nested tier/unit), dipanggil host
sebelum baris masuk `_pendingLaciMejaProposals`, buang baris identik dgn
host (kecuali `locally_modified`/`updated_at`). 5 test baru (3 unit DB +
2 end-to-end HTTP sungguhan, pola sama `proposal_unchanged_end_to_end_
test.dart`) — revert-verified.

_Update sesi 6 Agustus 2026 (lanjutan) — versi kerja tetap **2.10.0+15**,
schemaVersion tetap 28. User kirim 3 permintaan sekaligus dalam 1 pesan
(screenshot bug Laci Meja + 2 laporan bug lain + 1 ide fitur baru):

1. **fix (`62d739d`)**: usulan Laci Meja (client->host) gagal total
   `SqliteException 787 FOREIGN KEY constraint failed` saat transaksi
   terkaitnya SENDIRI belum tersync ke host (screenshot user: pre-order
   "Bu Diah"). Akar: usulan Laci Meja & usulan sync "Transaksi" adalah
   DUA ANTRIAN INDEPENDEN tanpa jaminan urutan (arsitektur sengaja
   paralel, lihat CLAUDE.md). Fix: `applyLaciMejaProposals` cek dulu
   `transaction_id` ada di host sebelum insert — kalau belum, baris itu
   DILEWATI (bukan gagalkan seluruh batch), tampil alasan ke owner, baris
   otomatis diusulkan lagi begitu transaksinya tersync. Test end-to-end
   HTTP loopback ASLI (FK enforcement ON) mereproduksi persis bug di
   screenshot — revert-verified. **Efek samping ketemu**: 2 widget test
   lama (`laci_meja_proposal_review_test.dart`) jadi gagal krn hostDb-nya
   TIDAK pernah seed transaksi (sebelumnya lolos cuma krn FK OFF di DB
   test biasa) — disesuaikan seed transaksi di hostDb juga, sesuai
   skenario legitimate (transaksi sudah tersync duluan).
2. **fix (`4d5c170`)**: handoff QR keranjang antar device (scan kamera)
   kehilangan harga override/Harga Lain/checklist verifikasi — penerima
   selalu resolve harga fresh dari DB seolah pesanan katalog HTML biasa.
   Fix: `encodeHandoff()`/`parse()` di `order_parser_service.dart` sekarang
   membawa segmen opsional `|p=/|o=/|k=/|v=/|c=/|pr=/|pd=/|dq=` setelah
   qty tiap item — HANYA diisi jalur handoff antar-device (kode katalog
   HTML pelanggan TETAP tanpa segmen ini, perilaku lama utuh). 2 test
   baru, revert-verified.
3b. **fix (`70089e7`) — susulan langsung dari poin 2 di atas**: user
   sendiri menyadari konsekuensi fix handoff QR — pegawai TANPA izin
   `terima_pembayaran` bisa setel Harga Lain/override manual TANPA
   digerbang izin apa pun di `item_entry_sheet.dart`, jadi kalau harga
   itu ikut dibawa apa adanya, owner menerima harga tak tervalidasi dari
   device tak berizin. Fix: `encodeHandoff(trustPrices: bool)` — dipanggil
   `trustPrices: !needsGate` dari `cart_sheet.dart`. Device tanpa izin
   bayar → flag harga (p=/o=/k=/v=) TIDAK disertakan, `parse()` resolve
   fresh dari DB penerima (perilaku lama). Atribut NON-harga (checklist,
   status pre-order) TETAP dibawa apa pun izinnya — bukan concern-nya.
5b. **feat (`d99e4b1`) — susulan LANGSUNG dari poin 5**: user kadang butuh
   tekan minus BERKALI-KALI beruntun tanpa pindah jempol — jendela waktu
   tetap 1.5 detik (poin 5 di bawah) bikin tap terlambat (walau jempol
   MASIH di stepper) salah dianggap tap pertama lagi. **Timer dihapus
   total**, diganti: "bersenjata" berlaku SELAMA stepper baris ini masih
   membesar (`AddControl.activeStepper` — mekanisme "pijakan jempol" yg
   SUDAH ADA sebelumnya, tidak disentuh) — lepas HANYA kalau stepper
   baris LAIN jadi aktif (jempol pindah) atau scroll, TIDAK PERNAH krn
   lewat waktu. Tap beruntun selama bersenjata langsung mengurangi qty
   tiap kali (persis stepper biasa setelah "terkonfirmasi" sekali).
   Implementasi: `GlobalKey<State<AddControl>>` per baris dibandingkan
   `identical()` thd `AddControl.activeStepper.value` tiap listener
   terpicu. Test diganti (skenario jeda lama tanpa pindah jempol tetap
   confirm; tap beruntun; pindah jempol ke baris lain BENAR melepas
   status) — revert-verified.
5. **feat (`cdde036`) → REDESAIN LANGSUNG (`5740203`) — SELESAI**: user
   minta 1 lagi di dialog "Pengaturan Keranjang" yang sama — toggle
   "Konfirmasi sebelum kurangi qty" (`cartMinusConfirmProvider`, default
   OFF/opt-in). Versi AWAL pakai `AlertDialog` "Kurangi Qty?" — user
   SENDIRI sadar itu kurang pas (jempol biasanya sudah menutupi tombol
   minus itu sendiri saat menekannya, jadi warning visual yang cuma di
   situ tak kentara; fokus mata pun kadang di bagian lain baris, bukan
   stepper). **Redesain total**: tap PERTAMA tombol minus bikin SELURUH
   BARIS item bergetar (warning, qty BELUM berkurang) — tap KEDUA yang
   jatuh dalam ~1.5 detik baru benar-benar mengurangi qty; lewat jendela
   itu tanpa tap kedua, kembali netral (tap berikutnya = tap pertama
   lagi, harus getar ulang). Lebih cepat dari dialog utk aksi yg sering
   diulang (kurangi qty satu-satu), tidak perlu tap ekstra "Kurangi"+
   tutup popup. Implementasi: `_CartItemTile` diubah `ConsumerWidget` →
   `ConsumerStatefulWidget` (`AnimationController` getar + `Timer`
   jendela per-item) — `ValueKey(item.productUnitId)` WAJIB ditambah di
   `itemBuilder` supaya state "bersenjata"/timer TIDAK bocor ke baris
   lain kalau urutan keranjang berubah (mis. qty item lain diubah, ikut
   memanggil `orderCartItems` ulang). 5 test baru menggantikan test
   dialog versi awal — revert-verified (3 test terbukti gagal sensible
   saat mekanisme dilepas).
4. **feat (`3ef3019`) — SELESAI**: tombol "Pengaturan Keranjang" (ikon
   gerigi) di samping ikon "Tempel Pesanan" — dialog 4 opsi letak
   checkbox verifikasi (`CartCheckboxPosition` di `theme_provider.dart`,
   persisted SharedPreferences pola sama `fontScaleProvider`): depan
   qty/kiri (default), belakang stepper/kanan, kiri stepper minus, kanan
   nama item (baris nama `Expanded`→`Flexible` supaya checkbox menempel
   PAS setelah nama pendek, bukan terdorong ke ujung kanan). Jawaban
   PERMANEN atas posisi checkbox yang sudah 2x dibalik bolak-balik sesi
   sebelumnya — sekarang user pilih sendiri, tidak perlu kode diubah lagi
   kalau minta ganti posisi. 4 test baru — revert-verified.

Full suite 920 hijau (2 kegagalan `proposal_unchanged_end_to_end_test.dart`
flaky pre-existing/port-conflict — TIDAK terkait perubahan sesi ini).
`flutter analyze` 0 issue di semua 3 commit sesi ini.

_Riwayat sesi 6 Agustus 2026 (awal) — versi kerja tetap **2.10.0+15**,
schemaVersion tetap 28. Satu susulan kecil: checkbox verifikasi baris keranjang
(`_CartItemTile`, `cart_sheet.dart`) DIKEMBALIKAN ke paling KIRI baris
(`bd2ee9b`) — membalik keputusan sesi 1 Agustus yg memindahkannya ke kanan
(kiri stepper). Test posisi di-rename & disesuaikan (revert-verified).
Ini kemungkinan BUKAN keputusan final selamanya — sudah 2x bolak-balik
posisi checkbox ini dalam beberapa sesi terakhir, kalau user minta ubah
lagi jangan heran/protes, cukup eksekusi & catat di sini lagi.

_Riwayat sesi 5 Agustus 2026 — versi kerja tetap **2.10.0+15**,
schemaVersion tetap 28. Susulan langsung dari fitur "Tentang Aplikasi"/
"Info Lisensi & Serial" yang dibangun sesi 4 Agustus (ringkasan lengkap
ada di bawah):

1. **CI**: `build-apk.yml` sempat gagal total (`3485f42`) padahal APK-nya
   sendiri sukses dibuild — `gh release create` kena HTTP 503 (hiccup API
   GitHub sesaat), langkah itu dulu tanpa retry sama sekali padahal jalan
   di SETIAP push branch. Fix (`09927d1`): retry 4x (jeda 0/5/15/30 detik)
   + fallback `gh release upload --clobber` kalau rilisnya ternyata sudah
   terbuat di percobaan sebelumnya (hindari rilis dobel). API yang
   benar-benar down terus TETAP menggagalkan build (bukan lolos diam-diam).
2. **5 penyesuaian About/Lisensi** (`ead32f8`) dari feedback user: ikon
   pakai `filterQuality: high`+`isAntiAlias`; jarak chip Lisensi–AppBar
   direnggangkan; seksi "Segera Hadir" di halaman Lisensi DIHAPUS TOTAL;
   nomor serial jadi **spoiler** (pola titik-titik, tap utk reveal — QR di
   atasnya SENGAJA tidak ikut disamarkan, sudah spt noise visual).
3. **`license-generator.html`: pesan error kamera scan QR** (`4fa815d`) —
   user laporkan "Permission denied" polos. Dugaan awal soal "secure
   context" TERBUKTI SALAH (Playwright: `isSecureContext==true` utk
   `file://` di Chromium) — akar sebenarnya banyak browser (Chrome Android
   khususnya) auto-tolak izin kamera TANPA dialog sama sekali kalau HTML
   dibuka langsung dari file manager (bukan lewat alamat web), muncul sbg
   `NotAllowedError`/`NotFoundError`. Fix: deteksi error itu, kasih
   panduan `python3 -m http.server`/`npx serve .` + buka via localhost.
   Diverifikasi via Playwright dgn BarcodeDetector+getUserMedia PALSU yg
   disuntik utk mensimulasikan persis skenario itu (Chromium bundelan
   Playwright sendiri tidak support BarcodeDetector sama sekali, jadi
   tidak bisa dites lewat klik tombol sungguhan — harus disuntik manual).
4. **Ikon HD asli + tutorial dilengkapi + bug garis ExpansionTile**
   (`0f70fc8`): user kirim file emoji resmi 512x512 ber-alpha (`Image` di
   pesan chat, DIEKSTRAK dari base64 transcript JSONL sesi ini — bukan
   dari upload folder biasa, krn gambar terkirim inline via clipboard/
   paste, cek `message.content[].source.data` di `.jsonl` kalau kejadian
   lagi). Source lama (192x192, mipmap-xxxhdpi) adalah resolusi TERBESAR
   yang ADA di repo, sengaja diganti total. Source baru TRANSPARAN (emoji
   mentah, bukan squircle solid spt mipmap Android) — backdrop `#FFC896`
   (disampel dari pixel pojok mipmap lama via Pillow) ditambahkan di
   belakang `Image` supaya bentuk squircle tetap identik dgn launcher asli.
   Tutorial +6 bab (Printer Bluetooth, Backup&Restore+Alihkan Owner, Poin
   Loyalitas, Retur&Edit Transaksi Lunas, Tutup Kasir vs Tutup Buku,
   Katalog Pesanan) — SEMUA Pro Tip di-grep-verifikasi ke kode/nama-test
   nyata dulu sebelum ditulis (2 draft awal dicoret krn spekulatif, tidak
   ada dasar di kode — soal pairing Bluetooth "remembers" lama, dan klaim
   "device asal tak lagi owner" stlh Alihkan Owner). Bug visual dari
   screenshot user: `ExpansionTile` bawaan Flutter gambar border tema saat
   expanded, nempel aneh di dalam `Card` — fix `shape`/`collapsedShape:
   const Border()`.

5. **Redesain keranjang katalog HTML** (`0577fef`) — mockup Playwright
   JPG (3 frame: sheet, konfirmasi hapus-item, konfirmasi kosongkan-semua)
   dikonfirmasi user DULU, termasuk cek eksplisit kompatibilitas dark mode
   (disuntik `data-theme=dark` + toggle asli via tombol tema, discreenshot
   ulang) sebelum eksekusi ke `order_page_service.dart`. Perubahan: (a)
   ikon 🗑 hapus per-baris keranjang, terpisah dari stepper qty (dulu
   cuma bisa hapus dgn tekan − sampai 0, tanpa konfirmasi); (b) modal
   konfirmasi custom (`showConfirm`/`hideConfirm`, ikut tema — GANTI
   `confirm()` bawaan browser) utk hapus-satu-barang MAUPUN
   kosongkan-semua; (c) tombol "Kosongkan" (teks polos) jadi pill ikon+
   "Kosongkan Keranjang" aksen merah di kanan-atas header. Token
   `--danger`/`--danger-bg` baru, dgn varian dark (pola sama persis
   `--ok`/`--warn` yg sudah ada). Test baru (`order_page_service_cart_
   delete_test.dart`) — revert-verified via python patch+restore (bukan
   sed) krn JS-dalam-Dart-raw-string rawan escaping kalau pakai sed.

Full suite 925 hijau tiap commit (1 flaky pre-existing
`proposal_unchanged_end_to_end_test.dart`, port-conflict paralel, lolos
sendirian — TIDAK terkait perubahan manapun sesi ini). `flutter analyze`
0 issue di semua commit.

_Riwayat sesi 4 Agustus 2026 (lanjutan) — QR sidik jari device + "Tentang
Aplikasi"/"Info Lisensi & Serial" dibangun dari nol, lalu DIKOREKSI BESAR
sekali krn versi pertama (`b97a0e8`) dibangun TANPA membuka ulang mockup
yang sudah dikonfirmasi (ikon 108px di ATAS wordmark bukannya 178px
DI BAWAH wordmark, AppBar berjudul bukannya polos+tombol "?" bulat, entri
lisensi jadi kartu besar bukannya chip rata-kanan) — user menegur ("Design
melenceng jauh... baca mockup yang anda buat sendiri"), dikoreksi total di
`dcf7bf8`. **Pelajaran WAJIB diingat**: mockup yang sudah dibuat &
dikonfirmasi WAJIB dibuka lagi saat implementasi, jangan dibangun ulang
dari ingatan/deskripsi teks. Bug nyata ikut ketemu saat koreksi itu:
`DeviceLicenseScreen` sempat pakai `DateFormat(..., 'id_ID')` →
`LocaleDataException`, app TIDAK PERNAH `initializeDateFormatting` (sudah
didokumentasikan di CLAUDE.md §Gotcha & `expenses_screen.dart`, terlewat
saat menulis layar baru ini) — format nama bulan manual, ada test
regresinya sekarang. Hasil akhir arsitektur: `AboutScreen`
(`/pengaturan/tentang`, wordmark+ikon+versi+"made with ♥️ by Dre"+chip
Lisensi rata-kanan) → tombol "?" ke `TutorialListScreen`
(`/pengaturan/tentang/tutorial`, searchable+Pro Tips) & chip Lisensi ke
`DeviceLicenseScreen` (`/pengaturan/lisensi`, QR+serial+tanggal
aktivasi/berlaku). Entri "Info Lisensi & Serial" lama di kartu "Device
Ini" Pengaturan SUDAH DIHAPUS (bukan cuma ditambah alternatif), diganti
"Tentang Aplikasi" di kartu Diagnostik.

_Riwayat sesi 4 Agustus 2026 (awal) — versi kerja **2.10.0+15** (naik dari
2.9.1+14, MINOR bump eksplisit diminta user — lihat poin 6), schemaVersion
**28** (naik sesi 3 Agustus). Sesi itu jawab 4
pertanyaan/insight user (poin 1-4) + 1 fix susulan (poin 5) + rilis resmi
(poin 6):
1. **Percepat input harga modal/stok dari nota supplier** — user minta
   PENDING dulu (bukan dieksekusi). Insight tercatat di **PLAN.md Item
   53** (`ddbe65c`): manfaatkan CSV import yang sudah ada (sudah dukung
   `harga_beli`/`stok` + update produk existing), mode "restock" ala
   `StockOpnameScreen`, OCR dinilai ROI rendah, plus keputusan desain yg
   menggantung (harga modal "terakhir" vs rata-rata tertimbang).
2. **Posisi scroll `CartSheet` dipulihkan saat sheet dibuka ulang**
   (`ef18cdd`) — `_cartScrollMemory` (top-level `Map<String,double>` per-
   `cartId` di `cart_sheet.dart`), listener pada scroll controller +
   `jumpTo` (di-clamp ke `maxScrollExtent`) saat sheet dibuka lagi, kalah
   dari `scrollToBottom` eksplisit. Gotcha test ditemukan saat menulis
   test-nya: `DraggableScrollableSheet` — drag PERTAMA cuma membesarkan
   tinggi sheet (initialChildSize→maxChildSize), scroll konten baru
   bergerak di drag KEDUA (lihat komentar di
   `test/cart_sheet_scroll_restore_test.dart`). Selesai & di-commit.
3. **QR scan merge ke keranjang aktif di mode Tambah Belanjaan** —
   dikonfirmasi SUDAH otomatis jalan dari fix sesi 3 Agustus (`c690329`,
   lihat riwayat di bawah) — `_handleOrderCode` pakai `_cartId` yang
   sudah resolve ke `addToTxId`, scanner tidak digembok mode ini. TIDAK
   ada tindakan lebih lanjut (dikonfirmasi user).
4. **Produk nonaktif owner ikut ke client TANPA menghapus produk baru
   client** (`512aae9`, test-only) — riset kode membuktikan KEDUA hal
   yang diminta user SUDAH terpenuhi SEKALIGUS oleh desain sync yang ada
   (bukan trade-off pilih salah satu): `dumpSince`/`mergeRows` untuk
   `products` delta by `updated_at` TANPA filter `is_active` (deaktivasi
   owner sudah otomatis propagate — dibuktikan test LAMA
   `product_deactivate_sync_test.dart`), DAN `mergeRows` cuma memproses
   baris yang benar-benar ADA di payload host — produk baru client yang
   belum di-approve tidak PERNAH tersentuh krn host tidak pernah
   mengirim baris utk produk yg belum ia terima. Test baru
   `product_new_client_survives_host_sync_test.dart` membuktikan
   KEDUANYA sekaligus dalam 1 skenario. Tidak ada perubahan kode produksi.
5. **Layar review usulan produk (`ProductProposalReviewScreen`) tampilkan
   SEMUA perubahan terdeteksi, bukan cuma harga** (`eefb4b0`) — laporan
   user: mengubah SATUAN produk di client, harga tetap sama, layar review
   di owner tetap bilang "Tidak ada perubahan harga" (nyaris di-dismiss
   krn dikira glitch). `_diffProduct` baru bandingkan proposal vs data
   host per-aspek: nama, satuan (tipe/isi-rasio/lacak-stok, dicocokkan by
   id — stabil lintas edit), satuan ditambah/dihapus, harga satuan
   NON-dasar, jumlah tier grosir, barcode & harga alternatif (dibanding
   sbg SET nilai — id-nya diregenerasi tiap simpan form produk). Harga
   satuan DASAR tetap RichText strikethrough seperti sebelumnya (TIDAK
   diubah tampilannya), cuma ditambah baris lain di bawahnya kalau ada.
   `filterUnchangedProposals` (host) sudah benar sejak awal — bug murni
   di tampilan review, bukan logika filter usulan. Selesai & di-commit.
6. **Rilis resmi v2.10.0** — user minta audit semver dari commit pertama
   (lihat CHANGELOG utk histori lengkap; ringkas: proses versioning sudah
   benar sejak `2.3.0+5` [28 Juli], tapi angka MINOR jauh understate
   histori Juni-Juli yang batch-bump — user putuskan BIARKAN, terus dgn
   `2.10.0` sesuai rencana). Bump MINOR: 4 `feat:` sejak `2.9.1+14`
   (Tempel Pesanan di keranjang + tambah belanjaan + QR merge, usulan
   sync pelanggan, highlight item tercentang, scroll-restore keranjang),
   tidak ada breaking change (schemaVersion 28 additive). Branch
   `claude/kategori-produk-qty-harga-mqjh21` di-merge ke `main` —
   user akan tag rilis manual di GitHub.

Full suite 908 hijau, `flutter analyze` 0 issue.

**MENGGANTUNG — Item 52 PLAN.md, bug sinkron harga antar toko (BELUM
diselesaikan, masih terputus di titik yang sama, TIDAK disentuh sesi
ini)**: user laporkan kasus nyata — barcode sama, harga sudah sama di
kedua toko ("Rinso cair 500", 5000), tapi sync tetap usulkan harga beda
(4400). Analisis mendalam SUDAH dilakukan (baca detail lengkap di PLAN.md
Item 52 & CLAUDE.md), root cause PALING MUNGKIN sudah diidentifikasi:
asimetri dedup di `price_sync_service.dart` (query ekspor katalog dedup
barcode via `GROUP BY` tapi TIDAK dedup JOIN `price_tiers WHERE
min_qty=1` — kalau toko sumber punya tier duplikat `minQty=1`, 1 barcode
bisa muncul 2x di katalog dgn harga beda). **BELUM diverifikasi ke kasus
nyata** — user diminta kirim baris log `unit=...`/verdict harga khusus
utk "Rinso cair 500", atau cek manual Edit Produk di kedua toko (tier
harga duplikat? produk nonaktif dgn nama/barcode sama?) — user belum
sempat balas. **Next action begitu sesi lanjut**: tunggu/minta detail itu
dari user, baru eksekusi fix (dedup query + one-time cleanup data tier
duplikat). Pertanyaan terpisah yang juga menunggu keputusan user: apakah
field pencarian kasir perlu bisa cari-by-barcode juga (sekarang cuma
nama/`kode_produk`).

_Riwayat sesi 3 Agustus 2026 (lanjutan) — schemaVersion naik 27→28._
Enam hal: highlight soft item keranjang tercentang (`f606428`); jarak
baris keranjang ke tepi layar diperlebar (`5266dcd`); tombol QR handoff
"Sudah Dikirim, Kosongkan Keranjang" diganti "Share Pesanan" (`31c9b26`,
`onDone` callback lama dihapus); "Tempel Pesanan" langsung dari
`CartSheet` + diaktifkan di mode Tambah Belanjaan + QR scan merge ke
keranjang aktif (`c690329`, 3 penyempurnaan terkait — `_handleOrderCode`
cek `cartProvider(_cartId)` sebelum `db.holdOrder(...)`); usulan sync
pelanggan dari device non-owner (`d196ccd`, kolom
`customers.locally_modified`, pola sama persis usulan produk Item 40 &
Laci Meja Item 52, `CustomerProposalReviewScreen` baru); gotcha baru
didokumentasikan di CLAUDE.md §Gotcha soal widget test `KasirScreen` yang
bisa hang tanpa batas kalau `AppDatabase` dibuka lewat top-level
`setUp()`/`tearDown()` tanpa `drain()` manual. Detail lengkap tiap poin:
lihat CHANGELOG.md tanggal yang sama.

_Riwayat sesi 1 Agustus 2026 (lanjutan 3) — versi kerja **2.9.1+14**,
schemaVersion 27. **Item 53 PLAN.md SEKARANG BENAR-BENAR SELESAI TOTAL**
(dihapus dari PLAN.md) — user tanya susulan "Apakah bisa dibuat sync
juga?" menutup gap yang sempat dicatat: saklar "Ikut harga satuan dasar"
varian sekarang cascade lewat DUA jalur — `saveProduct` (form Edit Produk
biasa, sudah ada) DAN `applyProductProposals` (owner approve usulan harga
dari device lain via sync, baru ditambahkan). Pola: kumpulkan
`(productId -> satuan dasarnya)` sambil proses tabel `product_units`,
harga barunya sambil proses `price_tiers`, lalu panggil
`_cascadeVariantPricesForUnit` yang SAMA PERSIS SETELAH `transaction()`
commit — scope ketat per `parentProductId` (usulan produk lain yg
diapprove bersamaan tidak ikut mencascade). 3 test baru
(`variant_follow_price_proposal_sync_test.dart`), revert-verified. Full
suite 883 hijau.

_Riwayat sesi 1 Agustus 2026 (lanjutan 2) — versi kerja **2.9.0+13**.
Setelah sempat diusulkan redesain varian jadi "atribut" (bukan entity
terpisah) — user memutuskan **pertahankan skema varian sekarang**
(keputusan final), sebagai gantinya minta 2 perbaikan: (1) saklar "Ikut
harga satuan dasar" per satuan jual varian — kolom baru `product_units.
follows_parent_price` (migrasi additive, default false), cascade lewat
`AppDatabase._cascadeVariantPricesForUnit` dipanggil dari `saveProduct`
SETIAP kali harga satuan dasar produk induk disimpan ulang (bukan cuma
saat benar2 berubah — cascade selalu menegakkan invariant harga×isi,
bukan listen ke diff). (2) UX harga varian di `ItemEntrySheet`: ikon
popup "Pilih harga" DIGANTI field harga manual + chip Harga Lain
(`_MiniPriceChip`) tampil langsung, TAPI cuma muncul saat variannya
qty>0 — supaya modal tidak penuh sesak kalau variannya banyak. Kedua
desain dirancang via mockup HTML+Playwright (2x revisi visual sebelum
sentuh kode Flutter — permintaan eksplisit user "takutnya salah lagi"
setelah 2 percobaan layout keranjang sebelumnya meleset). 12 test baru,
semua revert-verified. Full suite 880 hijau._

**Gotcha migrasi kena LAGI, PERSIS seperti yang sudah didokumentasikan**:
step migrasi baru (`addColumn` ke `product_units`, TANPA syarat versi
awal) mematahkan 3 test migrasi lama (`migration_v23/24/26_test.dart`)
yang skema sintetisnya sengaja tidak menyertakan tabel `product_units` —
fix: tambahkan `CREATE TABLE product_units` (skema PERSIS pra-migrasi
ini) ke setup sintetis ketiganya. Ini kejadian BERULANG (sudah 2x
didokumentasikan sebelumnya di CLAUDE.md) — WAJIB cek SEMUA test migrasi
lama (bukan cuma yang terasa relevan) tiap kali menambah migration step
baru yang menyentuh tabel yang sudah ada sejak versi lama.

_Riwayat sesi 1 Agustus 2026 (lanjutan) — versi kerja **2.8.0+11**.
**Pertanyaan "jangkar satuan varian" AKHIRNYA TERJAWAB & DIEKSEKUSI**
(Item 52 PLAN.md dihapus, lalu jadi Item 53 setelah revisi lanjutan sesi
ini). Keputusan final user (saat itu): varian TETAP jangkar ke satuan
dasar, TAPI
diberi pilihan satuan jual sendiri (Ret/Dus/dll) + "isi per satuan" yang
mengonversi balik ke satuan dasar. Implementasinya SENGAJA tanpa migrasi
schema: varian yang isinya != 1 mendapat SATU baris `product_units`
non-dasar tambahan sebagai satuan JUAL; satuan dasar tetap jadi jangkar &
pemegang stok (semua `stock_ledger` app ini memang ditulis dalam satuan
dasar). Aturan pemilihan disatukan di `AppDatabase.variantSaleUnit(units)`
("prefer non-dasar") — kalau menambah konsumen baru yang membaca satuan
varian, WAJIB lewat helper itu, jangan `firstWhere(isBaseUnit)` lagi.
Satuan jual dibuat MALAS (baru saat isi pertama kali != 1) dan setelah ada
TIDAK PERNAH dihapus walau isi dikembalikan ke 1 — `transaction_items`
nota lama menunjuk ke id satuan itu.

Plus 4 penyesuaian dari user di sesi yang sama: nominal subtotal keranjang
pindah ke bawah baris qty (dulu stepper bergeser tiap diketuk krn lebar
teks rupiah berubah), checkbox keranjang pindah ke kanan (kiri tombol
minus), ikon tab Ringkasan `grid_view` -> `note_alt`, dan bugfix status
centang keranjang yang hilang di jalur "Tambah Belanjaan".

**Gotcha BARU yang layak diingat**: `ListTile` mengunci tinggi
`leading`/`trailing` ke 48px (dense; 56px non-dense) APA PUN tinggi
barisnya — menumpuk 2 baris konten di `trailing` PASTI overflow. Baris
keranjang (`_CartItemTile`) karena itu tidak lagi memakai `ListTile`,
diganti `InkWell`+`Row` manual. 15 test baru, semua revert-verified. Full
suite hijau, `flutter analyze` 0 issue._

_Riwayat sesi 31 Juli 2026 (lanjutan 2) — versi kerja **2.7.0+10**. Susulan
langsung dari sesi sebelumnya di hari yang sama (`b7744d7`, v2.6.0+9 —
"Harga Lain per varian + status stok varian DITAMPILKAN"): user tanya 3
hal soal Pengaturan Produk varian — (1) "jangkar satuan varian" (klaim ada
pembahasan kemarin — **tidak ditemukan jejaknya sama sekali** di
PLAN.md/CHANGELOG.md/`git log`; dicatat sbg **Item 52 di PLAN.md**, BELUM
disentuh, nunggu klarifikasi user), (2) atur stok varian — belum ada UI
(FIXED sesi ini), (3) pakai Harga Lain varian saat jual — tersimpan tapi
tak terpakai (FIXED sesi ini). User bilang "Kerjakan semua, hingga
tuntas" — diinterpretasikan cakup poin 2+3 saja (yang sudah ditawarkan
konkret), BUKAN poin 1 (jangkar satuan, tak ada dasar klarifikasi).

Fix: (a) ikon "Sesuaikan stok varian" baru di tiap baris varian
(`produk_form_screen.dart`, method `_adjustVariantStock`) — reuse dialog
`_adjustStockDialog` yg sudah ada utk satuan produk utama, tinggal
diberi `unitId`+label varian; ditolak dgn banner kalau varian non-stok.
(b) `_VariantOption.altPrices` (`item_entry_sheet.dart`) di-fetch di
`_load()`, `_VariantRow` diberi ikon popup kecil (`Icons.sell_outlined`,
HANYA muncul kalau varian punya Harga Lain) berisi "Harga dasar" + tiap
Harga Lain — state baru `_variantPriceOverride` (map productId->harga
terpilih), dipakai `_variantTotal` & `_submit` saat membangun `CartItem`
varian (`price:`, bukan lagi selalu `v.price` mentah).

4 test baru (`produk_form_variant_stock_adjust_test.dart` x2,
`item_entry_variant_alt_price_test.dart` x2) — semua revert-verified
(stash file produksi, tes gagal "widget not found" sensible, pop lagi).
Full suite hijau (853 test), `flutter analyze` 0 issue. **Belum di-commit
per akhir turn ini** — commit + merge ke `main` masih perlu dieksekusi
turn berikutnya (lihat instruksi commit di CLAUDE.md §Git)._

_Update sesi 28 Juli 2026 — **v2.3.0 SUDAH RESMI DIRILIS** (tag `v2.3.0`,
non-prerelease, APK ter-attach, lihat "Rilis v2.3.0" di bawah). Proyek
memasuki fase MAINTENANCE (fitur dianggap selesai per user) — repo
`The-POS` rencananya akan di-private-kan (hemat, tidak ada build rutin),
dibuka public lagi sementara HANYA kalau perlu compile APK via GitHub
Actions (kuota gratis repo public). Dua dependensi yang sempat butuh repo
public SUDAH DIPUTUS: (1) kill-switch lisensi (`revoked.json`) sudah
dipindah ke GitHub Gist terpisah (`gist.github.com/Ikanuri/
ff6a99c3b1e642c81809b0664c8d681a`, URL raw TANPA hash revisi) — Gist
independen dari visibility repo, jadi aman private permanen; (2) BARU
DITEMUKAN & DIPERBAIKI sesi ini: backup penuh/Alihkan Owner ternyata
TIDAK menyertakan 3 tabel Laci Meja (`left_behind_items`, `borrowed_items`,
`preorder_entries`) — lihat "fix: backup Laci Meja" di CHANGELOG. Semua
perubahan sesi ini SUDAH di-merge ke `main` & di-push ke `origin`
(termasuk tag rilis). Belum ada pekerjaan menggantung di branch
`claude/kategori-produk-qty-harga-mqjh21` per akhir sesi ini._

_Riwayat sesi 27 Juli 2026 (lanjutan) — **Item 52 ("Laci Meja") SELESAI
TOTAL** termasuk bagian yang sempat ditunda (layar review usulan), 2
koreksi UX dari user setelah demo awal (link ke produk struk, redirect
dashboard ke nota), 1 bugfix KRITIS (checkout gagal setelah handoff QR
bolak-balik) + 4 perbaikan UI dari laporan screenshot device asli, 2
penyesuaian susulan (Bayar tetap di kanan saat cart bar 2 baris;
keterangan Laci Meja membedakan titip vs ketinggalan), SATU putaran
redesign (menu cepat Kasir/Laci Meja + 2 perbaikan di tab Ringkasan &
struk share), SATU PUTARAN LAGI (animasi menu, grouping frame
Titip/Ketinggalan + qty/satuan, tombol Ambil minimalis), REDESAIN BESAR
Pre-order (nyambung total ke keranjang/nota, ganti 2 jalur lama), lalu
gap Ringkasan AKHIRNYA KETEMU akarnya (percobaan ke-4, `TabAlignment`,
BUKAN soal padding/margin sama sekali — 3 percobaan sebelumnya semua
salah sasaran), grouping Pre-order/Pinjaman di dashboard, dan penanda
"Pinjaman" baru di struk in-app — lihat bagian di bawah._

## Putaran TERBARU: redesain cart bar + pinjaman plain text + cari/statistik Pre-order

1. **Pinjaman kembali PLAIN TEXT** (dikonfirmasi user via AskUserQuestion,
   membalik keputusan putaran sebelumnya). Alasannya kuat & layak diingat:
   yang dipinjamkan biasanya **WADAH** (galon/tabung KOSONG) — dan wadah itu
   justru BUKAN baris di nota (yang jadi baris nota adalah isi/refill-nya).
   Checklist-barang-nota karena itu membuat barang yang sebenarnya dipinjam
   MUSTAHIL dicatat. Konsekuensi: penanda pinjaman di struk tidak bisa
   nempel per-baris produk (tak ada `transactionItemId`) → diganti **SECTION
   "Pinjaman Barang"** tersendiri (`getBorrowedForTransaction` +
   `_buildBorrowedCard`), tetap memenuhi maksud "rujukan kebenaran".
   **Kolom `BorrowedItems.transactionItemId` (migrasi v24) DIBIARKAN ADA
   tapi tidak dipakai lagi** — schemaVersion SENGAJA tidak diturunkan balik
   ke 23 karena build user sudah terlanjur v24; menurunkan schemaVersion
   bikin drift menolak membuka DB (`user_version` > schemaVersion).

2. **Redesain cart bar** (3 hal sekaligus):
   - Pengingat Laci Meja jadi **satu baris per kategori**
     (`LaciMejaReminder.linesOf`, dulu satu string digabung " · ").
     Baris pre-order menyebut **nama produk + qty + jaminan**, diringkas
     "+N lagi" bila >2 produk (dikonfirmasi user — cart bar tidak boleh
     jadi sangat tinggi).
   - **Pengingat hutang akumulatif** (total rupiah + jumlah nota) muncul
     DI BAWAH nominal Total via `cartCustomerDebtProvider` (autoDispose).
     Warna `cs.error` merah, SENGAJA beda dari dusty rose Laci Meja di
     atas Total — dua peringatan beda makna.
   - **Layout tidak lagi melipat**: `Wrap` → `Row` tetap dgn
     `Expanded(flex: 4/3)` utk chip Pelanggan/Pegawai (porsi Pelanggan
     terbesar & tidak pernah dikurangi — permintaan eksplisit user), dan
     nama panjang ditangani `_MarqueeText` (teks berjalan kiri↔kanan).

3. **`_MarqueeText` — 2 jebakan yang SUDAH kena, jangan diulang**:
   - `OverflowBox` tanpa `maxHeight` di dalam Column tak-berbatas =
     "infinite size during layout" (crash render). Tinggi WAJIB dikunci ke
     `TextPainter.height`.
   - Animasi **tidak boleh abadi**. Versi pertama `repeat(reverse: true)`
     tanpa henti bikin `tester.pumpAndSettle()` TIMEOUT di **10 test kasir
     yang sudah ada** (bukan cuma test baru). Sekarang dibatasi 4 putaran
     lalu berhenti di awal teks, dan dimulai ulang saat teksnya berganti.
     **`addStatusListener` TIDAK BISA dipakai utk menghitung putaran** —
     `repeat()` menggerakkan controller lewat simulasi internal dan tidak
     pernah memancarkan `completed`/`dismissed`; pakai `Timer(durasi *
     maxCycles)` (sudah dicoba keduanya). Bonus: perangkat POS menyala
     seharian, animasi 60fps abadi di bar bawah = baterai terbakar sia-sia.

4. **Tab Pre-order dashboard**: kotak pencarian (cocokkan nama pelanggan
   ATAU nama produk) + statistik akumulatif **total produk** & **total
   jaminan** sbg dua angka TERPISAH (satuannya beda maknanya — barang yang
   ditunggu vs wadah yang dipegang toko). Keduanya ikut tersaring hasil
   pencarian, supaya angkanya menjawab pertanyaan yang sedang dicari.

5. **Bug lama ikut tertutup**: `getLaciMejaPendingForCustomer`/`ForName`
   disatukan jadi `getLaciMejaPending({customerId, customerName})`. Versi
   lama yang berbasis `customerId` SELALU mengembalikan `preorder: 0` —
   artinya pre-order milik pelanggan TERDAFTAR tidak pernah muncul di
   pengingat mana pun (cart bar maupun modal checkout). Sekarang keduanya
   dikirim bersamaan: titip/pinjaman dicocokkan lewat id, pre-order lewat
   nama (tabel `PreorderEntries` memang hanya menyimpan nama, tanpa FK).

Test baru: `cart_bar_reminder_lines_test.dart` (3),
`receipt_borrowed_section_test.dart` (4, termasuk regresi "jaminan tidak
hilang setelah Penuhi"), +4 pencarian/statistik di
`laci_meja_dashboard_grouping_test.dart`, +2 marquee di
`cart_bar_bayar_button_test.dart`, +3 di
`laci_meja_marks_and_reminder_test.dart` — semua revert-verified. Full
suite: **822 test hijau**, `flutter analyze` 0 issue.

## ✅ Gap Ringkasan — AKHIRNYA KETEMU akarnya (percobaan ke-4, SELESAI)

**Riwayat lengkap 4 percobaan** (WAJIB dibaca kalau ada laporan gap
serupa lagi — 3 dari 4 percobaan salah total, pelajarannya penting):
1. `673d045` — margin Card KPI (jarak ANTAR-baris). User konfirmasi
   build update, gap MASIH terasa.
2. Top padding `ListView` 16px→8px (gap ATAS kartu pertama, dari
   screenshot panah PERTAMA). User KEMBALI konfirmasi build update
   (`AskUserQuestion` eksplisit), gap MASIH terasa. Diukur via widget
   test: gap sungguhan BENAR berkurang jadi 8px sesuai kode — arah fix
   benar tapi PERCUMA, karena bukan itu akarnya sama sekali.
3. Top padding dibuat 0 penuh, atas rekomendasi user sendiri. **User
   kirim SCREENSHOT PANAH KEDUA** — dan panahnya menunjuk KE KIRI tab
   "Ringkasan" itu sendiri (bukan area vertikal kartu SAMA SEKALI).
   Ternyata 3 percobaan sebelumnya salah sasaran arah TOTAL (vertikal
   vs horizontal) — deskripsi teks user ("renggang", "gap") sejak awal
   TIDAK CUKUP presisi utk membedakan "gap di atas kartu" vs "gap di
   kiri tab", dan saya keliru berasumsi itu soal jarak ke kartu KPI dari
   percobaan pertama.
4. **Akar sesungguhnya**: `TabBar(isScrollable: true)` Material 3
   default `tabAlignment: TabAlignment.startOffset` — inset ~52dp di
   depan tab PERTAMA (dirancang API Flutter utk sejajar leading
   icon/drawer button; `LaporanScreen`'s AppBar TIDAK punya leading icon
   jadi inset ini murni buang-buang ruang tanpa alasan). Fix:
   `tabAlignment: TabAlignment.start`. Test baru
   `laporan_tab_left_align_test.dart` — revert-verified (gap SUNGGUHAN
   68px sebelum fix, terbukti presisi cocok dgn deskripsi "~52dp inset
   bawaan" + padding AppBar bawaannya).

**Pelajaran KERAS** (kalau laporan visual serupa muncul lagi di layar
LAIN): "gap"/"renggang" dari user BISA merujuk ke sumbu yang SAMA SEKALI
beda dari yang kelihatan jelas dari kode (contoh nyata: margin Card
antar-baris — jelas ADA bug-nya secara kode — ternyata bukan yang
dimaksud user sejak awal). **Screenshot beranotasi PANAH WAJIB diminta
di percobaan PERTAMA** kalau laporan "ada gap" datang tanpa gambar,
BUKAN ditunda sampai 2-3 percobaan gagal dulu — tiap percobaan buta
berarti minimal satu siklus build+install APK yang terbuang.

**Susulan (27 Juli)**: user minta padding `ListView` Ringkasan
dikembalikan "seperti semula" — top padding yang sempat ditekan ke 0px
di percobaan ke-3 (blind guess, sebelum akar sungguhan ketemu) sudah
tidak perlu lagi karena `TabAlignment.start` adalah fix sungguhannya.
Dikembalikan ke `EdgeInsets.all(16)` seragam, test
`ringkasan_kpi_card_margin_test.dart` disesuaikan.

**Susulan lagi (27 Juli)**: statistik tab Pre-order — istilah "wadah"
diganti "jaminan" (`_StatTile` sub-label), dan kartu "Total jaminan"
sekarang menampilkan rincian per produk di bawah angka total (mis.
"LPG: 20 jaminan"), dihitung dari entri hasil pencarian yang sama dgn
`totalDeposit` (bukan seluruh data — supaya konsisten dgn statistik lain
yang ikut tersaring). `_StatTile` dapat parameter opsional `breakdown`
(default kosong, tidak memengaruhi kartu "Total produk").

**Susulan visual (27 Juli)**: user minta nama produk & qty di-bold di 2
tempat kartu Pre-order — baris rincian item (`_preorderTile`) DAN baris
rincian jaminan (`_StatTile.breakdown`). Keduanya jadi `Text.rich` (dulu
`Text` polos) supaya sebagian teks bisa bold sebagian tidak —
`_StatTile.breakdown` type diganti dari `List<String>` jadi
`List<({String name, String qty})>` supaya nama & qty bisa jadi span
terpisah. **Gotcha lama (sudah didokumentasikan di CLAUDE.md) muncul
lagi**: `find.text`/`find.textContaining` polos TIDAK match `Text.rich` —
2 assertion existing disesuaikan `findRichText: true`. Test baru dibuat
via helper `findBoldableSpan` (traversal rekursif `TextSpan.children`,
krn `Text.rich(span)` selalu membungkus span kita 1 level ke dalam span
default tema) — revert-verified (bold dicabut sementara, test gagal
sensible "Expected FontWeight.w700, Actual null").

**Keputusan jaminan pre-order DIBALIK LAGI (27 Juli)**: user kirim
screenshot struk yg masih menampilkan "Titip 10" walau pre-order-nya
sudah "Dipenuhi" di dashboard, lalu MINTA EKSPLISIT disamakan dgn pola
Titip/Ketinggalan — temporary, hilang begitu terpenuhi. Ini MEMBALIK
keputusan sesi sebelumnya (yg sengaja bikin permanen atas permintaan
user YANG SAMA — lihat bagian "Redesain BESAR: Pre-order..." di bawah).
**Pelajaran**: kadang user berubah pikiran setelah lihat hasil nyata di
device — jangan asumsikan keputusan lama final selamanya, tapi JUGA
jangan langsung ubah tanpa konfirmasi kalau permintaan baru tampak
kontradiktif dgn permintaan eksplisit sebelumnya (sempat tanya balik via
`AskUserQuestion` sebelum eksekusi, walau akhirnya user jawab lewat chat
biasa bukan lewat pilihan). Fix: `getPreorderDepositForTransaction`
tambah filter `fulfilledAt.isNull() & cancelledAt.isNull()`. Test
`receipt_borrowed_section_test.dart` dibalik assersinya — revert-verified.

**Bug NYATA ditemukan: `_MarqueeText` terpotong permanen di skala font
besar (27 Juli)**. User kirim screenshot nama pelanggan "Buk..." yg
kepotong di kata kedua, BUKAN bergeser seperti seharusnya. Akar: `main.
dart` menerapkan pengali skala font GLOBAL (`fontScaleProvider` x faktor
ukuran layar) lewat `MediaQuery.textScaler` di root app — tapi
`TextPainter` internal `_MarqueeText` (dipakai MENGUKUR apakah nama
overflow) TIDAK menyertakan `textScaler` itu, jadi mengukur selalu di
skala 1.0 sementara `Text` sungguhan dirender lebih besar. Kalau device/
user setting bikin skala gabungan >1, pengukuran keliru simpul "muat"
padahal SEBENARNYA overflow -> kode jatuh ke cabang `Text` statis
ber-`overflow: TextOverflow.clip` PERMANEN, marquee tak pernah aktif.
Fix: tambah `textScaler: MediaQuery.textScalerOf(context)` di
`TextPainter` pengukur (satu baris, `kasir_screen.dart`).

**Gotcha test BARU ditemukan saat menulis regresinya** (penting kalau
menyentuh marquee/animasi rute lagi): `find.byType(Transform)` polos utk
mendeteksi "marquee aktif" MEMBERI FALSE POSITIVE — halaman kasir ini
navigasi via GoRouter/MaterialPage yg default `ZoomPageTransitionsBuilder`
(Material 3 di Android) JUGA membungkus konten rute dgn `Transform` saat
transisi. Fix test: pakai ancestor `OverflowBox` sbg penanda (satu-
satunya pemakaian `OverflowBox` di seluruh codebase, unik ke jalur
marquee). Juga: menentukan lebar teks "pas muat" scr MANUAL pakai
`TextPainter` di file test sendiri TIDAK BISA dipercaya — font ambient
app (`DefaultTextStyle`/tema Hanken Grotesk) beda dari font default
`TextPainter` polos tanpa `fontFamily` eksplisit, jadi perhitungan lebar
meleset. Fix: cari batas EMPIRIS lewat widget sungguhan (`pumpKasir` +
cek `OverflowBox` ancestor), bukan hitung manual.

**Susulan LANGSUNG (27 Juli): marquee berhenti PERMANEN jadi kelihatan
"kepotong" lagi.** Setelah fix textScaler di atas, user kirim screenshot
KEDUA: nama "Bu Khotimah" tetap tampil "Bu" statis. Bukan bug yg sama —
`_maxCycles=4` SENGAJA didesain berhenti SELAMANYA di posisi awal nama
stlh 4 putaran (~8-32 detik). Kasir yg baru lihat layar SESUDAH periode
itu (wajar — tidak nonton terus) melihat hasil yg PERSIS SAMA dgn bug
pemotongan yg baru "diperbaiki". Fix: `_startCycle` sekarang menjadwalkan
`_restTimer` (3 detik) setelah tiap putaran-nyala selesai, lalu MEMANGGIL
DIRINYA SENDIRI LAGI — bukan berhenti sekali lalu diam selamanya (masih
dibatasi PER putaran-nyala, bukan `repeat()` tanpa henti sama sekali,
demi alasan baterai + `pumpAndSettle` yg sama).

**Susulan LANGSUNG lagi (27 Juli): qty DESIMAL utk Titip/Ketinggalan.**
User: "bagaimana jika barang yang ketinggalan itu bentuk desimal? Misal
Filma 4.5kg?" — stepper +/-1 (baru ditambah) TIDAK BISA mencapai nilai
desimal sembarang murni dari langkah 1 (loncat 4.5→3.5→2.5..., tidak
pernah pas di "2" bulat). Fix: angka qty jadi `TextField` bisa diketik
bebas (keyboard desimal), stepper tetap ada utk kenyamanan qty bulat.
**Bonus bug ketemu**: stepper +1 versi sebelumnya bisa MELEBIHI batas qty
kalau sisa <1 (`qty>=item.qty?null:qty+1` — utk maks 4.5 dari 4, +1 jadi
5!) — fix klem ke `item.qty` PERSIS. **Gotcha dispose**: sempat coba
dispose `TextEditingController` qty tepat setelah `showDialog` selesai
→ crash "used after disposed" (dialog MASIH animasi keluar saat itu) —
dibiarkan TIDAK di-dispose eksplisit sama sekali, konsisten dgn
`customerController` di fungsi yg sama yg JUGA tak pernah di-dispose
(GC alami cukup utk `TextEditingController` transien dialog, bukan
resource native mahal).

## Rilis v2.3.0 — bersih-bersih menjelang rilis resmi (27-28 Juli)

Konteks: sebelum bikin tag rilis resmi pertama (sebelumnya semua rilis lewat
`main`/`claude/**` jadi pre-release `dev-<timestamp>`), user minta 4 hal:
bump versi, bersihkan file tak terpakai, pastikan codegen bersih (tidak ada
drift spt `migration_v24_test.dart` yg synthetic schema-nya ketinggalan
tabel baru), dan sinkronkan dokumentasi.

Versi kerja awal sempat dinaikkan ke `3.0.0+5` (bump MAJOR), tapi setelah
ditinjau ulang (tidak ada breaking change — semua migrasi backward-compatible),
diturunkan jadi `2.3.0+5` supaya sesuai semantic versioning (MINOR: tambah
fungsi cara backward-compatible, bukan MAJOR). Tag `v2.3.0` di-publish
LEWAT WEB UI GitHub (Releases → New release), BUKAN `git push` tag dari
CLI — proxy git sesi ini menolak (403) `git push` khusus untuk ref tag
(push commit/branch biasa tetap jalan normal), jadi utk sesi non-lokal
murni-GitHub, cara ini yang tervalidasi bekerja: pilih/tulis tag baru di
kolom "Choose a tag", target commit yang benar, pastikan bukan pre-release,
Publish — GitHub otomatis membuat tag & memicu `push: tags` event.

**Dependency dihapus dari `pubspec.yaml`** (diverifikasi per-paket via
`grep -rl "package:$pkg/" lib/` — tiap dependency lain punya ≥1 pemakaian
nyata, HANYA 3 ini yang nol):
- `riverpod_annotation` + `riverpod_generator` (dev) — TIDAK ADA `@riverpod`
  ataupun `.g.dart` hasil riverpod codegen di codebase manapun. Semua state
  memang manual `StateNotifierProvider`/`StateProvider` sejak awal.
- `printing` — 0 import. Ekspor PDF/Excel sudah lama pindah ke
  `FilePicker.saveFile` (lihat gotcha CLAUDE.md soal `Printing.sharePdf`
  OOM/gagal-diam), paket lama ini kepakai lagi.
- `flutter pub get` setelahnya otomatis drop 9 paket total (termasuk
  transitive: `analyzer_plugin`, `custom_lint_core`, `custom_lint_visitor`,
  `freezed_annotation`, `pdf_widget_wrapper`, `riverpod_analyzer_utils`, dst).

**File dihapus**: `preview/index.html` & `preview/phase6.html` — mockup
desain pra-implementasi ("Phase 6 Preview"), diverifikasi 0 referensi di
`.dart`/`.md`/`.yml` manapun, sudah lama digantikan app sungguhan.

**File yang SENGAJA DIPERTAHANKAN** (jangan dihapus lagi kalau audit
berikutnya menganggapnya "kelihatan tidak terpakai"):
- `docs/reference/*` — sample data asli dari user, tidak bisa dibuat ulang.
- `docs/PROPOSAL_PERTIMBANGAN_BAROKAH_ORDER.md` — rationale historis
  keputusan desain fitur "Tempel Pesanan", masih relevan sbg konteks.

**Verifikasi codegen bersih** (langsung menjawab kekhawatiran user soal
"codegen yg tidak bisa dijalankan cuma krn kode tidak match"): `rm -rf
.dart_tool/build` lalu `dart run build_runner build
--delete-conflicting-outputs` dari NOL — `app_database.g.dart` yang
dihasilkan cocok BYTE-PER-BYTE dgn yang sudah di-commit. Tidak ada drift.

**Ditemukan (bukan regresi, TIDAK diperbaiki — di luar scope)**: full suite
`flutter test` kadang gagal di `test/proposal_unchanged_end_to_end_test.dart`
dgn `SocketException: Address already in use, port 8625` — beberapa file
test LAN-sync (`lan_sync_slow_transfer_test.dart`,
`lan_sync_timeout_test.dart`, `sync_screen_proposal_layout_test.dart`) pakai
port hardcoded yg bisa bentrok saat dijalankan paralel. Dikonfirmasi lolos
100% saat file itu dijalankan sendirian — murni flakiness test-infra, bukan
bug produk. Perlu port dinamis per-test kalau mau dibenahi suatu saat.

**Dokumentasi diupdate**: `README.md` (tambah seksi fitur Laci Meja &
Sinkron Harga Antar Toko, update tabel teknologi, diagram arsitektur
`skema v25`) dan `CLAUDE.md` (hardcode `schemaVersion = 21` yg sudah basi
diganti jadi pointer ke kode, bukan angka statis).

**Hasil akhir**: versi `2.3.0+5`, full suite 832/832 hijau, `flutter analyze`
0 issue. Tag `v2.3.0` dipublish di commit merge `c78c489` (`main`, hasil
merge dari `claude/kategori-produk-qty-harga-mqjh21`) — ini rilis resmi
PERTAMA (sebelumnya semua rilis lewat pre-release otomatis). Workflow
`build-apk.yml` run #405 sukses, APK ter-attach ke release.

**FIXED — `revoked.json` dipindah ke GitHub Gist terpisah (bukan lagi di
repo `The-POS`)**: ditemukan pas user tanya soal rencana private-kan repo —
`license_provider.dart` sebelumnya fetch `revoked.json` via URL RAW
`raw.githubusercontent.com/Ikanuri/The-POS/main/license/revoked.json`, yang
SELALU butuh repo PUBLIC (unauthenticated raw fetch 404 di repo private).
Kill-switch juga cuma fail-safe utk device yang SUDAH pernah ke-cache
`revoked: true` — device BARU yang belum pernah fetch berhasil default
`cachedRevoked: false`, jadi tetap lolos aktivasi meski fetch gagal
(celah nyata, bukan cuma teoretis).

Fix: `_revokedListUrl` sekarang nunjuk ke **GitHub Gist public terpisah**
(`gist.githubusercontent.com/Ikanuri/ff6a99c3b1e642c81809b0664c8d681a/raw/revoked.json`
— TANPA hash revisi di URL, supaya selalu ambil versi TERBARU, bukan
snapshot beku). Gist punya visibility sendiri, independen dari status
private/public repo `The-POS` — jadi repo boleh private permanen TANPA
mematikan kill-switch. File `license/revoked.json` di repo DIHAPUS (bukan
lagi sumber kebenaran, mencegah drift dua-sumber). **Untuk revoke lisensi
ke depannya: edit Gist itu langsung di gist.github.com, BUKAN file di
repo** (filenya sudah tidak ada).

## ✅ Nama pelanggan terpotong — AKAR SESUNGGUHNYA ketemu (percobaan ke-3)

**WAJIB dibaca kalau ada laporan teks terpotong/tak muat lagi.** Tiga
percobaan; dua yang pertama bug NYATA tapi BUKAN akar keluhan user:

1. `cfebc31` — `textScaler` ambient tak diikutkan painter. Bug nyata,
   keluhan user TETAP ADA.
2. `99f1e88` — marquee berhenti PERMANEN stlh 4 putaran. Bug nyata juga,
   keluhan TETAP ADA (user konfirmasi eksplisit lewat `AskUserQuestion`:
   diam SELAMANYA, sudah ditunggu — bukan kebetulan kena jeda).
3. **AKAR SESUNGGUHNYA: `fontFamily` ambient diabaikan `TextPainter`.**

**PELAJARAN PALING PENTING — cara akhirnya ketemu**: BACA GEJALA VISUAL
DI SCREENSHOT SECARA PRESISI, jangan berhenti di deskripsi teks user.
"Buk Khotimah" tampil **"Buk" + RUANG KOSONG LEBAR** sebelum tombol ×.
Kalau marquee aktif lalu ter-clip krn sempit, yang tampil PASTI "Buk
Khotim…" MENGISI PENUH sampai batas clip. Kata kedua hilang tepat di
*word boundary* DAN menyisakan ruang kosong = itu **text WRAPPING**
(`maxLines: 1` menampilkan baris pertama saja), BUKAN clipping. Begitu
dibaca begitu, akarnya ketemu langsung tanpa tebak-tebakan lagi.
(Percobaan 1 & 2 gagal justru krn saya menduga-duga mekanisme animasi,
tidak menginterogasi gejala visualnya dulu.)

**Akarnya**: `_MetaChip` memberi `_MarqueeText` style
`TextStyle(fontSize: 12.5, ...)` yang SENGAJA **tanpa `fontFamily`** —
jadi `Text` sungguhan mewarisi **Hanken Grotesk** dari `DefaultTextStyle`
tema (`GoogleFonts.hankenGroteskTextTheme`, `app_theme.dart`), sementara
`TextPainter` yang diberi `TextSpan` style MENTAH memakai **font default
engine (Roboto)**. Hanken Grotesk lebih LEBAR → painter SELALU
under-measure → `overflow <= 0` → jatuh ke cabang `Text` biasa yang
(waktu itu) tanpa `softWrap: false` → wrap di spasi → tinggal kata
pertama.

**Fix**: (1) painter mengukur pakai
`DefaultTextStyle.of(context).style.merge(widget.style)` — style yang
PERSIS dirender; (2) `softWrap: false` di cabang non-marquee sbg jaring
pengaman: kalau pengukuran masih meleset tipis, teks terpotong MEPET
(nyaris tak kelihatan) bukan runtuh jadi kata pertama (yang terlihat
seperti data hilang).

**ATURAN UMUM**: setiap `TextPainter` yang dipakai untuk MEMUTUSKAN
layout WAJIB diberi style PERSIS SAMA dgn yang dirender — `DefaultTextStyle`
ambient (fontFamily, letterSpacing, height) DAN `MediaQuery.textScaler`.
Style mentah dari parameter widget hampir selalu TIDAK LENGKAP.

**Kenapa 3 test marquee sebelumnya LOLOS padahal bug-nya ada**: di
`flutter_test` GoogleFonts TIDAK BISA fetch font (tanpa jaringan), jadi
painter DAN `Text` sama-sama jatuh ke font fallback yang SAMA —
diskrepansinya HILANG, kelas bug ini MUSTAHIL direproduksi dgn tema app
apa adanya. Reproduksinya pakai PROXY deterministik: suntik
`letterSpacing` ke `theme.textTheme.bodyMedium` (properti style TURUNAN
lain yang juga melebarkan teks & juga tak terlihat painter mentah).
CATATAN: membungkus `DefaultTextStyle.merge` di LUAR router TIDAK BISA —
`Material` MENGGANTI (bukan merge) DefaultTextStyle dgn `bodyMedium`,
jadi harus lewat tema. Lihat param `ambientLetterSpacing` di `pumpKasir`
(`cart_bar_bayar_button_test.dart`).

**Pelajaran test**: konstanta empiris HARDCODE di test ("Karti" di test
`textScaler`) JADI BASI begitu logika pengukurannya diperbaiki — test itu
langsung gagal walau fix-nya benar. Test yang mencari batasnya SENDIRI
scr empiris (loop prefix + cek `OverflowBox`) tahan thd perbaikan
pengukuran berikutnya; pola itu yang dipakai sekarang.

**Susulan (27 Juli): qty SEBAGIAN utk Titip/Ketinggalan.** User: "kadang
yang ketinggalan hanya sebagian (tidak semua)" — checklist polos (fase
sebelumnya) selalu menyiratkan SELURUH qty baris nota, tidak bisa catat
mis. beli 5 ketinggalan cuma 2. Fix: `LeftBehindItems.qty` baru
(nullable — null = entri LAMA/seluruh qty, entri BARU selalu isi
eksplisit), migrasi v24->v25. Dialog "Catat Titip/Ketinggalan" dapat
stepper +/- per item (pola SAMA PERSIS `_showReturnSheet` yg sudah ada —
clamp 1..qty baris nota, default penuh saat dicentang). Penanda struk
& tile dashboard ikut menampilkan qty sebagian kalau ada.

**Gotcha migrasi test lama ikut kena (27 Juli)**: menambah schemaVersion
BARU (25) otomatis membuat SEMUA test migrasi lama (`migration_v7`
s.d. `v24`) yg mengasersi versi akhir via `PRAGMA user_version` GAGAL
(hardcode angka lama) — WAJIB disesuaikan tiap kali schemaVersion naik,
bukan cuma test migrasi yg BARU ditambah. `migration_v24_test.dart`
LEBIH RUMIT: skema sintetisnya HANYA `borrowed_items` (sengaja diisolasi
utk fokus 1 langkah migrasi), tapi migrasi v25 BARU (nambah kolom ke
`left_behind_items`) berjalan SETELAHNYA di chain yg sama — meledak "no
such table" krn tabel itu memang tak dibuat di skema sintetis tsb. Fix:
tambahkan `CREATE TABLE left_behind_items` (skema PERSIS versi v23,
sudah ada `transaction_item_id`) ke setup sintetis test itu juga.
**Pelajaran**: migrasi step BARU yg menyentuh tabel LAMA bisa mematahkan
test migrasi tak-terkait yg skema sintetisnya sengaja minimal/parsial —
cek SEMUA test migrasi (bukan cuma yg terasa relevan) tiap menambah
migration step baru.

**Gotcha test PALING RUMIT sesi ini**: membuktikan "istirahat lalu ulang
lagi" via polling offset itu SULIT krn `repeat(reverse:true)` SENDIRI
ALAMI menyentuh offset=0 berulang kali SAAT MARQUEE MASIH AKTIF (di titik
balik antara leg reverse & leg forward berikutnya, ~`2 * jeda(0.18) *
durasi` detik) — kalau nama yg dites overflow-nya BESAR (durasi diklem
ke maksimum 8 detik), jeda alami ini bisa sampai ~2.9 detik, HAMPIR SAMA
dgn `_restPause` (3 detik) yg mau dibuktikan — bikin test SALAH POSITIF
(lolos walau fix dicabut, krn "jeda alami" itu sendiri disalahartikan
sbg "istirahat sungguhan"). Fix: pilih nama yg overflow-nya SEMINIMAL
mungkin (bukan nama sangat panjang) supaya durasinya diklem ke MINIMUM (2
detik) — jeda alami jadi cuma ~0.72 detik, jauh di bawah ambang deteksi
1.5 detik yg dipakai test, sementara `_restPause` (3 detik) tetap jelas
di ATASnya. Revert-verify JUGA harus mensimulasikan ULANG flag `_done`
(guard "sudah selesai, jangan restart") yg lama — sekadar menghapus baris
penjadwalan `_restTimer` TIDAK CUKUP mensimulasikan kode lama, krn tanpa
flag itu `_sync` akan restart lagi begitu widget rebuild krn alasan LAIN.

## Dashboard Laci Meja: grouping Pre-order (per-nota) & Pinjaman (per-pelanggan)

Susulan redesain Pre-order besar (bagian di bawah) — user minta 2
penyesuaian tampilan dashboard, plus 1 fitur baru di struk:

1. **Pre-order** — grouping SAMA persis Titip/Ketinggalan (per
   `transactionId`, satu Card per nota), TAPI beda format konten: header
   Card = NAMA PELANGGAN bold (SEKALI per grup, bukan diulang tiap
   baris spt Titip/Ketinggalan), tiap baris produk format ringkas
   `"[qty] [nama produk] - [qty jaminan]"` (bagian jaminan cuma muncul
   kalau `depositQty > 0`). Butuh JOIN baru
   `getProductUnitLabelsFor(productUnitIds)` (`app_database.dart`) krn
   `PreorderEntries` cuma simpan `productId`/`productUnitId`, TIDAK
   simpan nama produk cache (beda dari `LeftBehindItems.itemName` yg
   sudah simpan nama langsung).
2. **Pinjaman — grouping BEDA dari 2 kategori lain**: PER-PELANGGAN
   (`customerId` kalau ada, fallback nama teks, fallback `'anon'`),
   BUKAN per-nota — krn satu pelanggan bisa pinjam di BEBERAPA nota
   beda-beda waktu, semua harus kelihatan jadi satu daftar biar
   trackingnya utuh. Tiap baris di dalam grup TETAP tertaut ke
   `transactionId` MILIKNYA SENDIRI (bisa beda-beda per baris dalam satu
   grup) — jadi tap satu baris redirect ke NOTA baris itu, bukan nota
   pertama yg kebetulan ada di grup.
3. **Penanda "Pinjaman" di struk in-app** ("rujukan kebenaran" —
   permintaan user: staf bisa cek nota asli utk konfirmasi barang apa
   yg benar dipinjamkan) — butuh kolom BARU
   `BorrowedItems.transactionItemId` (migrasi schemaVersion 23→24, pola
   identik `LeftBehindItems.transactionItemId` dari migrasi v23) utk
   tautan PRESISI (bukan cocok-nama — sama alasan kenapa
   `LeftBehindItems` butuh kolom itu duluan: produk sama bisa muncul 2x
   di satu nota dgn satuan beda). **Konsekuensi**: dialog "Catat
   Pinjaman Barang" (`receipt_screen.dart`) DIROMBAK dari `TextField`
   nama+qty bebas jadi CHECKLIST barang nyata di nota ini (pola identik
   `_showLeftBehindDialog`) — perlu diketahui kalau menyentuh dialog ini
   lagi: qty pinjaman SEKARANG otomatis = qty produk di baris nota
   (bukan input manual terpisah lagi). Penanda tampil TERLEPAS status
   sudah/belum kembali (nota = bukti historis permanen, bukan indikator
   status hidup — SENGAJA, lihat komentar di
   `getBorrowedMarkersForTransaction`).

Test baru: `laporan_tab_left_align_test.dart`, `migration_v24_test.dart`,
+6 test di `laci_meja_dashboard_grouping_test.dart` (grup Pre-order & 2
test Pinjaman), `receipt_borrowed_marker_test.dart` (3 kasus) — semua
revert-verified. `receipt_catat_laci_meja_test.dart` disesuaikan ke
checklist Pinjaman baru. Full suite: **809 test hijau**, `flutter
analyze` 0 issue.

## Redesain BESAR: Pre-order nyambung ke keranjang/nota (ganti total jalur lama)

Permintaan user, dikonfirmasi lewat 4 `AskUserQuestion` sebelum coding
(krn perubahan arsitektur besar, salah tebak = banyak kerja ulang):
ganti TOTAL 2 jalur lama ("+ Antri" di pencarian Kasir, "Catat Pre-order"
di Cek Stok — keduanya dialog terpisah `preorder_entry_dialog.dart`,
`transactionId` SERING NULL) jadi SATU jalur baru via `ItemEntrySheet`
(modal tap item produk kasir).

**Alur baru**: kartu "Pre-order?" muncul HANYA saat `_markedOutOfStock`
true (state lokal di `ItemEntrySheet`, reaktif — toggle habis on/off
langsung memunculkan/menyembunyikan kartu tanpa reload). Toggle Ya/Tidak
(default Tidak) → toggle "DP?" (Ya = harga penuh & `paid=true`, dibayar
lunas sekarang; Tidak/default = harga dipaksa 0, `paid=false`, dicatat
dulu bayar nanti) → field "Jumlah jaminan dititip" (HANYA muncul bila
`sel.unit.requiresDeposit`, default = qty pesanan, bisa diubah manual).

**Field baru di `CartItem`** (`lib/core/models/cart_item.dart`):
`isPreorder`, `preorderPaid`, `depositQty` — full round-trip di
`copyWith`/`toJson`/`fromJson` (pola sentinel `_unset` utk `depositQty`
sama seperti `itemNote`).

**Checkout** (`payment_screen.dart`, KEDUA jalur — transaksi baru
`_confirmPayment` DAN tambah-belanjaan `_confirmAddItems`): setelah
`saveTransaction`/`addItemsToTransaction`, loop `cart.where((i) =>
i.isPreorder)` menulis `db.addPreorderEntry(...)` dgn `transactionId:
txId` OTOMATIS (bukan lagi via dialog terpisah tanpa tautan) —
inilah yg bikin tap-redirect-ke-nota di dashboard Laci Meja langsung
jalan tanpa kerja tambahan. **Keputusan penting (dikonfirmasi user)**:
item pre-order DIKECUALIKAN dari `stockItems` (pengurangan stok) di
KEDUA jalur checkout — barangnya belum ada fisik di toko, stok baru
bergerak nanti saat direstock sungguhan; kalau ini tidak dikecualikan,
produk yg SUDAH minus/habis akan tambah minus lagi hanya krn dipesan.

**Dihapus total**: tombol "+ Antri" (`kasir_screen.dart`, grid & list
tile), tombol "Catat Pre-order" + param `onPreorder` (`cek_stok_screen
.dart`), file `preorder_entry_dialog.dart`, dan 2 test lamanya
(`kasir_preorder_entry_test.dart`, `cek_stok_preorder_entry_test.dart` —
menguji jalur yg sudah tidak ada).

**Label "Titip [qty]"** (jaminan) ditambahkan di 2 tempat, keduanya
DISATUKAN ke text run nama produk yg sama (`Text.rich`, BUKAN `Text`
terpisah + `SizedBox` gap) — permintaan user eksplisit: posisi persis
pola badge "Habis" di katalog kasir (`'${name} · Habis'`, satu run,
tanpa jarak tambahan):
1. `cart_sheet.dart` — `_CartItemTile` title, kalau `item.depositQty >
   0`.
2. `receipt_screen.dart` — title item struk, gabungan SEMUA penanda
   (Dititip/Ketinggalan DAN Titip-jaminan) jadi satu `Text.rich` dgn
   banyak `TextSpan`. Butuh query baru `getPreorderDepositForTransaction`
   (`app_database.dart`, key `'$productId|$productUnitId'` krn
   `PreorderEntries` TIDAK simpan `transactionItemId`, beda dari
   `LeftBehindItems` yg sudah punya kolom itu sejak migrasi v23).

**Gotcha test PENTING** (bakal kena lagi kalau ada yg convert `Text`
lain jadi `Text.rich` di masa depan): `find.text(name)` HANYA cocok
`Text` widget dgn `.data` persis — begitu diganti `Text.rich`, PECAH
semua test yg pakai `find.text(nama_produk)` polos utk membaca style
(3 file lama pecah: `receipt_item_name_bold_test.dart`,
`receipt_qty_unit_bold_test.dart`, `laci_meja_marks_and_reminder_test
.dart`). Fix: (a) `find.textContaining(x, findRichText: true)` utk
sekadar cek keberadaan teks; (b) utk baca STYLE span tertentu, cari
`RichText` via `find.byType(RichText)` + `.text.toPlainText() == '...'`,
LALU descend SATU LEVEL ke `(richText.text as TextSpan).children!
.first` — `Text.rich(mySpan)` SELALU membungkus `mySpan` sbg CHILD dari
TextSpan LUAR (default style bawaan tema), jadi `richText.text.style`
langsung TIDAK PERNAH mencerminkan style yg kita set sendiri (selalu
w400 normal, bukan span kita).

Test baru: `item_entry_preorder_test.dart` (6 kasus: card visibility,
DP toggle, deposit qty conditional+default), `payment_preorder_checkout_
test.dart` (2: transactionId terisi + stok tidak terpotong, DP Ya ->
paid=true), `cart_sheet_preorder_deposit_label_test.dart` (1) — semua
revert-verified. Full suite sesudah semua ini: **801 test hijau**,
`flutter analyze` 0 issue.

**Pelajaran**: laporan visual user ("ada gap/renggang") bisa BUKAN
merujuk ke hal yang paling jelas kelihatan sekilas dari kode (jarak
antar-baris yg memang ada bug margin-nya) — screenshot beranotasi PANAH
dari user jauh lebih presisi drpd menebak dari deskripsi teks semata.
Kalau fix pertama sudah dikonfirmasi live tapi keluhan MASIH ADA, JANGAN
coba varian fix yg sama lagi — minta gambar beranotasi lebih dulu.

## Redesain menu cepat Kasir/Laci Meja + 2 perbaikan lain (putaran kedua)

User minta 4 hal lagi setelah putaran redesign pertama:

1. **Animasi smooth muncul/hilangnya menu cepat** — `_QuickMenuPopup`
   baru (`main_shell.dart`), `StatefulWidget` dgn `SingleTickerProvider
   Mixin`: `FadeTransition`+`ScaleTransition` (durasi 160ms, `Curves.
   easeOutBack` utk scale, `alignment: Alignment.bottomCenter` biar
   terasa "tumbuh dari tab Kasir"). Tutup (tap area luar ATAU pilih item)
   WAJIB `await _controller.reverse()` dulu baru `onRemove()` (lepas
   `OverlayEntry`) + `onSelect()` (navigasi) — urutan animasi-keluar dulu
   baru aksi, bukan sebaliknya. **Gotcha test PENTING**: `Tooltip` bawaan
   Flutter (dipakai `_QuickMenuIcon`) JUGA punya `FadeTransition` sendiri
   internal — `find.byType(FadeTransition).first` TANPA `Key` eksplisit
   bisa salah tangkap widget Tooltip (opacity selalu 0, bukan punya kita)
   alih-alih punya kita, GANTI-GANTI tergantung urutan build/pumpAndSettle
   — WAJIB pasang `Key('quickMenuFade')` di `FadeTransition` sendiri &
   query lewat `find.byKey`, bukan `find.byType().first`. Revert-verified
   (duration `Duration.zero` -> opacity langsung 1.0, gagal sensible).
2. **Barang Titip/Ketinggalan dari NOTA YANG SAMA dikumpulkan jadi SATU
   frame (`Card`)** — dashboard Laci Meja (`laci_meja_dashboard_screen.
   dart`) dulu render flat `ListView.separated` per-barang (screenshot
   user: 5 baris nyaris identik, tidak jelas mana yg satu nota). Sekarang
   di-`groupBy transactionId` (`Map` biasa, insertion-order = FIFO
   otomatis mengikuti `watchLeftBehindItems` `ORDER BY created_at`), tiap
   grup jadi satu `Card` berisi N `ListTile` (dipisah `Divider` internal).
   Tap tiap `ListTile` tetap individual redirect ke nota (sama tujuannya
   krn satu grup = satu `transactionId`).
3. **Qty+satuan ditampilkan per barang** — butuh JOIN baru
   `getQtyUnitForTransactionItems` (`app_database.dart`, satu query utk
   sekumpulan `transaction_items.id`, BUKAN N+1) + provider
   `leftBehindQtyUnitProvider` (`laci_meja_provider.dart`). Entri LAMA
   tanpa `transactionItemId` (dibuat sebelum kolom itu ada, migrasi v23)
   tetap tampil TANPA qty — bukan error, memang tidak bisa dipetakan ke
   baris nota manapun.
4. **Tombol "Sudah Diambil" diredesain minimal** — `_CollectButton` baru:
   pill kecil `StadiumBorder` (bukan kotak persegi `TextButton` lama),
   ikon centang + label singkat "Ambil".

Test baru `laci_meja_dashboard_grouping_test.dart` (3 kasus: grouping,
qty/satuan tertaut vs tidak, tombol Ambil) + 1 test animasi di
`laci_meja_bottom_nav_gesture_test.dart` — semua revert-verified. Full
suite sesudah semua ini: **794 test hijau**, `flutter analyze` 0 issue.

## Redesain menu cepat Kasir/Laci Meja + 2 perbaikan lain (putaran pertama)

User minta 6 hal sekaligus; 4 poin pertama satu redesign menu, 2 sisanya
perbaikan terpisah:

1-4. **Menu tekan-tahan tab Kasir dirombak total** dari `showMenu`
   (`PopupMenuItem` teks) jadi `OverlayEntry` custom di
   `main_shell.dart`: (1) posisi DI ATAS bottom bar (dihitung dari
   `_bottomBarKey.currentContext` render box top, BUKAN dari titik jari
   spt versi lama yg kadang nongol ke samping); (2) HANYA ikon, label
   teks "Buka Kasir"/"Buka Laci Meja" dihapus (pakai `Tooltip` utk
   aksesibilitas & sbg pegangan test, bukan `Text` visible); (3) sudut
   rounded via `ClipRRect(borderRadius: circular(20))`; (4) delay
   tekan-tahan dipercepat 500ms→250ms — `GestureDetector` biasa TIDAK
   bisa custom durasi long-press, wajib `RawGestureDetector` +
   `LongPressGestureRecognizer(duration:)` eksplisit. Test lama
   `laci_meja_bottom_nav_gesture_test.dart` disesuaikan (`find.byTooltip`
   ganti `find.text`) + 3 test baru (icon-only, posisi+rounded, delay
   300ms cukup) — semua revert-verified.
5. **`RingkasanTab` "agak renggang"** — akar: `Card` Material 3 punya
   margin bawaan `EdgeInsets.all(4)`, dipasang berulang di 4 baris KPI yg
   SUDAH punya `SizedBox(height:12)` eksplisit antar baris → jarak
   sungguhan 12+4+4=20px, tidak sesuai desain. Fix: `margin:
   EdgeInsets.zero` khusus di Card KPI (`_KpiRow`) — Card lain di tab yg
   sama (payment method, chart harian) SENGAJA tidak disentuh, konsisten
   dgn tab laporan lain yg juga tidak override margin. Test baru
   `ringkasan_kpi_card_margin_test.dart` — revert-verified.
6. **Struk share (gambar) qty tidak bold lagi** — `_ReceiptPaper` baris
   qty+satuan+harga dulu w600 (revisi lama), disederhanakan jadi `Text`
   polos style `_mono` (normal). PENTING: user spesifik bilang "struk
   share" — struk IN-APP (`_ItemRow` biasa, bukan `_ReceiptPaper`)
   SENGAJA TIDAK disentuh, masih w600 sesuai
   `receipt_qty_unit_bold_test.dart` yg sudah ada duluan (dua widget
   BEDA, jangan disamakan kalau menyentuh ini lagi). Test baru
   `receipt_paper_qty_not_bold_test.dart` — revert-verified.

Full suite sesudah keenam poin: **790 test hijau**, `flutter analyze` 0
issue.

## Penyesuaian susulan (Bayar kanan + jenis Laci Meja, sesudah 4 perbaikan UI, commit `45ede18`)

User beri 2 catatan kecil setelah cek hasil 4 perbaikan UI:

1. **"Bayar" harus tetap di kanan walau cart bar melipat 2 baris.** Fix
   sebelumnya (`Wrap` tunggal utk Pelanggan/Pegawai/Tahan/Bayar) membiarkan
   Bayar ikut hanyut ke mana pun sisa ruang jatuh begitu melipat. Sekarang
   `_CartMetaTab` (`kasir_screen.dart`) pakai `Row` terluar: `Expanded(Wrap(
   ...))` menampung 3 chip kiri (boleh melipat bebas), Bayar jadi elemen
   `Row` TERAKHIR di luar Wrap itu — posisinya selalu di ujung kanan,
   independen dari berapa baris kiri melipat. Test baru di
   `cart_bar_bayar_button_test.dart` (nama pelanggan sangat panjang @420px,
   verifikasi tepi kanan `find.text('Bayar')` tidak bergeser dibanding
   sebelum nama diisi) — revert-verified (layout `Wrap` lama gagal dgn
   selisih ~260px, sensible).
2. **Keterangan Laci Meja harus sebut jenis yang benar.** `getLaciMeja
   PendingForCustomer`/`ForName` (`app_database.dart`) dulu menggabung
   `titip`+`ketinggalan` jadi satu angka `titipKetinggalan`, dan
   `LaciMejaReminder.summaryOf` SELALU menulis "N barang dititip" — barang
   yang jenisnya `ketinggalan` (ketinggalan tanpa sengaja) ikut tertulis
   seolah dititip sengaja. Record dipecah jadi `{titip, ketinggalan,
   pinjaman, preorder}` (dihitung per `jenis` dari `LeftBehindItems`),
   `summaryOf` sekarang punya klausa terpisah "N barang dititip" DAN/ATAU
   "M barang ketinggalan". Propagasi lewat `laciMejaPendingProvider`
   (`lib/core/providers/laci_meja_provider.dart`) & `_laciMejaPending`
   (`payment_screen.dart`). Test baru di
   `laci_meja_marks_and_reminder_test.dart` — revert-verified.

Test suite penuh sesudah kedua fix: **785 test hijau**, `flutter analyze`
0 issue.

## Item 52 ("Laci Meja") — SELESAI TOTAL, ringkasan implementasi

Fitur lengkap: Titip/Ketinggalan, Pinjaman Barang, Pre-order (termasuk
antrian tabung LPG), plus layar review usulan owner. Rancangan detail
sudah dihapus dari PLAN.md (selesai dieksekusi, sesuai konvensi) — kalau
perlu rujuk lagi detail bisnis rules/skema, baca commit-commit `feat:
Laci Meja (Item 52) fase N` di riwayat, atau `git show` satu-satu.

- **Fase 1-3** (`2411e17`): skema (schemaVersion 21->22), DB layer CRUD,
  sync (host->klien auto-merge, klien->host via antrian usulan PARALEL
  yg tidak menyentuh alur usulan produk Item 40).
- **Fase 4+8** (`955551c`): dashboard `/laci-meja` + gesture tekan-tahan
  tab Kasir di bottom nav.
- **Fase 5** (`50d778f`): tombol "+ Catat" di Struk.
- **Fase 6** (`e5fe487`): dua jalur entry Pre-order (Kasir + Cek Stok).
- **Fase 7** (`8f9e667`): toggle "Butuh Jaminan Fisik" di form produk.
- **Fase 9 fix** (`ec7257e`): 11 test migrasi lama disesuaikan (assert
  versi 21->22, + 7 di antaranya butuh tabel `product_units` sintetis
  baru krn migrasi v22 menyentuhnya) — bukan bug produksi.
- **Susulan review UI** (`d25b8f2`): layar review usulan Laci Meja utk
  owner (`LaciMejaProposalReviewScreen`, kartu "Usulan Laci Meja" di
  `SyncScreen`) — bagian yang sempat ditunda di commit fase 1-3, sekarang
  sudah ada. `SyncState.laciMejaProposals` diwire ke
  `LanSyncService.onLaciMejaProposalsChanged`.
- **Koreksi rute + pewarisan pelanggan** (`3c7df58`, laporan user dari
  DEVICE ASLI, sesudah `35495aa` ternyata masih bermasalah):
  1. Redirect ke nota menampilkan **halaman BLANK**. Akar: `/laci-meja`
     ditaruh di LUAR `ShellRoute` (biar bottom nav hilang), sedangkan
     `/kasir/struk/:txId` bersarang DI DALAM shell — push lintas batas
     shell bikin shell baru ter-mount dgn body kosong. Fix mengikuti
     arahan user "bandingkan dgn pendekatan laporan hutang": dashboard
     dipindah KE DALAM shell sbg **`/kasir/laci-meja`** (anak `/kasir`,
     sebelah `/kasir/struk/:txId`) — persis situasi Buku Hutang yang
     sudah lama terbukti. Bottom nav ikut tampil, konsisten dgn Struk.
  2. Nama pelanggan tidak tampil di kartu → sekarang **diwarisi dari
     nota** (dialog pra-isi + `customerId` nota ikut disimpan).

  **PELAJARAN PENTING (jangan terulang)**: test navigasi dgn router
  TIRUAN buatan sendiri (tanpa `ShellRoute`) **TIDAK PERNAH** bisa
  menangkap kelas bug batas-shell — `laci_meja_dashboard_redirect_test.
  dart` lulus hijau sementara device asli blank. Test navigasi WAJIB
  pakai `routerProvider` ASLI (lihat `laci_meja_dashboard_redirect_
  real_router_test.dart`). Pola umumnya: kalau menambah layar baru,
  IKUTI struktur rute layar sejenis yang sudah ada di produksi, jangan
  bikin penempatan rute baru yang belum pernah dipakai di app ini.

- **Koreksi UX** (`35495aa`, setelah user menjelaskan 2 kesalahpahaman
  desain awal):
  1. "Barang ketinggalan" WAJIB ditaut ke produk NYATA yang ada di nota
     — dialog "Catat Titip/Ketinggalan" diganti dari TextField nama
     bebas jadi checklist produk di nota ini (toggle centang 1+ barang
     sekaligus), `itemName` diambil dari nama produk asli.
  2. "Link ke nota" yang dimaksud user BUKAN sekadar kolom
     `transactionId` tersimpan (itu sudah ada sejak fase 1), tapi TAP
     kartu di dashboard Laci Meja harus redirect ke struk terkait —
     ditambahkan `onTap` di 3 daftar dashboard, mekanisme identik
     `HutangTab` (`context.push('/kasir/struk/:txId')`). Pre-order (satu-
     satunya `transactionId` NULLABLE) di-guard: redirect hanya kalau
     ada, kasus titip-wadah-tanpa-beli sengaja tidak navigasi apa pun.
  **Pelajaran**: setelah demo/deskripsi fitur ke user, JANGAN asumsikan
  "link ke nota" berarti kolom FK tersimpan sudah cukup — user sering
  memaksudkan MEKANISME NAVIGASI UI yang konkret (spt pola yang sudah
  ada di fitur lain, mis. Lacak Hutang). Tanyakan pola UI acuan yang
  dimaksud kalau istilah "link"/"terhubung" ambigu.

**Bug nyata ditemukan & diperbaiki SELAMA build** (bukan pra-eksisting):
`applyLaciMejaProposals` awalnya `customInsert` tanpa param `updates:` —
baris berhasil tertulis ke DB tapi `.watch()` tidak refresh (gotcha yang
SAMA PERSIS sudah didokumentasikan di bagian Gotcha CLAUDE.md, ternyata
masih bisa lolos ke kode BARU juga — pelajaran: pola lama tetap harus
diperiksa ulang di kode baru, bukan diasumsikan otomatis dihindari).

**Gotcha baru ditemukan saat menulis test widget** (sudah cukup penting
utk dicatat, belum masuk CLAUDE.md — pertimbangkan menambahkannya bila
sesi depan mengonfirmasi berulang): memanggil `db.watchXxx().first`
LANGSUNG di dalam `testWidgets` pada instance `db` yang SAMA dgn yang
dipakai widget tree, SETELAH interaksi widget → bikin test **hang tanpa
batas waktu** persis di langkah drain (`pumpWidget(SizedBox())`), bukan
pada saat query-nya sendiri (query-nya sendiri selesai dgn benar). Fix:
pakai one-shot `db.select(db.table).get()` alih-alih `.watch().first`
utk verifikasi state di widget test.

**Belum sempat/sengaja ditunda** (kosmetik/keputusan desain, bukan
fungsional — tidak menghalangi status "selesai"):
- Ambang warna umur (hijau/kuning/merah) di dashboard Laci Meja pakai
  angka sementara (7/30 hari, sama seperti `HutangTab`) — user belum
  pernah diminta konfirmasi ambang spesifik utk kategori ini.
- Hint UX utk gestur tekan-tahan (yang "tersembunyi"/tanpa affordance
  visual) belum dibuat — didiskusikan sbg kebutuhan follow-up saat
  desain, belum diimplementasi.

## Fix: kembalian terakhir di Ringkasan struk in-app di-bold (26 Juli)

User: "di struk in app, kembalian terakhir (bukan riwayat) itu
highlight/bold". `_ChangeTakenRow` (widget yg sama dipakai di 2 tempat:
baris Ringkasan atas & baris per-pembayaran di kartu Riwayat Pembayaran)
dapat parameter `bold` baru (default false — TIDAK mengubah tampilan
Riwayat Pembayaran), di-set `true` HANYA di baris Ringkasan (nominal yg
harus benar-benar diserahkan sekarang, beda dari histori). Test
`receipt_change_taken_bold_test.dart` memverifikasi 2 `Text('Kembalian')`
yg match `find.text('Kembalian')` — pertama (Ringkasan) harus `w700`,
kedua (Riwayat Pembayaran) harus TETAP normal.

## Fitur: non-stok produk utama + jeda stok semua produk (26 Juli)

User tanya "adakah fitur produk bisa diset ke non stok?" — ternyata SUDAH
ada tapi HANYA utk varian (`_variantDialog` "Lacak stok varian" di
`produk_form_screen.dart`, dipakai `createVariant`/`updateVariant`).
Produk utama (base unit / satuan tambahan lewat `_UnitCard`) selalu hardcode
`isNonStock: const Value(false)` — tak pernah bisa diubah dari UI. User
minta ditambahkan, lalu SUSUL minta "set semua produk ke non stok untuk
sementara".

**Bagian 1 — toggle per satuan**: `_UnitEntry` (`produk_form_screen.dart`)
dapat field `isNonStock` baru (default false, dimuat dari `ProductUnit.
isNonStock` saat edit) + `SwitchListTile` "Lacak stok" di `_UnitCard`
(persis gaya "Lacak stok varian"), diletakkan setelah baris ratio/barcode.
`saveProduct`'s hardcode `Value(false)` diganti `Value(u.isNonStock)`.
Berlaku baik di satuan dasar maupun satuan tambahan (tiap `ProductUnit`
punya kolom sendiri) — TIDAK ada logika baru yg memaksa semua satuan 1
produk konsisten; kalau produk py 2+ satuan & user mau semuanya non-stok,
toggle tiap kartu (jarang jadi masalah krn kebanyakan produk cuma 1 satuan).

**Bagian 2 — jeda massal, reversibel**: `AppDatabase.
pauseStockTrackingForAllProducts()`/`resumeStockTrackingForAllProducts()`/
`isStockTrackingPaused()` — snapshot id `product_units` yang MASIH dilacak
(`isNonStock=false`) disimpan sbg JSON di `app_settings` key
`stock_pause_snapshot` SEBELUM di-set semua jadi non-stok; resume membaca
snapshot itu balik & HANYA memulihkan id-id itu (bukan "semua produk jadi
tracked lagi" polos) — satuan yang MEMANG sudah non-stok dari awal (mis.
varian jasa) tidak pernah tersentuh sama sekali di kedua arah. Idempoten:
pause 2x / resume tanpa sedang dijeda = no-op (return 0). Toggle
"Jeda Pelacakan Stok" baru di Pengaturan > Manajemen Data (kartu merah,
owner-only), dgn dialog konfirmasi saat MENYALAKAN (efeknya luas — SEMUA
produk), tanpa konfirmasi saat mematikan (resume aman/diharapkan).

**Belum/tidak dikerjakan**: tidak ada UI/laporan yang menunjukkan APA SAJA
yang sedang dijeda (cuma toggle on/off + snapshot count di snackbar) — kalau
user butuh lihat daftar produk yang kena, itu perluasan terpisah, belum
diminta.

Test baru: `produk_form_non_stock_toggle_test.dart` (2 kasus, salah satunya
lewat `routerProvider` sungguhan krn "Simpan Produk" memanggil
`context.pop()` yg butuh GoRouter asli — `pumpWithFakeApp` tanpa router
akan crash "No GoRouter found"), `stock_pause_db_test.dart` (4 kasus DB
murni), `pengaturan_stock_pause_toggle_test.dart` (1 kasus end-to-end
toggle ON→OFF via UI) — semua revert-verified.

## Fix: pembayaran dibatalkan ikut tercetak/ter-share di struk (26 Juli)

User kirim 2 foto: struk kertas (3 baris "Tunai Rp150.000" identik) vs
layar in-app "Struk" (kartu Riwayat Pembayaran yg BENAR menampilkan 2 dari
3 itu sbg "Dibatalkan" dgn coretan). Kertas termal tidak bisa mencetak
coretan, jadi 2 pembayaran yg sudah batal terlihat identik dgn yg asli di
struk fisik — pelanggan bisa salah kira dibayar 3x.

**Akar**: `_visiblePayments` getter (`receipt_screen.dart`, dipakai widget
`_ReceiptPaper` khusus utk share-image) & `visiblePayments` local var
(`printer_service.dart`, dipakai builder ESC/POS cetak fisik) SAMA-SAMA
sudah filter `method != 'edit' && method != 'retur'` (Item 49f, marker
audit internal) tapi LUPA filter `voided` — padahal `_refundTotal`/
`_refundMethod` di FILE YANG SAMA (`_ReceiptPaper`) sudah benar pakai
`!p.voided`. Simpel oversight, bukan bug baru — sudah ada sejak
`voidPayment` (Item pembatalan pembayaran) dibuat.

**Fix**: tambah `&& !p.voided` di kedua tempat. In-app SENGAJA TIDAK
disentuh — kartu "Riwayat Pembayaran" (bagian LAIN dari `receipt_screen.
dart`, bukan `_ReceiptPaper`) memang harus tetap tampilkan semua incl. yg
dibatalkan (dgn coretan), itu satu-satunya tempat histori lengkap ada.

Test baru `receipt_paper_voided_payment_hidden_test.dart` (mirip pola
`receipt_paper_audit_marker_hidden_test.dart` yg sudah ada utk marker
audit 'retur'/'edit') — revert-verified.

## Layar Cek Duplikat Data (Pengaturan > Diagnostik) — susulan temuan Amplop

User cek sendiri produk "Amplop" di device HOST-nya (screenshot) — 2
barcode berlabel "Primer" sekaligus, padahal form Edit Produk cuma py 1
field Barcode. Awalnya kukira bug orphan-cleanup di atas (client-side), tapi
user klarifikasi: **ini di device HOST**, bukan klien — jadi bug sync di
atas tidak relevan langsung (host tidak pernah `mergeRows` data
`product_barcodes` masuk dari mana pun, tabel ini SATU ARAH host→bawah).

Ditelusuri lebih lanjut, user konfirmasi: **host pernah restore backup FULL
dari device client** (dulu krn ada produk yang tidak muncul). Itu akar
masalahnya — `restoreFromDump` (`app_database.dart`) DELETE seluruh tabel
lalu `INSERT OR REPLACE` verbatim dari isi file backup, TANPA cek invarian
apa pun ("1 barcode Primer per satuan", dst). Device client itu sudah kena
duplikat (dari bug orphan-cleanup di atas, SEBELUM fix-nya ada), jadi
restore membawa duplikatnya mentah² ke host.

**Fitur baru**: `AppDatabase.findMasterDataDuplicates()` — scan
`product_barcodes`/`price_tiers`/`alt_prices` (3 tabel yang SAMA-SAMA
rentan krn full-dump tanpa `updated_at`) cari unit dgn >1 baris yg
seharusnya unik (>1 `isPrimary=true`, min_qty dobel, label Harga Lain
dobel). Layar baru `DuplicateDataScreen` (`/pengaturan/duplikat-data`,
owner-only, di section Diagnostik) melaporkan produk yg kena + tautan ke
Edit Produk masing².

**Keputusan desain penting**: TIDAK auto-delete. Tabel-tabel ini tak punya
kolom waktu, jadi tidak ada cara algoritmik menentukan baris mana yang
"benar" (mis. barcode mana yg labelnya sudah tercetak & dipakai kasir) —
kalau auto-pilih salah, bisa membuang barcode yang justru masih dipakai.
Owner yg tinjau manual & tekan "Simpan Produk" — `saveProduct` sudah
otomatis delete-semua-primer-lama-lalu-insert-satu-baru, jadi resave polos
(tanpa ubah apa pun) sudah cukup merapikan.

**Belum dikerjakan / menggantung**: user belum menjalankan/cek layar ini
di device asli utk tahu berapa banyak produk lain yg kena (screenshot
Amplop cuma 1 sample yg kebetulan ketemu manual). `restoreFromDump` sendiri
juga BELUM diperbaiki utk MENCEGAH duplikat masuk lagi di masa depan (mis.
dedup saat restore) — scope sesi ini murni deteksi+laporan, bukan
pencegahan di titik masuknya data.

## Fix: barcode/tier grosir/Harga Lain lama tidak terhapus di klien (25 Juli)

User laporan: owner edit barcode produk di host → setelah sync ke client,
barcode LAMA masih ada (bisa di-scan) BERDAMPINGAN dgn yg baru. Diprobe
langsung (bukan cuma baca kode) sebelum menyimpulkan.

**Akar masalah**: `saveProduct` HAPUS baris lama + INSERT baris baru (id
UUID baru) saat barcode/tier/Harga Lain diedit — bukan update in-place.
`product_barcodes`/`price_tiers`/`alt_prices` SELALU full-dump tanpa
`updated_at` (lihat `dumpSince`), jadi `INSERT OR REPLACE` di `mergeRows`
tidak PERNAH menghapus baris lokal yg sudah tak ada di payload. Persis pola
bug yg SUDAH pernah terjadi & diperbaiki di `product_group_tags` (ada
sweep-nya) — luput ditutup di 3 tabel ini.

**Fix**: sweep orphan-cleanup yg sama diterapkan ke ketiga tabel — hapus
baris lokal yg id-nya TIDAK ada di payload full-dump (payload full-dump =
kebenaran LENGKAP host saat ini, jadi aman dihapus), KECUALI baris milik
unit yg `protectedUnitIds` (locally_modified=1, usulan blm di-approve
owner — guard yg sudah ada dari fix Item 41 sebelumnya, dipakai ulang).

**SENGAJA belum disentuh**: `product_units` sendiri (satuan yg di-hard-
delete) punya kerentanan SAMA, tapi lebih riskan — anak-anaknya
(price_tiers/alt_prices/product_barcodes/customer_group_prices) referensi
FK RESTRICT (default Drift) ke `product_units(id)`, jadi orphan unit tidak
bisa dihapus polos tanpa urutan hapus anak-dulu yg lebih hati-hati. Belum
diminta user — kalau muncul lagi sbg bug nyata, ini akar masalahnya.

Test baru `orphan_master_data_sync_test.dart` (3 kasus: barcode diganti,
tier dihapus tanpa pengganti, guard proteksi usulan tidak ikut kehapus) —
revert-verified (2 dari 3 gagal sensible saat fix dicabut, kasus proteksi
tetap lolos krn tidak butuh cleanup utk lolos).

## Yang dikerjakan sesi sebelumnya (masih relevan sbg konteks)

1. **Fix `sync_upload_queue` per-IP collision** (sama persis dgn bug
   `_pendingProposals` yang sudah diperbaiki commit `d4b17b9`) — kolom baru
   `SyncUploadQueue.deviceCode` (nullable, migrasi v20->v21, guard
   `from >= 18` krn `createTable` di step v18 sudah pakai definisi tabel
   TERKINI shg addColumn lagi akan gagal "duplicate column" utk upgrade
   yang lewat kedua step di satu chain). `enqueueSyncUpload` sekarang kunci
   slot "1 per pengirim" pakai `deviceCode` (fallback `fromIp` utk klien
   lama yg belum kirim). `lan_sync_service.dart`: parsing `rawDeviceCode`
   dipindah lebih awal, dipakai ulang utk kedua antrian (proposal + upload
   queue) — tidak lagi diparse 2x.
2. **Fix Item 38 (PLAN.md) — `_rawBaseStock` tie-break tidak kronologis**
   — ditemukan TAK SENGAJA lewat investigasi flake test Stock Opname
   (`stock_opname_unit_conversion_test.dart` gagal ~1-in-5 di full-suite,
   TIDAK reproducible isolasi). Sempat salah duga akar masalah popup
   `DropdownButton` timing (rewrite ke `onChanged` langsung TIDAK
   menghilangkan flake) — debug print `stock_ledger` row content
   membuktikan WRITE benar, READ salah → `ORDER BY created_at DESC, id
   DESC`: `created_at` presisi detik, `id` UUID acak, 2 tulis stok di
   detik sama bisa salah pilih baris lama. Fix: tie-break kedua pakai
   `rowid` SQLite built-in (monoton sesuai insert, tanpa migrasi).
   **Sudah dibuktikan berdampak nyata** (bukan cuma teoretis spt status
   PLAN.md sebelumnya) — item ini SUDAH DIHAPUS dari PLAN.md.

**Test baru** (semua revert-verified): `migration_v21_test.dart`,
`sync_upload_queue_device_slot_key_test.dart` (real HTTP round-trip),
`stock_ledger_tiebreak_test.dart` (deterministic DB-level, id string
sengaja dibalik leksikografis supaya bug ke-trigger PASTI, bukan
untung-untungan UUID acak).

## Audit pra-rilis 2.2.0 (25 Juli) — hasil & 2 fix susulan

Diminta user sebelum memutuskan tag resmi. **Verifikasi bersih**: 677 test
hijau, analyze 0 issue, APK build hijau di CI (`e796189`), rantai migrasi
v1→v21 konsisten (tiap `addColumn` yg tabelnya pernah di-`createTable`
lebih awal SUDAH ber-guard), bug kelas `_allTables` TIDAK terulang
(`sync_upload_queue` satu-satunya yg dikecualikan & itu benar: tanpa FK +
antrian transien), tak ada pola crash di kode baru, tak ada TODO/`print`
bocor.

**2 temuan, keduanya sudah diperbaiki** (lihat CHANGELOG utk detail):
1. `_loadUnits()` Stock Opname N+1 berlapis + memblokir seluruh layar di
   balik spinner → satu query JOIN (`getUnitsWithTypeNamesFor`). Diukur:
   1000 produk = 3000 query/441ms → 1 query/7ms.
2. Dialog "Sesuaikan Stok" `autofocus` + field terisi = ketikan MENEMPEL
   (stok 5 + ketik "12" → tersimpan 512, bahaya data nyata, bukan cuma
   merepotkan) → select-all. Plus field Poin pelanggan berhenti prefill '0'.

**Dua sisa risiko yang tak bisa ditutup test otomatis SUDAH DITUTUP user
(25 Juli)**: scanner HID (Item 32) & printer thermal Bluetooth Android ≤11
(Item 41/D.1) dilaporkan user "sudah ditest dan baik baik saja" di device
asli — kedua item itu DIHAPUS dari PLAN.md. Jadi tidak ada lagi verifikasi
manual yang menggantung untuk rilis 2.2.0. Catatan konteks: surface rilis
ini tetap besar (157 commit sejak 2.1.1).

## Bug barcode ganda (dilaporkan user 25 Juli, SESUDAH merge a08af7a)

User: "membuat dua produk dengan barcode yang sama, dan itu lolos".
Diprobe langsung: yang terjadi lebih buruk dari sekadar lolos — produk
kedua **MENCURI** barcode dari yang pertama (probe: A punya 0 barcode, B
punya 1, `lookupBarcode` -> B), tanpa error apa pun. Produk lama jadi tak
bisa di-scan & scan kode itu menagih produk SALAH di kasir.

Akar masalah: `saveProduct` menjalankan `DELETE ... WHERE barcode = value`
polos semata-mata untuk menghindari `UNIQUE(barcode)`. Fix: helper baru
`_claimBarcodeFor` — bentrok lintas-produk yg pemegangnya masih AKTIF
dilempar sbg `BarcodeConflictException` (transaksi rollback total, barcode
produk lain TIDAK tersentuh, pesan menyebut nama produk pemegangnya).

**Kasus sah yang SENGAJA tetap jalan** (ada test-nya masing²): (a) produk
pemegang sudah dinonaktifkan (`_releaseBarcodesForProduct` sudah me-rename
nilainya jadi `RELEASED:...`), (b) barcode dipegang produk ITU SENDIRI sbg
alias `isPrimary=false` dari sinkron harga antar toko (lihat CLAUDE.md) lalu
dipromosikan jadi barcode utama, (c) simpan-ulang produk yang sama.

Jalur lain sudah diperiksa & TIDAK punya bug ini: `updateVariant` &
`createVariant` pakai update/insert tanpa pre-delete (menabrak UNIQUE =
gagal keras, tanpa kehilangan data), sinkron LAN tidak lewat `saveProduct`,
dan impor CSV sudah punya try/catch per baris shg baris bentrok kini
dilaporkan sbg baris gagal (membaik, tidak perlu diubah).

**Susulan atas usulan user: nama produk di banner bisa diketuk.**
`InlineBanner` dapat 2 param opsional baru `linkText`/`onLinkTap` —
potongan pesan yang cocok dirender jadi `TextSpan` ber-`TapGestureRecognizer`
(highlight accent + bold + underline). Tiga hal yang perlu diingat kalau
menyentuh ini lagi: (1) selama `onLinkTap` di-set, banner **tidak
auto-dismiss** — 4 detik tidak cukup utk membaca lalu mengetuk, banner yg
hilang sendiri bikin aksinya mustahil diraih; (2) recognizer-nya SATU objek
yg `onTap`-nya diganti tiap build & di-dispose di `dispose()` (bikin baru
di build = bocor); (3) kalau `linkText` tidak ditemukan di `message`,
otomatis jatuh ke teks biasa — tidak pernah kosong/error. `productId`
ditambahkan ke `BarcodeConflictException` supaya UI bisa `context.push`.
Navigasinya PUSH di atas form, jadi isian yang belum tersimpan tetap utuh
saat kembali (alur yang dituju: ketuk → bebaskan barcode di produk itu →
kembali → simpan).

**Pelajaran test (dari revert-verify)**: test auto-dismiss versi pertama
LOLOS walau fitur dimatikan — `message`-nya sama di kedua `pumpWidget`,
padahal timer hanya di-arm saat `message` BERUBAH di `didUpdateWidget`.
Kalau menulis test banner: WAJIB pump `null` dulu lalu pesan non-null.

## Item 4 DIROMBAK (25 Juli) — order restock: qty diisi owner, teks dua arah

User membandingkan hasil kerja dgn HTML acuan yang dia kirim & menemukan
versi pertama Item 4 SALAH SECARA KONSEP. Kutipan keluhannya: "bagaimana
teks order akan bisa berubah sesuai jumlah orderan jika kita tidak bisa set
angkanya? lagipula, designnya tidak sama persis dengan html yang saya
kirim."

**Yang salah di versi pertama**: qty di teks order diambil dari STOK lalu
dibagi rasio, dan tidak bisa di-set sama sekali. Di data nyata user (stok
semua minus) hasilnya `-104 Pres Lawet Ijo` / `0 Pres Lawet Ijo`. Plus
produk bersatuan tunggal jatuh ke `- Nama` polos tanpa qty/satuan.

**Hasil pembacaan HTML acuan** (`05a57790-index.html`, fitur "Order ke
Karyawan"), untuk rujukan kalau menyentuh ini lagi:
- Tiap kartu: `[−] [qty] [+] [satuan ▾]`. Angka diketuk → modal papan-angka
  (`openCalc`). Tombol −/+ ada tekan-tahan; minus MEMBEKU di 1, tidak
  pernah desimal (`skAdjustQty`).
- qty awal **1**, BUKAN dari stok. Satuan default `dus`.
- Output `<textarea>` **editable dua arah** (`skOnOutputChange`): tiap baris
  di-parse jadi centang + qty + satuan; `skParseLine` = `{qty} {satuan}
  {nama}`, kalau depannya bukan angka+satuan dikenal maka SELURUH baris
  dianggap nama (qty 1).
- Satuan dari daftar tetap 13 nama (`SK_UNITS`): dus, slp, biji, kg, btl,
  sak, lusin, pak, bal, ret, rek, kas, ikt.
- Output dikelompokkan per tanggal dgn header `── Hari ini ──` — **BELUM**
  ditiru, sengaja (butuh menyimpan kapan produk dicentang).

**Keputusan user utk versi baru**: (a) satuan = satuan milik produk DULU
lalu daftar umum dari tabel `unit_types` (bukan 13 nama hardcode acuan —
supaya tetap nyambung ke master data app); (b) qty awal selalu 1 spt acuan;
(c) textarea dua arah PENUH.

**Catatan implementasi**: parser di-debounce 600ms — tiap baris yang cocok
berarti tulis `markedOutOfStock` ke DB & tiap tulis memicu stream emit
ulang, tanpa debounce satu ketikan = beberapa tulis DB + rebuild yang
berebut dgn ketikan user. `_syncOrderText` tidak menimpa textarea selama
fokus ada di situ (kecuali `force` saat fokus dilepas, utk merapikan bentuk
kanonik). `_suppressSync` memutus loop tulis-baca. Konversi rasio TIDAK
dipakai lagi di layar ini — qty adalah angka order apa adanya dalam satuan
terpilih, jadi `_UnitChoice`/`ratioToBase` dihapus dari sini.

**Test lama `cek_stok_unit_output_test.dart` DIHAPUS** — 2 dari 3 test-nya
mengunci desain yang user batalkan (produk 1 satuan TIDAK dapat pemilih
satuan; qty dari stok). Diganti `cek_stok_order_qty_test.dart` (7 kasus).
Revert-verify dilakukan dgn menjalankan test baru melawan versi file dari
git HEAD: 7/7 gagal di versi lama, 7/7 lolos di versi baru.

**Belum dikerjakan / menggantung dari sesi ini**: (1) header tanggal di
output spt acuan; (2) `setMarkedOutOfStock` TIDAK mencap `updated_at` —
kelas bug yang CLAUDE.md sudah catat 2x (perubahan tidak pernah sampai ke
device lain lewat `dumpSince`), ditemukan sambil jalan, sengaja TIDAK
disentuh; (3) pertanyaan qty utk stok minus & stok minus itu sendiri —
user menahan keputusannya.

## Filter status centang di Cek Stok (usulan user, 25 Juli)

Chip `Semua / Dicentang / Belum`, TEGAK LURUS dgn filter kategori (dipakai
bersamaan). Dua hal penting kalau menyentuh ini lagi:

1. **Filter status HANYA menyaring daftar yang tampil, TIDAK teks order.**
   `_lastRows` (dipakai `_syncOrderText` & parser dua-arah) sengaja diisi
   nilai stream MENTAH, penyaringan dilakukan lokal di dalam `data:` builder.
   Kalau teks ikut disaring, memilih "Belum" bikin teksnya kosong dan parser
   dua-arah akan MEMBATALKAN SEMUA centang yang sudah dikumpulkan user. Ada
   test khusus utk properti ini ("PENTING: pindah ke filter Belum ...").
2. **Barisnya `Row` + `Expanded`, BUKAN ListView horizontal** seperti baris
   kategori. Versi ListView-nya terukur: dgn label berangka
   ("Tercentang (1)") chip terakhir terdorong sampai R520 di layar 430px —
   ~90px di luar layar, hit test MELESET, opsinya seakan tidak ada. Setelah
   label dipendekkan masih 3,75px lewat di 360px. Karena opsinya tetap 3,
   membaginya rata membuat ketiganya pasti muat di lebar apa pun. Hitungan
   angka dipindah ke judul panel teks ("Teks Order Restock — N produk"),
   tempat yang lebih berguna & tidak memakan lebar chip.
   Test 360px (`getRect(...).right <= 360` + tap yang harus benar² mengenai)
   menjaga ini — test tanpa surface sempit TIDAK menangkapnya.

## Redesain stepper Cek Stok (Opsi A) + kecualikan kategori dari output (25 Juli)

User pilih **Opsi A** dari 3 mockup (artifact terpisah, disusun dari token
`app_theme.dart` — lihat pesan sebelumnya). Sekaligus 2 permintaan susulan.

**Opsi A diimplementasikan** (`_QtyUnitStepper`/`_StepGlyph` baru): satu
jalur ber-latar `Theme.of(context).inputDecorationTheme.fillColor` (token
`field` app, otomatis benar di 2 mode tanpa warna baru), qty pakai
`AppTheme.numStyle` (Newsreader + tabular figures — token numerik WAJIB
app yg dulu diabaikan di layar ini), satuan jadi `PopupMenuButton<String>`
(bukan `DropdownButton` lagi).

**Sekalian diperbaiki** (bagian dari rekomendasi mockup, berlaku lepas dari
opsi mana pun yg dipilih): kartu produk TERCENTANG dulu memakai
`badgeBg`/`badgeFg` — warna KEPARAHAN STOK — utk menandai "terpilih", jadi
produk kritis (merah) yg dicentang jadi merah-di-atas-merah. Sekarang
terpilih SELALU accent terracotta (`Color.alphaBlend` di atas warna
kartu), badge stok tetap independen/semantik.

**BUG NYATA ditemukan & diperbaiki SAAT implementasi Opsi A** (bukan di
produksi, ketahuan sebelum sempat commit — tapi WAJIB diingat kalau
menyentuh stepper serupa lagi): tombol minus yg "dinonaktifkan" (qty<=1)
sempat diberi `onTap: null` (utk meniru "beku" spt di mockup). Ternyata
`InkWell(onTap: null)` TIDAK menyerap gesture-nya — tap MENEMBUS ke
`CheckboxListTile` pembungkus & MEMBATALKAN CENTANG seluruh baris. Ketahuan
dari test sendiri (icon "hilang" di iterasi ke-3 test tekan-minus-berkali,
krn baris jadi ter-uncheck). Fix: `onTap` `_StepGlyph` dibuat NON-nullable
selamanya (`required this.onTap`, bukan `this.onTap`) — `enabled` HANYA
boleh mempengaruhi opacity tampilan, pemanggil yg "menonaktifkan" tetap
wajib kasih callback (no-op dari sisi logika `_adjustQty` yg sudah membekukan
qty<=1), bukan `null`. Test regresi
`REGRESI: menekan tombol minus...` mengunci ini; revert-verified dgn
sengaja mereproduksi bug (StateError: Bad state: No element saat loop tap,
krn baris hilang di tengah jalan).

**Fitur baru: kecualikan kategori dari teks output** (usulan user, "seperti
HTML" — meniru `skCatExcluded`/`sk-outcat-bar`/`skRenderOutCats` di acuan
persis). Chip ✓/✕ per kategori muncul di atas kotak teks (HANYA kalau ≥2
kategori bernama, sama spt acuan `cats.length<2`), disimpan sbg blob JSON
id kategori di app_settings key `cek_stok_excluded_output_groups` (pola
sama `saved_catalogs`, TANPA migrasi). Produk kategori dikecualikan TETAP
boleh dicentang & tampil normal — HANYA tidak ikut ke teks maupun ke parser
dua-arah (baris kategori dikecualikan di-`continue` penuh, centangnya tidak
pernah disentuh parser).

**Keputusan desain penting**: visibilitas PANEL (bukan chip toggle-nya)
memakai centang MENTAH (`markedOutOfStock` saja), BUKAN yg sudah disaring
kategori — kalau tidak, produk yg SEMUA kategorinya kebetulan dikecualikan
bikin panel (dan chip sertakan-baliknya) hilang total, user kejebak tanpa
jalan mengembalikan. Ada test khusus utk properti ini ("PENTING: semua
kategori tercentang kebetulan dikecualikan").

**Catatan test**: label chip toggle SAMA PERSIS dgn label chip filter
kategori di baris atas (nama kategori yg sama) — `find.text(nama)` ambigu
antara keduanya. Chip toggle dikasih `Key(ValueKey('outcat-$id'))` eksplisit
supaya bisa dibedakan baik oleh test maupun (potensial) automation lain.

## Item 19 REVISI (25 Juli) — "Harga Lain" jadi chip, bukan popup menu

User klarifikasi Q3 lewat screenshot kedua: maksudnya BUKAN minta balik ke
chip menumpuk lama (yg Item 19/`9af9cb6` sengaja hindari) — tapi tiap opsi
harga (Harga dasar + tier grosir + Harga Lain) tampil sbg CHIP SENDIRI
langsung kelihatan semua, persis pola "Pilih satuan" di atasnya. Widget
`_PriceChip` (sudah ada, dipakai satuan) DIPAKAI ULANG apa adanya utk ini —
bukan komponen baru.

`_buildPriceMenuButton`/`PopupMenuButton<int>`/`_selectedPriceLabel`
dihapus total. Baris baru "Pilih harga" (judul sama gaya dgn "Pilih
satuan") — horizontal scroll berisi SEMUA `_priceOptions()` (termasuk
"Harga dasar" pertama, konsisten dgn popup lama yg juga selalu
menyertakannya sbg opsi pertama), hanya muncul kalau ada >1 opsi (satuan
tanpa tier/Harga Lain tidak dapat baris ini sama sekali — tidak ada
gunanya menampilkan satu chip doang). Posisi: baris tersendiri selebar
penuh SETELAH baris Qty & Harga, SEBELUM Catatan item — bukan lagi
mepet di kolom Harga (kolom itu cuma setengah lebar layar, sempit utk N
chip).

Test lama `item_entry_price_menu_test.dart` (mengunci tombol "Harga lain
(N)" + popup) DITULIS ULANG total (bukan cuma disesuaikan) — sekarang
memverifikasi chip langsung terlihat tanpa buka apa pun, ketuk chip
mengisi field, chip "Harga dasar" bisa dipakai balik, dan baris "Pilih
harga" tidak muncul sama sekali kalau cuma 1 opsi. Revert-verified vs git
HEAD: 2/3 gagal di versi lama (test "tanpa Harga Lain" tetap lolos krn
memang tidak menguji beda popup-vs-chip).

**Belum dikerjakan / masih menggantung dari giliran ini**:
- Header tanggal di teks output Cek Stok spt acuan (`── Hari ini ──`) —
  masih ditunda dari giliran sebelumnya.
- `setMarkedOutOfStock` tidak mencap `updated_at` — kelas bug tercatat 2x
  di CLAUDE.md, ditemukan sambil jalan giliran sebelumnya, BELUM disentuh.

## `setMarkedOutOfStock` updated_at: host→klien FIXED, client→host BELUM (butuh keputusan)

User setuju menutup celah, lalu tanya sendiri hal yang tepat: "bagaimana
jika dari client ke host?" — investigasi menemukan itu BUKAN cuma bug
watermark yang sama, tapi celah arsitektur terpisah & lebih dalam.

**Host→klien: FIXED** (`1dfd159`). Pola identik `deactivateProduct`/
`applyProductProposals` — `updated_at` sekarang dicap ulang di
`setMarkedOutOfStock`. Test `marked_out_of_stock_sync_test.dart`.

**Client→host: TIDAK sekadar bug, TIDAK dikerjakan — perlu keputusan
desain user.** Ditelusuri sampai akar:
1. `syncToHost` (`lan_sync_service.dart`) mengirim
   `db.dumpSince(uploadSince, includeMasterData: false)` — SENGAJA
   (`products` = master data, cuma boleh mengalir SATU ARAH host→bawah,
   supaya harga/nama dari device asisten/kasir tidak menimpa data owner).
2. Jalur PENGECUALIAN yang sudah ada utk perubahan master-data dari device
   non-owner = "usulan produk" (Item 40): `markProductLocallyModified` men-
   set `products.locally_modified=1`, lalu `dumpLocalProposals` mengambil
   SEMUA kolom produk itu (termasuk `markedOutOfStock`, krn `SELECT *`) &
   mengirimkannya sbg usulan TERPISAH yg wajib direview manual owner
   (`_pendingProposals`/`sync_upload_queue`).
3. TAPI: `setMarkedOutOfStock` (dipanggil dari `_toggleOutOfStock` di
   `item_entry_sheet.dart` & `_toggle` di `cek_stok_screen.dart`) TIDAK
   PERNAH memanggil `markProductLocallyModified` — beda dgn jalur edit
   form produk penuh (`produk_form_screen.dart`, 3 titik panggil). Jadi
   toggle "stok habis" oleh kasir/asisten TIDAK PERNAH ditandai
   `locally_modified`, TIDAK PERNAH masuk `dumpLocalProposals`, TIDAK
   PERNAH sampai ke host — bahkan lewat jalur review sekalipun. Ini
   berlaku SEJAK fitur Item 25a dibuat, bukan regresi baru.

**Kenapa ini keputusan desain, bukan "tinggal tambah 1 baris"**: kolom
`markedOutOfStock` SENGAJA didesain "akses cepat, bukan izin ter-audit —
semua role bisa toggle" (lihat komentar Item 25a). Kalau toggle kasir
dipaksa lewat jalur `markProductLocallyModified` yg sama dgn edit
harga/nama, itu akan MASUK antrian review owner yg sama — bertentangan
dgn maksud "akses cepat" (toggle jadi tertunda sampai owner sempat
approve, bukan instan). Perlu user putuskan salah satu:
  (a) **Biarkan lokal-per-device** (status quo) — toggle kasir cuma
      berlaku di device itu sendiri, tidak pernah menyebar ke host/device
      lain. Konsisten dgn "bukan izin ter-audit", tapi kasir A menandai
      habis tidak akan terlihat kasir B/owner sampai owner sendiri yg
      menandainya di host.
  (b) **Jalur upload instan terpisah** (BUKAN via `dumpLocalProposals`/
      review) — `markedOutOfStock` dikirim client→host tanpa antrian
      approval (risikonya rendah, cuma boolean, beda dari harga/nama),
      host langsung apply + cap `updated_at` sendiri, lalu ikut tersebar
      ke device LAIN di sync host→bawah berikutnya. Butuh field/endpoint
      baru di payload sync (`lan_sync_service.dart`) — bukan reuse
      `dumpLocalProposals` yg maknanya "usulan perlu approval".
  (c) **Ikut jalur usulan Item 40 apa adanya** — panggil
      `markProductLocallyModified` di `setMarkedOutOfStock` juga. Paling
      murah implementasinya, tapi mengubah semantik fitur ("akses cepat")
      jadi "tertunda sampai owner approve" — kemungkinan besar BUKAN yg
      diinginkan user, tercantum di sini supaya opsinya lengkap.
**UPDATE (giliran yg sama, langsung setelah opsi ditawarkan)**: user
jawab "tidak perlu deh" — client→host utk `markedOutOfStock` SENGAJA
TIDAK dikerjakan, opsi (a) (biarkan lokal per-device) yg berlaku secara
default. JANGAN dikerjakan lagi kecuali user minta ulang secara eksplisit.

## Bug highlight satuan hilang saat pilih Harga Lain (dilaporkan user 25 Juli)

User: "kita jadinya tidak tahu satuan mana yang sedang dipilih" setelah
menekan chip Harga Lain. Akar masalah SUDAH ADA sejak `6564852` (jauh
sebelum sesi ini) — chip satuan (`item_entry_sheet.dart`, baris "Pilih
satuan") pakai `selected: i == _selectedIdx && !_priceOverridden`. Begitu
chip Harga Lain dipilih (`_applyTierPrice` men-set `_priceOverridden =
true`), highlight satuan yg sedang aktif ikut MATI walau satuannya sendiri
tidak berubah — dua hal berbeda (satuan aktif vs harga yg dipakai) dipaksa
jadi satu kondisi. Baru KETARA sekarang krn chip Harga Lain sesi ini
dibuat selalu tampil (dulu tersembunyi di popup, jadi user jarang lihat
efeknya bersamaan).

Fix: `selected: i == _selectedIdx` saja — satuan aktif independen dari
harga yg dipakai; harga yg dipakai sudah py highlight sendiri di baris
"Pilih harga" di bawahnya. Test baru di `item_entry_price_menu_test.dart`
(baca warna `Container.decoration.color` chip sebelum/sesudah tap Harga
Lain, harus IDENTIK) — revert-verified: `Color(0x1fc96442)` (accent tint)
vs `Color(0xffebe8e0)` (netral) saat bug direproduksi.

## Status test suite

`flutter test` PENUH: **736 test, SEMUA hijau** (run terakhir sesi ini
bersih). Run sebelumnya sempat 2 gagal (`migration_v9_test.dart`,
`migration_v18_test.dart`, tak terkait perubahan kode sama sekali) — pola
flake full-run yg sudah tercatat (test acak beda-beda tiap run, selalu
hijau saat isolasi — lihat paragraf flake port di bawah). `flutter
analyze` bersih (0 issue).

Flake port yang masih mengintai (muncul/tidak tergantung undian; run
terakhir bersih): `SocketException: Address already in use, port = 8625`. **8625 itu port sync TETAP milik app**
(`lan_sync_service.dart`), dan 4 file test real-HTTP memperebutkannya saat
`flutter test` menjalankan file secara paralel: `lan_sync_item41_test.dart`,
`lan_sync_slow_transfer_test.dart`, `lan_sync_timeout_test.dart`,
`proposal_unchanged_end_to_end_test.dart`. **File mana yang kalah undian
port BERGANTI-GANTI tiap run** (pernah `lan_sync_item41`, pernah
`proposal_unchanged_end_to_end`) — itu justru penanda bahwa ini balapan
port, bukan bug logika di file tertentu. Yang kalah selalu lolos bersih
saat dijalankan sendiri (sudah diverifikasi tiap kali). Kelas flake ini
tercatat sejak sesi 24 Juli. Kalau mau benar² dihilangkan: port harus bisa
disuntik per-test (bukan konstanta) — itu perubahan kode produksi, ditahan.

Flake lama `stock_opname_unit_conversion_test.dart`/`cek_stok_unit_output_
test.dart` (akar masalahnya Item 38) dikonfirmasi HILANG — 3x run batch
berulang semua bersih.

## Yang menggantung / belum sempat

- **Fix barcode ganda belum di-merge ke `main`** (main terakhir di
  `a08af7a`). Tag `v2.2.0` juga BELUM dibuat — sengaja, menunggu keputusan
  user. Fix ini sebaiknya masuk SEBELUM tag, karena bug-nya kehilangan data
  diam-diam.
- Item lama yang masih terbuka: lihat `PLAN.md` (Item 17+21 sync ditunda
  sesi fokus, Item 23 sisa, Item 28 konsep, Item 41 sisa P3, Item 51 tunggu
  keputusan user). Item 32 & D.1 sudah DITUTUP (user konfirmasi tes device).
