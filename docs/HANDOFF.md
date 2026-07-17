# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 17 Juli 2026 (sesi lanjutan — fitur Alihkan Owner +
3 bug susulan dari testing device asli + fix poin loyalitas + fix
keamanan lisensi + fix debounce scanner + fix nama pelanggan riwayat +
warna aksen toolbar kasir + fix sinkron harga SKU non-unik)._ Full
`flutter test` **412 test hijau**,
`flutter analyze` bersih. schemaVersion masih 15
(tidak ada migrasi baru). Branch `claude/setup-dependencies-am31te` —
belum di-merge ke `main` (tunggu instruksi user). User sudah perbaiki
`license/revoked.json` di `main` secara manual (typo tanda kutip) —
item ini SELESAI, tidak perlu ditindaklanjuti lagi.

## Item 35 — fix sinkron harga antar-toko: SKU non-unik salah cocok (17 Juli, SELESAI)

User lapor: tiap sinkron harga dgn toko lain, SELALU ada harga "berubah"
walau logikanya sama & tidak pernah konvergen. Minta log matching (tombol
🐛 di layar Preview Harga). Log 2.745 item vs 1.831 produk lokal
MEMBANTAH dugaan awal tier ganda (semua unit `1 buah` tier) — akar
masalahnya **matching salah**.

**Root cause**: `_tryMatch` (`price_match_service.dart`) cocok via SKU
pakai `.firstOrNull` padahal `kode_produk` di data user TIDAK unik (banyak
produk berkode nama satuan "Dos"/"Bal"/"Pak"). Bukti log: `Adem Sari
Cingku/Dos` DAN `Alamo Tg/Dos` dua-duanya nyasar ke `Agar Satelit`;
`76 12/bal` → `Atira 2000`. Saat Terapkan, harga ditulis ke produk salah
→ sync berikutnya baris asli produk itu menimpanya balik → saling-timpa
selamanya (non-konvergen). Bug KEMBAR di sisi apply: `_findOrCreateProduct`
(`price_preview_screen.dart`) juga `.firstOrNull` untuk kode.

**Fix** (3 bagian, disetujui user):
1. Pengaman tabrakan SKU: cocok SKU hanya kalau kode dimiliki TEPAT 1
   produk. Kalau >1 → tidak auto-match; fuzzy-nama fallback yang tangani
   (masuk tab "Mirip", default skip → tidak menimpa diam-diam).
2. `_resolveUnitStrict` baru: match SKU juga wajib satuannya ada di produk
   lokal (cegah `76 12/bal` → `Atira 2000` yg tak punya satuan "Bal").
   Kalau `unitTypeName` katalog kosong → fallback base unit (tak bisa lebih
   ketat). Jalur fuzzy/ambiguous TETAP pakai `_resolveUnit` lenient (di
   sana ada konfirmasi manusia).
3. `_findOrCreateProduct` pakai kode hanya kalau unik; >1/0 → jatuh ke
   pencocokan nama.

Fuzzy sudah benar sejak awal (masuk tab "Mirip", TIDAK ada tombol "Samakan
Semua" massal) — tidak diubah, cukup diverifikasi.

Test: `test/price_sync_sku_collision_test.dart` (DB-tier, reproduksi persis
kasus log: `Dos`→2 produk tidak nyasar ke Agar Satelit & masuk ambiguous;
`bal`→produk tanpa satuan Bal ditolak → notFound; kontrol positif SKU unik
+ satuan cocok tetap match). Revert-verify: kembalikan `.firstOrNull` +
`_resolveUnit` lenient → 2 test bug GAGAL (nyasar ke Agar Satelit/Atira),
kontrol positif tetap hijau → fix dikembalikan, hijau lagi.

**Opsi belum dikerjakan** (dibahas, tidak masuk batch ini): mode "sinkron
via barcode saja" utk toko besar. Ada di PLAN.md Item 35 kalau user mau
lanjut.

## Item 33 — aksen warna toolbar kasir (16 Juli, SELESAI, Varian C)

User pilih **Varian C** dari 3 mockup Playwright yang dikirim sesi
sebelumnya (`toolbar_color_mockups.html/.jpg`, scratchpad — tidak
di-commit). Ditambahkan 4 pasang warna baru di `AppTheme`
(`scanFg/scanBg`, `antrianFg/antrianBg`, `riwayatFg/riwayatBg`,
`tempelFg/tempelBg`, masing-masing `Color Function(bool isDark)`,
mengikuti pola pasangan fg/bg yang sudah ada spt `debtFg`/`debtBg`).
`_TbBtn` (`kasir_screen.dart`) diberi parameter opsional
`fg`/`bg` (`Color Function(bool)?`) — kalau null, fallback ke warna
netral lama (`cs.onSurfaceVariant`/`cs.surface`). 4 dari 5 tombol
toolbar diwarnai (scan=biru, antrian=amber, riwayat=ungu, tempel
pesanan=hijau); toggle grid/list SENGAJA dibiarkan netral (bukan
error/kelupaan — murni preferensi tampilan, bukan fungsi yang perlu
disorot warna).

Test: `test/kasir_toolbar_accent_color_test.dart` (cek warna icon scan/
antrian/riwayat sesuai `AppTheme`, dan toggle grid/list TETAP
`onSurfaceVariant`). Revert-verify dilakukan (lepas `fg`/`bg` dari
tombol scan → test gagal tepat sesuai ekspektasi → dikembalikan).
**Item 33 SELESAI, tidak ada pekerjaan menggantung.**

## Fix: riwayat transaksi nyangkut "Pelanggan" generik utk pelanggan terhapus (16 Juli)

User lapor bug ini SETELAH lihat data hasil "Alihkan Owner" di device
tujuan (screenshot: beberapa baris riwayat transaksi tampil "Pelanggan"
polos, bukan nama asli) — TAPI setelah ditelusuri, ini BUKAN bug Alihkan
Owner, murni bug lama yang kebetulan baru ketahuan saat review data pasca-
transfer.

**Akar masalah**: `_custNamesProvider` (`tx_history_sheet.dart:80`)
membangun peta id→nama pelanggan lewat `db.searchCustomers('')`, yang
DIAM-DIAM memfilter `isActive=true` (`app_database.dart:2483`, dipakai
jg oleh dropdown pilih pelanggan — filter ini MEMANG benar utk kebutuhan
itu). Begitu pelanggan dihapus (`deactivateCustomer()` — soft-delete, set
`isActive=false`), namanya hilang dari peta ini → `_customerLabel()`
(baris 791) jatuh ke fallback literal `'Pelanggan'`. Ini bertentangan
LANGSUNG dgn komentar `deactivateCustomer()` sendiri: *"Transaksi &
riwayat historis tetap utuh krn hanya menyembunyikan dari daftar
aktif"* — niatnya nama tetap kelihatan di riwayat, implementasinya
malah menyembunyikan.

**Fix**: method baru `AppDatabase.getAllCustomerNamesIncludingInactive()`
(select semua pelanggan TANPA filter isActive, khusus utk historical
label lookup) — `_custNamesProvider` diarahkan ke situ, `searchCustomers()`
sendiri TIDAK diubah (tetap benar utk dropdown pilih pelanggan aktif).

**Bug ini akan muncul di DEVICE MANAPUN** yang pernah menghapus pelanggan
yang sudah dipakai transaksi — tidak spesifik Alihkan Owner, cuma
kebetulan baru kelihatan sekarang. Kalau ada laporan serupa lagi
("riwayat transaksi nama pelanggan hilang/generik"), cek dulu apakah
pelanggannya sudah di-soft-delete.

Test: `test/customer_names_including_inactive_test.dart` (DB-tier: method
baru TETAP include pelanggan inactive, beda dari `searchCustomers()`),
`test/tx_history_deleted_customer_name_test.dart` (widget-tier: transaksi
dgn `customerId` milik pelanggan terhapus & `customerName` null — pola
NYATA saat pelanggan dipilih dari daftar, bukan diketik manual — tetap
tampil nama asli, bukan fallback). Revert-verify dilakukan.

## Fix: debounce scanner eksternal 300ms → 150ms (16 Juli)

User lapor: scan barcode dobel cepat berturut (mis. sengaja scan 2x utk
qty 2) kadang cuma menghasilkan 1 output. Akar masalah: `_handleBarcode`
(`kasir_screen.dart:1126`) punya debounce anti-echo hardware utk scanner
eksternal — barcode SAMA dalam window waktu tsb diabaikan. Window itu
300ms (dari commit `051357b`, 27 Juni — DITAMBAHKAN sbg fix anti-duplikat
saat itu, BUKAN diturunkan dari nilai lebih tinggi; ditelusuri via git
log krn user tidak ingat detail persis, cuma ingat "dulu kurang
responsif lalu di-fix" — kemungkinan besar memori itu soal pengalaman
scan lain di rentang commit yg sama, bukan window 300ms spesifik ini).

**Fix**: turunkan ke 150ms (matching konvensi debounce anti-misclick
lain di app, mis. `AddControl`) — tetap ada jaring anti-echo, cuma
window-nya separuh. **TIDAK BISA diverifikasi otomatis** (perilaku echo
hardware scanner sungguhan tidak bisa disimulasikan widget test) — user
SUDAH diberi tahu WAJIB coba manual di device asli dgn scanner fisiknya:
(a) pastikan scan dobel cepat yg disengaja sekarang berhasil dobel, DAN
(b) pastikan tidak muncul balik gejala lama (barcode kepencet dobel
sendiri tanpa disengaja). **STATUS: kode sudah diubah & dipush, TAPI
verifikasi manual user belum dikonfirmasi** — kalau sesi depan lanjut,
tanyakan hasil tes user dulu sebelum menganggap ini selesai total (lihat
juga PLAN.md Item 32).

## Diskusi belum dieksekusi — Item 29/30/31 siap kapan saja

- **Item 29** (katalog HTML auto-"habis" dari stok ril) — desain final,
  belum diimplementasi.
- **Item 30(a)** (kartu cek cepat di Ringkasan Harian) — desain final,
  agak bergantung ke 30(b) (target navigasi "Lihat semua").
- **Item 30(b)** ("Cek Stok" screen) — layout mockup SUDAH di-approve
  user (`cek_stok_mockup.html`/`.jpg` di scratchpad sesi ini, tidak
  di-commit — lihat deskripsi lengkap di PLAN.md kalau perlu regenerasi).
  Siap diimplementasi ke Flutter kapan saja.
- **Item 30(c)** (tab analitik/audit di Laporan, chart+tabel) — desain
  final.
- **Item 31** (Tutup Buku tanggal custom, sekali/tahun) — redesain
  teknis (periodStart/periodEnd) sudah disetujui, belum diimplementasi.
- **Item 4/5** (migrasi data Griyo POS/transaksi lama) — **DIPENDING**
  atas permintaan user: scope migrasi ternyata bukan cuma
  transaksi+pelanggan, tapi juga produk dll (belum dirinci). Jangan
  mulai sebelum user re-konfirmasi scope penuh & minta lanjut.

## Fitur baru: "Alihkan Owner" + "Pulihkan dari File" (16 Juli, Item 27/28)

Diimplementasikan SELESAI setelah diskusi desain panjang (lihat CHANGELOG
utk histori keputusan lengkap kalau perlu telusuri). Ringkasan final:

**Format file baru `BPOT1`** (`db_export_service.dart`) — sama enkripsinya
dgn `.berkahpos` portable (BPOP2, PBKDF2+salt acak), TAPI payload-nya JUGA
bawa `storeUuid`/`storeKey`/`storeName` toko asal, dan itu BENAR-BENAR
diterapkan ke device penerima (bukan cuma ekspor data). SENGAJA magic byte
& fungsi terpisah dari `exportPortable`/BPOP2 (bukan sekadar flag) — supaya
user tidak salah pencet backup rutin & tanpa sadar mengubah identitas
device (lihat CHANGELOG utk analisis trade-off lengkap kenapa ini dipisah,
bukan defaultnya diubah). `DbExportService.decrypt()` sekarang return
record `({payload, isOwnerTransfer})`, bukan `Map` polos lagi — SEMUA
caller lama (`backup_screen.dart`, `widget_test.dart`,
`backup_restore_bug_test.dart`) sudah disesuaikan.

**Rekey SQLCipher** (`AppDatabase.rekey()`, app_database.dart) — bagian
PALING KRITIS & PALING BERISIKO di fitur ini. File fisik DB (`the_pos.db`,
path TETAP sama apa pun storeKey-nya) di-encrypt pakai key yang diturunkan
dari storeKey saat itu (`deriveDatabaseKey`, PRAGMA key). Kalau device yang
SUDAH ada datanya menerima transfer (Opsi B — lihat di bawah), storeKey
device itu BERGANTI ke storeKey toko baru — TANPA rekey fisik, file lama
tetap terenkripsi key LAMA sementara device "mengira" key-nya sudah BARU,
sehingga app TIDAK BISA BUKA DB LAGI SAMA SEKALI setelah restart (tidak
ada jalan pulih tanpa tahu key lamanya). Urutan WAJIB:
1. `DbExportService.restore()` — isi tabel pakai koneksi lama (key lama).
2. `db.rekey(deriveDatabaseKey(storeKeyBaru))` — SEBELUM identitas diganti.
3. `DeviceNotifier.joinStore(...)` — baru sekarang identitas berubah.
Diimplementasikan di `DeviceNotifier.applyOwnerTransferInPlace()`
(device_provider.dart) persis urutan ini. **Device BARU (belum pernah
setup, welcome screen)** tidak butuh rekey sama sekali — file DB belum
pernah ada, jadi key pertama yg dipakai otomatis "menempel" tanpa konflik.
**CATATAN PENTING kalau lanjut kerjakan fitur ini**: rekey TIDAK bisa
diverifikasi end-to-end di unit test (`NativeDatabase.memory()` test pakai
sqlite3 polos, `PRAGMA rekey` dianggap no-op bukan SQLCipher asli) — cuma
validasi hex input yg testable, PERILAKU ENKRIPSI FISIKNYA WAJIB dites
manual di device/emulator sungguhan sebelum rilis (belum dilakukan sesi
ini — TODO sebelum build APK dirilis kalau fitur ini dipakai user).

**Siapa boleh jadi penerima — Opsi B dipilih user**: device MANAPUN,
termasuk yang SUDAH aktif dipakai (kasir/asisten/owner toko lain) — bukan
cuma device baru. Makanya ada 2 entry point terpisah pakai fungsi inti
yang sama:
- **Pengaturan → Alihkan Owner** (`alih_owner_screen.dart`, route
  `/pengaturan/alih-owner`) — utk device yg SUDAH ada datanya. Bagian
  "Buat File Alihan" (ekspor) HANYA tampil utk owner; "Terima Alihan"
  (impor) tampil utk SEMUA role. Import di sini pakai dialog konfirmasi
  KUAT (beda dari restore biasa) + checkbox manual "sudah pastikan
  ter-sync" (BUKAN pengecekan otomatis — cek otomatis butuh query status
  sync host yg kompleks, sengaja disederhanakan jadi acknowledgment
  manual, keputusan sadar utk membatasi scope).
- **Welcome screen → "Pulihkan dari File"** (`restore_file_screen.dart`,
  route `/setup/pulihkan`) — utk device BARU (belum setup). Terima 2
  jenis file: BPOT1 (identitas dari file langsung dipakai via `joinStore`
  role owner) ATAU `.berkahpos` biasa (device bikin identitas toko BARU
  spt "Setup Toko Baru", lalu data dari file di-restore di atasnya).

**TIDAK ADA logika demosi/kill-switch device lama** (keputusan final dari
diskusi panjang) — device yg "kalah" (tidak lagi jadi sumber data
terbaru) dibiarkan begitu saja, sesuai kebiasaan user "hapus & setup ulang
kalau mau dipakai lagi". Jalur sync biasa (`lan_sync_service.dart`,
kasir/asisten ↔ owner) SUDAH DIKONFIRMASI tidak tersentuh sama sekali oleh
fitur ini — protokol terpisah total, watermark sync (`last_sync_download_at`
di tabel `app_settings`) otomatis ikut ke-restore/rekey krn `app_settings`
termasuk `_allTables`.

Test: `test/owner_transfer_export_test.dart` (round-trip export/decrypt
BPOT1 vs BPOP2, restore, validasi rekey), `test/apply_owner_transfer_in_place_test.dart`
(deviceName/deviceCode BARU diterapkan — lihat susulan di bawah,
persist ke storage sungguhan via mock secure-storage channel),
`test/alih_owner_screen_visibility_test.dart` (role gating),
`test/welcome_screen_restore_button_test.dart`. Revert-verify dilakukan
utk role-gating & penerapan deviceName/deviceCode baru. TIDAK ada widget
test utk alur file-picker penuh (butuh mock platform channel
`file_picker`, tidak ada preseden di codebase ini utk `backup_screen.dart`
juga) — cukup DB-tier utk logika kritis (kripto/rekey/identitas), sesuai
prinsip "pilih level sesuai yg disentuh".

### Susulan (16 Juli, `1d09200`) — 2 bug ditemukan user via testing device ASLI

User coba fitur ini di 2 device sungguhan, laporkan 2 temuan:

1. **Nama/kode device ikut warisan data lama** — device eks-kasir/asisten
   toko lain (mis. nama "Asisten", kode "K1") menerima transfer & jadi
   Owner, TAPI nama/kode tetap "Asisten"/"K1" (bukan cuma tampilan aneh —
   `deviceCode` dipakai sbg prefix nomor transaksi yg harus UNIK per
   device DALAM SATU toko; kode lama bisa TABRAKAN dgn device lain yg
   sudah pairing ke toko tujuan pakai kode yg sama). **Fix**:
   `applyOwnerTransferInPlace()` (device_provider.dart) sekarang WAJIB
   terima `deviceName`/`deviceCode` sbg parameter dari pemanggil (bukan
   diam-diam pakai `state.deviceName`/`state.deviceCode` lama) —
   `alih_owner_screen.dart` sekarang munculkan dialog "Identitas
   Perangkat" (mirip pairing_screen.dart) SETELAH dialog konfirmasi
   destruktif, SEBELUM benar-benar menerapkan transfer, default
   "Owner"/"O1".
2. **Redirect loop router** (`GoException: redirect loop detected /kasir
   => /aktivasi => /aktivasi => /setup => /setup => /aktivasi`, screenshot
   "Page Not Found") — muncul saat user hapus data aplikasi/install ulang.
   Akar masalah: BUKAN disebabkan kode Alihkan Owner — bug PRE-EXISTING
   di `app_router.dart`'s `redirect()`. Blok cek lisensi & blok cek device
   dieksekusi berurutan tapi TIDAK saling eksklusif: begitu di-redirect ke
   `/aktivasi` krn `license.isLocked`, blok device SETELAHNYA tetap sempat
   jalan & redirect lagi ke `/setup` (device belum configured, bukan di
   `/aktivasi`) — dari `/setup`, license masih locked & bukan di
   `/aktivasi` → balik lagi ke `/aktivasi` — bolak-balik selamanya. Bisa
   dialami SIAPA PUN yang hapus data app/install ulang (license & device
   identity SAMA-SAMA di SharedPreferences, terhapus bareng), bukan
   spesifik Alihkan Owner — cuma kebetulan ketahuan saat testing sesi ini.
   **Fix**: restrukturisasi jadi `if (license.isLocked) return inAktivasi
   ? null : '/aktivasi';` — begitu locked, blok device TIDAK PERNAH
   dievaluasi sama sekali.

Test baru: `test/router_redirect_loop_test.dart` (render `ThePosApp` penuh
dgn license locked + device unconfigured bersamaan, pastikan menetap di
`AktivasiScreen` bukan loop). `test/apply_owner_transfer_in_place_test.dart`
diperbarui total (assersi lama "deviceName dipertahankan" DIBALIK jadi
"deviceName BARU diterapkan"). Revert-verify dilakukan utk kedua fix.

**STATUS AKHIR — SUDAH TERVERIFIKASI user di device asli** (setelah kedua
fix `1d09200` di atas): device penerima yang SUDAH punya data sendiri
(install ulang → buat toko → isi 1-2 data) menerima "Terima Alihan", lalu
di-force-close & dibuka ulang — **TIDAK crash, semua data ter-update
benar**. Ini membuktikan rekey SQLCipher (bagian paling berisiko di fitur
ini) berfungsi sesuai desain di device sungguhan, bukan cuma di unit test.
**Fitur "Alihkan Owner" + "Pulihkan dari File" (Item 27/28) SELESAI &
TERVERIFIKASI — tidak ada pekerjaan menggantung dari fitur ini.**

## Fix: poin loyalitas nyangkut di pelanggan lama (16 Juli)

User lapor: transaksi umum diubah ke pelanggan terdaftar (dapat poin),
lalu diubah BALIK ke Umum lagi — poin TETAP nempel di pelanggan lama,
padahal transaksinya sudah tidak lagi tercatat atas namanya
(`voidTransaction`'s reversal butuh `customerId != null`, jadi begitu
customerId di-null-kan jalur reversal lama itu tidak bisa jalan lagi).

**Fix**: method baru `AppDatabase.changeTransactionCustomer()`
(app_database.dart) — atomic (`transaction()`), dipakai gantiin write
mentah `customerId`/`customerName`. Logika: kalau pelanggan BERUBAH
(bukan cuma nama tanpa ganti id) & tx sudah pernah dapat poin
(`pointsEarned > 0`), tarik balik poin dari pelanggan LAMA dulu (ledger
`adjust`, reset `pointsEarned` ke 0) — baru kalau pelanggan BARU bukan
null, hitung ulang & beri poin via `awardLoyaltyPointsIfEligible` yang
sudah ada (dari 0, otomatis dapat penuh sesuai `tx.total` kalau
eligible). Kalau id sama persis (cuma ganti nama tampilan customer yang
sama) → skip clawback sepenuhnya, tidak ada side-effect.

**2 titik pemanggilan diperbaiki** (bug yang sama ada di 2 tempat,
jangan asumsikan cuma 1 lokasi kalau nanti ada laporan serupa lagi):
`receipt_screen.dart` `_saveCustomer()` DAN `tx_history_sheet.dart`
`_editCustomer()` (dialog pelanggan dari layar riwayat transaksi,
punya tombol "Umum" sendiri yang sebelumnya juga bypass poin sama
sekali).

Test: `test/change_transaction_customer_test.dart` (4 skenario DB-tier:
balik ke Umum, ganti A→B, Umum→pelanggan baru, id sama/no-op).
Revert-verify dilakukan (matikan blok clawback pakai `if (false && ...)`
→ 2 test gagal tepat dgn pesan yg sesuai → dikembalikan, hijau lagi).
`tx_history_sheet.dart` sendiri TIDAK dapat widget test baru (dialog
`_TxDetail` cukup dalam nested-nya utk butuh setup harness signifikan) —
cukup DB-tier krn wiring-nya cuma satu panggilan ke method yang sudah
diuji, tidak ada logic baru di sisi UI.

## Fix keamanan: device revoked bisa "membuka diri sendiri" (16 Juli, `fc991d2`)

User (via eksperimen manual dgn `license/revoked.json`) menemukan celah:
`LicenseNotifier.activate()` (`license_provider.dart`) sebelumnya
unconditionally set `revoked=false` begitu **tanda tangan** kode aktivasi
valid — TANPA pernah re-cek status revoked LIVE. Karena kode ber-
`exp:'selamanya'` yang belum kadaluarsa tetap valid tanda tangannya
selamanya (verifikasi stateless, tidak ada server utk "pakai sekali"),
dan revoked status terikat ke fingerprint (bukan ke kode), device yang
SUDAH di-revoke bisa membuka diri sendiri lagi cuma dgn re-entry kode
lama yang SAMA di layar `/aktivasi` (semua state locked diarahkan ke
layar yang sama, `app_router.dart:55`).

**Fix**: `activate()` sekarang fetch `_fetchRevokedStatus()` (live) dulu
sebelum membuka gerbang, pakai `shouldBlockReactivation(liveRevoked,
cachedRevoked)` (logika murni, extracted spt `computeRevoked()`) —
`liveRevoked ?? cachedRevoked`: kalau fetch sukses, live menang; kalau
fetch gagal (offline), **fail-safe** — pertahankan status cache lama
(BEDA dari `_checkRevocation()` rutin startup yang sengaja fail-open,
supaya gangguan jaringan tidak pernah mengunci device tanpa alasan —
di re-aktivasi kita tidak boleh sebaliknya, diam-diam membuka device yg
sedang dicurigai revoked).

Test: `test/license_service_test.dart` group baru
`shouldBlockReactivation` (4 skenario: live-revoked, live-clear,
fetch-gagal+cache-revoked, fetch-gagal+cache-clear). Tidak bisa test
`activate()` end-to-end (hardcode public key produksi asli, tidak
diinjeksi spt `verify()`) — sempat dicoba lalu dibatalkan, cukup test
fungsi murni `shouldBlockReactivation` saja. Revert-verify dijalankan.

**Sekaligus ditemukan (BELUM diperbaiki, bukan bug kode)**: file
`license/revoked.json` di branch `main` sempat berisi JSON tidak valid
(`"dicabut": [xxx]` — fingerprint tanpa tanda kutip string). User sudah
konfirmasi ini akar masalah kenapa device yg di-revoke masih online
(`_checkRevocation()` gagal parse → ketangkep catch-all silent-fail by
design). **Status: belum jelas siapa yang perbaiki file JSON-nya** —
saya tawarkan (push fix ke `main` sendiri, atau user edit manual via
GitHub) tapi belum ada jawaban eksplisit. **Kalau sesi depan lanjut,
tanyakan ke user dulu sebelum menyentuh `main`** (branch policy: jangan
push ke branch lain tanpa izin). Kalau user lapor lagi "device revoked
masih online", cek dulu validitas JSON file ini sebelum curiga bug kode.

## Diskusi lain (sudah dijawab, tidak perlu tindakan kode)

- **Hosting katalog HTML**: Cloudflare Pages/GitHub Pages direkomendasikan
  (gratis, custom domain didukung keduanya, ~Rp150-250rb/tahun kalau mau
  domain sendiri — pembelian domain terpisah dari hosting). REKOMENDASI:
  repo TERPISAH dari `The-POS` (biar source code app tetap privat) kalau
  pakai GitHub Pages (perlu repo publik utk Pages gratis) — Cloudflare
  Pages bisa drag-drop tanpa perlu repo GitHub sama sekali. Katalog HTML
  fully self-contained/client-side (semua interaksi via JS ter-embed,
  klik stepper tidak pernah hit network) — TIDAK butuh Workers/KV.
  Model: developer "upload" (overwrite file yg sama tiap harga berubah),
  pelanggan cukup buka URL spt web biasa (bukan download file permanen ke
  storage device, beda dari cara share-file mentah yang berlaku sekarang).
  Kecepatan render tetap tergantung device pelanggan (sudah pernah ada bug
  nyata: grid re-render penuh tiap klik stepper, sudah diperbaiki jadi
  partial update).
- **Serial/kode aktivasi bisa dipakai berulang**: BUKAN bug — verifikasi
  Ed25519 stateless offline, tidak ada server utk tracking "sudah
  dipakai". Kode yang sama tetap valid tanda tangannya selamanya (kalau
  `exp:'selamanya'` & device belum di-revoke) — inherent trade-off
  arsitektur no-cloud-backend, bukan sesuatu yang perlu "diperbaiki".

## Item selesai sebelumnya (16 Juli, sesi awal — ringkas)
- Redesign header struk (Item 7) → watermark stempel
  (`status_watermark_stamp.dart`), `eb7da72` + follow-up bold nama produk,
  alamat dropdown cart bar, poin loyalitas kumulatif Tambah Belanjaan.
- Nota tempo `paid==0` boleh naikkan qty item sama di edit sheet
  (`2ade5b5`) — sebelumnya cuma bisa kurang/hapus.
- Detail teknis lengkap ada di CHANGELOG.md (baris tanggal yang sama).

## Gotcha (ringkas, detail lengkap di CLAUDE.md §Gotcha — tidak diulang di sini)
- HID scanner menelan input keyboard kalau `useRootNavigator: true`.
- `TextDirection` bentrok material vs pdf — pakai `ui.TextDirection.ltr` eksplisit.
- Teks putih tak terbaca di PDF — bungkus `Material` di dalam `Theme(data: AppTheme.light())`.
- Font PDF/ESC-POS tidak dukung en-dash/non-ASCII.
- `formatRupiah` pakai non-breaking space (U+00A0) — `find.text('Rp 5.000')` literal TIDAK match di widget test.
- Drift `StreamProvider` widget test bisa hang 10 menit — WAJIB `drain()` di akhir test.
- `OutlinedButton`/`FilledButton` default lebar-penuh — 2+ dalam 1 `Row` WAJIB override `minimumSize`, ekstra parah di dalam `AlertDialog.content` (`IntrinsicWidth`).
- `Clipboard.getData()` TIDAK di-mock otomatis `flutter_test` — pasang mock manual atau test hang selamanya.
- Stock ledger test: seed row butuh `createdAt` eksplisit di masa lalu (race dgn SQL-default timestamp vs `DateTime.now()` Dart-side).

## Gerbang lisensi (Item 25c) — status terkini
`LicenseService.publicKeyBase64` sudah ditanam (bukan kosong) — device
manapun yang belum aktivasi diarahkan ke `/aktivasi`. Layar aktivasi yang
SAMA dipakai utk semua state locked (belum aktivasi/expired/revoked/jam
mundur) — sengaja tidak membedakan alasan. `activate()` sekarang re-cek
revoked LIVE (lihat section fix di atas) — sebelumnya TIDAK. Detail
histori lengkap di CHANGELOG (`0d1efe2`, `3591396`, `fc991d2`).

## Lingkungan sesi ini
Flutter di `/opt/flutter`. Jalan sbg root menghasilkan warning "Woah!..."
yang tidak menggagalkan perintah, aman diabaikan.

## Menggantung / Kandidat Berikutnya
1. Item lama yang masih terbuka: lihat PLAN.md (Item 23 sisa, Item 17+21 sync, Item 3c/4/5 import data Griyo).

## Preferensi User (masih berlaku)
- Bahasa komunikasi & teks UI: Indonesia.
- Untuk fitur bervisual: usulkan opsi desain dulu (mockup/Artifact) sebelum implementasi.
- Untuk batch besar berisi item ambigu + jelas dicampur: minta opini dulu,
  lalu beri keputusan spesifik per-poin — item yg jelas dieksekusi
  langsung, item ambigu didiskusikan/plan dulu (task manager, bukan
  otomatis PLAN.md kalau user secara eksplisit minta ditahan).
- Setiap regresi/bugfix WAJIB revert-verify (buktikan test gagal dulu
  sebelum fix, baru pasang lagi) — sudah konsisten dijalankan sesi ini.
