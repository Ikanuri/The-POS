# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md).

_Update sesi 26 Juli 2026 (lanjutan) — semua pekerjaan sesi ini sudah
di-**merge ke `main`** (merge commit `1083388`). Sesudah itu: **bug
"codegen Drift tidak jalan" AKHIRNYA TERPECAHKAN** — ternyata BUKAN bug
sandbox sama sekali, tapi bug NYATA di repo (anotasi `@DriftDatabase`
terlepas dari class-nya). Sudah diperbaiki + dipagari test regresi.
`build_runner` kini berfungsi normal lagi, jadi **PLAN.md Item 52 ("Laci
Meja") sudah bisa langsung dieksekusi** tanpa hambatan alat._

## SOLVED: codegen Drift tidak pernah memperbarui `app_database.g.dart`

**Status: SELESAI.** Diagnosis sesi sebelumnya ("bug alat/sandbox, coba
lagi di sesi baru") **KELIRU** — jangan dipakai lagi sebagai acuan.

**Akar masalah sesungguhnya**: di `lib/core/database/app_database.dart`,
blok anotasi `@DriftDatabase(tables: [...])` **tidak lagi menempel di
`class AppDatabase`**. Sejak commit `dd4bad3` (17 Juli) ada beberapa
`typedef` (`StockOverviewRow`, `OpnameSessionSummary`, dst) plus
`class BarcodeConflictException` yang tersisip **di antara** blok anotasi
dan `class AppDatabase`. Dart menganggap ini **sah** — anotasi boleh
dipasang di `typedef` — jadi anotasi itu diam-diam menempel ke
`typedef StockOverviewRow`.

**Kenapa sangat sulit dilacak** (dan kenapa sempat disalahartikan sbg
bug sandbox):
- `flutter analyze` tetap **0 issue**, seluruh test tetap **hijau**.
- `build_runner` tetap melaporkan **"Succeeded"** dengan ribuan output.
- Tidak ada **satu pun** pesan error/warning di mana pun.
- Yang terjadi: drift_dev tidak menemukan database sama sekali, jadi
  `app_database.g.dart` **tidak pernah ditulis ulang** — file lama yang
  tercommit tetap dipakai, sehingga semuanya "kelihatan" normal.

**Cara membuktikannya lagi kalau perlu** (alat diagnostik yang manjur):
- `dart run drift_dev identify-databases` → kalau output kosong (tidak
  menyebut satu database pun), berarti anotasi tidak terbaca. Ini
  pemeriksaan **paling cepat & paling langsung**.
- `.dart_tool/build/generated/the_pos/lib/core/database/app_database.dart.drift_elements.json`
  → kalau `"elements": []` padahal `"imports"` terisi, gejalanya sama.

**Fix**: blok `@DriftDatabase(tables: [...])` dipindah agar **langsung di
atas `class AppDatabase`**; semua `typedef`/class lain digeser ke atas
blok anotasi. Tidak ada perubahan skema, tidak ada perubahan perilaku.

**Dampak ke `app_database.g.dart`**: hasil regenerasi berbeda ~948
baris dari yang tercommit, tapi **murni formatting + propagasi
doc-comment** dari drift_dev versi lebih baru (2.23.1). Sudah
diverifikasi **tidak ada kolom/tabel yang hilang atau bertambah**: 103
nama kolom dan seluruh class `$...Table` identik antara versi lama dan
baru. Jadi tidak pernah ada skema yang diam-diam rusak — kebetulan
memang belum ada tabel/kolom baru yang ditambahkan sejak 17 Juli.

**Pagar regresi**: `test/drift_codegen_in_sync_test.dart` (2 test)
- menolak deklarasi apa pun yang menyelinap di antara `@DriftDatabase`
  dan `class AppDatabase` (menangkap akar masalahnya), dan
- membandingkan jumlah tabel di anotasi vs `db.allTables` hasil generate
  (menangkap `app_database.g.dart` yang basi).
Sudah dibuktikan GAGAL saat fix-nya di-revert sementara, dengan pesan
yang menuntun ke solusinya.

**Pelajaran utk ke depan**: kalau `build_runner` "sukses" tapi `.g.dart`
tidak berubah, **jangan langsung menyalahkan sandbox/toolchain**. Cek
dulu apakah anotasinya benar-benar terbaca lewat
`dart run drift_dev identify-databases`.

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
