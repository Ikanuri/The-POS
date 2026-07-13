# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 13 Juli 2026. Item 24 SELESAI SEPENUHNYA. 4 bugfix
scanner SELESAI & terkonfirmasi bekerja (tap-to-scan mengulang barang
lama [2x], atribusi pelanggan/pegawai tertukar di antrian, kode #PSN:
pecah jadi beberapa scan di HID eksternal). **1 masalah BELUM
terselesaikan: crash Infinix Smart 8 — 2 percobaan fix sudah dikirim,
percobaan pertama TERKONFIRMASI GAGAL, percobaan kedua BELUM
dikonfirmasi — baca ⚠️ di bawah SEBELUM lanjut kerjakan apa pun soal
ini.**

**schemaVersion tetap 14** (tidak ada migrasi baru sesi ini). Full
`flutter test`: **282 test hijau**, `flutter analyze` bersih.

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

## ⚠️ MASIH BELUM TERSELESAIKAN — crash Infinix Smart 8 (status: 2 percobaan sudah tidak cukup)

**Update kritis**: fix pertama (`e3a7b7d`, secure-storage try/catch) **SUDAH
DIKONFIRMASI TIDAK CUKUP** — user install APK hasil fix itu, app MASIH
crash, dengan gejala PERSIS SAMA seperti sebelumnya (instan, tanpa
keterangan). Ini berarti dugaan awal (FlutterSecureStorage/Android
Keystore) KEMUNGKINAN BESAR SALAH, atau setidaknya bukan SATU-SATUNYA
penyebab. **Jangan asumsikan diagnosis lama itu benar** kalau lanjut
sesi ini — anggap penyebab sebenarnya MASIH BELUM DIKETAHUI.

User juga cek folder `Android/data/com.thepos.the_pos/files` via app
"Files by Google" — **kosong, tidak ada file log sama sekali**. Ini bisa
berarti DUA hal berbeda (belum bisa dipastikan mana): (a) jaring pengaman
Dart/Kotlin tidak sempat menangkap apa pun (crash terlalu dini/native), atau
(b) filenya ADA tapi Android 11+ blokir "Files by Google" (dan file
manager pihak ketiga lain) dari melihat isi folder `Android/data/<app
lain>/` sama sekali (temuan OS well-known, bukan bug app ini) — tampil
"kosong" adalah gejala UMUM restriksi ini, bukan bukti kosong beneran.

**Commit `2c5ddf9` (sesi ini) mencoba mengatasi kemungkinan (b)**: log
sekarang JUGA ditulis ke folder Downloads PUBLIK (`MediaStore`, API 29+)
yang TIDAK kena restriksi itu, plus jaring pengaman native dipasang LEBIH
AWAL lagi (`CrashCatchingApplication.attachBaseContext`, sebelum
`MainActivity` ada). **INI JUGA BELUM DIKONFIRMASI** — user belum sempat
test APK hasil commit ini saat sesi berakhir.

**Kalau sesi berikutnya lanjut soal ini, LANGKAH PERTAMA WAJIB**: tanya
user apakah sudah coba APK terbaru (`2c5ddf9`), dan:
- Kalau app SEKARANG BUKA NORMAL → selesai, tidak perlu apa-apa lagi.
- Kalau MASIH crash TAPI ada file di folder Downloads (`the_pos_crash_log.jsonl`,
  cari lewat File Manager biasa, TANPA perlu masuk `Android/data`) →
  MINTA ISI FILE ITU, itu petunjuk nyata pertama yang kita punya soal
  penyebab sebenarnya — diagnosis ulang dari situ, JANGAN based on
  dugaan lama.
- Kalau MASIH crash DAN folder Downloads JUGA tidak ada file sama sekali
  → ini bukti kuat crash terjadi di level yang genuinely tidak bisa
  ditangkap software apa pun (native segfault) — jaring pengaman sudah
  dipasang di titik paling awal yang mungkin (`attachBaseContext`), tidak
  ada lagi yang bisa diperlebar dari sisi app. **Di titik ini, JUJUR
  sampaikan ke user**: satu-satunya jalan tersisa adalah `adb logcat`
  (perlu PC/laptop, walau cuma sebentar/pinjam) — tidak ada trik software
  lain yang bisa menembus batas ini.

**Jangan ulangi pola "asumsikan fix ini pasti benar" tanpa bukti log
nyata** — sudah 1x salah asumsi (secure storage), jangan sampai
membangun teori kedua tanpa data juga.

## Bugfix (upaya ke-2, BELUM terkonfirmasi berhasil): pindahkan crash log ke Downloads publik (commit `2c5ddf9`)

Lihat bagian ⚠️ di atas untuk konteks kenapa ini diperlukan. Perubahan:
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

## Bugfix (upaya ke-1, TERKONFIRMASI TIDAK CUKUP): force-close diam-diam di HP tertentu (commit `e3a7b7d`)

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

## Lingkungan sesi ini
Flutter TIDAK terpasang default — dipasang manual ke `/tmp/flutter`
(versi 3.24.5 stable, samakan CI `build-apk.yml`). `/opt/flutter` yang
disebut CLAUDE.md TIDAK ADA di environment ini — selalu `which flutter`
dulu kalau command CLAUDE.md gagal. **Android SDK TIDAK ADA sama sekali**
(`ANDROID_HOME` kosong) — perubahan native Android (Kotlin/Gradle) tidak
bisa diverifikasi kompilasi lokal, cuma via CI. Jalankan flutter sebagai
non-root menghasilkan warning "Woah!... trying to run as root" yang TIDAK
menggagalkan perintah (aman diabaikan).

## Menggantung / Kandidat Berikutnya
- **PALING PRIORITAS — crash Infinix Smart 8 MASIH BELUM SELESAI.** Baca
  section ⚠️ di atas dulu sebelum menyentuh ini. Ringkas: fix ke-1
  (`e3a7b7d`, secure storage) TERKONFIRMASI GAGAL — app masih crash sama
  persis. Fix ke-2 (`2c5ddf9`, pindah log ke Downloads publik + jaring
  native lebih awal) BELUM dikonfirmasi user. Langkah pertama sesi
  berikutnya: tanya status test APK terbaru, JANGAN asumsikan apa pun
  sudah selesai tanpa konfirmasi eksplisit. Kalau file log akhirnya
  muncul di folder Downloads, itu data PERTAMA yang benar-benar bisa
  dipakai diagnosis — sebelum itu, semua "penyebabnya X" masih dugaan.
- **Item 21+17** (sync UI persisten lintas tab + persist antrian approval)
  — masih sengaja ditunda dari sesi-sesi sebelumnya.
- **Item 23** (scope bug "Sisa Tagihan" understated di lokasi lain) — lihat
  PLAN.md untuk daftar lengkap lokasi yang sengaja belum disentuh.
- **Item 3c/4/5/8** (import data toko lama dari dataset Griyo POS) — lihat
  PLAN.md, menunggu keputusan/data lanjutan dari user.
- **25c (lisensi)** — desain final, tunggu instruksi eksplisit user untuk
  mulai eksekusi. JANGAN disentuh tanpa instruksi baru.

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
  sampai instruksi eksplisit terpisah (lihat 25c).
- Untuk perubahan kecil yang jelas (tidak ambigu) — user eksplisit minta
  langsung eksekusi + merge ke main tanpa menunggu konfirmasi tambahan,
  TAPI kalau ada keputusan desain yang genuinely ambigu — tetap ajukan
  dulu sebelum eksekusi, jangan diasumsikan sepihak.
