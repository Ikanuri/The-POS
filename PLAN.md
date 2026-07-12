# PLAN.md

Daftar rencana kerja yang sudah didiskusikan tapi **belum dieksekusi**. Ini
BUKAN log — begitu satu item selesai dikerjakan & di-commit, **hapus item itu**
dari file ini (lihat aturan di [CLAUDE.md](CLAUDE.md) §Perencanaan). Riwayat
teknis pekerjaan yang SUDAH selesai ada di [CHANGELOG.md](CHANGELOG.md), bukan
di sini.

_Terakhir diperbarui: 12 Juli 2026. Item 9-22 SELESAI 12/13 (Item 17+21
sengaja ditunda). Item 3a/3b SELESAI/terjawab lewat fitur baru "Import dari
Griyo POS". Item 4 (import pelanggan Griyo) analisis+keputusan besar
selesai, siap diimplementasi. **Item 23** (bug "Sisa Tagihan" understated
saat kembalian dipakai ulang — scope Buku Hutang/Tutup Kasir/tempat lain
masih menggantung). **Item 24** (6 usulan fitur/penyesuaian dari sesi
diskusi lanjutan — kalkulator Tambah Bayar, checklist struk tersinkron,
katalog HTML disamakan POS, payment gate role Pegawai, tap-to-scan,
redesign toggle scanner) — SEMUA sudah disetujui scope-nya lewat diskusi
panjang, siap diimplementasi, kecuali 24f yang masih perlu 1 revisi visual.
**Item 25** (tanda "Stok Habis" cepat dari modal kasir, hapus produk
via swipe, gerbang aktivasi/lisensi offline) — 25b SELESAI, 25a SEDANG
dieksekusi.
**25c (lisensi) desainnya SUDAH FINAL & komprehensif** (lihat dokumentasi
terpisah yang dikirim ke user, `docs/keamanan-lisensi-offline.md` — TIDAK
di-commit ke repo atas permintaan user, cuma dikirim sebagai file) —
**TAPI SENGAJA BELUM dieksekusi**, user eksplisit minta tunda eksekusinya
walau desainnya sudah disetujui penuh. Jangan eksekusi 25c tanpa instruksi
baru dari user.
Sisa menggantung: Item 3c, 5, 8, 23, 25c — lihat masing-masing untuk
detail._

---

## Item 25 — 3 usulan tambahan (lanjutan sesi Item 24)

### 25a — Tanda "Stok Habis" cepat dari modal kasir (DISETUJUI, siap eksekusi)
**Konteks:** penanda manual sementara/eksperimental, TERPISAH dari sistem
stok resmi (yang belum diaudit) — akses cepat karena tap produk di kasir
lebih praktis daripada buka tab Produk. Juga jadi placeholder kalau nanti
fitur stok real sungguhan dibangun.

**Desain teknis:**
- Kolom boolean baru di tabel `products` (mis. `markedOutOfStock`, default
  `false`) — level PRODUK (bukan per-satuan/`product_units`), karena kalau
  barang fisik habis biasanya berlaku ke semua satuan jualnya sekaligus.
  Butuh migrasi kecil (schemaVersion +1).
- Icon toggle baru di `ItemEntrySheet` (`lib/features/kasir/widgets/item_entry_sheet.dart`,
  baris ~466-489 area — satu Row dengan icon edit produk & hapus item yang
  sudah ada), BUKAN di `produk_form_screen.dart` sesuai permintaan user.
- `order_page_service.dart`: produk dengan flag ini render badge "Stok
  Habis" + tombol tambah dinonaktifkan di JS katalog HTML.
- Tab kasir (`kasir_screen.dart`, kartu produk grid): badge kosmetik kecil
  di sebelah tombol + — **TIDAK menonaktifkan fungsi tombol**, supaya tidak
  tabrakan dengan sistem izin "Izinkan Stok Minus" yang sudah ada &
  independen.

**Klarifikasi penting yang SUDAH dikonfirmasi user:** update ke katalog
HTML BUKAN realtime/live (file statis terkirim via WA tidak punya koneksi
balik) — flag di database update seketika, tapi baru tercermin di HTML
saat owner **generate & kirim ulang** katalog berikutnya. User sudah paham
& terima batasan ini.

### 25c — Gerbang aktivasi/lisensi offline anti-penyebaran tanpa izin (DESAIN FINAL, EKSEKUSI SENGAJA DITUNDA)

**Konteks nyata dari user:** seseorang minta akses app ini (sudah
diperingatkan belum stabil/masih buggy), lalu diam-diam menyebarkannya ke
pihak lain tanpa izin. User ingin cara menghentikan rantai penyebaran +
mengunci fitur sepenuhnya, sekaligus placeholder untuk monetisasi nanti.

**⚠️ STATUS: desain sudah disetujui penuh lewat diskusi panjang (termasuk
1 lubang keamanan nyata yang ditemukan user sendiri & sudah ditambal di
desain final), TAPI user secara eksplisit minta EKSEKUSI kode DITUNDA**
("eksekusi semua plan... kecuali aspek security yang baru kita bahas").
**Jangan mulai implementasi 25c tanpa instruksi baru dari user di sesi
mendatang.**

**Dokumentasi lengkap (alur, logika, detail teknis tiap komponen) ada di
file terpisah `docs/keamanan-lisensi-offline.md`** — sengaja **TIDAK
di-commit ke repo** atas permintaan eksplisit user (dikirim sebagai file
saja). Kalau file itu sudah tidak ada di scratchpad/hilang saat sesi
mendatang mau eksekusi ini, regenerasi ringkasannya dari sini:

**Ringkasan arsitektur final (2 lapis independen, bisa dikombinasi bebas):**
- **Tingkat 1 (offline, ratchet ringan):** tiap device generate fingerprint
  unik saat install pertama → terkunci sampai user tempel kode aktivasi
  yang HANYA developer bisa keluarkan (dihitung dari fingerprint + masa
  berlaku pilihan developer, termasuk opsi "selamanya" → skema lisensi
  offline klasik ala serial-key, tidak butuh server). Masa berlaku
  dihitung pakai ratchet DASAR (waktu-terakhir-terlihat, tolak kalau
  mundur) — sengaja TIDAK dibuat berlapis-lapis rumit (skip cross-check
  file-mtime/elapsed-since-boot) karena Tingkat 3 menutup kasus yang lebih
  canggih.
- **Tingkat 2 (opsional, lewat rilis APK baru):** kode aktivasi lama
  otomatis tidak dikenali skema verifikasi baru begitu app di-update ke
  versi lisensi berbayar sungguhan — jalur alami untuk momen monetisasi
  aktif nanti.
- **Tingkat 3 (remote revoke, butuh internet sesekali, TERISOLASI dari
  logika offline-first lainnya):** 1 file JSON kecil yang dihost developer
  (mis. raw file di GitHub) berisi daftar fingerprint yang dicabut. App
  cek file ini opportunistic (saat dibuka, timeout pendek, gagal-diam
  kalau offline — TIDAK PERNAH memblokir fungsi inti) — kalau fingerprint
  device sendiri ada di daftar, terkunci di kesempatan cek berikutnya
  (bukan realtime/push, app tidak punya server untuk itu).
- **Lubang yang DITEMUKAN & DITAMBAL:** ratchet Tingkat 1 murni bisa
  diakali via "Hapus Data Aplikasi" (reset semua state lokal termasuk
  ratchet) lalu **restore backup DB lama** (fitur backup app ini sendiri)
  yang isinya ratchet versi "masih fresh" — trik replay yang tidak bisa
  ditambal murni lokal (clear-data menghapus SEMUA yang bisa diingat app,
  backup file adalah data eksternal di luar kendali app). **Solusinya
  Tingkat 3** — begitu device itu online lagi, dicek ulang lewat sumber di
  LUAR device, tidak bisa di-replay dari backup.
- **Kunci fitur (locked screen, data aman), BUKAN hapus data** — prinsip
  non-negotiable, konsisten offline-first (tidak ada cloud backup
  terjamin di app ini).
- **Batas jujur:** tidak ada proteksi client-side 100% tahan RE dari
  pihak yang benar-benar niat (root+disassembly) — tapi CI (`build-apk.yml`)
  sudah pakai `flutter build apk --release` (kode mesin ARM native, bukan
  bytecode gampang-dibaca) sebagai aset tahan-RE yang SUDAH ADA tanpa
  kerja tambahan. TIDAK disarankan investasi anti-tamper tambahan
  (risiko false-positive ke pengguna sah tidak sepadan untuk skala
  ancaman individu, bukan grup pembajakan terorganisir).

**UI/UX (final, lihat dokumentasi terpisah untuk detail penuh):**
- Satu layar "Aktivasi Diperlukan" (gerbang lewat `redirect` di
  `routerProvider`, pola sama seperti `/setup`) untuk SEMUA kondisi
  terkunci (belum aktivasi/habis masa/dicabut) — pesan SAMA & netral,
  sengaja tidak membedakan alasan (tidak membocorkan mekanisme
  pencabutan, tidak terasa menuduh). Visual tenang, konsisten dengan
  `WelcomeScreen`/token `AppTheme` yang sudah ada — BUKAN gaya
  DRM/ancaman merah.
- Kartu kode device + tombol "Salin Kode" + tombol "Kirim via WhatsApp"
  (buka WA dengan nomor developer + kode terisi otomatis).
- Field tempel kode aktivasi balasan + tombol "Aktifkan".
- Banner peringatan sebelum masa berlaku habis (H-5/7 hari) — reuse
  `InlineBannerStateMixin` yang sudah ada di banyak screen, BUKAN
  komponen baru.
- Alat generate kode & kelola daftar cabut: skrip lokal sederhana milik
  developer (BUKAN UI di dalam app) — dipakai jarang, cukup satu orang.

**Alasan ditunda (bukan ditolak):** user ingin fokus eksekusi fitur
fungsional (Item 24 + 25a/25b) dulu; 25c sudah matang & bisa dieksekusi
kapan saja user siap, tanpa perlu didiskusikan ulang dari nol.

---

## Item 24 — 6 usulan fitur/penyesuaian (sesi diskusi lanjutan setelah fix Item 23)

**Status:** Semua 6 sub-item sudah disetujui user lewat diskusi (termasuk
beberapa putaran koreksi scope) — siap diimplementasi. Urutan pengerjaan
belum ditentukan; 24a/24c/24e relatif berdiri sendiri & murah, 24b+24d
saling terkait erat (satu fitur, lihat penjelasan di 24d), 24f masih perlu
mockup visual final sebelum coding.

### 24b — Persist + sinkronkan state centang item struk (LIHAT JUGA 24d)
**File:** `lib/features/kasir/receipt_screen.dart` (`_checked`, baris ~80).
Sekarang murni `Map<String, bool>` di memori widget — hilang begitu layar
ditutup atau app di-kill OS.

**Keputusan scope (berubah di tengah diskusi — lihat 24d):** awalnya
diasumsikan cukup persist LOKAL (`SharedPreferences` per `transactionId`,
pola sama seperti `cart_v1_$cartId`), dengan asumsi 1 pegawai tuntaskan 1
order sendiri di 1 device. **Asumsi itu gugur** begitu 24d disetujui (alur
lintas-device: pegawai susun+centang → owner/asisten yang bayar di device
lain). Keputusan final: state centang HARUS ikut sebagai bagian payload
`held_orders` yang tersinkron (bukan `SharedPreferences` lokal lagi) —
supaya owner/asisten bisa lihat progres centang pegawai, ATAU centang
sendiri kalau pegawai belum sempat (keduanya use-case yang disebut user).
Auto-clear checklist saat semua item tercentang (bukan expiry berbasis
waktu — sinyal alami "selesai" lebih masuk akal daripada timer arbitrer).

### 24d — Payment gate untuk role Pegawai (rename kosmetik "Kasir"→"Pegawai" + handoff bayar + notifikasi realtime)
**Konteks:** pegawai yang cuma boleh input barang & cek kelengkapan (TIDAK
boleh terima uang) — pembayaran tetap wajib lewat owner/asisten yang pegang
laci uang.

**⚠️ CATATAN AUDIT PENTING (diminta eksplisit dicatat user):** rename
"Kasir" → "Pegawai" HANYA di label tampilan UI. **Nilai internal
`deviceRole` di database & kode TETAP `'kasir'`** — TIDAK diganti jadi
`'pegawai'`. Alasan: puluhan titik kode (`device.deviceRole == 'kasir'`)
+ data tersimpan di device yang sudah dipasangkan bergantung ke string
persis itu; mengganti nilainya butuh migrasi & berisiko pecah kompatibilitas
sync antar-device beda versi app. **Kalau mengaudit/review kode ini di masa
depan dan menemukan role "Pegawai" di UI tapi `deviceRole: 'kasir'` di
DB/kode — itu BUKAN bug, itu keputusan sadar yang didokumentasikan di sini.**

**Permission baru:** `terima_pembayaran` (nama tentatif), pola PERSIS sama
seperti `override_harga`/`batal_transaksi` yang sudah ada di
`kKasirPermissionKeys` (`app_database.dart`) + `kasir_permissions_screen.dart`.
**Default OFF** (bukan ON) — keputusan sadar user demi minimalkan celah
sejak awal ("kasus saya, pegawai memang tidak seharusnya terima
pembayaran"), owner yang sengaja NYALAKAN kalau mau device tertentu tetap
bisa jadi kasir penuh.

**DITOLAK (scope lebih besar yang sempat diusulkan, lalu dibatalkan
user):** permission PER-DEVICE individual (ditentukan saat pairing, bukan
kebijakan global-per-role). Alasan ditolak: tabel `KasirPermissions`
sekarang eksplisit "global untuk role, bukan per-user" (`settings_tables.dart`
baris 3) — upgrade ke per-device butuh ubah skema (kolom relasi device) +
ubah makna layar Izin Kasir/Izin Asisten dari "kebijakan toko" jadi
"daftar pegawai individual". User pilih TETAP model global demi
kesederhanaan & risiko lebih kecil — **jangan re-litigasi ide per-device
ini tanpa alasan baru yang kuat**, sudah dipertimbangkan & sengaja
ditolak.

**Alur "Bayar" untuk pegawai tanpa izin `terima_pembayaran`:** tombol
"Bayar" di keranjang berubah jadi **"Kirim ke Owner/Asisten"**. TIDAK
reuse mekanisme "Tempel Pesanan"/pause pribadi yang sudah ada (itu tetap
harus jalan normal & terpisah untuk kebutuhan pegawai sendiri) — sebagai
gantinya, buat entri `held_orders` dengan **penanda jenis baru** (mis.
kolom/flag `awaitingPayment` atau semacamnya) yang beda dari hold biasa.
Entri ini muncul di antrian tertahan milik owner/asisten (tersinkron LAN),
dengan **nama pegawai + timestamp di atas card** (beda visual dari hold
biasa — badge/warna aksen berbeda, mis. "Menunggu Anda Bayar"). Owner/
asisten buka & proses bayar normal di device sendiri.

**Notifikasi realtime ke pegawai:** begitu owner/asisten selesaikan
pembayaran, device pegawai yang mengirim tadi dapat notifikasi in-app
real-time "Transaksi [no. nota] lunas" — **LEWAT LAN yang sudah ada**
(bukan push notification OS/cloud — itu butuh FCM/internet, bertentangan
dengan prinsip app "tanpa backend cloud", SUDAH dikonfirmasi user bukan
yang dimaksud). Nyambung erat ke **Item 21** (sync UI persisten + banner
shell) yang sudah lama menggantung — pertimbangkan kerjakan bareng/setelah
Item 21 karena infrastrukturnya tumpang tindih (state sync global,
provider realtime).

**Mockup desain (rush-hour flow, non-blocking):** ada prototipe visual
interaktif dibuat sesi ini — HP kasir tampilkan pill status "menunggu
konfirmasi" TANPA menghalangi kasir lanjut kerja; HP owner tampilkan
badge+sheet dengan tombol "Setujui" besar (jalur utama) + isyarat geser-
untuk-approve (percepatan opsional, bukan wajib). Tidak disimpan sebagai
file permanen di repo — regenerasi kalau perlu rujukan visual lagi saat
implementasi.

### 24e — Tap-to-scan (mode Sekali maupun Berulang)
**File:** `lib/features/kasir/kasir_screen.dart` (area scanner kamera,
`MobileScanner`). Tambah sebagai **opsi tambahan** (toggle), BUKAN
pengganti default — continuous-scan tetap default (kecepatan = nilai jual
utama scanner kasir), tap-to-scan untuk situasi presisi lebih penting
(rak dengan banyak barcode berdekatan, rawan salah pindai kalau auto-
continuous).

### 24f — Redesign kontrol scanner: kapsul melayang in-frame, BUKAN titik-tiga (BELUM final, perlu 1 revisi visual)
**File:** `lib/features/kasir/kasir_screen.dart` (baris ~1084-1124: AppBar
title mode + tombol flash + `PopupMenuButton` berisi toggle Berulang +
pilihan durasi toast — semua sekarang terkubur di menu titik-tiga).

**Referensi gaya (dari screenshot user, kamera bawaan MIUI):** BUKAN satu
panel besar berisi banyak baris (draft awal sesi ini, sudah ditolak
implisit) — melainkan **kapsul-kapsul kecil terpisah yang melayang tipis**
langsung di atas feed kamera (persis seperti pill zoom "0.6 · 1X · 2" di
screenshot), bukan dibungkus 1 kotak pengaturan besar.

**BELUM SELESAI:** perlu 1 putaran revisi mockup visual mengikuti gaya
kapsul-melayang ini sebelum implementasi — jangan langsung coding dari
draft panel-besar yang sudah dikoreksi user.

---

## Konteks — kenapa semua item di bawah ini muncul

User punya dataset toko lama (`docs/reference/Contoh_Dataset.rar`,
`docs/reference/Products.csv`) yang ingin dipindahkan ke The POS: katalog
produk, data pelanggan + poin loyalty, dan riwayat transaksi. Diskusi dimulai
dari 3 pertanyaan (mekanisme update data berkala, dropdown pelanggan tidak
scrollable, bug pencarian nama pelanggan) yang ternyata saling terkait dan
mengarah ke beberapa temuan bug nyata di importer CSV yang sudah ada.

**Prinsip yang disepakati:** Claude TIDAK punya akses berkelanjutan ke
database toko (offline-first, terenkripsi SQLCipher, HP user adalah satu-
satunya sumber kebenaran). Jadi update data dari dataset selalu berbentuk:
user kirim data mentah → Claude olah/format jadi bentuk yang bisa diimpor →
user jalankan import sendiri di app lewat fitur yang sudah ada (atau yang
akan dibangun). Bukan Claude yang menulis langsung ke database terenkripsi.

---

## Item 23 — Sisa lokasi lain yang masih pakai `paid` mentah (double-count kembalian reuse)

**Konteks:** user laporkan "Sisa Tagihan" di struk salah hitung (understated)
saat kembalian yang sudah pernah diberikan dipakai ulang sebagai pembayaran
item tambahan — akar masalah: `paid` (Σ semua pembayaran) menghitung uang
yang sama 2× (masuk sbg pembayaran baru, tanpa pernah dikurangi saat keluar
sbg kembalian sebelumnya). **Sudah diperbaiki** (`19e679d` + susulan
`87cdaf0`, 12 Juli) untuk: status `kurang_bayar`/`lunas`
(`_reconcileTransactionTotals`, `addPaymentToTransaction`) + tampilan "Sisa
Tagihan"/"Sisa hutang" DAN "Dibayar" di `receipt_screen.dart` (Ringkasan,
prefill dialog Tambah Bayar, struk cetak/gambar untuk Sisa saja) via helper
`netRemainingOwed()`/`netPaidDisplay()`. **Pelajaran dari `87cdaf0`**: kalau
nanti perbaiki tempat lain di bawah, cek SEMUA baris nominal terkait di
layar/struk yang sama (bukan cuma "Sisa"-nya) — "Dibayar" sempat kelewat
diperbaiki sekalian padahal satu card yang sama dengan "Sisa Tagihan",
ketahuan user karena Total != Dibayar+Sisa jadi tidak nyambung.

**Scope yang SENGAJA belum disentuh** (dipilih user lewat poll — fokus dulu
ke laporan spesifik, bukan sapu bersih semua turunan `total-paid`):
- **Buku Hutang** (`getDebtBook`, `getUnpaidTxDetails` di app_database.dart)
  — angka hutang pelanggan bisa understated dengan pola bug yang SAMA
  (belum diverifikasi/diperbaiki).
- **`settleMergedDebt`** (engine pelunasan hutang gabungan Buku Hutang) —
  variabel `sisa` di dalamnya pakai `tx.total - tx.paid` mentah juga.
- **Tutup Kasir** (`getTodayCashRecap`, dipakai `tutup_kasir_screen.dart`)
  — TEMUAN LEBIH LUAS: "kas sistem" dihitung dari `SUM(paid)` mentah tanpa
  dikurangi kembalian SAMA SEKALI, bahkan di transaksi normal TANPA reuse
  kembalian — dugaan kuat "kas sistem" selalu overstated sebesar total
  kembalian harian. Ini BEDA kategori dari bug reuse (lebih fundamental,
  berpotensi bikin Tutup Kasir selalu "selisih" di toko manapun yang kasih
  kembalian) — belum dikonfirmasi user apakah ini disengaja atau bug,
  belum ada fix.
- Tempat lain yang masih pakai pola `tx.total - tx.paid` mentah: `printer_
  service.dart` (2×, struk cetak ESC/POS asli — beda dari `_ReceiptPaper`
  di receipt_screen.dart yang SUDAH diperbaiki), `transaksi_tab.dart` (2×,
  tab Laporan → Transaksi), `tx_history_sheet.dart` (3×, riwayat transaksi
  di kasir), `merged_receipt_screen.dart` (nota gabungan).

**Kalau ada laporan bug lanjutan dari salah satu tempat di atas**, akar
masalahnya kemungkinan besar SAMA (pola `total-paid` mentah) — cek dulu
apakah cukup diterapkan pola `netRemainingOwed()`-style (paid dikurangi Σ
changeGiven) sebelum investigasi dari nol. **PENTING kalau nanti fix
Tutup Kasir:** jangan asal kurangi `SUM(paid)` dengan Σ changeGiven murni —
perlu pikirkan ulang apakah "kas sistem" harus juga netral terhadap
`changeTaken` (kembalian yang belum diambil vs sudah), karena itu
memengaruhi apakah uangnya SUNGGUHAN sudah keluar dari laci fisik atau
belum.

---

## Item 3 — SEBAGIAN SELESAI (superseded oleh fitur "Import dari Griyo POS")

3a (delimiter `;`, alias header "Produk"/"Kode Produk"/"Grup Produk"/
"Harga Jual"/"Harga Pokok", ID satuan/grup legacy mentah) **SUDAH
DIPERBAIKI** — lihat CHANGELOG `63d0f2d`. 3b (auto-gabung baris nama-sama-
satuan-beda jadi 1 produk multi-satuan) **DITOLAK user** — keputusan final:
import tetap FLAT, counter `sameNameDifferentUnit` menandai kandidat gabung
manual (rasio konversi antar satuan memang tidak ada di CSV Griyo, jadi
auto-gabung berisiko rasio salah/tersembunyi).

**Sisa terbuka (prioritas rendah):** 3c — kolom "Non Stok" dari export
Griyo masih belum dibaca sama sekali oleh `csv_import_service.dart` (semua
produk hasil import selalu `isNonStock: false`). Belum ada laporan dampak
nyata dari user; kerjakan kalau ada keluhan konkret.

---

## Item 4 — Import pelanggan dari Griyo POS (fitur eksperimental, ANALISIS SELESAI — implementasi BELUM dimulai)

**Prioritas:** Siap dikerjakan — sumber data & keputusan besar sudah ada,
tinggal 1-2 keputusan kecil sebelum coding (lihat di bawah).

**Sumber data dianalisis:** `Pelanggan.xlsx` (Griyo POS), 493 baris, 1 sheet.
Kolom: `Pelanggan, Alamat, Telepon, Barcode, Keterangan, Poin, Piutang`.
Semua kolom tersimpan sebagai TEXT di file (termasuk Poin & Piutang yang
seharusnya angka) — parser perlu `double.tryParse`, BUKAN `int.tryParse`,
karena minimal 1 baris Piutang dalam notasi ilmiah (`"1.23745e+06"`) yang
akan gagal-diam-diam-jadi-0 kalau dipakai `int.tryParse`.

**Kecocokan skema `Customers`:** `Pelanggan`→`name`, `Alamat`→`address`,
`Telepon`→`phone`, `Poin`→`loyaltyPoints`, `Keterangan`→`notes` (kosong
semua di file ini). `Barcode` (kartu member) **tidak ada field setara**
di skema `Customers` sekarang — The POS belum punya fitur kartu
member/barcode pelanggan sama sekali; datanya toh nyaris kosong (1/493
baris) jadi kemungkinan besar cukup diabaikan.

**Keputusan yang SUDAH DIJAWAB user:**
1. **Piutang lama dari Griyo (327 pelanggan berpiutang) — TIDAK dibawa.**
   Import nama/alamat/telepon/poin saja, piutang mulai dari nol bersih di
   The POS. (Alasan yang dipertimbangkan: `customers.outstandingDebt` cuma
   cache lama — tab Buku Hutang menghitung fresh dari transaksi asli, jadi
   kalau field itu diisi langsung dari Griyo akan muncul di badge pelanggan
   TAPI TIDAK di Buku Hutang, dua tempat beda angka. User pilih untuk tidak
   membawa data ini sama sekali daripada membuat transaksi tempo pembuka
   sintetis.)
2. **Baris bernama "-" dengan Piutang ~Rp1,2 juta (bucket pelanggan
   umum/tanpa nama Griyo) — DILEWATI**, tidak diimport sebagai pelanggan.

**Sisa keputusan kecil (belum ditanyakan/dijawab eksplisit, ambil default
masuk akal saat implementasi kecuali user koreksi):**
- **17 nama duplikat** (mis. "Bu Ika" 2x) — sudah dicek manual pakai kolom
  Alamat: mayoritas memang orang BEDA (panggilan sama, lazim di kampung).
  Beberapa ambigu (alamat sama-sama kosong/nyaris identik: "Mbak Dwi",
  "Suhar", "Tantowi"). Default: import apa adanya sebagai entri terpisah
  (tidak bisa dibedakan otomatis dari data yang tersedia) — user gabung
  manual via UI kalau ternyata orang yang sama.
- **23 nama dengan whitespace nyasar** (mis. `"Bu Abi "`) — trim saat
  import supaya tidak dianggap beda dari pencarian nama tanpa spasi.
- **Piutang blank (bukan "0")** untuk 166 baris — treat sebagai 0 (tidak
  relevan lagi karena Piutang keputusan #1 di atas: tidak dibawa sama
  sekali).

**File yang kemungkinan terlibat:** file BARU, kemungkinan
`lib/core/services/customer_import_service.dart` (pola sama seperti
`csv_import_service.dart`, tapi untuk `.xlsx` bukan `.csv` — perlu cek
package excel yang sudah dipakai project, lihat §Stack di CLAUDE.md).
UI: entry baru di Pengaturan → Eksperimental (pola sama seperti "Import
dari Griyo POS" produk).

**Gotcha wajib diwariskan dari bug import produk (Item terbaru, `e4baa92`):**
`ProductUnitsCompanion` yang dibuat importer HARUS eksplisit set field yang
constraint lain di app diam-diam mengasumsikan ada nilainya (kasus produk:
`isBaseUnit`) — kalau ada pola serupa di `Customers`/relasi terkait
(mis. field yang beberapa layar UI baca dengan fallback tapi ada SATU layar
yang tidak), cek dulu SEMUA titik baca sebelum importer selesai, jangan
cuma tes "tab pelanggan muncul" lalu anggap beres.

---

## Item 5 — Import riwayat transaksi dari dataset lama (fitur baru + jadi data stress-test nyata)

**Prioritas:** Setelah Item 3 selesai (lihat alasan ketergantungan di
3b — bug dedup importer di Item 2 sudah selesai dikerjakan, lihat
CHANGELOG). User sudah konfirmasi punya beberapa file rentang tanggal (bukan cuma
satu hari), tapi **belum diketahui apakah cakupannya mendekati riwayat penuh
toko (Maret 2024–sekarang, sesuai rekap bulanan di file `Penjualan`) atau
cuma beberapa sampel** — perlu dikonfirmasi user sebelum estimasi skala
pekerjaan pencocokan produk final dibuat.

**Konteks penemuan:** User awalnya bertanya kenapa hasil ekstraksi riwayat
transaksi dulu membuat struk kosong (cuma nominal, tanpa rincian item).

**Root cause struk kosong (dikonfirmasi):** File `docs/reference/.../
Penjualan <rentang>.xlsx` yang tersedia adalah **rekap agregat BULANAN**
(kolom: Bulan, Penjualan, Transaksi, Item, Diskon, Biaya admin, Laba) — satu
baris = satu bulan, TIDAK ADA nama produk atau rincian item sama sekali di
file ini. Kalau file inilah yang dulu dipakai sebagai sumber import
transaksi, struk pasti kosong rinciannya karena informasinya sendiri sudah
tidak ada di sumbernya (bukan bug proses import).

**Kabar baik — ditemukan file lain yang jauh lebih detail:** file
`Transaksi <rentang-tanggal>.xlsx` (contoh yang sudah dicek:
`Transaksi 2026-06-10_2026-06-11 2026-06-10.xlsx`) punya struktur PER
TRANSAKSI dengan kolom:
```
Tanggal | ID | Pelanggan | Subtotal | Diskon | Total | Pembayaran |
Biaya admin | Laba | Poin | Pegawai | Catatan Internal | Catatan Struk | Rincian
```
Kolom **"Rincian"** berisi rincian item sebagai teks bebas, format
`NamaProduk:Qty` dipisah baris baru (`\n`) di dalam satu sel, contoh:
```
Minyak Filma:1
Intermie:5
Power F:1
Golda:4
...
```
(Nota #13164 milik "Mbak Ima" — nama yang sama dengan kasus pencarian di
Item 1, ditemukan langsung sebagai bukti nyata di dataset ini.)

**Kenapa item ini bernilai ganda:**
1. Mengembalikan rincian struk yang hilang (tujuan awal).
2. Karena ini data transaksi ASLI (bukan dummy/buatan), begitu masuk
   database ini otomatis jadi uji beban NYATA untuk seluruh aplikasi:
   pencarian riwayat transaksi, laporan, kartu poin pelanggan, performa
   daftar (grid/list) — semuanya teruji dengan volume & pola yang benar-
   benar terjadi di toko user, bukan skenario buatan yang bisa saja meleset
   dari kondisi sesungguhnya.

**Ketergantungan (urutan tidak boleh dibalik):** HARUS dikerjakan setelah
Item 3 terutama 3b (fix rasio multi-satuan) selesai. Alasan: pencocokan
nama produk di kolom "Rincian" bergantung penuh pada katalog yang sudah
lengkap & berstruktur benar. Kalau strukturnya kacau (Item 3b — "Sedap
Goreng" jadi banyak entitas tak berhubungan), baris rincian transaksi yang
menyebut produk itu otomatis ikut gagal/salah cocok juga — bug akan menumpuk
kalau urutan pengerjaan dibalik.

**Risiko/keputusan yang perlu diantisipasi saat implementasi (belum
diputuskan):**
- Nama produk di "Rincian" bisa ambigu kalau produk itu ternyata punya
  beberapa satuan/varian dengan nama sama (persis kasus "Sedap Goreng" per
  dus vs per biji). Perlu aturan: default ke satuan dasar? Tandai untuk
  direview manual kalau ambigu?
- Baris item yang nama produknya sama sekali tidak ketemu di katalog
  (produk sudah dihapus/berganti nama sejak transaksi itu terjadi asli) —
  dilewati dengan catatan, atau dibuat "produk tak dikenal" sebagai
  placeholder?
- Kolom "Poin" di file — direkonstruksi ke ledger poin pelanggan juga, atau
  cukup catatan transaksinya saja tanpa menyentuh poin (untuk menghindari
  dobel-hitung kalau poin di app sekarang sudah berbeda dari saat itu)?
- Ini akan jadi jalur "import transaksi" PERTAMA di aplikasi — pekerjaan
  baru dari nol, bukan modifikasi importer yang sudah ada.

**File yang kemungkinan terlibat (belum pasti):** file BARU, kemungkinan
`lib/core/services/transaction_import_service.dart`. Perlu menulis ke
`transactions`, `transaction_items`, kemungkinan `loyalty_point_ledger`.

---

## Item 8 — Bawa UI/UX "pilih harga" modal ItemEntrySheet ke halaman HTML (didiskusikan, BELUM diputuskan)

**Status:** Masih tahap diskusi kelayakan — user bertanya "bisakah", belum
ada keputusan scope final. Dicatat supaya tidak hilang dari radar.

**Ide:** modal `ItemEntrySheet` di tab Kasir (tap badan produk) sudah punya
UI pilih harga yang cukup kaya: chip horizontal untuk satuan + tier grosir +
harga alternatif (`_PriceChip`), qty stepper, dst. User bertanya apakah UI/UX
serupa ini bisa juga ditambahkan ke halaman HTML Katalog Pesanan (yang saat
ini pemilihan varian di HTML masih pakai `<details>` dropdown sederhana +
stepper polos, tanpa konsep "harga lain"/tier grosir sama sekali).

**Trade-off yang perlu dipertimbangkan sebelum lanjut (belum final,
menunggu keputusan user):**
- **Kompleksitas vs manfaat:** HTML katalog ini sengaja dibuat SEDERHANA
  (statis, tanpa framework, tanpa build step) supaya tetap ringan & mudah
  dirawat sebagai satu file. Menambahkan sistem "harga lain"/tier grosir ke
  sana berarti duplikasi LOGIKA price-resolving (`PriceService`) ke JS
  murni — dua tempat yang harus dijaga tetap sinkron kalau logika harga
  berubah di masa depan.
  - **Kaitan dengan optimasi performa HTML yang sudah dikerjakan** (debounce
    cari, update per-baris, dll — lihat CHANGELOG): semakin banyak
    UI/interaktivitas ditambahkan ke HTML ini, semakin besar risiko masalah
    performa serupa muncul lagi di tempat baru — perlu diperhatikan bareng,
    bukan ditambah dulu baru dioptimasi belakangan.
- **Relevansi ke pelanggan vs ke kasir:** tier grosir/harga alternatif itu
  fitur yang biasanya dipakai KASIR/OWNER untuk situasi tawar-menawar
  khusus, bukan sesuatu yang biasanya perlu dipilih PELANGGAN sendiri saat
  memesan dari HP-nya. Perlu dipikirkan: apakah relevan pelanggan melihat/
  memilih opsi harga alternatif sendiri, atau ini cuma perlu tetap jadi
  keputusan kasir saat pesanan diproses di tab Kasir (lewat "Tempel
  Pesanan")?
- **Menunggu keputusan user** sebelum ada rencana teknis lebih rinci.

---

## Item 17 — Persist antrian approval sync + majukan watermark upload (revisi dari catatan "ACK" lama)

**Prioritas:** Sedang. **Disetujui arah oleh user** (usul: simpan state
seperti pesanan tertahan). Menggantikan catatan lama di HANDOFF yang keliru
membingkai ini sebagai "sync satu arah tanpa ACK".

**Kondisi riil (dikoreksi setelah baca ulang `lan_sync_service.dart`):** sync
SUDAH dua arah, host SUDAH punya hak review (antrian approval manual, bukan
auto-merge), arah host→klien SUDAH pakai watermark (`last_sync_download_at`).
Yang jadi akar masalah SEMPIT: `_pendingQueue` (baris ~79) adalah
`static final [...]` — **cuma di memori host**. Kalau host restart sebelum
owner approve, antrian hilang. KARENA itu arah klien→host sengaja tetap
**full-dump** selamanya (komentar eksplisit baris ~486-498) sebagai pengaman —
bukan karena bidirectionality belum ada.

**Solusi:** persist `_pendingQueue` ke tabel DB baru (pola sama seperti
`held_orders` yang selamat dari app-kill). Urutan KRITIS yang harus dijaga:
simpan ke DB **sebelum** host membalas "diterima" ke klien (di handler baris
~421-447). Begitu itu dijamin, watermark upload klien boleh dimajukan →
klien berhenti kirim-ulang seluruh riwayat tiap sync.

**Klarifikasi timeout WiFi (dari pertanyaan user):** BUKAN masalah — koneksi
HTTP klien ditutup langsung setelah host membalas `pending_approval` (baris
431-447), approval terjadi async tanpa koneksi terbuka. Jadi tidak ada
sambungan yang digantung menunggu owner.

**File:** `lib/core/services/lan_sync_service.dart`, tabel baru + migrasi
`app_database.dart` (schemaVersion naik).

---

## Item 21 — Sync UI persisten lintas tab + status progres (global state)

**Prioritas:** Sedang. **Proposal user, DISETUJUI PENUH** — status progres
(Menyambung → Mengirim → Menunggu persetujuan) dikonfirmasi user persis
gambaran yang diinginkan. Refactor menengah.

**Temuan tambahan (lebih dalam dari keluhan user):** `sync_screen.dart`
`dispose()` (baris 42-43) memanggil `LanSyncService.stopHost()` → meninggalkan
layar Sync mematikan server host TOTAL, bukan cuma UI-nya hilang. State sync
(`_syncing`, `_queue`) juga lokal ke layar.

**Solusi:** angkat state sync ke **provider global Riverpod**, lepaskan
lifecycle host dari `SyncScreen`, render **banner inline persisten di level
shell** (`main_shell.dart`) yang bertahan di tab/halaman manapun sampai proses
selesai/dibatalkan (baik sisi host maupun klien).

**Soal "tidak realtime" (antrian muncul sekaligus) — batasan protokol:**
klien kirim SEMUA tabel dalam SATU request HTTP, jadi di host memang datang
sekaligus. "Realtime per-baris" TIDAK mungkin tanpa merombak protokol.
Yang bisa & sebaiknya diperbaiki: status progres sisi KLIEN (Menyambung →
Mengirim → Menunggu persetujuan) + animasi halus saat item baru masuk antrian
host. Jangan overpromise "per baris".

**File:** provider baru (mis. `lib/core/providers/sync_state_provider.dart`),
`lib/core/services/lan_sync_service.dart`, `lib/features/shell/main_shell.dart`,
`lib/features/pengaturan/sync_screen.dart` (baca dari provider global).

---

## Catatan lintas-item — perbaikan UX permission (murah, opsional)

Dari audit flow permission (bonus request user): perubahan izin owner **tidak
instan** ke HP kasir — baru berlaku setelah sync manual berikutnya (izin
mengalir sebagai master-data owner→kasir). UX-nya membingungkan ("sudah saya
matikan kok kasir masih bisa?"). Perbaikan murah: tambah teks info
"Perubahan berlaku setelah HP kasir sync berikutnya" di `kasir_permissions_screen.dart`
& `asisten_permissions_screen.dart`.

---

## Status ringkas & urutan sisa pekerjaan

**Item 9-22 (backlog audit besar 10-11 Juli) — SELESAI 12/13**, lihat
CHANGELOG untuk hash tiap item. Sisa satu: **Item 17+21 (sync)** — lihat
detail lengkap di atas, sengaja ditunda ke sesi fokus (risiko data-loss di
"majukan watermark upload" butuh test round-trip HTTP asli).

**Item lain yang masih terbuka:**
1. **Item 4** (import pelanggan Griyo) — analisis + keputusan besar SELESAI,
   siap diimplementasikan (lihat detail di atas).
2. **Item 3c** (kolom "Non Stok" diabaikan importer produk) — prioritas
   rendah, tunggu keluhan konkret.
3. **Item 5** (import riwayat transaksi dari dataset lama) — perlu
   konfirmasi user soal cakupan tanggal file `Transaksi ...xlsx` sebelum
   mulai; dependensi ke Item 3b (rasio multi-satuan) sekarang longgar
   karena user sudah memilih flat-import tanpa auto-gabung.
4. **Item 8** (bawa UI pilih-harga ke katalog HTML) — masih tahap diskusi
   kelayakan, menunggu keputusan user soal trade-off kompleksitas.
