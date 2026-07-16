# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 16 Juli 2026. Sesi 15 Juli: batch 14 item bugfix/
redesign/fitur kasir & katalog (lihat ringkasan di bawah). Full `flutter
test` **375 test hijau**, `flutter analyze` bersih. schemaVersion masih 15
(tidak ada migrasi baru). Branch `claude/setup-dependencies-am31te` — belum
di-merge ke `main` (tunggu instruksi user). Sesi susulan 16 Juli: redesign
header struk (Item 7) FINAL disepakati lewat 3 putaran mockup — **desain
sudah disetujui user, dicatat lengkap di PLAN.md Item 29, siap
diimplementasi sesi berikutnya** (belum ada kode yang berubah, baru
spesifikasi tersimpan)._

## Redesign header struk (Item 7 lama / PLAN.md Item 29) — DESAIN DISETUJUI, siap diimplementasi

Lihat **PLAN.md Item 29** untuk spesifikasi lengkap (sudah final, hasil 3
putaran mockup + revisi). Ringkas: header status besar "Transaksi
Berhasil/Tempo" dihapus total, status Lunas/Tempo jadi **stempel** (kotak
bersudut tumpul, double border, tepi bertekstur kasar, teks tebal miring
-11°, hijau/merah) menempel di sudut KANAN-ATAS kartu item (simetris dgn
`ItemCountBadge` yg TIDAK diubah di kiri), nomor nota (`tx.localId`)
pindah jadi baris kedua DI DALAM stempel, "Tandai Semua" jadi lingkaran
solid hijau persis gaya `ItemCountBadge`.

**Catatan revisi terakhir user (belum diverifikasi implementasi)**: stempel
TIDAK BOLEH menutupi nama produk/nominal harga di baris item pertama —
butuh clearance vertikal yang aman, verifikasi visual (bukan cuma asumsi
angka posisi) sebelum dianggap selesai.

Source mockup (scratchpad sesi ini, TIDAK di-commit): `struk_header_
mockup_v3.html`/`.jpg` adalah versi FINAL yang disetujui — kalau file
scratchpad sudah hilang (beda sesi), lihat PLAN.md Item 29 sudah cukup
detail utk rebuild dari nol tanpa perlu lihat mockup lagi.

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
