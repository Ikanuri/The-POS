# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 13 Juli 2026 (gabungan 2 sesi paralel via merge
`main`). Sesi cabang ini: fix bug tombol modal "Tambah Bayar" (2 iterasi —
`9fec89e` lalu `9633e7d`, lihat catatan gotcha di bawah, PENTING dibaca
kalau ada laporan bug tombol serupa lagi) + fitur checklist verifikasi
barang di keranjang kasir + stepper senada kartu produk (`2090d40`). Sempat
juga coba samakan gaya stepper keranjang katalog HTML (`beaf395`) tapi
DI-REVERT (`3a48d4e`/`e12c290`) begitu ketahuan desain katalog HTML sudah
ditangani terpisah di `main` (`24097ec`, lihat detail di bawah — jangan
kerjakan ulang). Sesi paralel di `main` (sudah di-merge ke sini):
redesign lanjutan katalog HTML sesuai referensi app kasir + 2 bugfix
lain (`24097ec`/`16b94b9`/`83e01dd`). **schemaVersion masih 15** (tidak
ada migrasi baru dari kedua sesi — checklist keranjang murni
SharedPreferences, `checkedItemIds` transaksi kolom lama dipakai ulang).
Setelah merge: full `flutter test` **331 test hijau** (327 dari cabang ini
+ 4 baru dari `main`), `flutter analyze` bersih, 0 konflik kode (cuma
`CHANGELOG.md`/`docs/HANDOFF.md` — file dokumentasi rolling-snapshot yang
memang wajar bentrok kalau 2 sesi jalan paralel)._

## Gotcha BARU — tombol lebar-penuh (Outlined/FilledButton) dalam Row di dalam AlertDialog

`AppTheme` set `minimumSize: Size(double.infinity, 48)` sebagai default
utk `OutlinedButtonThemeData`/`FilledButtonThemeData` (utk tombol CTA
berdiri sendiri di banyak layar). Kalau taruh 2+ tombol begini dalam SATU
`Row` (pola umum di app ini — lihat `payment_screen.dart`), WAJIB override
`minimumSize` ke lebar sempit (mis. `Size(0, 44)`) di style masing-masing,
KALAU TIDAK Row akan overflow.

Kasus KHUSUS di dalam `AlertDialog.content` (bukan BottomSheet/Column
biasa): `AlertDialog` SELALU membungkus content dgn `IntrinsicWidth`
(lihat framework `dialog.dart`), dan lebar konten yang tersedia jauh lebih
sempit dari layar penuh (dipotong `insetPadding` + `contentPadding`
default). **3 tombol sekaligus (mis. Batal + Uang Pas + Bayar) bisa SAMA
SEKALI TIDAK MUAT sejajar dalam satu Row** di dialog — bukan cuma soal
`minimumSize`, override itu SAJA TIDAK CUKUP (`debt_payment_dialog.dart`
sempat 2× salah fix sebelum benar: iterasi 1 taruh 3 tombol dlm 1 Row +
override minimumSize → overflow tetap terjadi, "Uang Pas"/"Bayar" hilang
total tanpa indikasi visual apapun di HP asli). **Fix yang benar:** pisah
tombol "Batal" ke baris sendiri (tidak berebut lebar dgn tombol lain),
baru 2 tombol utama (mis. Uang Pas + Bayar) sebaris di bawahnya dgn
`Expanded` pada tombol primer — persis pola `payment_screen.dart`. Kalau
nanti nemu dialog lain dgn pola serupa (>=3 tombol custom dlm 1 Row di
AlertDialog), curigai kelas bug yang SAMA — test widget dgn surface
SEMPIT (`tester.binding.setSurfaceSize(const Size(360, 800))`, BUKAN
default ~800×600 flutter_test yang terlalu lebar utk menangkap bug ini)
utk verifikasi nyata sebelum anggap fix selesai.

## Sesi ini — fix tombol Tambah Bayar + checklist keranjang kasir

**Bug tombol "Tambah Bayar" belum sejajar** (dilaporkan user via screenshot,
lalu screenshot susulan menunjukkan fix pertama malah bikin tombol hilang
total) — kronologi & akar masalah FINAL ada di section gotcha di atas,
jangan diulang di sini.

**Fitur checklist keranjang** (usulan user, disetujui setelah opini +
riset arsitektur): keranjang kasir (`cart_sheet.dart`) sekarang punya
- Checkbox di kiri nama tiap item (leading widget eksplisit, BUKAN
  `CheckboxListTile` — supaya tap checkbox vs tap baris/buka modal edit
  tidak tumpang tindih, ikuti gotcha yang sudah tercatat).
- Cascade centang induk↔varian sama persis logika Struk (`cart_provider.dart`
  method `setChecked`): centang induk → semua anak ikut; uncheck 1 anak →
  induk ikut ke-uncheck (tercentang hanya kalau SEMUA anak tercentang).
- Stepper qty diganti total: widget `_AddControl` (dulu private di
  `kasir_screen.dart`) diekstrak jadi shared widget publik
  `lib/features/kasir/widgets/add_control.dart` (`AddControl`), dipakai
  kartu/baris produk DAN baris keranjang — gaya lingkaran +/− identik di
  kedua tempat. Field qty tap-to-edit lama (`_QtyField`) dihapus total
  (edit qty manual sekarang lewat tap item → `ItemEntrySheet`, sudah ada
  sebelumnya).
- Teks baris item (nama, unit·harga, catatan, subtotal) diperbesar sedikit.
- Field `checked` baru di `CartItem` (`core/models/cart_item.dart`) — ikut
  ter-persist ke SharedPreferences otomatis (mekanisme persist cart yang
  sudah ada, per-perubahan state, tidak perlu kode baru).
- Saat checkout (`payment_screen.dart` `_confirm()`): item yang `checked`
  di cart diteruskan jadi nilai awal `checkedItemIds` transaksi baru (kolom
  lama, sudah ada sejak schemaVersion 15) — Struk melanjutkan checklist
  dari titik yang sama, bukan mulai dari nol.

**Keputusan default yang diambil tanpa tanya balik** (dikomunikasikan ke
user dulu, bukan sepihak diam-diam): cascade parent/varian ikut pola Struk;
increment stepper tetap ±1/tap tanpa input manual (konsekuensi dari field
input dihilangkan — bukan regresi baru, sudah begitu juga di stepper kartu
produk).

**Test baru** (`test/cart_checklist_test.dart`, 8 test, semua lolos
revert-verify): serialisasi `CartItem.checked`, cascade `setChecked` (3
skenario), UI `CartSheet` (checkbox + `AddControl` menggantikan widget
lama), dan end-to-end checkout → `checkedItemIds` transaksi via
`PaymentScreen` sungguhan (bukan reimplementasi logic di test).

## Follow-up round setelah user test PR batch 18-item (3 laporan baru)

Setelah PR batch 18-item di-merge, user langsung test & kirim 3 laporan baru
(2 screenshot + 1 laporan tekstual):

1. **Batalkan Pembayaran tidak muncul untuk pelunasan pertama kali** — akar
   masalah: `_showPaymentTimeline` (satu-satunya tempat tombol itu berada)
   sengaja menyembunyikan Riwayat Pembayaran untuk "penjualan tunai
   seketika" (1 pembayaran, `paidAt == createdAt`) — padahal itu skenario
   PALING UMUM. Fix: getter disederhanakan jadi selalu true bila ada ≥1
   pembayaran (`receipt_screen.dart`). Efek samping: baris "Kembalian" jadi
   tampil 2x untuk nota 1-pembayaran (Ringkasan + Riwayat) — pola yang SAMA
   dgn nota 2-pembayaran, `receipt_change_taken_test.dart` disesuaikan.
2. **Katalog HTML modal tap-item (baru dibuat sesi sebelumnya) TERLALU JAUH
   dari desain yang diminta** — user kirim screenshot app kasir asli sbg
   referensi persis. Redesain ulang signifikan di `order_page_service.dart`:
   - Baris produk kini punya kontrol +/- lingkaran meniru `_AddControl` app
     kasir (bukan badge angka/chevron polos) — lingkaran "+" oranye → angka
     hijau + minus merah begitu ada qty, fungsi `buildProwControls()`/
     `prowQuickAdd()`/`prowDecrement()` baru.
   - **Field harga custom yang bisa diketik pelanggan DIHAPUS TOTAL**
     (bukan cuma dikecualikan dari kode mesin seperti versi sebelumnya) —
     `cartPriceOverride`, `priceFor()`, anotasi "(harga custom)" semua
     dicabut. Harga di modal sekarang MURNI tampilan (`#itemPriceDisplay`,
     ikut satuan/varian terpilih).
   - Field jumlah jadi `<input>` beneran (bisa diketik langsung, mis. utk
     qty desimal), bukan cuma `<span>` statis.
   - `.cb-count` (badge jumlah item keranjang) dibuat lingkaran DIJAMIN via
     `aspect-ratio:1` + ukuran diperbesar — sebelumnya sempat tampak lonjong
     di screenshot user (dugaan: interaksi font-scaling browser HP).
   - SEMUA ukuran font di halaman dinaikkan (demografi pelanggan lebih
     terbiasa teks besar, "tidak apa-apa makan space" per instruksi user).
   - Stok TIDAK ditampilkan di modal (diputuskan via `AskUserQuestion` —
     user pilih rekomendasi: jangan expose jumlah stok toko ke publik).
3. **Scan pesanan pegawai via scanner HID TERTENTU masih salah rute ke
   Tempel Pesanan** (bukan antrian) — root cause BERBEDA dari bug serupa
   yang "sudah diperbaiki" sesi sebelumnya (`2ee8068`, soal timing merge
   fragmen). Kali ini: scanner tsb sama sekali TIDAK menerjemahkan newline
   di dalam payload QR jadi keystroke Enter (beda dari scanner yang sudah
   ditangani), jadi kode mesin & baris `Pegawai:` menyatu tanpa newline di
   SATU string ("...=2Pegawai: Budi") — regex `^Pegawai:` (butuh awal
   baris) gagal cocok, employeeName null. Fix di lapisan PARSER (bukan
   lapisan HID kasir_screen.dart yang sudah ada): `OrderParserService.
   parse()` sekarang punya `_normalizeMetaLineBreaks()` — sisipkan newline
   di depan marker `Pegawai:`/`Nama:`/`HP:`/`Catatan:` bila menempel tanpa
   pemisah, SEBELUM regex line-based dijalankan. **BELUM dikonfirmasi user**
   di scanner fisik aslinya (diverifikasi via unit test yang mensimulasikan
   payload fused, bukan hardware sungguhan) — kalau masih terjadi, curigai
   scanner INI mungkin juga tidak kirim Enter di akhir seluruh payload sama
   sekali (beda lagi failure mode-nya, perlu log/laporan lebih rinci).

**Catatan penting**: item "Uang Pas di modal Tambah Bayar sejajar kiri
tombol Bayar" yang disebut user di laporan #1 ternyata **SUDAH benar** di
kode (`debt_payment_dialog.dart`, dari fix sesi sebelumnya) — tidak ada
perubahan diperlukan, kemungkinan user menguji build lama atau cuma
menegaskan ulang requirement yang sudah terpenuhi.

## Batch 18-item bugfix/UX kasir + katalog HTML (sesi sebelumnya)

User kirim 18 laporan bug/permintaan sekaligus (kasir, struk, katalog HTML)
+ 2 screenshot bug. Instruksi eksplisit: "eksekusi dan merge, tidak perlu
masuk plan" — 4 keputusan desain genuinely ambigu diklarifikasi dulu lewat
`AskUserQuestion` sebelum eksekusi (lihat poin bertanda 🔀 di bawah), sisanya
langsung dieksekusi.

**Selesai (16/18):**
1. Tombol "Bayar"/"Tambah Belanjaan" disejajarkan + "Bayar" jadi hijau.
2. Checklist centang serah-terima di struk kini persisten (`transactions.checkedItemIds`).
3. Retur item seharga Rp0 (promo/bonus) kini valid.
4. 🔀 **Batalkan Pembayaran** — baris ditandai "Dibatalkan" & TETAP tersimpan
   sbg jejak audit (bukan dihapus), `paid`/status dihitung ulang tanpa baris
   itu. Kolom baru `transaction_payments.voided`, method `voidPayment()`.
5. 🔀 **Edit item nota belum lunas** — tap item di struk (hanya saat
   `kurang_bayar`/pembayaran baru dibatalkan) buka modal spt `ItemEntrySheet`:
   ubah harga/qty/catatan atau hapus. Efek ke total/hutang **sama seperti
   retur sebagian** (auto-recompute, tanpa refund tunai — belum pernah
   dibayar). Method baru `editUnpaidTransactionItem()`.
6. Tombol "Tambah Bayar" → "Bayar" saja (gabung dgn poin 1).
7. Font struk yang dibagikan di-pin ke `GoogleFonts.robotoMono` (dulu alias
   `'monospace'` generik → beda hasil render tablet vs HP).
8. Startup cleanup file share sementara (`struk_*`/`katalog_*` >24 jam) di
   temp dir — sebelumnya menumpuk selamanya (`temp_share_cleanup.dart`).
9. 🔀+12 **"Uang Diterima" (gross)** — baris baru di atas "Kembalian" saat
   bayar lebih dari tagihan; "Dibayar" TETAP net (Total = Dibayar + Sisa
   tetap konsisten di layar). Diterapkan di `receipt_screen.dart` DAN
   `merged_receipt_screen.dart`/`printer_service.dart` (nota gabungan) —
   yang terakhir ini juga jadi tempat ditemukannya bug baru (lihat di bawah).
10. Katalog HTML: tombol expand varian tidak responsif — **teratasi sbg efek
    samping item 14** (dropdown `<details>` diganti total dgn modal tap-item).
11. Modal "Tambah Bayar": "Uang Pas" pindah ke kiri tombol "Bayar" (sejajar
    layout kalkulator checkout), "Bayar" nonaktif selagi field kosong.
12. Lihat poin 9.
13. **BLOCKED** — katalog HTML dilaporkan "belum identik" dgn UI app, tapi
    investigasi menunjukkan token CSS byte-identik dgn `AppTheme.dart`. Sudah
    diminta screenshot/spesifik ke user, BELUM dijawab sesi ini. Jangan
    disentuh lagi tanpa info baru dari user.
14. 🔀 **Katalog HTML — modal tap-item ganti `<details>` total** (semua
    produk, varian atau tidak): pilih satuan/varian (chip), harga manual
    (decimal-aware), qty stepper, catatan (dipindah OUT dari cart sheet ke
    modal ini). Harga custom **TIDAK PERNAH** masuk baris kode mesin `#PSN:`
    — murni anotasi teks manusia `"... (harga custom)"` di pesan WhatsApp,
    konsisten dgn prinsip desain existing file ("kasir selalu sumber harga
    final"). Diverifikasi nyata via Playwright/Chromium (klik alur penuh:
    pilih varian, override harga, catatan, buka-ulang dari cart, hapus).
15. `cart_sheet.dart`: nominal (total/harga satuan/subtotal) pakai
    `AppTheme.numStyle` (dulu `TextStyle` polos, font beda dgn layar lain).
16. Tombol +/- stepper di baris item kasir & modal keranjang diperbesar +
    direnggangkan (`cart_sheet.dart`, `item_entry_sheet.dart`).
17. `produk_list_screen.dart`: harga di bawah nama produk pakai
    `StreamProvider` (`watchBaseUnitPrices()`) — dulu `FutureProvider`
    snapshot sekali-jalan yg tidak ikut reaktif.
18. Dijawab informasional (bukan kode) — stok bisa dipantau lewat filter
    chip "Stok Menipis" + count di tab Produk, dan form edit per-produk
    (belum ada kolom stok di list/laporan stok terpisah).

**Bug tambahan ditemukan & diperbaiki di luar 18 item** (langsung
dinecessitated oleh screenshot user "SISA Rp -31.400"): `merged_receipt_
screen.dart` (nota gabungan) ternyata masih pakai `tx.total - tx.paid`
MENTAH (kelas bug sama dgn "Item 23" lama di PLAN.md, yang sebelumnya
sudah diperbaiki di `receipt_screen.dart` tapi TIDAK di file gabungan ini) —
diperbaiki pakai `netRemainingOwed()`/`netPaidDisplay()` yg sama, plus
`printer_service.dart` `_buildMergedBytes` (cetak ESC/POS gabungan) yg
punya bug identik. **Item 23 di PLAN.md masih ada sisa** (single-tx
`printer_service.dart printReceipt`, `transaksi_tab.dart`,
`tx_history_sheet.dart`, `settleMergedDebt`, Buku Hutang, Tutup Kasir "kas
sistem") — lihat PLAN.md.

**4 keputusan desain diklarifikasi via `AskUserQuestion` sebelum eksekusi:**
- Batalkan Pembayaran → "Tandai batal, tetap tersimpan" (bukan hapus record).
- Edit harga item → efek ke total sama seperti retur sebagian (bukan alur baru).
- Dibayar gross vs net → tetap net + tambah baris terpisah "Uang Diterima".
- Modal tap-item katalog HTML → berlaku semua produk, GANTIKAN `<details>` total.

**Test baru sesi ini** (semua lolos revert-verify — fix di-revert dulu,
buktikan test gagal dgn pesan relevan, baru kembalikan): `migration_v15_
test.dart`, `payment_void_test.dart`, `edit_unpaid_item_test.dart`,
`watch_base_unit_prices_test.dart`, `temp_share_cleanup_test.dart`, +
`order_page_service_test.dart` diperbarui (2 test baru utk modal tap-item,
1 test lama disesuaikan krn `ci-note` editable input di cart sheet sengaja
dihapus/dipindah ke modal). 6 file fixture migrasi lama (`migration_v7`
s/d `v14_test.dart`) disesuaikan ke `schemaVersion` 15 (bumping schema
version membuat SEMUA fixture lama ikut migrasi sampai versi terbaru, 3 di
antaranya perlu ditambah tabel `transactions`/`transaction_payments` minimal
krn migrasi v15 menyentuh kedua tabel itu).

## Gerbang aktivasi/lisensi offline (Item 25c) — KODE SELESAI, TAPI BELUM AKTIF

Selesai sesi sebelumnya (commit `174cad7`), **belum disentuh sesi ini**.
`LicenseService.publicKeyBase64` masih string kosong (kill-switch sengaja —
`isLocked` selalu false selama itu kosong, JANGAN hapus guard ini). Butuh 2
input developer sebelum aktif sungguhan:
1. **Public key developer** — buka `scripts/license-generator.html` (100%
   offline, Web Crypto API, TIDAK disentuh app), generate keypair, WAJIB
   unduh cadangan, kirim BALIK public key saja (private key TIDAK PERNAH
   dikirim ke Claude — prinsip inti desain).
2. **Nomor WhatsApp developer** — tombol "Kirim via WhatsApp" di
   `AktivasiScreen` sementara pakai `Share.share()` generik krn tidak ada
   nomor WA developer di codebase. Upgrade ke deep-link `wa.me` butuh nomor
   + dependency `url_launcher` baru.

Setelah keduanya diisi: tanam public key, `flutter test`/`analyze`, commit —
barulah gerbang aktif. `PATCHNOTES.md` SENGAJA belum ditambah entri (nol
dampak terlihat selama nonaktif).

## Crash Infinix Smart 8 — fix di-merge, BELUM dikonfirmasi user

Akar masalah terkonfirmasi (`fb8ba80`): APK CI sebelumnya cuma target
`android-arm64`, HP 32-bit (armeabi-v7a) butuh `libflutter.so`/`libapp.so`
yang tidak ada sama sekali → crash `dlopen` sebelum kode app manapun jalan.
Fix: `build-apk.yml` → `--target-platform android-arm,android-arm64` (fat
APK). **Kalau topik ini muncul lagi**: tanya dulu apakah user sudah install
APK CI terbaru & app bisa dibuka normal di HP itu — kalau MASIH crash walau
sudah fat APK, ada penyebab LAIN, jangan asumsikan sama.

## Item 24 (payment gate role Pegawai via QR) — SELESAI SEPENUHNYA
Semua sub-item (24a-24f) selesai & di-commit sesi-sesi sebelumnya. Tidak
ada sisa pekerjaan — lihat CHANGELOG kalau perlu detail teknis.

## Gotcha teknis (kumulatif, masih berlaku)

- **`order_page_service.dart`**: `_htmlTemplate` punya 2 baris
  pathologis-panjang (base64 font-face woff2, puluhan KB) — `Read` tool
  akan error/gagal kalau range yang diminta mencakup baris itu. Selalu
  target range yang menghindarinya, atau pakai `Grep`/`sed -n` utk baris
  spesifik. Cek posisi barisnya dulu tiap sesi (`awk '{print length, NR}' |
  sort -rn | head`) — bisa geser kalau ada edit sebelumnya.
- **Playwright/Chromium tersedia tanpa install lokal**: module di
  `/opt/node22/lib/node_modules` (butuh `NODE_PATH=/opt/node22/lib/
  node_modules node script.js`), Chromium di `/opt/pw-browsers/chromium`.
  Berguna utk verifikasi nyata file HTML/JS mandiri (katalog HTML, alat
  generator lisensi) — generate output real (mis. lewat `dart run` sekali
  pakai yg ekstrak `_htmlTemplate`), klik alur lewat Playwright, baca
  balik state via `page.evaluate()`.
- Bumping `schemaVersion` membuat SEMUA fixture test migrasi versi lama
  (`migration_vN_test.dart`) ikut ter-migrasi sampai versi TERBARU (bukan
  cuma versi yang mereka test) — fixture yang tidak punya tabel yang
  disentuh migrasi baru akan gagal `no such table`. Cek SEMUA
  `migration_v*_test.dart` tiap kali `schemaVersion` naik, bukan cuma
  tambah test baru utk versi barunya.
- `CheckboxListTile` seluruh barisnya SATU tap-target (toggle checkbox) —
  kalau butuh gesture TERPISAH di baris yang sama (mis. tap-buka-modal),
  restrukturisasi ke `ListTile` + `leading: Checkbox(...)` eksplisit,
  BUKAN coba tumpuk `GestureDetector` di atas `CheckboxListTile`.
- Lihat gotcha lama (HID scanner menelan input, `TextDirection` PDF vs
  material, font PDF non-ASCII, `formatRupiah` non-breaking space, drift
  `StreamProvider` widget test hang) — semua di CLAUDE.md, masih berlaku,
  tidak diulang di sini.

## Lingkungan sesi ini
Flutter di `/tmp/flutter` (bukan `/opt/flutter` yg disebut CLAUDE.md — cek
`which flutter` dulu kalau command CLAUDE.md gagal). Android SDK TIDAK ADA
(`ANDROID_HOME` kosong) — perubahan Kotlin/Gradle cuma ditinjau manual,
verifikasi riil lewat CI. Jalan sbg root menghasilkan warning "Woah!..."
yang tidak menggagalkan perintah, aman diabaikan.

## Menggantung / Kandidat Berikutnya
- **Item 13 lama (katalog HTML "belum identik" UI app) — kemungkinan
  TERJAWAB** lewat redesain modal tap-item follow-up round #2 (user kirim
  screenshot referensi app kasir asli, sudah ditindaklanjuti — lihat
  section follow-up di atas). Belum ada konfirmasi eksplisit user bahwa
  ini SUDAH cukup — kalau ada laporan susulan soal visual katalog HTML,
  lanjutkan dari situ, bukan dari nol.
- **Scan pesanan pegawai via HID — fix BELUM dikonfirmasi di hardware
  fisik** (lihat detail follow-up #3 di atas) — kalau user lapor masih
  gagal setelah fix ini, kemungkinan scanner itu juga tidak kirim Enter
  di akhir SELURUH payload, minta detail/log lebih lanjut sebelum coba
  fix lain.
- **Item 23 sisa** (`printer_service.dart printReceipt` tunggal,
  `transaksi_tab.dart`, `tx_history_sheet.dart`, `settleMergedDebt`, Buku
  Hutang, Tutup Kasir "kas sistem" overstated) — lihat PLAN.md.
- **Item 21+17** (sync UI persisten lintas tab + persist antrian approval)
  — masih sengaja ditunda dari sesi-sesi sebelumnya.
- **Item 3c/4/5** (import data toko lama dari dataset Griyo POS) — lihat
  PLAN.md, menunggu keputusan/data lanjutan dari user.
- **Crash Infinix Smart 8 — tinggal konfirmasi user** (lihat section di atas).
- **25c (gerbang lisensi)** — tunggu developer generate keypair + putuskan
  nomor WA (lihat section di atas).

## Preferensi User (masih berlaku)
- Bahasa komunikasi & teks UI: Indonesia.
- Untuk fitur bervisual: usulkan opsi desain dulu sebelum implementasi.
- Untuk bug: laporkan dulu contoh kasus + severity, baru eksekusi.
- Untuk fitur baru berisiko/besar: diskusikan cakupan dulu, eksekusi
  setelah instruksi eksplisit ("eksekusi semua"/konfirmasi serupa/"Execute!").
- **User sering mengoreksi/menyederhanakan scope lewat pertanyaan tajam** —
  jangan buru-buru eksekusi desain awal kalau user masih mengajukan
  pertanyaan klarifikasi/skeptis, itu sinyal scope akan berubah.
- **Batch besar berisi item ambigu + jelas dicampur**: user OK item jelas
  langsung dieksekusi tanpa PLAN.md, TAPI item genuinely ambigu tetap harus
  diklarifikasi dulu (lihat pola `AskUserQuestion` batch sesi ini) —
  jangan asumsikan sepihak keputusan desain yang punya >1 opsi masuk akal.
- **User melaporkan bug dgn observasi presisi** (termasuk screenshot) —
  baca laporan kata per kata, biasanya sudah menunjuk lokasi/skenario
  presisi; screenshot bisa membongkar bug LAIN yang belum dilaporkan
  eksplisit (lihat bug nota gabungan sesi ini, ditemukan dari screenshot
  yang awalnya cuma utk melaporkan item 9).
- Rencana yang didiskusikan tapi belum dieksekusi → masuk PLAN.md
  komprehensif, jangan cuma tersimpan di riwayat chat.
- Perubahan sensitif/berisiko (mis. aspek security) — tunda eksekusi
  sampai instruksi eksplisit terpisah.
- Untuk perubahan kecil yang jelas (tidak ambigu) — user eksplisit minta
  langsung eksekusi + merge ke main tanpa menunggu konfirmasi tambahan.
