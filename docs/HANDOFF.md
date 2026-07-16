# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 16 Juli 2026. Sesi 15 Juli: batch 14 item bugfix/
redesign/fitur kasir & katalog (lihat ringkasan di bawah). Sesi susulan 16
Juli: redesign header struk (Item 7) SELESAI diimplementasi (`eb7da72`),
plus 3 fix susulan kecil — nama produk struk bold (`87b8c42`), alamat
pelanggan belum tampil di dropdown cart bar (`f098fa4`), **poin loyalitas
sekarang kumulatif saat Tambah Belanjaan** (`32d017e`, lihat detail di
bawah — ini yang paling signifikan). Full `flutter test` **381 test
hijau**, `flutter analyze` bersih. schemaVersion masih 15 (tidak ada
migrasi baru). Branch `claude/setup-dependencies-am31te` — belum di-merge
ke `main` (tunggu instruksi user)._

## Poin loyalitas kumulatif saat Tambah Belanjaan (16 Juli, susulan)

User lapor: poin loyalitas tidak ikut bertambah saat "Tambah Belanjaan"
menaikkan total nota yang SUDAH pernah dapat poin sebelumnya. Akar
masalah: `awardLoyaltyPointsIfEligible` (`app_database.dart`, awalnya
dibuat utk bug lain — lihat commit sebelumnya soal ganti pelanggan Umum→
terdaftar di struk) punya guard `if (tx.pointsEarned > 0) return;` —
idempotent tapi TERLALU agresif, bikin nota yang sudah dapat poin sekali
TIDAK PERNAH dapat tambahan lagi walau totalnya naik banyak lewat item
susulan.

**Fix**: method diubah jadi hitung ulang poin TARGET dari `tx.total`
terkini (`floor(total/threshold)*pointsPer`), lalu tambahkan SELISIH
(`target - tx.pointsEarned`) — bukan lagi all-or-nothing. Aman dipanggil
berkali-kali dgn total sama (selisih 0 → no-op, perilaku lama utk kasus
non-Tambah-Belanjaan tetap sama persis). `_confirmAddItems`
(`payment_screen.dart`) memanggil method ini lagi setelah
`addItemsToTransaction`, pakai `customerId` tx yang di-fetch fresh
(mode Tambah Belanjaan selalu warisi pelanggan transaksi asli, tidak
pernah diubah).

**PENTING kalau nanti ada bug loyalty lain**: method ini sekarang jadi
"recompute + top-up", BUKAN "award sekali doang" — kalau ada tempat lain
yang butuh pola serupa (mis. retur sebagian yang menurunkan total), method
ini SENGAJA tidak claw-back poin kalau total turun (`delta <= 0` →
no-op, tidak pernah mengurangi) — pengurangan poin akibat void/retur sudah
ditangani jalur terpisah (`voidTransaction`, proporsional) yang TIDAK
disentuh sesi ini.

Test: `test/award_loyalty_points_customer_change_test.dart` (tambah 1 test
DB-tier baru utk skenario kumulatif, 4 test lama tetap hijau tanpa
diubah) + `test/tambah_belanjaan_loyalty_points_test.dart` (BARU,
end-to-end lewat `PaymentScreen(addToTxId:)` sungguhan — tap "Bayar X" →
"Uang Pas" → "Bayar", verifikasi `tx.pointsEarned`/`customer.loyaltyPoints`
naik sesuai selisih, bukan dobel/tetap). Revert-verify dijalankan di
kedua level (DB murni + widget end-to-end).

## Alamat pelanggan — 1 dropdown lagi ketinggalan (16 Juli, susulan)

Sesi sebelumnya (batch 14-item) sudah menambah alamat pelanggan di bawah
nama pada dropdown `payment_screen.dart` & `receipt_screen.dart`, TAPI
ada satu dropdown lagi yang terlewat: `showCustomerPickerSheet`
(`lib/features/kasir/widgets/cart_meta_pickers.dart`) — dipakai dari
`_CartMetaTab` di cart bar kasir (BEDA file/BEDA widget dari 2 dropdown
yang sudah diperbaiki). Kalau nanti ada laporan serupa lagi ("alamat
belum tampil di [tempat X]"), curigai ADA dropdown pelanggan lain yang
belum ke-cover — cek semua pemakaian `searchCustomers`/pola
`ListTile(title: Text(c.name), subtitle: ...)` di codebase, jangan
asumsikan cuma 2 tempat yang sudah diperbaiki sudah cukup.

Test: `test/cart_meta_customer_picker_address_test.dart`.

## Redesign header struk (Item 7 lama) — SELESAI diimplementasi (16 Juli)

Desain final disepakati user lewat BEBERAPA putaran mockup (jauh lebih
banyak iterasi dari perkiraan awal — arah desain berubah signifikan di
setiap putaran, JANGAN kaget kalau pola serupa terulang di redesign lain).
Urutan keputusan (kalau perlu telusuri histori diskusi, cek riwayat chat
sesi 15-16 Juli, bukan cuma commit ini):
1. Awalnya: chip status dgn gaya "kertas dijepit" (3 opsi A/B/C).
2. Direvisi jadi stempel bulat teks melengkung — DITOLAK user, minta
   bentuk kotak persis foto referensi asli yang dikirim user.
3. Direvisi jadi stempel kotak (double border, tepi kasar) menempel di
   sudut kanan-atas kartu item (simetris `ItemCountBadge`) — TERNYATA
   menutupi nama+harga baris item pertama, ketahuan dari screenshot.
4. Diperbaiki dulu (padding-top kartu dinaikkan) — TAPI user lalu usul
   pendekatan BEDA sepenuhnya: jadikan **watermark** (bukan lagi elemen
   menempel di sudut) supaya dijamin tidak PERNAH menutupi apapun,
   berapa pun panjang daftar itemnya.
5. Watermark pertama (teks polos, lurus, tanpa border) — user minta
   kembali ke bentuk stempel asli (double border + tekstur) tapi
   diperlakukan sbg watermark (besar, samar, di belakang teks) — inilah
   arah FINAL yang diimplementasi.
6. Terakhir: ukuran watermark diperkecil (78% → 46% lebar kartu, opacity
   dinaikkan 16%→22% biar tetap kebaca meski lebih kecil).

**Implementasi final** (`receipt_screen.dart` + `lib/core/widgets/
status_watermark_stamp.dart` baru):
- Header status besar "Transaksi Berhasil"/"Transaksi Tempo" + `Container`
  ber-`Icon` DIHAPUS TOTAL dari atas kartu.
- Widget baru `StatusWatermarkStamp`: stempel kotak (double border via
  `CustomPainter`, tepi "kasar/bertinta" dari dash acak ber-seed tetap —
  DETERMINISTIC, bukan `feTurbulence` SVG asli krn Flutter tidak
  punya API itu), teks "LUNAS"/"TEMPO" + nomor nota (`tx.localId`) baris
  kedua, dirotasi -11° via `Transform.rotate`, opacity 0.22.
  Warna: `AppTheme.payGreen` (lunas) / `scheme.error` (tempo/kurang_bayar).
- Watermark ditaruh di dalam `Stack` yg SAMA dgn baris item
  (`_buildItemRows`), sbg child **non-Positioned** (bukan
  `Positioned.fill`!) — gotcha ketemu saat implementasi: `Positioned.fill`
  memaksa watermark ikut tinggi Stack (bisa sependek 1 baris item kalau
  notanya cuma 1 barang), bikin teks 3-baris overflow. Fix: pakai
  `Stack(alignment: Alignment.center)` biasa + `FractionallySizedBox
  (widthFactor: 0.46)` tanpa height constraint, supaya watermark bebas
  menentukan tinggi alaminya sendiri terlepas dari tinggi Stack.
- `ItemCountBadge` (badge jumlah item, sudut kiri-atas) **TIDAK DIUBAH**.
- "Tandai Semua" (`TextButton.icon` lama) diganti `Container` lingkaran
  solid hijau (`AppTheme.payGreen`) 34px, persis gaya `ItemCountBadge`,
  dgn `Tooltip` (bukan `Text` label) — kalau butuh assert di widget test,
  pakai `find.byTooltip('Tandai Semua')`, BUKAN `find.text(...)`.
- `merged_receipt_screen.dart` (struk gabungan) **SENGAJA TIDAK ikut
  disentuh** — belum ada keputusan/permintaan user apakah nota gabungan
  ikut redesign ini.

Test baru: `test/receipt_status_watermark_test.dart` (label/warna/serial
watermark utk status lunas & tempo, header lama tidak ada lagi) + update
`test/item_count_display_test.dart` (assertion "Tandai Semua" ganti dari
`find.text` ke `find.byTooltip`). Revert-verify sudah dijalankan (label
lunas/tempo ditukar sengaja → test gagal tepat; header lama disisipkan
balik sementara → test gagal tepat) sebelum dianggap selesai.

Mockup sumber (scratchpad sesi ini, TIDAK di-commit — kalau perlu
regenerasi lain waktu, deskripsi di atas + kode final di
`status_watermark_stamp.dart` sudah cukup, tidak perlu lihat mockup lagi):
`struk_header_mockup.html/.jpg` (v1, 3 opsi awal) → `_v2` (stempel bulat,
ditolak) → `_v3` (stempel kotak nempel sudut, lalu diperbaiki
clearance-nya) → `_v4` (watermark teks polos) → `_v5` (watermark bentuk
stempel — FINAL, 2 iterasi ukuran).

## Ringkasan sesi ini (14 item dari 1 pesan user)

User kirim 14 laporan/pertanyaan/redesign sekaligus, instruksi eksplisit:
"berikan opini dulu" → user balas dengan keputusan spesifik per-poin → lalu
"poin yang tidak saya sebut atau sudah saya konfirmasi, kerjakan. poin yang
masih dipertimbangkan diskusikan. mockup design kerjakan". Hasil:

**Dikerjakan (kode, commit terpisah per tema):**
- Label verbose diringkas ("Pegawai (yang melayani)" → "Pegawai").
- Field Pelanggan & Pegawai di modal checkout disejajarkan (`Row`+`Expanded`,
  bukan ditumpuk) — `payment_screen.dart`.
- Qty desimal (0,25) di stepper `AddControl` tidak proper → `FittedBox`
  auto-shrink font, badge TETAP bulat (keputusan eksplisit user: "shrink
  saja, karena bulat dibutuhkan") — juga diperbaiki di toast scan kontinu
  (`kasir_screen.dart`) & katalog HTML (`order_page_service.dart`).
- Warna tombol "Bayar" disamakan antara modal checkout & in-app struk
  (`AppTheme.payGreen` baru, dipakai juga di `debt_payment_dialog.dart`).
- **Bug poin loyalitas**: ubah pelanggan Umum→terdaftar di STRUK (bukan
  saat checkout) tidak pernah memberi poin — diekstrak
  `AppDatabase.awardLoyaltyPointsIfEligible()` (idempotent), dipanggil dari
  `receipt_screen.dart` `_saveCustomer`.
- Tombol "Transaksi Baru" di struk dihapus (redundan dgn tab kasir).
- Alamat pelanggan ditampilkan di bawah nama di SEMUA dropdown/list saran
  pelanggan (payment_screen & receipt_screen) — cegah salah pilih nama kembar.
- Debounce anti-missclick di `AddControl` (150ms, berbasis `Timer` bukan
  `DateTime.now()` — WAJIB `Timer` supaya testable dgn `tester.pump`,
  `DateTime.now()` TIDAK ikut virtual clock widget test).
- Countdown lisensi di Pengaturan (`LicenseState.remainingLabel`/
  `licenseStatusLabel`, auto-scale hari→jam→menit).
- Toggle direct WhatsApp (wa.me ke nomor toko) vs share generik
  (`api.whatsapp.com/send` tanpa nomor) untuk katalog HTML — setting baru
  `katalog_wa_direct` di `order_share_screen.dart`.
- **Font di-bundle lokal** (Hanken Grotesk, Newsreader, Roboto Mono) — lihat
  gotcha khusus di bawah, ini yang paling berisiko/rumit di batch ini.

**Didiskusikan, TIDAK dikerjakan (sesuai keputusan user):**
- Hold-to-queue di mode "Tambah Belanjaan" — ditelusuri, disimpulkan TIDAK
  PERLU: cart provider mode ini sudah `family` keyed `tx.id` (bukan
  `kMainCartId`), non-autoDispose, jadi progres pegawai otomatis aman
  walau pindah tab tanpa fitur tahan tambahan.
- "Alihkan Owner" (transfer sesi role owner antar-device) & "pegawai
  lanjutkan pesanan yg sudah diproses owner" — masuk PLAN.md Item 27 & 28,
  belum didesain detail, implementasi ditunda.

## Gotcha BARU — bundling font lokal utk `google_fonts` (self-hosting)

**Paket `google_fonts` TIDAK memakai deklarasi `fonts:` Flutter biasa.**
Ia mencari file lewat `assets:` (AssetManifest) dgn pola nama PERSIS
`<FamilyInternal>-<NamaBerat>.ttf` (mis. `HankenGrotesk-SemiBold.ttf`,
tanpa spasi di nama keluarga — beda dari nama tampilan "Hanken Grotesk").
Kalau declare via `fonts:` pubspec seperti font custom biasa, TIDAK akan
kepakai — package tetap mencoba fetch runtime lalu exception kalau
`allowRuntimeFetching = false`. Solusi yang benar: taruh file di folder yg
didaftar `assets:` (project ini: `assets/fonts/`), biarkan `google_fonts`
menemukannya sendiri via `AssetManifest`.

File sumber yg didownload dari `google/fonts` (OFL) untuk 3 keluarga ini
cuma **variable font** (satu file per keluarga, axis `wght` 100-900), BUKAN
static per-berat seperti yg diharapkan `google_fonts`. Instans statis
per-berat di-generate pakai `fonttools varLib.instancer` (`pip install
fonttools`, instantiate tiap nilai `wght` jadi file terpisah) — 23 file
total (Hanken 9 berat 100-900, Newsreader 7 berat 200-800 sesuai axis
range aslinya, RobotoMono 7 berat 100-700).

**Widget test TIDAK BISA dipakai untuk verifikasi regresi bundling ini** —
`flutter test` SELALU jalankan `flutter_tester` dgn flag
`--disable-asset-fonts --use-test-fonts` (bukan opsional), jadi
render-based test lolos/gagal TIDAK MENCERMINKAN apakah asset font asli
benar2 resolve (dibuktikan manual: test tetap hijau walau file font
sengaja dihapus). Test yang benar & sudah dipasang
(`test/local_fonts_offline_test.dart`): cek keberadaan file di disk sesuai
konvensi nama persis, utk SEMUA kombinasi (keluarga, berat) yg benar2
dipakai app — bukan widget test.

**Build cache asset test bisa basi**: `build/unit_test_assets/
AssetManifest.json` di-cache dan TIDAK otomatis rebuild walau isi
`assets/fonts/` berubah (cuma rebuild kalau `pubspec.yaml` berubah) —
kalau nanti nambah/hapus file di folder assets tanpa ubah pubspec, hapus
`build/unit_test_assets/` manual sebelum test kalau curiga manifest basi.

## Gotcha lain (masih berlaku, dari sesi-sesi sebelumnya — ringkas, detail di CLAUDE.md §Gotcha)
- HID scanner menelan input keyboard kalau `useRootNavigator: true`.
- `TextDirection` bentrok material vs pdf — pakai `ui.TextDirection.ltr` eksplisit.
- Teks putih tak terbaca di PDF — bungkus `Material` di dalam `Theme(data: AppTheme.light())`.
- Font PDF/ESC-POS tidak dukung en-dash/non-ASCII.
- `formatRupiah` pakai non-breaking space (U+00A0) — `find.text('Rp 5.000')` literal TIDAK match di widget test.
- Drift `StreamProvider` widget test bisa hang 10 menit — WAJIB `drain()` di akhir test.
- `OutlinedButton`/`FilledButton` default lebar-penuh — 2+ dalam 1 `Row` WAJIB override `minimumSize`, ekstra parah di dalam `AlertDialog.content` (`IntrinsicWidth`).
- `Clipboard.getData()` TIDAK di-mock otomatis `flutter_test` — pasang mock manual atau test hang selamanya.

## Gerbang lisensi (Item 25c) — masih AKTIF, tidak disentuh sesi ini
`LicenseService.publicKeyBase64` sudah ditanam (bukan kosong) — device
manapun yang belum aktivasi diarahkan ke `/aktivasi`. Detail lengkap
keputusan & mekanisme ada di CHANGELOG (`0d1efe2`, `3591396`) — tidak
diulang di sini, tidak ada perubahan sesi ini.

## Lingkungan sesi ini
Flutter di `/opt/flutter`. `pip install fonttools` dipakai sekali utk
generate font statis (lihat gotcha di atas) — tidak perlu diinstall ulang
kecuali environment baru. Jalan sbg root menghasilkan warning "Woah!..."
yang tidak menggagalkan perintah, aman diabaikan.

## Menggantung / Kandidat Berikutnya
- **Redesign header struk (Item 7)** — tunggu user pilih opsi A/B/C dari
  Artifact mockup (lihat section paling atas).
- **PLAN.md Item 27** ("Alihkan Owner") & **Item 28** (pegawai lanjutkan
  pesanan lintas device) — baru sebatas konsep, belum didesain detail.
- Item lama yang masih terbuka: lihat PLAN.md (Item 23 sisa, Item 17+21
  sync, Item 3c/4/5 import data Griyo).

## Preferensi User (masih berlaku)
- Bahasa komunikasi & teks UI: Indonesia.
- Untuk fitur bervisual: usulkan opsi desain dulu (mockup/Artifact) sebelum implementasi.
- Untuk batch besar berisi item ambigu + jelas dicampur: minta opini dulu,
  lalu beri keputusan spesifik per-poin — item yg jelas dieksekusi
  langsung, item ambigu didiskusikan/plan dulu.
- Rencana yang didiskusikan tapi belum dieksekusi → masuk PLAN.md
  komprehensif, jangan cuma tersimpan di riwayat chat.
- Setiap regresi/bugfix WAJIB revert-verify (buktikan test gagal dulu
  sebelum fix, baru pasang lagi) — sudah konsisten dijalankan sesi ini.
