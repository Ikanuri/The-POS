# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 18 Juli 2026 (sesi AUDIT KODE — baca-kode saja,
TIDAK ada perubahan kode produksi). Hasil: **PLAN.md Item 41** berisi
daftar temuan lengkap (A bug/silent bug, B keamanan, C performa/daya,
D kompatibilitas, E clean code) dengan prioritas [P1]–[P3]; belum ada
satu pun yang dieksekusi — mulai dari [P1]: stok multi-device korup
pasca-sync (`stock_after` tidak direkonsiliasi), zona waktu watermark
sync (`toIso8601String()` lokal tanpa offset), dan storeKey polos di QR
pairing tanpa mekanisme revoke. Lanjutan sesi yang sama: Flutter 3.24.5
(persis pin CI) di-install manual → `flutter analyze` BERSIH (0 issue) &
`flutter test` **498 test SEMUA HIJAU** (2m36s) — klaim terverifikasi
ulang. Percobaan SDK 3.44.6 stable: proyek GAGAL kompilasi (1 error
CardTheme→CardThemeData + 53 deprecation) → tercatat sbg Item 41 D.5
(rencanakan sesi upgrade SDK khusus). Sesi sebelumnya (18 Juli):
Item 40 "usulan harga/produk dari device non-owner" [`fcadcb1`] — kini
SUDAH ada di `main`; Item 39 [`5c244da`] + fix kembalian struk
[`3f3a4c0`] juga sudah di `main`._ Full `flutter test` **498 test, SEMUA
HIJAU** (per sesi 18 Juli pra-audit; 9 test baru Item 40:
`product_proposal_test.dart` 6, `migration_v16_test.dart` 1,
`product_proposal_review_screen_test.dart` 2), `flutter analyze` bersih
(0 issue). **schemaVersion 16** (kolom `products.locally_modified`).
CLAUDE.md masih menulis schemaVersion 9 — basi, kode adalah sumber
kebenaran (tercatat di Item 41 D.4).

## Item 40 — Usulan harga/produk dari device non-owner via sync LAN (18 Juli, SELESAI & di-commit `fcadcb1`)

**Konteks**: user lapor kasus nyata — asisten kadang lebih update soal
harga terbaru (kadang juga nambah produk sendiri) & input langsung di
HP-nya sendiri; begitu sync, perubahan asisten itu malah TERTIMPA balik
oleh data owner yang belum di-update (arsitektur sync sengaja satu-arah
host→klien utk master data). User minta: perubahan dari asisten TETAP
perlu approval eksplisit dari owner (bukan otomatis timestamp-based
last-write-wins) — owner lihat pop-up/list utk setuju/tolak per
perubahan. Ditanya soal produk BARU beserta atributnya (satuan, barcode,
harga lain, varian) — dijawab: seluruh row-set terkait (bukan cuma
kolom harga) ikut diusulkan sbg 1 paket. User: **"tidak perlu masukkan
ke plan, langsung eksekusi"** — dieksekusi langsung tanpa masuk PLAN.md.

**Desain**: kolom baru `products.locally_modified` (default false) —
di-set true oleh `produk_form_screen.dart` (`_persistProduct`/
`_addVariant`/`_editVariant`) HANYA kalau `!device.isOwner`. Saat sync
(`syncToHost`), klien panggil `db.dumpLocalProposals()` — bundel PENUH
row-set (products+product_units+price_tiers+alt_prices+product_barcodes)
utk produk yg ditandai, dikirim lewat key **`proposals`** TERPISAH dari
key `tables` (append-only queue yg sudah ada) di payload sync — sengaja
tidak digabung ke `_pendingQueue`/`PendingSyncItem` yg sudah ada supaya
lifecycle approve/reject harga TIDAK bercampur dgn approve/reject
transaksi append-only. Host simpan ke queue baru `_pendingProposals`/
`PendingProductProposal` (in-memory, sama polanya spt `_pendingQueue`).

**Review UI**: `ProductProposalReviewScreen` (baru,
`lib/features/pengaturan/product_proposal_review_screen.dart`) — diff
row usulan vs data host LIVE (BUKAN vs snapshot lama) saat layar dibuka,
kelompokkan jadi "Harga/Produk Berubah" (tampil harga lama→baru via
`RichText` strikethrough) vs "Produk Baru". Semua item default TERCENTANG,
owner bisa uncheck yg tidak mau, tombol "Terapkan (N produk)" panggil
`LanSyncService.applyProposal(id, approvedIds)` →
`db.applyProductProposals()` (INSERT OR REPLACE per row, urutan
products→product_units→price_tiers/alt_prices/product_barcodes, filter
child row by parent id yg di-approve, paksa `locally_modified=0` di
kolom yg ditulis krn host jadi sumber kebenaran baru). Diakses dari
`sync_screen.dart` bagian "Usulan Harga/Produk (N)" (owner-only, listen
`LanSyncService.onProposalsChanged`).

**Keputusan desain kunci** (divalidasi eksplisit dgn user, JANGAN diubah
tanpa didiskusikan ulang): usulan yg TIDAK direview/di-apply TIDAK
disimpan sbg "ditolak" permanen — akan otomatis muncul lagi di sync
BERIKUTNYA (kolom `locally_modified` di device asisten tetap true sampai
diterapkan host, TIDAK ada mekanisme dismiss permanen). User pernah
tanya soal konflik "kalau owner JUGA ubah harga yg sama, mana yg
menang?" — jawabannya: TIDAK ada resolusi otomatis via timestamp,
review screen selalu diff terhadap data host LIVE saat itu, jadi owner
yg lihat & putuskan sendiri, bukan sistem yg diam-diam pilih salah satu.

**Environment issue besar ditemukan sesi ini (BUKAN bug kode, catat utk
sesi depan)**: `dart run build_runner build --delete-conflicting-outputs`
GAGAL total meregenerasi `app_database.g.dart` di environment ini —
selalu lapor "sukses" tapi file hasil generate tidak pernah muncul di
disk (dikonfirmasi lewat file intermediate drift analyzer sendiri,
`*.drift_elements.json`, isinya `"elements": []` bahkan utk
`app_database.dart` yg PRISTINE/belum diubah sama sekali — jadi bukan
gara-gara perubahan skema Item 40). **Root cause belum ditemukan**
(bukan disk space/memory/inode — semua sudah dicek cukup). **Workaround
yg dipakai**: hand-patch `app_database.g.dart` langsung via script Python
(cari-ganti presisi, tiap blok diverifikasi match PERSIS 1x sebelum
diterapkan) meniru pola kode generated kolom `markedOutOfStock` yg sudah
ada, utk kolom baru `locallyModified`. **Kalau sesi depan perlu ubah
skema DB lagi**: build_runner kemungkinan BESAR gagal lagi dgn cara yg
sama — coba dulu (barangkali sudah kebetulan jalan), tapi kalau gagal,
pola hand-patch yg sama (tiru struktur kolom `BoolColumn`/`markedOutOfStock`
yg sudah ada persis) adalah fallback yg TERBUKTI berhasil.

**Bug tersembunyi ditemukan & diperbaiki via full-suite test run (BUKAN
regresi dari kode produksi Item 40 — murni fixture test lama yg kurang
lengkap)**: `test/migration_v15_test.dart` fixture DB v14 mentah tidak
pernah bikin tabel `products` sama sekali (beda dari fixture migration
test lain spt v9/v10/v13/v14 yg semuanya sudah py `CREATE TABLE
products(id TEXT PRIMARY KEY);` stub) — begitu schemaVersion naik ke 16
& migrasi `from<16` (`addColumn(products, products.locallyModified)`)
ikut jalan di atas fixture v14 itu, kena `SqliteException: no such
table: products`. HANYA muncul di full-suite run (test lain di suite yg
sama tidak memicu jalur ini krn masing2 py DB fixture sendiri) — test
individual `migration_v15_test.dart` tetap lolos sendirian sebelum fix
krn... (catatan: sebenarnya tetap gagal sendirian juga, bukan cuma
full-suite — dikonfirmasi via revert-verify). Fix: tambah baris yg sama
(`CREATE TABLE products(id TEXT PRIMARY KEY);`) ke fixture v14 di
`migration_v15_test.dart`. Revert-verify dilakukan (hapus baris fix →
`SqliteException` yg sama persis muncul lagi → fix dikembalikan, hijau).

**Temuan test infra baru (widget test gotcha, catat utk CLAUDE.md kalau
perlu)**: `RichText`/`Text.rich` dgn `TextSpan` children TIDAK terlihat
oleh `find.text()`/`find.textContaining()` (matcher itu cuma cek widget
`Text`/`EditableText`) — dipakai `_ProposalTile` utk render diff harga
strikethrough. Solusi: `find.byWidgetPredicate((w) => w is RichText &&
w.text.toPlainText().contains(substring))` (lihat helper
`findRichTextContaining` di `product_proposal_review_screen_test.dart`).

**Belum dikerjakan/didiskusikan lebih lanjut**: tidak ada — fitur ini
dianggap SELESAI oleh user (diminta eksekusi langsung, tidak ada
follow-up terbuka). Kalau muncul laporan lanjutan (mis. owner mau
approve/reject dari notifikasi push, atau mau riwayat "siapa usul apa"),
itu scope BARU, masukkan ke PLAN.md dulu sebelum eksekusi (beda dari
sesi ini yg eksplisit diminta skip planning).

## Fix: struk cetak/gambar "Kembali" akumulasi, bukan pembayaran terakhir (18 Juli, SELESAI & di-commit `3f3a4c0`)

User lapor: di nota/struk yang dicetak, baris "Kembali" seharusnya
menampilkan kembalian TERAKHIR, bukan akumulasi. Root cause: baik
`printer_service.dart` (`_buildBytes`, struk ESC/POS tunggal) maupun
`_ReceiptPaper` (widget struk gambar/share di `receipt_screen.dart`)
masih memakai `tx.changeAmount` MENTAH — kolom header yang dihitung ulang
dari `Σpayments.amount - total` tiap kali `_reconcileTransactionTotals`
jalan, sehingga kalau kembalian lama dipakai ulang sbg pembayaran baru
(mis. "Tambah Belanjaan"), nilainya jadi AKUMULASI seluruh riwayat
kembalian nota, bukan cuma yang baru saja diberikan. Ini adalah lokasi
YANG SAMA yang sudah lama tercatat sbg "belum diperbaiki" di Item 23 lama
(scope "printer_service.dart printReceipt tunggal — beda dari
_ReceiptPaper yang SUDAH diperbaiki" — catatan itu keliru: `_ReceiptPaper`
TERNYATA belum pernah diperbaiki juga, sama-sama pakai `tx.changeAmount`
mentah).

**Fix**: tambah fungsi `latestChangeGiven(payments)` di `receipt_screen.
dart` (pola sepadan dgn `netRemainingOwed`/`netPaidDisplay` yg sudah ada)
— ambil `changeGiven` dari pembayaran TERAKHIR yang tidak dibatalkan.
Dipakai di `_ReceiptPaper` (ganti `tx.changeAmount`) & logika sepadan
inline di `printer_service.dart._buildBytes` (ganti `tx.changeAmount`,
plus tambah baris "Uang Diterima" gross dari pembayaran terakhir, sama
seperti pola nota gabungan `_buildMergedBytes` yang sudah lama benar).
"Bayar"/"Bayar.." juga diganti dari `tx.paid` mentah ke net (dikurangi
total kembalian yg pernah diberikan) supaya "Total = Bayar + Kembali"
tetap konsisten — bukan cuma baris Kembali yang diperbaiki sendirian.

**Bug kecil ikut ketemu & diperbaiki** (bukan yg dilaporkan user, ketahuan
saat menulis test skenario 2-pembayaran): Row timeline riwayat pembayaran
di `_ReceiptPaper` overflow kalau teks tanggal+metode cukup panjang —
dibungkus `Expanded`. Jalur ini rupanya belum pernah teruji sebelumnya di
widget struk gambar (beda dari timeline di Ringkasan on-screen yang sudah
ada test-nya).

Test: `test/receipt_paper_kembali_net_test.dart` — skenario 2 pembayaran
di mana `tx.changeAmount` (akumulasi, 15.000) BEDA dari kembalian
pembayaran terakhir yang benar (5.000), verifikasi struk gambar tampilkan
5.000 bukan 15.000. Revert-verify: kembalikan ke `tx.changeAmount` mentah
→ test gagal persis ("Rp 5.000" tidak ditemukan) → fix dikembalikan,
hijau lagi.

**Catatan test infra (bukan bug produksi)**: pastikan `db.close()` HANYA
dipanggil sekali (via `tearDown`, JANGAN dobel dgn pemanggilan eksplisit
di akhir body test) — sempat bikin test ini HANG >3 menit tanpa pesan
error yang jelas sebelum ketahuan akar masalahnya murni dari double-close,
bukan bug di kode yang diuji.

## Item 39 — Sync LAN lebih andal: deteksi IP + profil timeout + logging (18 Juli, SELESAI & di-commit)

**Konteks**: user minta analisis kenapa "kadang di jaringan WiFi yang
sama tapi tidak tersambung" — bukan laporan bug spesifik, tapi diskusi
open-ended yang menghasilkan 5 kandidat penyebab (lihat histori chat kalau
perlu detail lengkap analisisnya): (1) AP/client isolation di router,
(2) `NetworkInfo.getWifiIP()` tidak selalu andal di semua ROM Android,
(3) IP host berubah tapi UI tidak refresh, (4) battery optimization/Doze
membekukan koneksi background saat layar owner mati, (5) HP kasir salah
rute lewat data seluler alih-alih WiFi. User minta "kerjakan semua, beri
log jika perlu" + tambah setting timeout bervariasi.

**Yang DIKERJAKAN (executable dari Dart, tanpa native platform channel
baru)**:
1. **Deteksi IP dual-strategi** (`LanSyncService.detectHostIp()`): coba
   `NetworkInfo.getWifiIP()` dulu (utama), fallback ke
   `NetworkInterface.list()` (dart:io murni, TIDAK butuh izin tambahan
   apa pun, tidak lewat API WiFi manager Android sama sekali) kalau hasil
   utama null/kosong/`0.0.0.0`. Filter `isPrivateIPv4()` (public, pure,
   testable) memilih alamat privat (10.x/172.16-31.x/192.168.x) dari
   daftar interface, melewati IP publik (VPN/tethering).
2. **Tombol "Refresh IP"** baru di kartu "Jadi Host" (`sync_screen.dart`)
   — `LanSyncService.refreshHostIp()` deteksi ulang TANPA restart server,
   utk kasus IP berubah SAAT server sudah jalan (poin #3 di atas).
3. **`SyncTimeoutProfile` enum** (Cepat/Normal/Lambat/Sangat Lambat),
   dropdown baru di kartu "Hubungkan ke Host", tersimpan persisten ke
   `app_settings` key `sync_timeout_profile`, di-load ulang tiap layar
   dibuka & dipakai sbg `connectTimeout`/`responseTimeout` ke
   `syncToHost()`.
4. **Pesan error client dipertajam** per jenis `SocketException` — pesan
   `TimeoutException` sekarang sebut 3 kemungkinan (isolasi AP, battery
   optimization/layar mati, data besar → naikkan profil timeout);
   `SocketException` cek substring pesan OS ("unreachable" → kemungkinan
   salah rute data seluler, "refused"/"no route" → kemungkinan IP
   basi/isolasi router).
5. **`CrashLogService.record()`** dipasang di titik gagal: client
   timeout/socket exception, host request handler catch-all, kegagalan
   deteksi IP (kedua strategi) — bisa dicek user via layar "Log Error
   Terakhir" yg sudah ada kalau laporan berulang.
6. **Hint teks UI** di kartu "Jadi Host": jangan kunci layar/pindah app
   selama menunggu kasir sync (poin #4, battery optimization) — TIDAK
   minta permission `ignoreBatteryOptimizations` (butuh entry manifest
   baru + ada risiko kebijakan Play Store utk app non-utilitas — sengaja
   dihindari, cukup edukasi teks).

**SENGAJA TIDAK dikerjakan (di luar jangkauan Dart murni)**: poin #1 (AP
isolation) & #5 (client salah rute lewat data seluler) BUKAN sesuatu yang
bisa "diperbaiki" dari kode app — keduanya keputusan level OS/router.
Yang bisa dilakukan cuma diagnosis lebih baik (pesan error #4) supaya
user tahu harus ngapain (matikan data seluler, cek pengaturan router),
bukan fix otomatis. Kalau nanti mau coba fix #5 beneran (bind proses ke
network WiFi spesifik), itu perlu platform channel native Android
(`ConnectivityManager.bindProcessToNetwork`) — belum dikerjakan, catat di
PLAN.md kalau user minta lanjut.

**Test**: `test/lan_sync_ip_detect_test.dart` (16 test: `isPrivateIPv4`
pure logic, `detectHostIp` dgn dependency-injection utk
getWifiIpOverride/listInterfacesOverride — TIDAK hit network sungguhan,
`SyncTimeoutProfile` save/load/fromKey) + `test/sync_screen_timeout_ip_
test.dart` (3 widget test: dropdown default & persist, tombol Refresh IP
TIDAK muncul sebelum host aktif).

**Temuan penting saat menulis test (test infra, BUKAN bug produksi)**:
mem-bind `HttpServer` sungguhan (`shelf_io.serve`, dipakai `startHost()`)
di DALAM `testWidgets(...)` terbukti bikin `AppDatabase.close()` sesudahnya
HANG TANPA BATAS WAKTU — dikonfirmasi via debug bertahap (server bind
sendiri OK, `db.close()` sendiri OK, kombinasi keduanya dalam SATU
`testWidgets` yang hang). Root cause pastinya belum ditelusuri sampai
tuntas (dugaan: interaksi `TestWidgetsFlutterBinding`'s fake-async/timer
tracking dgn socket TCP asli yang terdaftar di event loop), tapi **solusi
aman**: jangan pernah start host sungguhan di dalam `testWidgets` — test
level service (`test()` polos, tanpa widget pump) utk `startHost`/
`refreshHostIp` bekerja normal tanpa masalah (lihat grup test di
`lan_sync_ip_detect_test.dart`). Kalau nanti nulis test baru yang perlu
mengetes UI + host sungguhan berbarengan, JANGAN diulang caranya —
pisahkan jadi 2 test terpisah (service-level utk network asli, widget-
level utk UI murni tanpa network asli), persis pola yang dipakai di sini.

**PENTING kalau laporan serupa muncul lagi**: bug "asisten tidak bisa
override X walau sudah digrant izin" di app ini historisnya SELALU
berlapis, jangan berhenti di investigasi pertama yang "lolos test" —
lihat 4 babak di bawah, tiap babak nemuin lapisan baru yang test
sebelumnya TIDAK menyentuh sama sekali (logic fungsi izin → topologi
host/klien sync → ADA-tidaknya timeout jaringan → jenis timeout yang
BENAR/idle vs total). Kalau user lapor lagi soal sync lambat/lag/gagal
SETELAH fix idle-timeout ini terpasang, curigai dulu: apakah timeout-nya
(default 30s connect/response) masih kurang panjang utk ukuran data
toko itu, sebelum cari bug baru dari nol.

## Fix: timeout TOTAL memutus transfer besar di tengah jalan (17 Juli, BELUM di-commit/push, babak ke-4)

Lanjutan lagi — setelah fix timeout dasar (`939048a`) dipasang di APK &
dites, user konfirmasi sync jadi SUKSES tapi user laporkan "ada sedikit
lag", lalu setelah dicek lebih lanjut: **"Timeout memutus rantai
transfer, padahal baru sampai"** — transfer yang SEDANG AKTIF mengalir
(bukan macet) tetap terputus paksa.

**Root cause**: di fix babak ke-3, `.timeout()` dipasang SETELAH
`.toList()` — `respBytes = await response.expand((c) => c).toList()
.timeout(responseTimeout)`. `Future.timeout()` adalah DEADLINE TOTAL
(tidak peduli progres, cuma peduli total durasi sejak awal), BUKAN
idle-timeout. Toko dengan data besar (banyak produk/transaksi, apalagi
sync pertama kali yang full-dump) bisa transfer >20-30 detik SECARA
WAJAR selama datanya terus mengalir — pola lama itu memutus transfer di
tengah jalan walau tidak macet sama sekali, cuma butuh waktu lebih lama.

**Fix**: pindahkan `.timeout()` ke SEBELUM `.toList()` — diterapkan ke
`Stream<int>` (`response.expand((c) => c).timeout(responseTimeout)
.toList()`), bukan ke `Future<List<int>>` hasil `.toList()`.
`Stream.timeout()` itu timeout PER-EVENT (reset tiap ada chunk baru
lewat) — jadi transfer lambat-tapi-terus-progresif TIDAK pernah kena,
cuma transfer yang benar2 STALL (tidak ada byte baru sama sekali dalam
`responseTimeout`) yang kena. Pola sama diterapkan ke sisi HOST
(pembacaan body request klien). `responseTimeout` default dinaikkan
20s→30s (dipakai dobel: deadline total tunggu host MULAI membalas — host
perlu waktu susun+enkripsi SELURUH dump SEBELUM kirim byte pertama sama
sekali, tidak streaming — DAN idle-timeout per-chunk saat baca body).

Test: `test/lan_sync_slow_transfer_test.dart` — server TCP mentah
mengirim body ASLI (payload terenkripsi valid, dibangun pakai
`CryptoService` yg sama persis dgn yg dipakai host sungguhan) dalam 5
potongan kecil dgn jeda 300ms antar-chunk (total ~1.5s), timeout test
di-set 800ms — total durasi (1.5s) MELEBIHI timeout (800ms) tapi tiap
jeda individual (300ms) DI BAWAHNYA — buktikan `syncToHost` tetap
SUKSES (bukan gagal krn total durasi). Revert-verify: pola lama
(`.toList().timeout()`) bikin test ini gagal persis dgn pesan "Tidak ada
respons dari host dalam waktu wajar" walau data terus mengalir —
dibuktikan via `git apply`/`git checkout --` bolak-balik.

**Catatan test infra (bukan bug produksi)**: test file baru ini &
`lan_sync_timeout_test.dart`/`lan_sync_watermark_test.dart` semua bind
ke port TCP 8625 yg sama (port sync tetap) — kalau `flutter test`
menjalankan beberapa file itu di worker paralel yg sama scr kebetulan,
bisa tabrakan "Address already in use" (flaky, BUKAN bug kode). Sudah
diverifikasi TIDAK terjadi di full-suite run normal (467-468 test lain
tidak terpengaruh), kalau muncul lagi jalankan ulang atau pakai
`--concurrency=1` utk isolasi.

**Belum di-commit/push** — tunggu konfirmasi user.

## Fix: sync HTTP client tanpa timeout → infinite loading di klien (17 Juli, babak ke-3, SUDAH di-commit `939048a`/`2a7ef21`, SUDAH di-merge ke main)

Lanjutan laporan "asisten tidak bisa override stok minus" — setelah fix
"Jadi Host" khusus owner (`d21889f`) dipasang di APK & dites ulang, user
konfirmasi: owner TETAP di layar Sync (tidak pindah tab sama sekali, jadi
BUKAN Item 21/dispose()-stopHost), tapi di layar ASISTEN **tidak muncul
apa pun — infinite loading**, tombol sync berputar terus tanpa pernah
sukses/gagal.

**Root cause**: `LanSyncService.syncToHost()` (`lan_sync_service.dart`)
SAMA SEKALI TIDAK PUNYA TIMEOUT di request HTTP-nya (`client.post()`,
`request.close()`, baca body respons) — kalau paket dibuang diam-diam di
jaringan (mis. AP client isolation di router/WiFi tertentu yang
memblokir device-to-device walau satu SSID, atau host sempat freeze
sebentar), Future-nya menggantung SELAMANYA. UI klien (`_sync()` di
`sync_screen.dart`) sebenarnya sudah benar (`finally` reset `_syncing =
false`), tapi itu tidak pernah tereksekusi krn `await` di dalamnya tidak
pernah selesai — persis "infinite loading" yang dilaporkan. Ini juga
menjelaskan "owner tidak menerima konfirmasi sync": request klien
kemungkinan besar tidak pernah benar-benar nyampe/selesai diproses host.

**Fix**: `connectTimeout`/`responseTimeout` (parameter opsional,
default 10s/20s, dapat dipersingkat di test) dibungkus ke
`client.post()`, `request.close()`, dan pembacaan body respons —
`on TimeoutException`/`on SocketException` ditangkap & dilempar ulang
sbg pesan error Bahasa Indonesia yg jelas ("Tidak ada respons dari host
dalam waktu wajar..."/"Tidak bisa terhubung ke host..."). Sisi HOST
(`_handleRequest`) juga dikasih timeout 30s di pembacaan body request
sbg defense-in-depth (bukan titik infinite-loading yg dilaporkan, tapi
prinsip sama).

Test: `test/lan_sync_timeout_test.dart` — `ServerSocket` mentah yg
terima koneksi tapi SENGAJA tidak pernah membalas (simulasi paket
dibuang diam-diam), buktikan `syncToHost` throw dalam batas waktu custom
(bukan hang). Revert-verify: tanpa fix, test gagal compile (parameter
`connectTimeout` belum ada) — dibuktikan dgn `git apply`/`git checkout --`
bolak-balik, bukan cuma dibaca.

**Belum di-commit/push** — tunggu konfirmasi user. Kalau user lapor lagi
sync masih bermasalah SETELAH fix ini dipasang di APK, kemungkinan
BUKAN lagi soal timeout/topologi — mungkin genuinely masalah jaringan
fisik (AP client isolation permanen di router toko, dll, di luar
kendali app) atau something else sama sekali baru, jangan otomatis
curiga ke 3 hal yang sudah dites di atas lagi.

## Fix: asisten tidak bisa override stok minus walau sudah digrant izin (17 Juli, babak ke-2, SUDAH di-commit `d21889f`/`e1d35f5`, SUDAH di-merge ke main)

User lapor: owner sudah nyalakan izin "Izinkan Stok Minus" di layar Izin
Asisten, tapi device asisten (2 HP fisik terpisah, terhubung via sync LAN)
tetap muncul "Stok tidak cukup" saat checkout.

**BUKAN bug di `resolveAllowNegativeStock()`/toggle UI itu sendiri** —
sudah diverifikasi 2x via test nyata sebelum curiga ke tempat lain: (1)
widget test tap toggle di `AsistenPermissionsScreen` → DB tersimpan benar,
(2) test sync LAN sungguhan (2 `AppDatabase` terpisah, koneksi 127.0.0.1
asli) dgn owner=host/asisten=client → izin ikut ter-propagate benar.
Kedua test itu LOLOS dari awal — kalau nanti curiga bug serupa muncul
lagi, JANGAN ulangi jalur investigasi ini, langsung ke akar masalah
sungguhan di bawah.

**Root cause sungguhan**: `sync_screen.dart` bagian "Jadi Host" pakai
gate `device.canSeeReports` (owner ATAU asisten — flag ini aslinya untuk
visibilitas laporan, dipinjam serampangan utk gating host sync). Tapi
arsitektur sync SENGAJA satu arah: master data (produk, harga,
**`kasir_permissions`**) HANYA mengalir host→klien, klien cuma boleh
upload append-only (`lan_sync_service.dart`, komentar existing: "Master
data tidak pernah di-merge dari klien"). Kalau **ASISTEN yang jadi
host** (owner connect ke asisten sbg klien, bukan sebaliknya) —
perubahan izin yang dibuat owner di device-nya sendiri (klien dalam
topologi ini) TIDAK PERNAH sampai ke DB asisten (host), karena upload
klien selalu cuma append-only. Bug ini generik utk SEMUA master data
(produk/harga/pelanggan ikut kena, bukan cuma izin) kalau toko kebetulan
punya kebiasaan "HP asisten yang selalu nyala/jadi host".

**Fix**: `if (device.canSeeReports)` → `if (device.isOwner)` di gate
"Jadi Host" — owner WAJIB selalu jadi satu-satunya host, kasir & asisten
selalu jadi klien. Bagian klien ("Client mode") TIDAK disentuh — tetap
terlihat semua role, sesuai komentar existing "semua device bisa sync"
(sbg klien).

Test: `test/sync_screen_host_gating_test.dart` (widget-tier, 3 skenario:
owner LIHAT "Jadi Host", asisten & kasir TIDAK). `test/asisten_
permissions_screen_test.dart` + `test/asisten_permission_sync_test.dart`
(bukti pendukung bahwa toggle & sync SUDAH benar, jadi kalau ada regresi
laporan serupa lagi, itu BUKAN dari 2 jalur itu). Revert-verify
dilakukan utk fix utama (`canSeeReports` balik → test asisten gagal
persis, kasir tetap lolos krn tidak pernah termasuk `canSeeReports`).

**Belum di-commit/push** — tunggu konfirmasi user.

User lapor: mau refactor 2 produk single-varian (mis. Pop Ice Coklat &
Pop Ice Stroberi, masing-masing produk terpisah dgn barcode sendiri) jadi
1 produk dgn 2 varian — TIDAK BISA, karena barcode lama masih "terkunci"
walau produk lama sudah "dihapus" dari UI.

**Root cause**: `deactivateProduct()`/`deleteVariant()`
(`app_database.dart`) SELALU cuma soft-delete (`isActive=false`) — TIDAK
PERNAH menyentuh `product_barcodes`. Kolom `product_barcodes.barcode`
UNIQUE di seluruh katalog (`product_tables.dart:68`), jadi barcode produk
lama tetap memblokir barcode yang sama dipakai produk/varian baru
selamanya.

**Trade-off hard-delete dibahas & DITOLAK** (didiskusikan dgn user
sebelum coding): `transaction_items`/`stock_ledger` referensi
`productId`/`productUnitId` TANPA foreign key sungguhan (beda dari
`product_units`/`price_tiers`/`product_barcodes` yg py FK asli ke
`Products`) — hard-delete produk yg SUDAH pernah terjual akan: (1)
membuang baris itu total dari `getTopProductsByRevenue` (pakai
`innerJoin`, bukan cuma nama kosong — omzet/laba historis ikut hilang
dari laporan), (2) reprint struk lama tampil UUID mentah (`receipt_
screen.dart` resolve nama produk via live-lookup, fallback ke id kalau
tidak ketemu), (3) sync LAN TIDAK delete-aware (full-dump + `INSERT OR
REPLACE`/`INSERT OR IGNORE`, tanpa tombstone) — device lain bisa
"menghidupkan lagi" produk yg dihapus di device lain saat sync. User
setuju: TETAP soft-delete produknya (riwayat/nama historis utuh), tapi
lepas barcode-nya saja.

**Fix**: `_releaseBarcodesForProduct()` baru — dipanggil dari
`deactivateProduct()` maupun `deleteVariant()` (SAMA-SAMA py bug ini,
bukan cuma satu tempat) di dalam `transaction()` yang sama dgn set
`isActive=false`. SENGAJA **mutasi** nilai `barcode` (prefix
`RELEASED:<id_baris>:<barcode_asli>`), **BUKAN DELETE** baris —
`product_barcodes` di-dump PENUH setiap sync (tanpa watermark, lihat
`dumpSince`), jadi kalau baris benar2 dihapus, device lain yg sudah py
salinannya TIDAK PERNAH dapat kabar "baris ini dihapus" (sync bukan
delete-aware) → salinan basi itu akan mengunci barcode SELAMANYA di
device tersebut. Dgn mutasi nilai, barisnya tetap ada & ikut ke-dump lagi
di sync berikutnya, ter-`INSERT OR REPLACE` (keyed by id yg sama) ke
device lain — pelepasan otomatis terpropagasi lewat mekanisme sync yg
SUDAH ADA, **tanpa perubahan protokol/skema sync sama sekali**.

Test: `test/product_barcode_release_test.dart` (DB-tier, 2 test:
`deactivateProduct` & `deleteVariant` masing-masing — barcode lama bisa
dipakai ulang produk/varian baru tanpa exception, baris lama tetap ada
dgn prefix `RELEASED:`). Revert-verify dilakukan (kedua test gagal persis
dgn `SqliteException(UNIQUE constraint failed: product_barcodes.barcode)`
sebelum fix → fix dikembalikan, hijau lagi, 462 total).

**Belum di-commit/push** — tunggu konfirmasi user.

## Diskusi belum dieksekusi (dari sesi ini, isu #2 laporan produk)

User lapor kedua: "Kolom laporan statistik produk tidak sesuai dengan
history" — **BELUM diinvestigasi tuntas, BELUM ada fix**. Analisis awal
(baca kode, tanpa ubah apa pun): `getTopProductsByRevenue`
(`app_database.dart`) pakai `innerJoin` ke `products` LIVE (bukan
snapshot nama saat transaksi) utk kolom nama — kandidat kuat: kalau user
sudah sempat hard-delete/refactor produk di branch lokal lain yg belum
di-push, baris `transaction_items` lama yg productId-nya sudah tidak ada
akan HILANG TOTAL dari agregasi laporan (bukan cuma nama kosong). Ada
juga implementasi terpisah/terduplikasi utk "top produk" di
`ringkasan_screen.dart` (`_ProductStat`, N+1 manual, beda source code
sepenuhnya dari `getTopProductsByRevenue`) yg berpotensi divergen kalau
ada produk yg sudah dihapus (LEFT JOIN manual vs innerJoin — beda
behavior). **Belum dikonfirmasi user**: mismatch yang dilihat itu
membandingkan laporan Produk vs riwayat transaksi mentah, atau vs
Ringkasan Harian? Apakah muncul setelah user hapus/refactor produk di
branch lokal? Tanyakan dulu sebelum lanjut investigasi/fix — lihat
histori chat sesi ini utk detail lengkap analisis kode yang sudah
dilakukan.

## Item 36 (Stock Opname) + Item 37 (Publish Cloudflare Pages) — SELESAI (17 Juli)

**Item 36 — Stock Opname**: `lib/features/produk/stock_opname_screen.dart`
(baru) — alur pilih kategori/Semua → hitung BUTA (stok sistem
DISEMBUNYIKAN saat input, cuma field qty kosong) → review selisih (baru
di sini stok sistem vs fisik dibandingkan) → commit. DB layer di
`app_database.dart`: `commitOpname()` (tulis banyak baris `stock_ledger`
type='adjustment' dgn timestamp+note SAMA PERSIS dalam 1 sesi),
`getOpnameSessions()`/`getOpnameSessionDetail()` (riwayat, dikelompokkan
dari note+createdAt, TANPA tabel baru), `buildOpnameNote()` (konvensi
`"Opname <tgl> (Seluruh|Kategori: X)"`). `StockOverviewRow` typedef
ditambah field `unitId` (dulu cuma `productId`) — dipakai `commitOpname`
yg butuh productUnitId. Entry point: ikon ✅ di AppBar Cek Stok. Test:
`test/stock_opname_test.dart` (DB-tier) + `test/stock_opname_screen_test.
dart` (widget-tier, verifikasi mode buta beneran tidak tampilkan angka
stok).

**Item 37 — Publish Katalog ke Cloudflare Pages**: `lib/core/services/
cloudflare_publish_service.dart` (baru) — `CloudflarePublishService`
pakai Cloudflare Pages Direct Upload API murni HTTP (`dart:io HttpClient`,
BUKAN package `http` — konsisten dgn `lan_sync_service.dart`). Nama
project Cloudflare **deterministik**: `slug(storeName)-<hash storeUuid>`,
dihitung SEKALI & disimpan permanen di secure storage (TIDAK berubah
walau storeName diganti nanti, supaya URL yg sudah dibagikan ke pelanggan
tetap valid; suffix hash storeUuid WAJIB krn subdomain `*.pages.dev` unik
GLOBAL lintas akun Cloudflare, bukan cuma per akun). Kredensial (Account
ID + API Token) di `FlutterSecureStorage`, pola sama seperti `storeKey`.
UI: tombol "Publish ke Web" + ikon ☁️ (dialog kredensial) di
`order_share_screen.dart`, berdampingan dgn "Buat & Bagikan" manual
(fallback offline-first kalau token belum diisi/publish gagal). Abstraksi
`CloudflareApi` (interface) dgn fake di test krn tidak mungkin hit API
Cloudflare sungguhan tanpa akun/token nyata — test:
`test/cloudflare_publish_service_test.dart` (7 test: gating kredensial,
determinisme nama project, no-collision antar-toko, persist lintas
instance/reinstall) + `test/order_share_publish_button_test.dart`
(widget-tier).

**2 bug nyata ditemukan & diperbaiki via test SEBELUM commit** (bukan
laporan user — test yg saya tulis sendiri menangkapnya):
1. `_shortHash()` awalnya `.substring(0, 6)` (6 hex digit PERTAMA) —
   dua storeUuid yg cuma beda di akhir string (mis. beda 1 karakter
   terakhir) bisa hasilkan hash SAMA krn justru digit pembedanya ada di
   akhir hex, bukan awal. Fix: ambil 6 digit hex TERAKHIR.
2. Tombol "Publish ke Web" set `_publishing = true` (nyalakan
   `CircularProgressIndicator`, animasi tak terbatas) SEBELUM membuka
   dialog Pengaturan Cloudflare saat kredensial belum diisi — bikin
   `pumpAndSettle()` widget test macet (animasi tak pernah "settle"
   selama menunggu input user di dialog). Fix: cek kredensial dulu TANPA
   spinner, baru nyalakan spinner setelah benar-benar mulai kerja network.

**Temuan sampingan (dicatat sbg Item 38 di PLAN.md, prioritas rendah,
BUKAN bug yg dilaporkan user)**: `_rawBaseStock()` tie-break `ORDER BY
created_at DESC, id DESC` bisa salah pilih baris kalau 2 perubahan stok
jatuh di detik yang sama persis (createdAt presisi detik, id UUID acak
tidak berkorelasi kronologis) — ketahuan lewat test Item 36 yg menulis 2x
stok tanpa jeda. Test sudah disesuaikan (kasih jeda >1 detik antar
langkah), tapi celah di kode produksi belum diperbaiki (lihat Item 38 utk
detail & opsi fix).

## Fix: varian produk dgn barcode bentrok gagal-diam tanpa pesan error (17 Juli)

User lapor: kalau varian produk diberi barcode, varian TIDAK tersimpan;
tanpa barcode, tersimpan normal. Root cause (dikonfirmasi via DB-tier
test): `product_barcodes.barcode` UNIQUE di seluruh katalog — kalau
barcode yg dimasukkan sudah dipakai produk/varian LAIN mana pun,
`db.createVariant()`/`updateVariant()` (dibungkus `transaction()`) throw
`SqliteException` & rollback total (produk+unit+tier+barcode varian sama
sekali tidak tersimpan). **Bug sebenarnya**: `_addVariant()`/
`_editVariant()` di `produk_form_screen.dart` TIDAK PERNAH membungkus
pemanggilan itu dgn try/catch — exception lolos tak tertangani, user
cuma lihat "tidak terjadi apa-apa" tanpa pesan error sama sekali.

**Fix**: try/catch di kedua fungsi, pesan spesifik via
`_friendlyBarcodeError()` kalau exception match pola
`UNIQUE constraint failed` + `barcode` ("Barcode sudah dipakai
produk/varian lain..."), fallback pesan generik utk error lain.

Test: `test/variant_barcode_error_banner_test.dart` (widget-tier, seed 2
produk — satu sudah pegang barcode, satu mau ditambah varian pakai
barcode sama — pastikan pesan error muncul DAN varian benar2 tidak
tersimpan). Revert-verify: `rethrow` sementara di `_addVariant` → test
gagal persis dgn `SqliteException` mentah lolos ke widget tree (sama
seperti laporan user) → fix dikembalikan, hijau lagi.

## Migrasi data Griyo POS → file `.berkahpos` (17 Juli, one-off, SELESAI)

User migrasi toko produksi sungguhan dari Griyo POS. Proses:
**BPOP2 (backup murni)** dipilih setelah diskusi tradeoff vs BPOT1
(Alihkan Owner) — user pilih BPOP2 murni krn tidak mau ada risiko sama
sekali (walau risiko keduanya sebenarnya setara utk restore ke device
baru, lihat histori chat kalau perlu detail argumennya).

**Sumber data**: 14 file `Transaksi <bulan>_<tahun>.xlsx` (Jun 2025–Jul
2026, upload user, 2 file "rentang penuh" gagal upload/0-byte tapi tidak
masalah krn tercakup file bulanan), `Pelanggan.xlsx` (493 baris, dari
`Contoh_Dataset.rar` lama), `Products.csv` (**PENTING: sempat pakai
versi USANG** dari `docs/reference/Products.csv` di rebuild pertama —
user upload versi TERBARU belakangan, 80 produk beda harga + beberapa
placeholder ternyata produk asli yg cuma hilang dari versi lama — SUDAH
di-rebuild ulang pakai versi terbaru, jangan pakai `docs/reference/
Products.csv` lagi kalau ada permintaan migrasi serupa, tanya user versi
terbaru dulu).

**Keputusan desain kunci** (semua sudah dieksekusi & divalidasi):
- Harga per-item struk historis TIDAK ADA di data Griyo manapun (dicek
  3 sumber: Transaksi, Arus Kas, Penjualan harian) — item disimpan
  nama+qty saja (`priceAtSale=0`), Total nota tetap ASLI/akurat.
  `stock_ledger` KOSONG sama sekali (stok mulai 0 bersih, transaksi
  historis tidak mengurangi stok), poin loyalitas TIDAK dihitung ulang
  dari histori (diambil langsung dari saldo `Pelanggan.xlsx`, hindari
  dobel-hitung).
- Barang di Rincian yang tak ada di katalog (kode_produk Griyo TIDAK
  unik, sama seperti temuan Item 35 — banyak produk berbagi
  `kode_produk` yg sebenarnya nama satuan spt "Dos"/"Pak") → **importer
  CSV mem-blank kode DUPLIKAT** (kode pertama tetap, ke-2+ di-kosongkan)
  sebelum importFromBytes, supaya dedup-by-kode importer tidak salah
  gabung produk beda jadi satu — tanpa fix ini placeholder membengkak
  145 nama (termasuk 1 nama dipakai 883× transaksi!). Sisanya (~38-55
  nama tergantung versi katalog) jadi produk placeholder
  (`isNonStock=true`, harga 0).
- Pelanggan "Umum" tanpa profil (126 nama, TIDAK ada di `Pelanggan.xlsx`
  maupun laporan resmi Griyo "Pelanggan Utama") → disimpan sbg
  `customerName` teks apa adanya (termasuk karakter aneh spt
  `"Demoiselle <3"`), BUKAN `customerId` — sesuai skema
  `transactions.customerName` yg memang didesain utk "pembeli umum
  bernama".
- ~19-21 nota tempo (kolom Pembayaran = angka minus di Griyo = SISA
  HUTANG, bukan negatif harga — divalidasi lewat pola `paid = total -
  |angka|`, semua masuk akal) → **dipertahankan sbg hutang AKTIF**
  (status `tempo`/`kurang_bayar`), BUKAN "Lunas" — beda dari piutang
  SNAPSHOT lama di `Pelanggan.xlsx` yg TETAP tidak dibawa (keputusan
  lama, tidak berubah). 2 nota tempo atas nama "Umum" (tanpa pelanggan
  tertaut) di-treat sbg Lunas krn tidak ada yg bisa ditagih.
- Audit cross-check dgn laporan resmi Griyo "Pelanggan Utama"
  (`Pelanggan_Utama_....xlsx`) menemukan & menjelaskan 2 sumber
  perbedaan kecil (~1,4% dari 14.348 tx, BUKAN bug proses): (a) 13 nama
  py >1 profil BEDA di sistem Griyo sendiri (mis. "Bu Ika" 2x, org
  beda), (b) transaksi yg pelanggannya "diketik bebas" vs "dipilih dari
  daftar tersimpan" — cuma yg dipilih yg masuk hitungan resmi Griyo,
  tapi data mentah (yg diimpor) py keduanya. Keputusan: pakai data
  mentah apa adanya (lebih konsisten & bisa ditelusuri drpd override
  angka dari laporan agregat yg tak py rincian transaksi).

**Cara build** (kalau perlu diulang/di-generate ulang): skrip Python
sekali-pakai (parse XML mentah xlsx via regex — openpyxl gagal krn ada
karakter tak ter-escape spt `<` di nama pelanggan & `<dimension>` tag yg
kadang salah/under-report jumlah kolom asli) → JSON bersih
(`customers.json`/`transactions.json`) + CSV produk yg sudah
di-preprocess (stok di-nol-kan, kode duplikat di-blank) → skrip Dart
throwaway (`test/griyo_migration_build.dart`, SUDAH DIHAPUS dari repo
setelah selesai — pola sama dipakai kalau perlu lagi) yg pakai KODE ASLI
app (`AppDatabase`+`CsvImportService`+`DbExportService.exportPortable`)
supaya file dijamin valid, BUKAN reimplementasi format. Self-test wajib:
restore file ke DB kosong, cocokkan jumlah/total ke sumber (skrip kedua,
`test/griyo_migration_verify.dart`, juga sudah dihapus).

**Hasil akhir (revisi ke-2, Products.csv terbaru)**: 2.834 produk (2.791
dari katalog + 43 placeholder), 474 pelanggan (poin loyalitas total
27.024 terbawa), 14.348 transaksi (Rp 1.606.131.152, 19 nota tempo aktif
Rp 418.550), 62.646 baris item. Semua tervalidasi via self-test restore
sungguhan (bukan cuma dibaca ulang, benar2 di-decrypt+restore ke
`AppDatabase(NativeDatabase.memory())` kosong lalu di-query). File
terkirim ke user via `SendUserFile`, password terakhir: `riverwas`
(sempat ganti 1x dari password acak awal atas permintaan user — kalau
user lapor masalah restore, pastikan tanya password mana yg dipakai).

**Status: SELESAI, menunggu konfirmasi user berhasil restore di device
produksi.** Tidak ada follow-up kode diperlukan kecuali user lapor
masalah spesifik saat restore, atau minta versi baru (mis. kalau
Products.csv berubah lagi / mau tambah data lain).

## Item 29/30/31/35(opsional) — batch besar "kerjakan semua" (17 Juli, SEMUA SELESAI & di-commit)

User minta eksekusi SEKALIGUS semua yang sudah didesain/disetujui sesi
ini. Urutan commit: `dd4bad3` (Item 29+30abc), `fa3e496` (Item 35
opsional), `886db53` (Item 31). Ringkasan tiap bagian:

### Item 29 — katalog HTML auto-"habis" dari stok riil
`order_page_service.dart` (`_buildCatalogJson`) sekarang JUGA cek stok
riil (base unit) via `AppDatabase.getBaseUnitRealStock()` (baru) saat
`allow_negative_stock` OFF — `outOfStock = markedOutOfStock ||
(!allowNegativeStock && stok<=0)`. **Keputusan desain penting**:
`getBaseUnitRealStock()` HANYA mencakup produk yang PUNYA histori
`stock_ledger` (pakai `EXISTS`, bukan `COALESCE(...,0)`) — produk yang
belum pernah disentuh stoknya sama sekali TIDAK dianggap "stok 0", supaya
toko yang belum sempat isi stok awal produknya tidak mendadak semua
produknya jadi "Stok Habis" di katalog publik. Ini ketahuan dari test
lama yang gagal (`Item 25a — produk TIDAK ditandai stok habis`) sebelum
disempitkan pakai `EXISTS`.

### Item 30 — kontrol stok 3 bagian
- **(a)** Kartu "Kontrol Stok" baru di `ringkasan_screen.dart` — filter
  kategori (state provider TERPISAH dari 30b), hitung "N menipis, M
  habis" dari `watchStockOverview()`, preview 3 produk tertipis, tombol
  "Lihat semua" bawa `groupId` sbg extra ke route `/produk/cek-stok`.
- **(b)** Layar baru `cek_stok_screen.dart` (route `/produk/cek-stok`,
  entry point SELALU terlihat: ikon 📦 di AppBar `produk_list_screen.dart`
  — SENGAJA bukan chip kondisional spt filter "Stok Menipis" lama yg
  hilang total kalau `lowStockCount==0`/tanpa kategori). Checkbox per
  baris toggle `markedOutOfStock` REAL (via `setMarkedOutOfStock`) DAN
  otomatis masuk panel "Teks Order Restock" sticky di bawah (Salin +
  Kirim ke Supplier via `Share.share`) — BUKAN checklist manual terpisah
  dari stok riil (poin user yg dipegang teguh: "untuk apa ada stok kalau
  akhirnya dicek manual juga").
- **(c)** Tab baru "Stok" (index 5) di `laporan_screen.dart` →
  `tabs/stok_tab.dart`. TIDAK terikat rentang tanggal (beda dari tab
  lain) — snapshot nilai SEKARANG, jadi TIDAK ada di `ReportTab` enum &
  TIDAK bisa diekspor (sama spt tab Hutang). Agregasi (grand total,
  per-kategori, deteksi harga-pokok-kosong, sort stok-negatif-paling-minus)
  dihitung di provider (Dart murni) dari `AppDatabase.getInventoryRows()`
  (1 query mentah). Ada catatan kecil permanen di UI: laporan ini
  MELENGKAPI, bukan MENGGANTIKAN, stock opname fisik.

DB baru: `AppDatabase.getBaseUnitRealStock()`, `watchStockOverview()`
(typedef `StockOverviewRow`), `getInventoryRows()` (typedef
`InventoryRow`) — semua di `app_database.dart`, semua 1-query
agregat/JOIN (bukan N+1).

Test: `order_page_service_test.dart` (+3 Item 29), `stock_overview_test.dart`,
`cek_stok_screen_test.dart`, `ringkasan_stock_quick_check_test.dart`,
`inventory_rows_test.dart`, `stok_tab_test.dart`. Revert-verify dilakukan
utk: real-stock check Item 29, EXISTS-vs-COALESCE Item 29 (kasus paling
krusial), toggle checkbox Cek Stok, sort stok negatif Laporan.

### Item 35(opsional) — mode "sinkron via barcode saja"
`PriceMatchService.match(barcodeOnly: true)` baru — skip SKU/fuzzy
sepenuhnya, item tanpa barcode-cocok langsung `notFound`. Fungsi baru
`_tryMatchBarcodeOnly` (duplikasi ringkas blok barcode di `_tryMatch`,
SENGAJA tidak fallback ke SKU/fuzzy sama sekali). Toggle di
`price_sync_screen.dart` (`SwitchListTile`), berlaku utk fetch LAN
maupun import CSV. Test + revert-verify di
`price_sync_sku_collision_test.dart`.

### Item 31 — Tutup Buku tanggal custom
`TutupBukuService.execute()` param `year` (int) → `periodStart`/
`periodEnd` (DateTime, INKLUSIF keduanya — batas atas internal =
periodEnd+1 hari). Label arsip (`archive_$year.db`, filename TIDAK
berubah) = `periodEnd.year` — desain SENGAJA begini (bukan skema
filename baru berbasis tanggal spt draft awal di PLAN.md) supaya
`ArchiveService.open(year,...)`, exclusion sync di
`lan_sync_service.dart` (`listArchivedYears()`), dan seluruh UI arsip
TIDAK perlu disentuh — cukup "tahun" itu sekarang bisa merentang tanggal
custom, bukan wajib Jan1-Des31. `suggestPeriodStart()` baru: hari SETELAH
`last_archive_date` (setting baru, ganti `last_archive_year`) kalau sudah
pernah tutup buku, atau tanggal transaksi PALING LAMA kalau belum pernah
(bukan 1 Jan). Manifest (`archive_manifest` di `app_settings`, JSON
per-tahun: start/end/txCount) dibaca via `listArchiveEntries()` — arsip
LAMA tanpa manifest tetap tampil via fallback kalender-tahun-penuh
(`isLegacyFallback: true`). UI (`tutup_buku_screen.dart`): label statis
"Tahun $currentYear" diganti info dinamis + `showDatePicker` utk pilih
periodEnd.

**Test migrasi** (bukan bug, perubahan API disengaja): `db_fixes_test.dart`
2 test lama diupdate dari `execute(year: 2024)` →
`execute(periodStart: DateTime(2024), periodEnd: DateTime(2024,12,31))`
(perilaku efektif SAMA, cuma API-nya berubah). Test baru
`tutup_buku_custom_date_test.dart` (7 test: suggestPeriodStart 3 skenario,
periode custom inklusif, manifest tersimpan+terbaca, arsip lama
fallback, validasi periodEnd>periodStart). Revert-verify dilakukan utk
inclusive-boundary (+1 hari) & suggestPeriodStart (+1 hari dari
last_archive_date) — 2 bagian paling gampang salah-satu-hari.

**Belum dikerjakan** (opsional, dibahas tapi tidak diminta): mode
"barcode saja" default-ON, validasi keras jarak minimal antar tutup buku.

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

## Diskusi belum dieksekusi

- **Item 4/5** (migrasi data Griyo POS/transaksi lama) — **DIPENDING**
  atas permintaan user: scope migrasi ternyata bukan cuma
  transaksi+pelanggan, tapi juga produk dll (belum dirinci). Jangan
  mulai sebelum user re-konfirmasi scope penuh & minta lanjut.
- **Item 35 mode "barcode saja" default-ON** & validasi jarak minimal
  antar Tutup Buku — dibahas sbg opsional, belum diminta user.

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
