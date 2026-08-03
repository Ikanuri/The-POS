# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md).

_Update sesi 3 Agustus 2026 (lanjutan) — versi kerja **masih 2.9.1+14**
(TIDAK di-bump — user eksplisit minta "jangan naikkan bump versi jika
tidak diminta", berlaku utk semua commit sesi ini & seterusnya sampai user
minta lagi), **schemaVersion NAIK ke 28** (kolom `customers.locally_modified`,
lihat poin 4). Lima hal dikerjakan sesi ini:
1. **Jarak baris keranjang ke tepi layar diperlebar di kedua sisi**
   (`5266dcd`) — dulu 8/4px, terlalu mepet, checkbox+stepper nyaris
   nempel tepi kanan & nama+nominal nyaris nempel tepi kiri. Sekarang
   16/16px (varian 40px). Selesai & di-commit.
2. **Tombol "Sudah Dikirim, Kosongkan Keranjang" di sheet QR handoff
   (`_HandoffQrSheet`) diganti tombol "Share Pesanan"** (`31c9b26`) —
   tombol lama persis di atas "Tutup", rawan ke-misclick & menghapus
   keranjang yang sebenarnya belum terkirim. `Share.share(qrText)`
   dipanggil, TIDAK ada lagi aksi yang mengosongkan keranjang di sheet
   ini. Mengosongkan keranjang tetap lewat ikon tempat sampah di header
   `CartSheet` (`_confirmClear`, sudah ada, tidak berubah). `onDone`
   callback lama & plumbing terkait (`releaseLocalId`, dsb di
   `_showHandoffQr`) DIHAPUS karena tidak ada lagi pemanggil. Selesai &
   di-commit.
3. **"Tempel Pesanan" langsung dari `CartSheet` + diaktifkan di mode
   Tambah Belanjaan + QR scan merge ke keranjang aktif** (`c690329`) —
   tiga penyempurnaan terkait: (a) ikon baru di header `CartSheet` yang
   membuka `PasteOrderSheet(cartId: widget.cartId)` — widget itu SUDAH
   generik per-cartId & sudah merge ke cart yang ada, tidak perlu logika
   baru; (b) tombol yang sama diizinkan tampil juga saat
   `KasirScreen(addToTxId:)` (dulu sengaja `null`-kan kondisinya di
   `kasir_screen.dart:1783`, sekarang cuma exclude mode Katalog); (c)
   `_handleOrderCode` (`kasir_screen.dart`) sekarang cek
   `ref.read(cartProvider(_cartId))` SEBELUM memutuskan
   `db.holdOrder(...)` — kalau keranjang aktif TIDAK kosong, item hasil
   scan QR handoff di-merge langsung ke situ (pola sama persis dgn
   `PasteOrderSheet._addToCart`, pakai `_ensureParentInCart` versi
   `kasir_screen.dart` yang sudah ada, BUKAN duplikat baru) alih-alih
   selalu ke antrian `held_orders`. Selesai & di-commit.
4. **Usulan sync pelanggan dari device non-owner** (`d196ccd`,
   schemaVersion 27→28) — pola SAMA PERSIS dgn usulan produk (Item 40) &
   Laci Meja (Item 52): kolom `customers.locally_modified` (migrasi
   additive — 15 file test migrasi lama v7-v26 disentuh, tambah
   `CREATE TABLE customers(id TEXT PRIMARY KEY)` minimal ke synthetic
   schema masing² + update assertion `PRAGMA user_version` dari 27→28,
   pola SAMA PERSIS dgn gotcha `product_units` yg sudah didokumentasikan
   di CLAUDE.md §Gotcha), `markCustomerLocallyModified`/
   `dumpLocalCustomerProposals`/`applyCustomerProposals` di
   `AppDatabase`, dipanggil `pelanggan_form_screen.dart` gated
   `!device.isOwner`. Antrian usulan PARALEL (`PendingCustomerProposal`)
   di `LanSyncService`, field payload `customerProposals` — TIDAK
   menyentuh `proposals`/`laciMejaProposals` sama sekali. Layar review
   baru `CustomerProposalReviewScreen` + kartu "Usulan Pelanggan" di
   `SyncScreen`. Sebelumnya pelanggan yang ditambah/diubah di device
   kasir/asisten TIDAK PERNAH sampai ke host (customers = master data,
   sengaja tidak diupload klien→host) — sekarang lewat jalur usulan yang
   sama seperti produk. Selesai & di-commit.
5. **Gotcha baru ditemukan & DIDOKUMENTASIKAN di CLAUDE.md §Gotcha
   (susulan poin di atas)**: widget test yang pump `KasirScreen` (drift
   `StreamProvider`, mis. antrian held orders) via top-level
   `setUp()`/`tearDown(() async => db.close())` bisa membuat `flutter
   test` tampak HANG TANPA BATAS (bukan cuma lambat) — beda dari pola
   lama yg sudah didokumentasikan (test yg pakai `final db =` lokal +
   `await db.close()` di akhir body TIDAK kena). Fix: `drain()` manual
   di akhir tiap `testWidgets` (`pumpWidget(SizedBox())` +
   `pump(Duration(milliseconds: 10))`) SEBELUM `tearDown` global
   sempat jalan. Reproduksi persis: `test/kasir_add_mode_paste_order_
   test.dart` sebelum fix vs sesudah.

Full suite hijau (900+ test, termasuk semua test baru sesi ini),
`flutter analyze` 0 issue.

**MENGGANTUNG — Item 52 PLAN.md, bug sinkron harga antar toko (BELUM
diselesaikan, masih terputus di titik yang sama)**: user laporkan kasus
nyata — barcode sama, harga sudah sama di kedua toko ("Rinso cair 500",
5000), tapi sync tetap usulkan harga beda (4400). Analisis mendalam SUDAH
dilakukan (baca detail lengkap di PLAN.md Item 52 & CLAUDE.md), root
cause PALING MUNGKIN sudah diidentifikasi: asimetri dedup di
`price_sync_service.dart` (query ekspor katalog dedup barcode via
`GROUP BY` tapi TIDAK dedup JOIN `price_tiers WHERE min_qty=1` — kalau
toko sumber punya tier duplikat `minQty=1`, 1 barcode bisa muncul 2x di
katalog dgn harga beda). **BELUM diverifikasi ke kasus nyata** — user

**MENGGANTUNG — Item 52 PLAN.md, bug sinkron harga antar toko (belum
diselesaikan, terputus di titik ini)**: user laporkan kasus nyata —
barcode sama, harga sudah sama di kedua toko ("Rinso cair 500", 5000),
tapi sync tetap usulkan harga beda (4400). Analisis mendalam SUDAH
dilakukan (baca detail lengkap di PLAN.md Item 52 & CLAUDE.md), root
cause PALING MUNGKIN sudah diidentifikasi: asimetri dedup di
`price_sync_service.dart` (query ekspor katalog dedup barcode via
`GROUP BY` tapi TIDAK dedup JOIN `price_tiers WHERE min_qty=1` — kalau
toko sumber punya tier duplikat `minQty=1`, 1 barcode bisa muncul 2x di
katalog dgn harga beda). **BELUM diverifikasi ke kasus nyata** — user
diminta kirim baris log `unit=...`/verdict harga khusus utk "Rinso cair
500", atau cek manual Edit Produk di kedua toko (tier harga duplikat?
produk nonaktif dgn nama/barcode sama?) — user belum sempat balas
sebelum sesi ini terputus/di-compact. **Next action begitu sesi
lanjut**: tunggu/minta detail itu dari user, baru eksekusi fix (dedup
query + one-time cleanup data tier duplikat). Pertanyaan terpisah yang
juga menunggu keputusan user: apakah field pencarian kasir perlu bisa
cari-by-barcode juga (sekarang cuma nama/`kode_produk`).

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
