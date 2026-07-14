# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 14 Juli 2026 (lanjutan lagi). Sesi ini: fix bug sync
LAN gagal total di HP yang app-nya belum ter-update (`2d4467a`, lihat
detail di bawah — PENTING, ini kelas bug yang akan BERULANG tiap ada
kolom skema baru selama device belum update serentak) + badge jumlah
item di struk/keranjang disamakan gaya cart bar (`67414e1`) + katalog
HTML kini tampilkan SEMUA satuan produk, bukan cuma satuan dasar
(`7c65b78`) + fix susulan "N pilihan" under-count utk kombinasi
varian+multi-satuan (`69abb77`) + tombol "Salin Teks Pesanan" di bawah QR
handoff pegawai (`458fc77`, lihat detail di bawah — PENTING, gotcha
`Clipboard.getData()` hang di widget test, sudah ikut ditambahkan ke
CLAUDE.md `102399d`) + redesign kartu antrian "Pesanan Ditahan" (`3200c0e`,
lihat detail di bawah — diusulkan via mockup Playwright dulu sebelum
dikerjakan, sesuai permintaan user) + fix poin loyalitas tempo selalu 0 +
tap luar tutup panel antrian (`45ac0c5`, lihat detail di bawah) + perf
katalog HTML — update satu baris produk, bukan render ulang grid penuh
(`d4a8e71`, lihat detail di bawah — didahului sesi riset performa
read-only, user minta insight dulu sebelum eksekusi).
**schemaVersion masih 15** (tidak ada migrasi baru). Full `flutter test`
**341 test hijau**, `flutter analyze` bersih._

## Perf katalog HTML — update satu baris produk, bukan render ulang grid

User tanya (insight-only dulu, TANPA kode): "html ui sudah bagus, tapi
sekarang jadi berat, apakah bisa dibuat ringan tanpa mengorbankan
UI/UX?" + 2 pertanyaan lain (state centang persisten? fitur useless
resource besar?). Riset dikerjakan oleh Explore agent (read-only) +
verifikasi manual sendiri, jawaban lengkap sudah diberikan ke user tanpa
ubah kode dulu. User lalu approve implementasi item prioritas #1
("boleh, kerjakan").

**Akar masalah** (`order_page_service.dart`, sebelum fix): `setQty()`
(dipanggil tiap tap +/- baik di grid produk maupun stepper keranjang)
SELALU panggil `renderList()` penuh — rebuild SELURUH grid produk dari
nol via `DocumentFragment`, walau cuma 1 baris yang qty-nya berubah.
O(jumlah produk) kerja DOM per tap, makin kerasa lag makin banyak
produk di katalog.

**Fix**: `renderList()` sekarang tag tiap `.prow` dengan `row.dataset.pid
= p.id`. `setQty()` cari produk via `findProductForUnit(unitId)` (helper
yg sudah ada), lalu panggil `refreshProwControls(p)` baru — cari row via
`querySelector('.prow[data-pid="..."]')`, replace HANYA `.prow-controls`
di dalamnya (`buildProwControls(p)` baru), bukan seluruh row apalagi
seluruh grid. Fallback ke `renderList()` penuh kalau produk tidak
ketemu (harusnya tidak pernah terjadi). Nama/meta/harga tiap baris
memang tidak pernah berubah gara-gara qty jadi aman di-skip dari update.

**Verifikasi Playwright manual** (bukan test committed, scratch file
sudah dihapus): generate HTML dari DB uji 5 produk, tandai semua node
`.prow` dengan marker JS custom, klik +/- pada satu produk berkali-kali,
buktikan SEMUA node lain (termasuk node yg diklik sendiri — cuma child
`.prow-controls`-nya yang diganti) tetap node yang SAMA (bukan
rebuild) — plus qty/cart bar/search debounce/stepper keranjang semua
tetap berfungsi identik ke perilaku lama.

Test committed baru: `test/order_page_service_test.dart` — assertion
string-based (pola yang sudah dipakai file ini) mengecek `setQty()`
memanggil `refreshProwControls(p)` bukan `renderList()` tanpa syarat lagi
(regex atas isi fungsi `setQty`), plus keberadaan `row.dataset.pid` &
`refreshProwControls`. Revert-verify: kembalikan `setQty` ke
`renderList()` polos → test gagal tepat di assertion yg diharapkan →
pasang lagi fix, hijau.

**Temuan riset lain (belum ditindaklanjuti, sekadar insight ke user)**:
2 font base64 (Hanken Grotesk + Newsreader) ±123 KB selalu ikut tiap
file katalog di-generate (`order_page_service.dart:187,191`) — biaya
tetap ukuran file share, bukan penyebab lag. N+1 query saat generate
katalog di app (`unitsJsonFor` per unit produk, sequential await) — bisa
bikin proses "Generate Katalog" lambat utk toko banyak produk, terpisah
dari lag di HP pelanggan. Crash log tidak pernah di-rotate
(`crash_log_service.dart`) — bisa membengkak kalau ada bug yg crash
berulang. State "centang" struk PERMANEN di SQLite
(`transactions.checked_item_ids`, per-baris, tidak ada masalah performa);
cart draft (termasuk `CartItem.checked`) di SharedPreferences dgn
cleanup 24 jam utk cart "tambah belanjaan" yatim — tidak ada potensi
menumpuk.

## Poin loyalitas transaksi tempo + tutup panel antrian via tap luar

User laporkan 2 hal sekaligus:
1. Transaksi tempo (tombol "Bayar Nanti") tidak pernah dapat poin
   loyalitas, walau totalnya melebihi threshold di Pengaturan.
2. Panel "Pesanan Ditahan" cuma bisa ditutup lewat tombol ✕ — user minta
   tap/swipe di luar wadah panel juga menutupnya, dengan animasi smooth.

**Poin tempo** — akar masalah di `payment_screen.dart:459` (sebelum fix):
syarat `!isTempo` di kondisi pemberian poin bikin `pointsEarned` SELALU 0
utk transaksi `status == 'tempo'`, tidak peduli besarnya `_total`. **Sempat
ditanya ke user dulu** (`AskUserQuestion`) soal timing: poin langsung saat
dicatat, atau baru saat lunas? Sebelum bertanya, sudah dicek dulu bahwa
`voidTransaction` (`app_database.dart:1279`) SUDAH generik membalikkan
poin berdasarkan `tx.pointsEarned` tersimpan, TIDAK peduli payment method
— jadi kalau poin diberikan langsung saat tempo dicatat, pembatalan tetap
otomatis aman tanpa kode tambahan. User pilih opsi ini (langsung saat
dicatat, lebih sederhana). Fix: hapus syarat `!isTempo` — poin dihitung
dari `_total` sama seperti tunai. Test baru: `test/tempo_loyalty_points_test.dart`
(drive lewat `PaymentScreen` sungguhan, tap "Bayar Nanti", verifikasi
`tx.pointsEarned`, `customer.loyaltyPoints`, & `loyaltyPointLedger`).

**Tutup panel via tap luar** — `_HeldInlinePanel` di `kasir_screen.dart`
sudah inline (bukan modal) di dalam `Listener` yang membungkus SELURUH
area topbar-ke-bawah (termasuk panel itu sendiri) — jadi tidak bisa
sekadar "tutup panel kalau ada tap di area Listener ini", karena tap DI
DALAM panel (kartu antrian, tombol ✕, scroll strip horizontal) juga akan
ke-hit-test oleh Listener yang sama. Fix: `GlobalKey _heldPanelKey`
dipasang ke `_HeldInlinePanel`, di `onPointerDown` cek posisi tap via
`RenderBox.globalToLocal` — kalau di LUAR bounds panel baru
`setState(() => _heldPanelOpen = false)`. Animasi smooth otomatis dari
`AnimatedSize` yang sudah membungkus panel (tidak perlu kode animasi
baru). `_HeldInlinePanel` constructor perlu ditambah `super.key` (tidak
ada sebelumnya). Test baru di `kasir_verify_order_test.dart`: 1) tap jauh
di bawah panel (grid produk) → panel tertutup, antrian TIDAK
ter-resume/terhapus; 2) tap DI DALAM panel (judul "PESANAN DITAHAN") →
panel TETAP terbuka.

Kedua fix sudah revert-verify (test gagal dgn pesan yang relevan sebelum
fix dipasang, hijau lagi sesudahnya).

## Redesign kartu antrian "Pesanan Ditahan"

User bilang desain kartu antrian yang lama "tidak pas" — diminta
proposalkan dulu via Playwright (mockup HTML statis, screenshot,
dikirim ke user) SEBELUM ada perubahan kode, baru setelah user setuju
("wah bagus itu, kerjakan sekarang juga") baru dieksekusi. Mockup ada di
scratchpad sesi ini (`queue_redesign/mockup.html` + `proposal.png`, tidak
di-commit — cuma alat komunikasi, bukan bagian app).

Masalah desain lama (`_HeldCard` + `_HeldCardWithTab`, sebelum redesign):
tinggi kartu dipaksa 152px demi menampung tab lipat (`_TabPainter`
trapesium, gaya yang cuma dipakai di sini) di kartu handoff — kartu
pesanan ditahan BIASA (tanpa handoff) jadi punya `Spacer()` kosong besar
karena tinggi disamakan. Badge "Menunggu Anda Bayar" pakai warna `error`
(merah) padahal bukan kondisi error — bertabrakan dgn konvensi semantik
warna project (merah = hutang/masalah, lihat §Gotcha CLAUDE.md). Nominal
total pakai font biasa, bukan `AppTheme.numStyle` (Newsreader) yg jadi
konvensi semua angka uang di app.

Redesign: gabung `_HeldCardWithTab` + `_HeldCard` jadi SATU class
`_HeldCard` — tidak ada lagi tab lipat terpisah. Beda status (pesanan
ditahan biasa vs handoff pegawai) sekarang cuma lewat warna **chip** di
baris atas KARTU YANG SAMA: abu netral "Ditahan" vs terracotta
(`AppTheme.accent`) berisi ikon + nama pegawai pengirim + jam. Semua kartu
jadi tinggi konsisten (134, turun dari 152) tanpa ruang kosong. Total
sekarang pakai `AppTheme.numStyle`. `_TabPainter` class TIDAK dihapus —
masih dipakai `_CartMetaTab` (komponen lain) di file yg sama.

**Bug ketemu saat implementasi** (langsung ke-catch oleh test yang sudah
ada, `kasir_scan_order_code_test.dart`): chip pertama kali ditulis dengan
`Text` polos di dalam `Row(mainAxisSize: MainAxisSize.min)` tanpa
`Flexible` — RenderFlex overflow 3px kalau nama pegawai+jam agak panjang,
karena Row(mainAxisSize.min) melayout child non-flex di lebar natural
(tak terbatas), BUKAN dibatasi lebar parent, walau parent (Column di
dalam Container lebar tetap) sudah sempit. Fix: bungkus `Text` dgn
`Flexible` supaya Row benar-benar memberi batas lebar & ellipsis bisa
jalan. Revert-verify: hapus `Flexible`, 4 test gagal dgn overflow error
yang sama persis → pasang lagi, hijau semua.

Test yang perlu diupdate (bukan bug, cuma teks assertion ikut desain
baru): 2 assertion `find.text('Menunggu Anda Bayar')` di
`kasir_scan_order_code_test.dart` diganti `find.textContaining('siap
dibayarkan')` (teks meta baris kedua khusus kartu handoff sekarang).

## Tombol "Salin Teks Pesanan" di bawah QR handoff pegawai

Usulan user: tambah jalur cadangan di `_HandoffQrSheet` (`cart_sheet.dart`,
sheet "Kirim ke Owner/Asisten" utk pegawai tanpa izin Terima Pembayaran)
kalau scan QR susah (kamera bermasalah/pencahayaan kurang) — pegawai bisa
salin teks pesanan (persis sama dgn isi QR, hasil `OrderParserService.
encodeHandoff`) lewat `OutlinedButton.icon` baru di bawah caption QR,
kirim manual via WhatsApp/Telegram, owner/asisten tempel di fitur "Tempel
Pesanan" yang sudah ada (parser sudah baca format ini).

**Gotcha besar ketemu saat nulis test** (sudah ditambahkan ke CLAUDE.md
§Gotcha, `102399d`): `Clipboard.getData()` TIDAK di-mock otomatis oleh
`flutter_test` di environment ini — beda dari asumsi umum "flutter_test
punya default clipboard mock". Tanpa handler manual, `await Clipboard.
getData(...)` di dalam test MENGGANTUNG SELAMANYA (bukan exception cepat)
— sempat bikin test hang >5 menit (dicoba `pumpAndSettle()` → `pump()`
biasa dulu mengira gara-gara timer SnackBar, TERNYATA bukan itu masalahnya
sama sekali) sebelum diisolasi via scratch test minimal dan ketahuan akar
masalahnya murni di sisi test. Fix: pasang mock method channel manual
(`TestDefaultBinaryMessengerBinding...setMockMethodCallHandler(
SystemChannels.platform, ...)`) yang menyimpan/mengembalikan teks sendiri
— lihat `test/kasir_handoff_qr_test.dart` utk pola lengkapnya, tiru kalau
nanti ada test lain yang butuh baca balik isi clipboard.

## Katalog HTML — satuan lain (mis. Dus) sekarang ikut tampil

User laporkan: produk yang punya >1 satuan di POS (mis. "Sedap Goreng"
per Biji + per Dus) cuma satuan dasarnya (Biji) yang muncul di katalog
online — Dus sama sekali tidak ada opsinya. Akar masalah: `_buildCatalogJson`
(`order_page_service.dart`) dari awal cuma pernah mengambil SATU baris
`product_units` per produk (yang `isBaseUnit`), field satuan lain tidak
pernah di-query sama sekali — ini KATEGORI BEDA dari fitur varian (varian
= produk anak terpisah, `getVariants`, sudah ter-handle lama; ini soal
multi-SATUAN produk yang SAMA, belum pernah ditangani).

Fix: field baru `units` (array semua satuan berharga valid milik produk,
base unit selalu di indeks 0) ditambahkan ke tiap entri produk/varian di
JSON yang di-embed. Fungsi JS (`byUnit`, `totalQtyForProduct`,
`minPriceForProduct`, `unitOptionsFor`, `findProductForUnit`, +
`totalOptionsFor` baru) semua digeneralisasi baca `p.units`/helper
`_ownUnits(p)` (fallback ke `[{unitId:p.unitId,...}]` kalau field lama
tanpa `units`, jaga-jaga data lama) — bukan cuma `p.unitId` tunggal. Kalau
produk punya >1 satuan, chip di modal tap-item sekarang menampilkan
SEMUA satuan (label = nama satuan, mis. "Biji"/"Dus"), dan grouping di
teks pesanan (`buildOrderText`) + tampilan keranjang meniru pola varian
(header nama produk + baris ber-indent per satuan) begitu produk itu
benar-benar punya >1 satuan.

**Susulan (dikonfirmasi via pertanyaan user "apakah varian juga bisa
diinput?"):** kombinasi varian yang PUNYA >1 satuan SENDIRI (mis. varian
"Pedas" juga py Pcs+Renceng) sudah diverifikasi nyata via Playwright —
chip di modal tampil benar (semua kombinasi produk-induk × varian ×
satuan muncul sbg chip terpisah, mis. "Pcs", "Pedas (Pcs)", "Pedas
(Renceng)"), TAPI ketahuan bug turunan: teks ringkasan "N pilihan" di
daftar produk under-count (bilang "2 pilihan" padahal 3 chip nyata
muncul) — `totalOptionsFor` menghitung tiap varian sebagai 1 opsi tetap,
tidak ikut menjumlahkan satuan internal varian itu. Fix: `totalOptionsFor`
sekarang menjumlahkan satuan TIAP varian, sama seperti cara
`unitOptionsFor` membangun chip (`69abb77`). Test baru
(`order_page_service_test.dart`) cover kombinasi ini secara eksplisit.

Diverifikasi Playwright/Chromium nyata (bukan cuma baca kode) utk KEDUA
skenario: produk induk 2-satuan (chip Dus muncul & berfungsi), DAN
varian+multi-satuan (3 chip benar, teks "3 pilihan" akurat setelah fix).

## Badge jumlah item disatukan gayanya (struk/keranjang/cart bar)

Widget `ItemCountBadge` baru (`lib/core/widgets/item_count_badge.dart`),
diekstrak dari lingkaran badge yang dulu private di `_CartBar`
(`kasir_screen.dart`) — dipakai ulang di `cart_sheet.dart` (samping kiri
Total) dan `receipt_screen.dart` (menempel/mengambang di sudut kiri-atas
kartu daftar barang struk, via `Stack`+`Positioned`+`elevated:true`,
sesuai posisi yg diminta user dari screenshot). Sebelumnya di kedua
tempat itu cuma teks polos "N item", tidak senada dgn cart bar.

## Fix sync LAN gagal total — device tertinggal 1 kolom skema (mis. Infinix Smart 8)

User laporkan error nyata saat sync dari HP Infinix Smart 8 ke host:
`SqliteException(1): table transactions has no column named
checked_item_ids`. Root cause (dikonfirmasi via investigasi, BUKAN
migrasi gagal diam-diam — sudah dicek tidak ada `try/catch` yang menelan
exception migrasi di `onUpgrade`): `AppDatabase.mergeRows()`
(`lib/core/database/app_database.dart`) membangun `INSERT OR IGNORE/
REPLACE` secara DINAMIS dari `row.keys` — yaitu kolom apa pun yang
kebetulan ada di dump SELECT * milik PENGIRIM — tanpa pernah divalidasi
ke skema fisik tabel LOKAL penerima. Device yang app-nya belum ter-update
ke schemaVersion terbaru (kemungkinan besar kasus Infinix ini: APK yang
ter-install lebih tua dari commit `a8c94ad`/schemaVersion 15) akan selalu
gagal total begitu menerima dump dari device lain yang skemanya lebih
baru — SATU kolom asing menggagalkan SELURUH baris & seluruh proses sync,
bukan cuma baris/kolom itu.

**Ini BUKAN kasus sekali-jadi** — app ini offline-first multi-perangkat
(owner+kasir update tidak serentak by design), jadi kelas bug yang SAMA
akan muncul lagi tiap kali ada kolom skema baru selama masih ada device
yang belum sempat update. Fix bersifat STRUKTURAL, bukan tambal 1 kolom:
`mergeRows()` sekarang baca kolom fisik lokal via `PRAGMA table_info
("$tableName")` (bukan definisi tabel Drift statis di kode — supaya
benar-benar mencerminkan skema SQLite yang SUNGGUHAN berjalan di device
itu), lalu filter row masuk ke kolom yang benar-benar ada sebelum build
INSERT. Kolom asing dari pengirim yang lebih baru diabaikan per-baris,
tidak menggagalkan sync.

**Belum disentuh** (di luar scope fix ini, dicatat sebagai potensi
follow-up kalau relevan nanti): protokol `lan_sync_service.dart` tidak
punya mekanisme cek/negosiasi `schemaVersion` sama sekali antar host↔klien
— fix ini menangani gejalanya (sync tidak gagal), bukan menambahkan
deteksi proaktif "device X butuh update" ke UI.

Test regresi (`test/merge_rows_schema_mismatch_test.dart`) mensimulasikan
device tertinggal dengan `ALTER TABLE transactions DROP COLUMN
checked_item_ids` pada DB in-memory yang sudah schemaVersion 15 (paling
presisi mereproduksi kondisi fisik device asli, dibanding coba pasang
fixture schemaVersion lama) — diverifikasi revert-verify, pesan error
tereproduksi PERSIS sama dengan laporan user sebelum fix dikembalikan.

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
