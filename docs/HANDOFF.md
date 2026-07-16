# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 16 Juli 2026 (sesi lanjutan — fix poin loyalitas +
fix keamanan lisensi)._ Full `flutter test` **392 test hijau**,
`flutter analyze` bersih. schemaVersion masih 15
(tidak ada migrasi baru). Branch `claude/setup-dependencies-am31te` —
belum di-merge ke `main` (tunggu instruksi user). User sudah perbaiki
`license/revoked.json` di `main` secara manual (typo tanda kutip) —
item ini SELESAI, tidak perlu ditindaklanjuti lagi.

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

## Item pending — dilacak di task manager (BUKAN PLAN.md, sesuai instruksi user)

Instruksi eksplisit user: *"masukkan plan dulu (jangan ke plan.md), kita
eksekusi barengan dengan yang lain."* — kalau task-list sesi ini hilang
(beda sesi/environment), berikut rekonstruksinya dari riwayat chat:

1. **"Alihkan Owner" (transfer sesi role owner antar-device)** — desain
   sudah cukup matang (lihat rekap di bawah), belum ada baris kode.
   - QR dipakai sbg handshake saja (terlalu kecil utk transfer DB penuh),
     transfer sungguhan lewat LAN (pola serupa `lan_sync_service.dart`).
   - **Mekanisme transfer = full wipe & replace**, PAKAI ULANG
     `dumpAllTables()`/`restoreFromDump()` yang sudah ada (persis jalur
     `.berkahpos`), cuma lewat koneksi LAN langsung (bukan file manual).
     Ini keputusan FINAL — jangan bangun protokol merge/incremental baru
     khusus fitur ini.
   - **TIDAK PERLU logika demosi/kill-switch sama sekali** (sempat
     didiskusikan panjang, akhirnya disimpulkan tidak perlu) — device
     lama dibiarkan begitu saja setelah transfer (tetap menganggap
     dirinya `owner` di kepalanya sendiri, data lama beku per momen
     transfer), TIDAK disentuh/direset. Ini valid krn pola pakai
     nyata user: device yang "kalah" selalu berhenti dipakai transaksi
     setelah transfer (bukan dipakai paralel) — kalau nanti dipakai
     lagi, sudah jadi kebiasaan user utk hapus data/setup ulang dari
     nol, bukan sesuatu yang perlu ditangani kode. Arah transfer BEBAS
     bolak-balik (A→B lalu B→A dst), tiap kali selalu wipe&replace total
     ke arah tujuan transfer saat itu.
   - Watermark sync (`last_sync_download_at`, di tabel `app_settings`)
     ikut ke-wipe&restore tiap transfer krn `app_settings` termasuk
     `_allTables` — otomatis konsisten, tidak perlu penanganan khusus.
     Jalur sync biasa (kasir/asisten ↔ owner, `lan_sync_service.dart`)
     **sudah dikonfirmasi TIDAK tersentuh** oleh fitur ini — protokol
     terpisah sepenuhnya.
   - `storeUuid`+`storeKey` ikut di-embed DI DALAM dump/transfer itu
     sendiri (bukan re-entry manual) — supaya device penerima benar2
     "menjadi" store yang sama, tidak meng-orphan device kasir/asisten
     lain yang sync-nya bergantung pada `storeKey` yang cocok.
2. **Opsi "Pulihkan dari Backup .berkahpos" langsung di welcome screen**
   — saat ini restore backup cuma bisa lewat Pengaturan (setelah setup
   toko selesai) — usul user: tambah opsi ke-3 di `welcome_screen.dart`
   (selain "Setup Toko Baru"/"Gabung Toko") utk restore langsung dari
   file tanpa perlu bikin toko dummy dulu. Sekarang arsitekturnya makin
   dekat dgn item #1 di atas (sama-sama wipe&replace total + storeUuid/
   storeKey ikut, cuma beda jalur: LAN live vs file `.berkahpos`).

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
1. Cabut poin loyalitas saat customer diubah balik ke Umum (lihat detail di atas).
2. Keputusan siapa yang perbaiki JSON `license/revoked.json` di `main` (typo tanda kutip).
3. "Alihkan Owner" & "Pulihkan dari Backup" welcome screen — desain besar, lihat detail di atas, JANGAN masuk PLAN.md dulu sampai user instruksikan lain.
4. Item lama yang masih terbuka: lihat PLAN.md (Item 23 sisa, Item 17+21 sync, Item 3c/4/5 import data Griyo).

## Preferensi User (masih berlaku)
- Bahasa komunikasi & teks UI: Indonesia.
- Untuk fitur bervisual: usulkan opsi desain dulu (mockup/Artifact) sebelum implementasi.
- Untuk batch besar berisi item ambigu + jelas dicampur: minta opini dulu,
  lalu beri keputusan spesifik per-poin — item yg jelas dieksekusi
  langsung, item ambigu didiskusikan/plan dulu (task manager, bukan
  otomatis PLAN.md kalau user secara eksplisit minta ditahan).
- Setiap regresi/bugfix WAJIB revert-verify (buktikan test gagal dulu
  sebelum fix, baru pasang lagi) — sudah konsisten dijalankan sesi ini.
