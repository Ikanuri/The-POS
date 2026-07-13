# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 13 Juli 2026 (Item 24 SELESAI SEPENUHNYA, plus 2
bugfix susulan: tap-to-scan mengulang barang lama, atribusi pelanggan/
pegawai tertukar di kartu antrian)._

**schemaVersion tetap 14** (tidak ada migrasi baru sesi ini — seluruh Item 24
+ bugfix susulan murni reuse `CartItem`, `CartMeta`, dan payload JSON blob
`held_orders` yang sudah ada, tanpa skema DB baru). Full `flutter test`:
**270 test hijau**, `flutter analyze` bersih.

## Item 24 (payment gate role Pegawai) — SELESAI SEPENUHNYA

Semua sub-item (24a–24f) selesai & di-commit. Ringkasan alur akhir:

1. **Rename kosmetik "Kasir"→"Pegawai"** di UI (`deviceRole` internal TETAP
   `'kasir'`, tidak disentuh) + permission baru `terima_pembayaran` (default
   OFF, self-heal via `beforeOpen`) — commit `4317c33`.
2. **Gerbang tombol "Bayar"**: pegawai (`deviceRole == 'kasir'`) TANPA izin
   `terima_pembayaran` melihat "Kirim ke Owner/Asisten" alih-alih "Bayar"
   (`cart_sheet.dart`, `_needsHandoffGateProvider` — dicek per cartId, mode
   Katalog `kCatalogCartId` TIDAK PERNAH digerbang). Tap membuka
   `_HandoffQrSheet`: QR (`qr_flutter`) berisi kode mesin
   `OrderParserService.encodeHandoff()` (format `#PSN:...` sama seperti
   katalog HTML + baris `Pegawai: <nama>` + `Nama: <pelanggan>` opsional).
   "Sudah Dikirim, Kosongkan Keranjang" HANYA mengosongkan cart lokal
   pegawai — TIDAK menulis `held_orders` di device pegawai (itu tugas
   device OWNER saat scan) — commit `1f18000`.
3. **Scan sisi owner**: `kasir_screen.dart` `_handleBarcode()` deteksi
   prefix `#PSN:` PALING AWAL (sebelum cabang `fromExternal`/
   `_continuousScan` — berlaku utk kamera MAUPUN scanner eksternal HID satu
   titik integrasi) → `_handleOrderCode()`. Ada baris `Pegawai:` →
   `db.holdOrder(...)` dengan payload `awaitingPayment: true` + `employeeName`
   TERPISAH dari `meta`/`label`, TIDAK langsung ke keranjang aktif (supaya
   tidak bentrok transaksi owner yang sedang berjalan). Tanpa baris
   `Pegawai:` (pesanan pelanggan biasa dari katalog HTML) → alur LAMA tetap
   jalan, buka `PasteOrderSheet` pra-diisi & otomatis diproses — commit
   `1f18000`, disempurnakan `c146695`.
   - **`label` kartu antrian = nama PELANGGAN** (`parsed.customerName`,
     fallback `'Tanpa Nama'`), **BUKAN nama pegawai** — nama pegawai
     pengirim + jam masuk tampil di **tab folder terpisah** di atas kartu
     (`_HeldCardWithTab`, pakai `_TabPainter` yang sama dgn tab pelanggan/
     pegawai di atas cart bar). Badge merah "Menunggu Anda Bayar" tetap di
     dalam kartu seperti sebelumnya. Panel `SizedBox` dinaikkan ke height
     152 (dari 128) supaya tab + badge muat tanpa overflow.
4. **24b — sheet "Verifikasi Pesanan"** (commit `b04e064`): tap kartu
   antrian `awaitingPayment` BUKA sheet checklist dulu (bukan langsung
   resume) — pegawai bacakan barang, owner centang tiap yang cocok, baru
   tombol "Lanjut ke Keranjang" masuk ke alur bayar seperti biasa
   (`_resumeHeld`). Pesanan ditahan BIASA (bukan handoff) tetap langsung
   resume tanpa sheet — checklist ini spesifik utk verifikasi handoff
   pegawai, bukan fitur hold umum.
   - **Scope sengaja disederhanakan setelah klarifikasi user**: murni
     **1 device (owner saja)** — pegawai TIDAK ikut mencentang sendiri di
     device-nya, tidak ada sinkronisasi lintas device sama sekali.
   - Centangan disimpan sbg array `checked` sejajar index `items` di
     `held_orders.cartJson` (TANPA migrasi schema) — setiap tap checkbox
     langsung `db.updateHeldOrder(id, cartJson)` (method baru di
     `AppDatabase`), **WAJIB tulis balik `meta`/`employeeName` ASLI dari
     payload** (bug pernah terjadi: `_toggle` sempat menulis balik
     `CartMeta()` kosong tiap centang, menghapus atribusi pelanggan/
     pegawai yang sudah kebawa QR — diperbaiki `c146695`).
   - **Checklist SELESAI tugasnya begitu "Lanjut ke Keranjang" ditekan** —
     TIDAK menempel ke `transaction_items`/`ReceiptScreen` sama sekali.
   - Tombol "Lanjut ke Keranjang" TIDAK dikunci walau belum semua
     tercentang — checklist ini alat bantu visual, bukan gerbang wajib.
5. **Notifikasi realtime arah balik (owner→pegawai "transaksi lunas")
   SENGAJA TIDAK dibangun** — keputusan final, bukan item menggantung.
6. **Transport**: QR-lewat-scanner-kasir-yang-sudah-ada (opsi servis
   jaringan terpisah port 8626 sempat didesain lalu SENGAJA ditolak user
   demi kesederhanaan).

**Item 24 tidak ada sisa pekerjaan** (2 bugfix susulan di atas sudah masuk).
Kalau ada permintaan lanjutan (mis. checklist post-payment ikut sinkron
lintas device, atau notifikasi balik) — itu scope BARU, bukan kelanjutan
otomatis dari desain saat ini.

## Bugfix susulan Item 24e (di luar Item 24, commit `c146695`)

**Tap-to-scan mengulang barang terakhir walau kamera tidak lihat apa-apa**:
`_pendingBarcode` (kasir_screen.dart) tidak pernah di-null-kan setelah
`_confirmPendingScan()` memprosesnya — tombol bidik tetap "enabled" (masih
menyimpan barcode LAMA), jadi tap lagi (kamera diarahkan ke mana pun, tanpa
barcode sama sekali) mengulang barang yang sama. Fix: `setState(() =>
_pendingBarcode = null)` segera setelah dipakai.

## Gotcha teknis baru sesi ini (selain yang sudah ada di CLAUDE.md)

- **Test regresi bisa "lolos palsu" gara-gara debounce internal, bukan
  karena fix beneran jalan** — kasus nyata: `_handleBarcode` punya
  debounce 1.5 detik per-barcode-yang-sama (`DateTime.now()`, REAL
  wall-clock, TIDAK ikut fast-forward `tester.pump(Duration(...))`). Test
  "tap shutter dua kali cepat lalu cek qty tetap 1" LOLOS baik dgn fix
  MAUPUN dgn bug sengaja dikembalikan (revert-verify gagal mendeteksi) —
  karena tap kedua di widget test terjadi hampir seketika (real time),
  jadi debounce SENDIRI sudah mencegah double-add, bukan fix-nya. Fix
  test: assert **state internal langsung lewat representasi UI**
  (`Icon.color` tombol bidik: abu-abu = `_pendingBarcode == null`) alih-
  alih re-trigger aksi yang punya side-channel independen (debounce) yang
  bisa menutupi bug. **Pelajaran umum**: kalau revert-verify tiba-tiba
  LOLOS (tidak gagal) padahal harusnya gagal, curigai ada mekanisme LAIN
  (debounce, cache, dsb) yang kebetulan menutupi efek bug — ganti
  pendekatan assertion ke sinyal yang lebih langsung.
- **`Column(mainAxisSize: MainAxisSize.min)` yang membungkus widget ber-
  `Spacer()` di dalam SLOT `ListView` horizontal (mis. utk nambah "tab" di
  atas kartu) bikin `Spacer()` itu CRASH** ("RenderFlex children have
  non-zero flex but incoming height constraints are unbounded") — item
  ListView horizontal dapat height TIGHT dari `SizedBox` pembungkus, tapi
  `Column` mainAxisSize.min memberi height UNBOUNDED ke children non-flex-
  nya sendiri, jadi widget anak yang px-nya bergantung pada height induk
  (`Spacer`) kehilangan constraint itu. Fix: bungkus widget-yang-punya-
  `Spacer()` dengan `Expanded` (BUKAN taruh langsung), dan JANGAN pakai
  `mainAxisSize: MainAxisSize.min` di Column pembungkusnya (biar `Expanded`
  benar-benar dapat sisa ruang, bukan collapse ke 0) — lihat
  `_HeldCardWithTab` (kasir_screen.dart).
- Double `Navigator.pop()` sinkron back-to-back bisa bikin `pumpAndSettle()`
  macet selamanya di widget test — cuma pop route TERDEKAT/terdalam.
- `await someDriftTable.watch().first` langsung di `testWidgets` bisa HANG
  selamanya (perluasan gotcha drift StreamProvider di CLAUDE.md) — pakai
  query one-shot (`db.select(db.tabelnya).get()`).
- Diagnosis hang widget test: `timeout <N> flutter test ...` + `tester.pump
  (Duration(...))` bertahap + `tester.takeException()`, bukan
  `pumpAndSettle()` buta.
- Sheet modal baru di atas `KasirScreen` otomatis aman dari HID scanner
  eksternal (`_onHardwareKey` berhenti intercept begitu bukan topmost route)
  — JANGAN reuse flag `_cartSheetOpen` (khusus `CartSheet` demi
  continuous-scan) di sheet baru manapun.
- Nambah konten visual baru (badge/tab dll) ke kartu horizontal-ListView
  butuh cek ulang `SizedBox` height pembungkusnya — pola overflow berulang,
  ketahuan dari widget test.

## Lingkungan sesi ini
Flutter TIDAK terpasang default — dipasang manual ke `/tmp/flutter`
(versi 3.24.5 stable, samakan CI `build-apk.yml`). `/opt/flutter` yang
disebut CLAUDE.md TIDAK ADA di environment ini — selalu `which flutter`
dulu kalau command CLAUDE.md gagal. Jalankan sebagai non-root
menghasilkan warning "Woah!... trying to run as root" yang TIDAK
menggagalkan perintah (aman diabaikan).

## Menggantung / Kandidat Berikutnya
- **Item 21+17** (sync UI persisten lintas tab + persist antrian approval)
  — masih sengaja ditunda dari sesi-sesi sebelumnya, TIDAK prasyarat utk
  item apa pun yang sudah selesai (Item 24 tidak bergantung sync/LAN).
- **Item 23** (scope bug "Sisa Tagihan" understated di lokasi lain: Buku
  Hutang, Tutup Kasir, printer_service.dart, transaksi_tab.dart,
  tx_history_sheet.dart, merged_receipt_screen.dart) — lihat PLAN.md untuk
  daftar lengkap lokasi yang sengaja belum disentuh.
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
  tengah diskusi** (lihat Item 24b: dari desain lintas-device rumit jadi
  murni 1-device setelah user jelaskan flow ril-nya, dan pertanyaan
  "apakah ini ganggu scanner eksternal?" sebelum eksekusi) — jangan buru-
  buru eksekusi desain awal kalau user masih mengajukan pertanyaan
  klarifikasi, itu biasanya sinyal scope akan menyempit/berubah.
- **User melaporkan bug dgn observasi presisi** (mis. "tap lagi dgn kamera
  diarahkan ke manapun, bahkan tanpa barcode" — detail yang langsung
  mengarah ke akar masalah `_pendingBarcode` tak dikosongkan) — baca
  laporan bug user kata per kata, biasanya sudah menunjuk lokasi/skenario
  presisi, jangan disederhanakan saat reproduksi.
- Rencana yang didiskusikan tapi belum dieksekusi → masuk PLAN.md
  komprehensif, jangan cuma tersimpan di riwayat chat.
- Perubahan sensitif/berisiko (mis. aspek security) — tunda eksekusi
  sampai instruksi eksplisit terpisah, walau desainnya sudah disetujui
  penuh (lihat 25c).
- Untuk perubahan kecil yang jelas (tidak ambigu) — user eksplisit minta
  langsung eksekusi + merge ke main tanpa menunggu konfirmasi tambahan
  (lihat pola Item 26 & bugfix `c146695`), TAPI kalau ada keputusan desain
  yang genuinely ambigu (banyak interpretasi valid) — tetap ajukan dulu
  sebelum eksekusi, jangan diasumsikan sepihak.
