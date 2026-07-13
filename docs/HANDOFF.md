# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 13 Juli 2026. Item 24 SELESAI SEPENUHNYA. 4 bugfix
scanner SELESAI & terkonfirmasi bekerja (tap-to-scan mengulang barang
lama [2x], atribusi pelanggan/pegawai tertukar di antrian, kode #PSN:
pecah jadi beberapa scan di HID eksternal). **Crash Infinix Smart 8:
akar masalah AKHIRNYA TERKONFIRMASI (commit `fb8ba80`) — APK sebelumnya
cuma dibuild utk arm64-v8a, HP itu butuh armeabi-v7a (32-bit). Fix sudah
di-push, BELUM dites user di APK hasil CI berikutnya.** **Item 25c
(gerbang lisensi offline) KODE SELESAI (commit `174cad7`) TAPI BELUM
AKTIF** — public key developer masih placeholder kosong (kill-switch
sengaja), lihat bagian "Gerbang aktivasi/lisensi offline" di bawah utk
2 hal yang perlu diisi developer sebelum gerbang benar-benar mengunci
siapa pun.

**schemaVersion tetap 14** (tidak ada migrasi baru sesi ini). Full
`flutter test`: **300 test hijau**, `flutter analyze` bersih.

## Gerbang aktivasi/lisensi offline (Item 25c) — KODE SELESAI, TAPI BELUM AKTIF

Dieksekusi penuh sesi ini (commit `174cad7`) atas instruksi eksplisit user
("Eksekusi ini serta plan yang sudah kita diskusikan") — desain lengkap
sudah difinalisasi sesi sebelumnya (arsitektur 3-lapis, lubang keamanan
backup-restore & tambalannya, UI/UX — lihat CHANGELOG/`PLAN.md` lama utk
jejaknya, ringkasan teknis final ada di bawah).

**Arsitektur yang jadi kode nyata:**
- **Lapis 1 (aktivasi offline)**: `lib/core/services/license_service.dart`
  (murni logika, testable) + `lib/core/providers/license_provider.dart`
  (I/O SharedPreferences — BUKAN tabel settings DB, harus bisa dicek
  SEBELUM device/DB ada, sama alasannya dgn `device_provider.dart`).
  Sidik jari device = 16 byte acak (`Random.secure()`), heksadesimal,
  digenerate sekali di `LicenseNotifier.load()`. Kode aktivasi format
  `<payload base64url>.<tanda tangan base64url>` (mirip JWT sederhana),
  payload JSON `{"fp":"...","exp":"..."}` (exp = ISO8601 UTC atau literal
  "selamanya"). Verifikasi Ed25519 PURE-DART via package `cryptography`
  (bukan platform channel — testable langsung di `flutter test`, TIDAK
  kena masalah "`Platform.isAndroid` selalu false di host test" seperti
  MethodChannel crash-log kemarin).
- **Ratchet**: `LicenseState.isClockRewound`/`isExpired` (logika murni di
  `license_provider.dart`) — `lastSeen` dimajukan tiap `load()` KECUALI
  kalau `now < lastSeen` tersimpan (indikasi jam baru dimundurkan).
- **Lapis 3 (revoke jarak jauh)**: `license/revoked.json` di repo INI
  SENDIRI (publik, diakses via `raw.githubusercontent.com`), dicek
  opportunistic pakai `dart:io HttpClient` timeout 3 detik di
  `LicenseNotifier._checkRevocation()` — gagal-diam total kalau offline,
  TIDAK PERNAH menahan startup atau memblokir fungsi inti.
- **Gerbang router**: `app_router.dart` — redirect ke `/aktivasi` dicek
  PALING AWAL, SEBELUM `/setup` (device yang belum configured pun tetap
  kena gerbang lisensi duluan).
- **UI**: `lib/features/aktivasi/aktivasi_screen.dart` — pesan SAMA utk
  semua kondisi terkunci (belum aktivasi/expired/revoked, sesuai desain
  final), kartu sidik jari + Salin/Bagikan, field tempel kode + tombol
  Aktifkan, banner peringatan H-7 sebelum expiry di `main_shell.dart`
  (pola sama dgn `BackupReminder`, SnackBar sekali per app-open — BUKAN
  `InlineBannerStateMixin` yang sempat direncanakan, itu pola utk banner
  di DALAM 1 screen, bukan pengingat lintas-app).

**Kenapa nonaktif (KILL-SWITCH SENGAJA)**: `LicenseService.publicKeyBase64`
MASIH STRING KOSONG di source ini. `LicenseState.isLocked` cek
`LicenseService.isConfigured` (`publicKeyBase64.isNotEmpty`) PALING AWAL —
kalau false, `isLocked` SELALU false apa pun kondisi lain (belum
aktivasi/expired/revoked tidak relevan sama sekali). Ini supaya merge
fitur ini TIDAK mengunci siapa pun yang sudah pakai app sekarang — device
lama TIDAK akan tiba-tiba diminta aktivasi begitu update, sampai developer
benar-benar menanam public key sungguhan. Ada test eksplisit yang
membuktikan properti ini (`license_service_test.dart`, grup "kill-switch
& ratchet") — **JANGAN hapus guard `isConfigured` ini** tanpa public key
sungguhan sudah siap ditanam bersamaan.

**Alat generator kode aktivasi**: `scripts/license-generator.html` — file
HTML mandiri, 100% offline, pakai **native Web Crypto API**
(`crypto.subtle`, BUKAN library JS pihak ketiga/CDN). Awalnya rencana
inline library seperti TweetNaCl, tapi permintaan fetch dari
npm/unpkg **DIBLOKIR classifier auto-mode sesi ini** ("kode dari sumber
eksternal yang tidak diminta user secara eksplisit") — pivot ke Web
Crypto API justru lebih baik (nol dependency pihak ketiga, browser modern
sudah dukung Ed25519 native, tidak ada kode kripto pihak ketiga yang perlu
dipercaya). Alur pemakaian: developer buka file ini sendiri di HP/PC-nya,
generate keypair (**private key TIDAK PERNAH masuk sesi Claude/chat** —
prinsip inti desain, dibahas panjang saat diskusi mitigasi human-error),
**WAJIB unduh cadangan** (`the-pos-license-key-backup.json`, format JSON
berisi `privateKeyJwk`/`publicKeyJwk`/`publicKeyBase64`) sebelum form
generator kode terbuka (mitigasi paksa, bukan sekadar imbauan), lalu
tempel sidik jari pelanggan + pilih masa berlaku → hasil kode aktivasi.
Ada juga konfirmasi native `confirm()` sebelum menimpa key yang sudah ada,
dan tampilan public key aktif tiap saat (utk dibandingkan manual dgn yang
tertanam di app — deteksi dini kalau salinan alat yang dipakai ternyata
beda key).

**Interop JS↔Dart diverifikasi NYATA** (bukan cuma ditinjau manual —
resiko tinggi krn ini kode kripto): dijalankan via Playwright/Chromium
headless (module ternyata ada di `/opt/node22/lib/node_modules/playwright`
walau tidak ter-install lokal di proyek — load via `NODE_PATH`,
`executablePath: '/opt/pw-browsers/chromium'` sesuai env notes) — generate
keypair SUNGGUHAN lewat file HTML asli, ambil kode aktivasi hasilnya,
lalu verifikasi lewat `LicenseService.verify()` Dart ASLI (bukan
reimplementasi/mock) via `dart run` script sekali-pakai (dihapus lagi
setelah verifikasi, tidak ikut ke-commit). Kasus valid LOLOS, kasus tamper
1 karakter di payload DITOLAK dgn `error: signature` — baru setelah lolos
verifikasi nyata cross-language ini, commit dilakukan.

**BELUM LENGKAP — 2 hal butuh input developer sebelum gerbang bisa
diaktifkan sungguhan:**
1. **Public key developer** — developer buka `scripts/license-generator.html`
   sendiri (offline), generate keypair, WAJIB unduh cadangan, lalu kirim
   BALIK public key (Base64, ~44 karakter, ditampilkan di alat itu) ke
   sesi berikutnya untuk ditanam di `LicenseService.publicKeyBase64`.
   Private key TIDAK PERNAH dikirim ke Claude — itu prinsip inti desain
   ini, jangan diminta/diterima kalau user mencoba mengirimkannya.
2. **Nomor WhatsApp developer** — tombol "Kirim via WhatsApp" di
   `AktivasiScreen` sementara pakai `Share.share()` (share sheet OS
   generik, user pilih sendiri aplikasi tujuan) karena TIDAK ADA nomor WA
   developer di codebase mana pun (`store_whatsapp` di tabel settings
   adalah nomor TOKO pelanggan, konteks beda total). Kalau user mau
   upgrade ke deep-link `wa.me` langsung (skip langkah pilih app di share
   sheet), perlu: (a) nomor WA developer, (b) izin nambah dependency
   `url_launcher` baru (belum ada di pubspec).

**Setelah 2 hal di atas diisi**: tanam public key di
`LicenseService.publicKeyBase64`, jalankan ulang `flutter test`/`analyze`,
commit — barulah gerbang BENAR-BENAR aktif (device baru mulai diminta
aktivasi saat itu juga). Baru di titik ITU `PATCHNOTES.md` perlu ditambah
entri (SENGAJA belum ditambah sesi ini — kriteria PATCHNOTES cuma
perubahan yang DIRASAKAN user, dan gerbang ini nol dampak terlihat selama
masih nonaktif).

## Bugfix susulan: tap-to-scan race + kode #PSN: pecah di HID (commit `2ee8068`)

**Laporan user 1**: tap-to-scan mode Berulang — scan barcode, SEGERA
singkirkan (<1 detik) lalu tap bidik lagi → KADANG no-op (benar), KADANG
masih menambahkan barang yang sama lagi. Akar masalah: fix sebelumnya
(`_pendingBarcode = null` setelah confirm) tidak menutup RACE — kamera
bisa melaporkan `onDetect` untuk barcode yang SAMA beberapa puluh/ratus ms
SETELAH confirm (frame basi dari sebelum barcode disingkirkan, latensi
pipeline kamera — lebih parah di HP kelas bawah), yang meng-isi ulang
`_pendingBarcode`. Fix: `_lastConfirmedBarcode`/`_lastConfirmedAt` +
cooldown 1.2 detik di `onDetect` — tolak re-arm dgn barcode yang SAMA
dalam jendela itu.

**Laporan user 2**: scan QR handoff pegawai via scanner EKSTERNAL salah
rute ke "Tempel Pesanan" (bukan antrian), + terasa lambat (~6 detik).
Akar masalah: payload `#PSN:` multi-baris (kode mesin + `Pegawai:`/`Nama:`
opsional, dipisah `\n`), tapi scanner keyboard-wedge mengirim newline DI
DALAM payload SEBAGAI keystroke Enter TERPISAH — 1 scan QR pecah jadi
BEBERAPA "scan" beruntun dari sudut pandang `_onHardwareKey`. Baris
`#PSN:...` tiba SENDIRIAN (tanpa `Pegawai:` yang menyusul beberapa puluh
ms kemudian) → `_handleOrderCode` tidak nemu `employeeName` → salah rute.
Baris lanjutan yang menyusul (`Pegawai: Budi` dll) juga masing-masing
dicoba sbg barcode produk biasa → beberapa lookup DB gagal ("Barcode
tidak ditemukan") — kombinasi ini yang bikin terasa lambat. **Catatan:
kamera (mobile_scanner) TIDAK kena bug ini** — dapat teks utuh sekali
baca, cuma HID keyboard-wedge yang split per-newline. Fix:
`_beginOrderCodeMerge`/`_continueOrderCodeMerge`/`_scheduleOrderCodeFinalize`
— tampung fragmen `#PSN:...` + baris lanjutan (`Pegawai:`/`Nama:`/`HP:`/
`Catatan:`) yang datang dalam jendela 350ms, gabung jadi satu teks
sebelum diproses. TIDAK mengubah format QR/wire (opsi yg dipertimbangkan
tapi lebih invasif) — cuma perbaikan sisi PENERIMAAN.

**Temuan metodologi penting**: sebelumnya (`kasir_hw_key_after_produk_nav_test.dart`)
ada gotcha "widget test TIDAK bisa simulasikan HID masuk ke TextField" —
itu BENAR tapi SEMPIT (soal kanal IME/`EditableText`). `_onHardwareKey`
didaftarkan via `HardwareKeyboard.instance.addHandler` (raw key event,
BUKAN lewat TextField) — `tester.sendKeyEvent(key, character: ch)` (param
`character` eksplisit override) TERBUKTI JALAN reach handler ini dgn
benar (lihat `kasir_hid_order_code_merge_test.dart`). Jangan generalisasi
gotcha lama ke SEMUA HID testing — cuma berlaku utk TextField.

## Crash Infinix Smart 8 — SELESAI (akar masalah terkonfirmasi, commit `fb8ba80`)

**Akar masalah sebenarnya** (baru terungkap setelah user berhasil ambil
isi file log lewat infrastruktur commit `2c5ddf9` — lihat riwayat upaya
di bawah): `UnsatisfiedLinkError: dlopen failed: library "libflutter.so"
not found`. APK yang dibuild CI (`build-apk.yml`) sebelumnya pakai
`--target-platform android-arm64` SAJA — cuma menyertakan native library
utk arsitektur 64-bit (arm64-v8a). Infinix Smart 8 (dan kemungkinan besar
HP kelas bawah/lama sejenis) butuh 32-bit (armeabi-v7a) — `libflutter.so`
(engine Flutter) dan `libapp.so` (kode Dart terkompilasi) TIDAK ADA sama
sekali utk arsitektur itu, jadi crash terjadi SEBELUM `FlutterActivity.
onCreate()` sempat jalan — persis kenapa BAIK jaring pengaman Dart
(`runZonedGuarded` dll) MAUPUN Kotlin (`MainActivity.onCreate`, bahkan
`Application.attachBaseContext`) tidak pernah bisa MENCEGAH crash ini —
titik kegagalannya di level `dlopen()` native, sebelum kode app manapun
(Dart/Kotlin) sempat dieksekusi. Yang BISA dilakukan jaring pengaman itu
cuma MENANGKAP hasilnya lewat log Android (`UncaughtExceptionHandler`
level OS/ART, bukan handler kita) — dan justru itulah yang membuat file
log yang user kirim BERISI stack trace `dlopen` ini, sehingga akar
masalah akhirnya bisa dipastikan dari data nyata, bukan dugaan.

**Fix**: `.github/workflows/build-apk.yml` — ganti
`--target-platform android-arm64` jadi
`--target-platform android-arm,android-arm64` (fat APK, kedua arsitektur
dalam satu file, tidak pakai `--split-per-abi` supaya UX download tetap
1 file lewat GitHub Releases). Juga catatan di CLAUDE.md §Perintah supaya
tidak dipersempit balik ke arm64-v8a saja tanpa alasan kuat.

**2 dugaan sebelumnya (secure storage try/catch, commit `e3a7b7d`) SALAH
— TERBUKTI dari user test langsung**, app masih crash identik setelah fix
itu terpasang. Pelajaran: untuk crash device-spesifik yang tidak bisa
direproduksi di environment dev, JANGAN percaya diagnosis dari inspeksi
kode SAJA — dorong dulu ke titik bisa dapat log/data nyata, baru
diagnosis. Riwayat lengkap kedua upaya (kode yang tetap berguna sbg
infrastruktur diagnostik, walau bukan fix akhir) ada di 2 subsection
di bawah, dipertahankan sbg referensi kalau ada crash device-spesifik
lain di masa depan.

**BELUM dikonfirmasi user**: fix `fb8ba80` sudah di-push & merge, APK
baru akan otomatis dibuild CI, TAPI user belum sempat install & test
ulang di Infinix Smart 8 fisik saat sesi ini berakhir. Kalau lanjut sesi
berikutnya dan user belum kabar — tanya duluan status test-nya sebelum
menganggap ini benar-benar tuntas.

## Infrastruktur diagnostik: pindahkan crash log ke Downloads publik (commit `2c5ddf9`)

Ini BUKAN fix akhir (lihat section di atas) — infrastruktur ini yang
membuat log crash asli akhirnya bisa diambil user & dikirim, yang pada
gilirannya membongkar akar masalah sebenarnya. Perubahan:
- `CrashLogWriter.kt` (baru) — tulis ke folder Downloads publik via
  `MediaStore.Downloads` (API 29+, TANPA izin runtime apa pun) SELAIN
  folder khusus app yang lama (dipertahankan sbg fallback HP <Android 10).
- `CrashCatchingApplication.kt` (baru, custom `Application` class,
  direferensikan di `AndroidManifest.xml` `android:name`) — jaring
  pengaman native di `attachBaseContext()`, titik PALING AWAL yang
  mungkin dalam siklus hidup proses Android (sebelum `Application.
  onCreate()`, jauh sebelum `MainActivity` ada). Rantai (bukan menimpa)
  dgn handler `MainActivity.onCreate()` yang sudah ada.
- `MainActivity.kt` — refactor pakai `CrashLogWriter` bersama + method
  channel baru `com.thepos/crash_log` (`append`/`readDownloads`/
  `clearDownloads`) sbg jembatan dari sisi Dart.
- `crash_log_service.dart` — `record()` sekarang tulis ke KEDUA lokasi;
  `readAll()` prioritaskan folder Downloads (lebih pasti terlihat),
  fallback ke folder lama.

**Batas testing**: sama seperti sebelumnya, bagian Kotlin TIDAK bisa
dikompilasi lokal (tidak ada Android SDK). Bagian Dart yang baru
(pemanggilan `MethodChannel` di `record()`/`readAll()`) juga TIDAK bisa
ditest di widget test — `Platform.isAndroid` selalu `false` di environment
test (jalan di host Linux, bukan device Android sungguhan), jadi cabang
kode itu otomatis terlewati di SEMUA test yang ada, tidak pernah benar-benar
tereksekusi kecuali di device asli. Test yang ADA (`crash_log_service_test.dart`)
cuma membuktikan behavior LAMA (`path_provider`) masih utuh, TIDAK
membuktikan jalur `MediaStore` baru bekerja.

## Infrastruktur diagnostik: jaring pengaman crash log awal (upaya ke-1, dugaan penyebab TERBUKTI SALAH, commit `e3a7b7d`)

**Laporan user**: HP Infinix Smart 8 — app terinstall sukses, tapi begitu
dibuka langsung force-close dalam hitungan milidetik, TANPA keterangan
error apa pun (bukan "app tidak merespons", bukan dialog error Android —
benar-benar langsung balik ke home screen).

**Diagnosis** (dari investigasi kode, BUKAN dari logcat asli — user tidak
punya akses PC/adb): `DeviceNotifier.load()` (`device_provider.dart`) baca
`store_key` dari `FlutterSecureStorage` (`encryptedSharedPreferences: true`
— pakai Android Keystore) **tanpa try/catch**, dipanggil `await` langsung
di `main()` **SEBELUM `runApp()`**. Kalau baca itu melempar exception
(dikenal luas jadi masalah di sebagian implementasi Android Keystore OEM,
terutama Transsion group/Infinix-Tecno-itel), seluruh `main()` crash
sebelum Flutter sempat merender apa pun — persis cocok dengan gejala
"tidak ada layar error sama sekali".

**Perbaikan (2 lapis):**
1. **Fix langsung**: `device_provider.dart` `load()` — bungkus baca/tulis
   `_secureStorage` dengan try/catch, fallback ke `store_key` lama di
   `SharedPreferences` (kalau ada, device yang sudah pernah dipakai) atau
   `null` (device baru — sama seperti alur normal sebelum Setup Toko Baru).
   **PENTING**: fallback ini HANYA aman untuk kasus "belum pernah migrasi
   ke secure storage" — TIDAK menyelesaikan skenario terpisah "device
   SUDAH terkonfigurasi normal, lalu suatu saat Keystore-nya rusak
   mendadak" (storeKey bisa jadi null, `isConfigured` jadi false, app
   bisa salah redirect ke `/setup` — risiko data-loss teoretis kalau user
   lanjut "Setup Toko Baru" padahal ada DB lama). Ini SENGAJA belum
   ditangani (di luar scope bug yang dilaporkan — itu soal HP baru/fresh
   install) — kalau ada laporan device LAMA yang tiba-tiba begini,
   perlu penanganan terpisah (jangan otomatis redirect /setup, munculkan
   error eksplisit dulu).
2. **Jaring pengaman diagnostik** (buat kasus lain yang belum diketahui,
   atau verifikasi ulang dugaan di atas kalau ternyata masih terjadi):
   - `CrashLogService` (baru, `lib/core/services/crash_log_service.dart`):
     tulis error ke file `the_pos_crash_log.jsonl` di folder eksternal
     khusus app (`path_provider` `getExternalStorageDirectory()` —
     `Android/data/com.thepos.the_pos/files/`, TANPA perlu izin apa pun).
     Format JSONL (1 objek JSON per baris), SELALU append (bukan
     read-modify-write) — sengaja biar cepat & tahan jeda sangat singkat
     sebelum OS mematikan proses yang crash.
   - `main.dart`: dibungkus `runZonedGuarded` + `FlutterError.onError` +
     `PlatformDispatcher.instance.onError` — cakupan Dart-level.
   - `MainActivity.kt`: `Thread.setDefaultUncaughtExceptionHandler`
     dipasang di awal `onCreate()` (sebelum `super.onCreate()`) — cakupan
     LEBIH LUAS dari Dart (exception Java/Kotlin native, mis.
     `UnsatisfiedLinkError` gagal load `.so`), tulis ke file YANG SAMA
     (path & nama file harus persis sama dgn `CrashLogService.fileName`
     — kalau salah satu diubah, HARUS ubah keduanya).
   - **Batas jujur yang disampaikan ke user**: TIDAK bisa menangkap crash
     native murni (segfault C/C++) — itu di luar jangkauan handler
     Java/Kotlin/Dart mana pun, satu-satunya cara lihat itu adalah adb
     logcat (perlu PC). Untuk kasus user ini (tidak ada PC sama sekali),
     ini adalah upaya terbaik yang bisa dilakukan tanpa akses fisik/adb.
   - Layar baru **"Log Error Terakhir"** (`crash_log_screen.dart`,
     route `/pengaturan/log-error`, menu di Pengaturan → Diagnostik,
     semua role) — baca file itu + tombol Bagikan (`share_plus`, pola
     sama dgn share struk). Ini BONUS kenyamanan (kalau app berhasil
     kebuka) — jaring pengaman UTAMA tetap file mentahnya sendiri, bisa
     dibaca lewat File Manager biarpun app tidak pernah berhasil
     menampilkan UI sama sekali (skenario terburuk yang dilaporkan user).

**Percakapan panjang sebelum eksekusi** (kalau perlu konteks lagi):
user awalnya minta cara `adb logcat` → tidak punya PC → didiskusikan
alternatif (custom log reader terpisah — ditolak, terlalu kompleks/rapuh
untuk kasus "realtime" karena keterbatasan Android sandboxing & CORS
`file://`) → disederhanakan ke pendekatan file lokal + File Manager →
user tanya soal akurasi vs adb (dijawab jujur: tidak 100% setara, blind
spot di crash native murni) → user tanya detail bentuk "log exporter"
(diklarifikasi: BUKAN app terpisah, kode nempel di app yang sama) → user
tanya paling tajam: "kalau app crash sepermili detik, bagaimana caranya
tetap bisa 'kirim' log?" — ini mengoreksi rencana awal (layar in-app jadi
TIDAK RELEVAN untuk crash-sebelum-UI, jalur utama HARUS file+File Manager).

## Item 24 (payment gate role Pegawai) — SELESAI SEPENUHNYA

Semua sub-item (24a–24f) selesai & di-commit. Ringkasan alur akhir:

1. **Rename kosmetik "Kasir"→"Pegawai"** di UI (`deviceRole` internal TETAP
   `'kasir'`, tidak disentuh) + permission baru `terima_pembayaran` (default
   OFF, self-heal via `beforeOpen`) — commit `4317c33`.
2. **Gerbang tombol "Bayar"**: pegawai (`deviceRole == 'kasir'`) TANPA izin
   `terima_pembayaran` melihat "Kirim ke Owner/Asisten" alih-alih "Bayar"
   (`cart_sheet.dart`, `_needsHandoffGateProvider`). Tap membuka
   `_HandoffQrSheet`: QR (`qr_flutter`) berisi kode mesin
   `OrderParserService.encodeHandoff()` (format `#PSN:...` + baris
   `Pegawai: <nama>` + `Nama: <pelanggan>` opsional).
3. **Scan sisi owner**: `kasir_screen.dart` `_handleBarcode()` deteksi
   prefix `#PSN:` PALING AWAL → `_handleOrderCode()`. Ada baris `Pegawai:`
   → `db.holdOrder(...)` payload `awaitingPayment: true` + `employeeName`
   TERPISAH dari `meta`/`label`. **`label` kartu antrian = nama PELANGGAN**
   (fallback `'Tanpa Nama'`), nama pegawai + jam tampil di **tab folder
   terpisah** di atas kartu (`_HeldCardWithTab`, pakai `_TabPainter` sama
   dgn tab cart bar).
4. **24b — sheet "Verifikasi Pesanan"**: tap kartu antrian `awaitingPayment`
   buka sheet checklist (owner centang sambil pegawai bacakan, MURNI 1
   device) sebelum "Lanjut ke Keranjang". Centangan persisted ke
   `held_orders.cartJson` (`db.updateHeldOrder`).
5. **Notifikasi realtime arah balik SENGAJA TIDAK dibangun** — final.
6. **Transport**: QR-lewat-scanner-kasir (opsi jaringan port 8626 ditolak).

**Item 24 tidak ada sisa pekerjaan.**

## Gotcha teknis baru sesi ini (selain yang sudah ada di CLAUDE.md)

- **Test regresi bisa "lolos palsu" gara-gara debounce internal** —
  `_handleBarcode` punya debounce 1.5 detik per-barcode (`DateTime.now()`,
  REAL wall-clock, TIDAK ikut fast-forward `tester.pump`). Test "tap dua
  kali cepat lalu cek qty" bisa LOLOS baik dgn fix MAUPUN bug dikembalikan
  (revert-verify gagal mendeteksi) karena debounce sendiri sudah mencegah
  efeknya. Fix: assert **state internal langsung lewat representasi UI**
  (mis. `Icon.color` tombol), bukan re-trigger aksi yang punya side-channel
  independen. **Kalau revert-verify tiba-tiba LOLOS padahal harusnya
  gagal, curigai mekanisme LAIN yang menutupi efek bug.**
- **`Column(mainAxisSize: MainAxisSize.min)` yang membungkus widget ber-
  `Spacer()` di dalam slot `ListView` horizontal CRASH** ("RenderFlex
  children have non-zero flex but incoming height constraints are
  unbounded"). Fix: bungkus dgn `Expanded`, JANGAN `mainAxisSize.min` di
  Column pembungkusnya — lihat `_HeldCardWithTab` (kasir_screen.dart).
- **Mock `PathProviderPlatform`/`flutter_secure_storage` MethodChannel di
  test** — pola: subclass `PathProviderPlatform` override
  `getExternalStoragePath()`/`getApplicationDocumentsPath()` arahkan ke
  `Directory.systemTemp.createTempSync(...)` (lihat `db_fixes_test.dart`,
  `crash_log_service_test.dart`); utk `flutter_secure_storage`, mock
  `MethodChannel('plugins.it_nomads.com/flutter_secure_storage')` via
  `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
  .setMockMethodCallHandler(...)`, method names `'read'`/`'write'` (lihat
  `device_provider_secure_storage_test.dart`).
- **Environment sesi ini TIDAK punya Android SDK** (`ANDROID_HOME` kosong)
  — perubahan Kotlin (`MainActivity.kt`) tidak bisa dikompilasi lokal,
  cuma ditinjau manual. GitHub Actions (`build-apk.yml`) yang jadi
  verifikasi RIIL pertama untuk perubahan native Android.
- **`Timer(Duration, ...)` beda dari `DateTime.now()` soal fast-forward di
  widget test**: `Timer` (dipakai `_scheduleOrderCodeFinalize` utk gabung
  fragmen HID) IKUT di-fast-forward oleh `tester.pump(Duration(...))` —
  bisa ditest deterministik tanpa nunggu wall-clock asli. `DateTime.now()`
  (dipakai debounce `_handleBarcode` & cooldown stale-detection tap-to-
  scan) TIDAK ikut fast-forward, tetap wall-clock asli — bisa jadi
  confound test kalau dua tap terjadi "seketika" dalam waktu test (lihat
  gotcha debounce di atas). Pilih `Timer` vs `DateTime.now()` sadar
  konsekuensi testing-nya masing-masing.
- **`tester.sendKeyEvent(key, character: ch)` REACH `HardwareKeyboard.
  instance.addHandler`-registered callback dgn benar** (raw key event
  pipeline) — beda dari gotcha lama soal TextField/IME yang TIDAK bisa
  disimulasikan via raw key event. Jangan generalisasi gotcha lama itu ke
  SEMUA skenario HID — cuma berlaku utk widget `TextField`/`EditableText`.
  Lihat `kasir_hid_order_code_merge_test.dart`.
- Double `Navigator.pop()` sinkron back-to-back bisa bikin `pumpAndSettle()`
  macet selamanya di widget test — cuma pop route TERDEKAT/terdalam.
- `await someDriftTable.watch().first` langsung di `testWidgets` bisa HANG
  selamanya — pakai query one-shot (`db.select(db.tabelnya).get()`).
- Sheet modal baru di atas `KasirScreen` otomatis aman dari HID scanner
  eksternal — JANGAN reuse flag `_cartSheetOpen` (khusus `CartSheet`).
- **`flutter build apk --target-platform android-arm64` SAJA bikin HP
  32-bit (armeabi-v7a) tidak bisa buka app sama sekali** — `libflutter.so`
  & `libapp.so` hilang total utk arsitektur itu, crash `dlopen` terjadi
  sebelum kode app manapun jalan (tidak bisa dicegah dari sisi
  Dart/Kotlin, cuma bisa DITANGKAP via `UncaughtExceptionHandler` level
  OS). Build APK produksi HARUS `--target-platform android-arm,
  android-arm64` (lihat `build-apk.yml`, kasus nyata Infinix Smart 8).
- **Folder `Android/data/<package>/` tidak selalu terlihat "kosong"
  krn benar-benar kosong** — Android 11+ blokir File Manager pihak
  ketiga (termasuk "Files by Google") dari melihat isi folder itu sama
  sekali, walau app sendiri bisa baca/tulis bebas via `path_provider`.
  Kalau perlu file yang HARUS terlihat user lewat File Manager biasa
  (mis. crash log darurat), tulis ke `MediaStore.Downloads` (API 29+,
  publik, tanpa izin runtime) — lihat `CrashLogWriter.kt`.
- **Auto-mode classifier bisa BLOKIR `curl`/fetch ke domain pihak ketiga**
  kalau alasannya "kode dari sumber eksternal yang tidak diminta user
  secara eksplisit" (kejadian nyata: coba fetch TweetNaCl.js dari
  unpkg/npm registry utk alat generator lisensi, user cuma minta "alat
  offline", tidak menyebut nama library spesifik). Bukan cuma soal proxy
  policy (`registry.npmjs.org` sebenarnya REACHABLE lewat noProxy list) —
  ini lapisan izin terpisah. Kalau kena blokir begini, jangan coba akali —
  cari alternatif yang tidak butuh kode pihak ketiga sama sekali (di sini:
  native Web Crypto API browser, bukan library JS yang di-inline).
- **Package `cryptography` (pub.dev) Ed25519 PURE-DART** — tidak butuh
  platform channel/native setup, jalan identik di `flutter test` (host
  Linux) maupun device asli. Kontras dgn banyak crypto/hardware API lain
  di project ini (`flutter_secure_storage`, `MediaStore` crash-log) yang
  SELALU butuh mock MethodChannel atau otomatis skip di test krn
  `Platform.isAndroid` selalu false di host. Kalau butuh crypto yang
  testable penuh tanpa compromise, cari varian pure-Dart dulu sebelum
  platform-channel.
- **Web Crypto API (`crypto.subtle`) Ed25519 interop dgn `cryptography`
  Dart package TERBUKTI JALAN** (diverifikasi nyata via Playwright, lihat
  section 25c di atas) — payload yang di-`TextEncoder().encode()` di JS
  lalu ditandatangani `crypto.subtle.sign({name:"Ed25519"}, ...)`
  menghasilkan signature 64-byte RAW yang diverifikasi identik oleh
  `Ed25519().verify()` Dart, SELAMA byte payload yang ditandatangani
  (bukan representasi ulang/re-serialize) yang dipakai kedua sisi — jangan
  re-encode JSON secara terpisah di sisi verify, selalu verifikasi
  signature atas byte MENTAH yang diterima.
- **State pra-DB/pra-setup (device belum configured) HARUS SharedPreferences,
  BUKAN tabel settings Drift** — pola `saved_catalogs` (blob JSON di tabel
  settings) TIDAK berlaku utk data yang perlu dicek SEBELUM DB bisa dibuka
  (`databaseProvider` butuh `storeKey` yang butuh `/setup` selesai). Gerbang
  lisensi (25c) HARUS ikut pola `device_provider.dart` (SharedPreferences)
  krn alasan yang SAMA — cek dulu KAPAN state itu perlu dibaca sebelum
  pilih tempat penyimpanan.

## Lingkungan sesi ini
Flutter TIDAK terpasang default — dipasang manual ke `/tmp/flutter`
(versi 3.24.5 stable, samakan CI `build-apk.yml`). `/opt/flutter` yang
disebut CLAUDE.md TIDAK ADA di environment ini — selalu `which flutter`
dulu kalau command CLAUDE.md gagal. **Android SDK TIDAK ADA sama sekali**
(`ANDROID_HOME` kosong) — perubahan native Android (Kotlin/Gradle) tidak
bisa diverifikasi kompilasi lokal, cuma via CI. Jalankan flutter sebagai
non-root menghasilkan warning "Woah!... trying to run as root" yang TIDAK
menggagalkan perintah (aman diabaikan).

**Node.js + Playwright + Chromium TERSEDIA** (dipakai utk verifikasi
interop `scripts/license-generator.html`, lihat section 25c) — Node di
`/opt/node22`, module `playwright` ter-install GLOBAL di
`/opt/node22/lib/node_modules` (bukan lokal per-proyek — butuh
`NODE_PATH=/opt/node22/lib/node_modules node script.js` biar `require
('playwright')` ketemu), Chromium executable di
`/opt/pw-browsers/chromium`. Berguna kapan pun perlu drive browser asli
utk verifikasi (bukan cuma screenshot UI Flutter — juga cocok utk test
file HTML/JS mandiri seperti alat generator ini).

## Menggantung / Kandidat Berikutnya
- **Crash Infinix Smart 8 — tinggal konfirmasi user.** Akar masalah sudah
  ditemukan & fix sudah di-merge (`fb8ba80`, lihat section di atas).
  Langkah pertama sesi berikutnya kalau topik ini muncul lagi: tanya
  apakah user sudah install APK CI terbaru & apakah app sekarang bisa
  dibuka normal di Infinix Smart 8. Kalau MASIH crash walau sudah fat
  APK (arm+arm64), itu artinya ada penyebab LAIN — jangan asumsikan
  otomatis sama dgn kasus ini, minta log baru lagi.
- **Item 21+17** (sync UI persisten lintas tab + persist antrian approval)
  — masih sengaja ditunda dari sesi-sesi sebelumnya.
- **Item 23** (scope bug "Sisa Tagihan" understated di lokasi lain) — lihat
  PLAN.md untuk daftar lengkap lokasi yang sengaja belum disentuh.
- **Item 3c/4/5/8** (import data toko lama dari dataset Griyo POS) — lihat
  PLAN.md, menunggu keputusan/data lanjutan dari user.
- **25c (gerbang lisensi) — tunggu developer generate keypair sendiri.**
  Kode sudah selesai & di-commit (`174cad7`), TAPI nonaktif total sampai
  developer: (1) buka `scripts/license-generator.html`, generate keypair,
  kirim BALIK public key-nya saja (bukan private key — jangan pernah
  terima/minta private key), (2) putuskan soal nomor WA developer utk
  tombol "Kirim via WhatsApp" (tetap share sheet generik, atau upgrade ke
  deep-link `wa.me` + `url_launcher`). Detail lengkap di section "Gerbang
  aktivasi/lisensi offline" di atas.

## Preferensi User (masih berlaku)
- Bahasa komunikasi & teks UI: Indonesia.
- Untuk fitur bervisual: usulkan opsi desain dulu sebelum implementasi.
- Untuk bug: laporkan dulu contoh kasus + severity, baru eksekusi.
- Untuk fitur baru berisiko/besar: diskusikan cakupan dulu, eksekusi
  setelah instruksi eksplisit ("eksekusi semua"/konfirmasi serupa/"Execute!").
- **User sering mengoreksi/menyederhanakan scope lewat pertanyaan tajam di
  tengah diskusi** (lihat Item 24b, dan sesi crash-log ini — "kalau app
  crash sepermili detik, bagaimana bisa kirim log?" langsung membongkar
  cacat rencana awal) — jangan buru-buru eksekusi desain awal kalau user
  masih mengajukan pertanyaan klarifikasi/skeptis, itu sinyal scope akan
  berubah. **Jawab jujur soal keterbatasan teknis** (jangan overselling
  solusi) — user menghargai batasan yang disampaikan terus terang
  (mis. "tidak bisa menangkap crash native murni") daripada janji kosong.
- **User melaporkan bug dgn observasi presisi** — baca laporan bug user
  kata per kata, biasanya sudah menunjuk lokasi/skenario presisi.
- Rencana yang didiskusikan tapi belum dieksekusi → masuk PLAN.md
  komprehensif, jangan cuma tersimpan di riwayat chat.
- Perubahan sensitif/berisiko (mis. aspek security) — tunda eksekusi
  sampai instruksi eksplisit terpisah. Pola yang sudah terbukti berhasil
  (lihat 25c): diskusi bertahap yang PANJANG dulu (arsitektur, lalu
  UX/format kunci, lalu skenario human-error/worst-case) sebelum
  "Eksekusi" — user menghargai proses ini walau makan banyak putaran
  tanya-jawab, JANGAN dipersingkat/dilewati demi kecepatan.
- Untuk perubahan kecil yang jelas (tidak ambigu) — user eksplisit minta
  langsung eksekusi + merge ke main tanpa menunggu konfirmasi tambahan,
  TAPI kalau ada keputusan desain yang genuinely ambigu — tetap ajukan
  dulu sebelum eksekusi, jangan diasumsikan sepihak.
