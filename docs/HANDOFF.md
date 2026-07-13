# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 13 Juli 2026 (Item 24 SELESAI SEPENUHNYA — payment
gate role Pegawai lewat QR + antrian handoff + sheet verifikasi checklist)._

**schemaVersion tetap 14** (tidak ada migrasi baru sesi ini — seluruh Item 24
murni reuse `CartItem`, `CartMeta`, dan payload JSON blob `held_orders` yang
sudah ada, tanpa skema DB baru). Full `flutter test`: **264 test hijau**,
`flutter analyze` bersih.

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
   katalog HTML + baris `Pegawai: <nama>`). "Sudah Dikirim, Kosongkan
   Keranjang" HANYA mengosongkan cart lokal pegawai — TIDAK menulis
   `held_orders` di device pegawai (itu tugas device OWNER saat scan) —
   commit `1f18000`.
3. **Scan sisi owner**: `kasir_screen.dart` `_handleBarcode()` deteksi
   prefix `#PSN:` PALING AWAL (sebelum cabang `fromExternal`/
   `_continuousScan` — berlaku utk kamera MAUPUN scanner eksternal HID satu
   titik integrasi) → `_handleOrderCode()`. Ada baris `Pegawai:` →
   `db.holdOrder(...)` dengan payload `awaitingPayment: true`, TIDAK
   langsung ke keranjang aktif (supaya tidak bentrok transaksi owner yang
   sedang berjalan). Tanpa baris `Pegawai:` (pesanan pelanggan biasa dari
   katalog HTML) → alur LAMA tetap jalan, buka `PasteOrderSheet` pra-diisi
   & otomatis diproses — commit `1f18000`. Badge merah "Menunggu Anda
   Bayar" di `_HeldCard` utk order `awaitingPayment` (panel `SizedBox`
   dinaikkan ke height 128 dari 86 supaya badge muat tanpa overflow).
4. **24b — sheet "Verifikasi Pesanan"** (commit `b04e064`): tap kartu
   antrian `awaitingPayment` BUKA sheet checklist dulu (bukan langsung
   resume) — pegawai bacakan barang, owner centang tiap yang cocok, baru
   tombol "Lanjut ke Keranjang" masuk ke alur bayar seperti biasa
   (`_resumeHeld`). Pesanan ditahan BIASA (bukan handoff) tetap langsung
   resume tanpa sheet — checklist ini spesifik utk verifikasi handoff
   pegawai, bukan fitur hold umum.
   - **Scope sengaja disederhanakan setelah klarifikasi user**: murni
     **1 device (owner saja)** — pegawai TIDAK ikut mencentang sendiri di
     device-nya, tidak ada sinkronisasi lintas device sama sekali. Owner
     bacakan-dengar-centang adalah satu-satunya sumber data.
   - Centangan disimpan sbg array `checked` sejajar index `items` di
     `held_orders.cartJson` yang sudah ada (TANPA migrasi schema) — setiap
     tap checkbox langsung `db.updateHeldOrder(id, cartJson)` (method baru
     di `AppDatabase`), jadi tahan kalau owner sempat tertunda (app
     background dll), sama seperti pesanan ditahan lainnya.
   - **Checklist SELESAI tugasnya begitu "Lanjut ke Keranjang" ditekan** —
     TIDAK menempel ke `transaction_items`/`ReceiptScreen` sama sekali
     (`ReceiptScreen`'s `_checked` yang sudah ada, murni post-payment,
     TIDAK disentuh — tetap terpisah, tidak digabung).
   - Tombol "Lanjut ke Keranjang" TIDAK dikunci walau belum semua
     tercentang — checklist ini alat bantu visual, bukan gerbang wajib.
5. **Notifikasi realtime arah balik (owner→pegawai "transaksi lunas")
   SENGAJA TIDAK dibangun** — keputusan final, bukan item menggantung.
6. **Transport**: QR-lewat-scanner-kasir-yang-sudah-ada (opsi servis
   jaringan terpisah port 8626 sempat didesain lalu SENGAJA ditolak user
   demi kesederhanaan — histori di CHANGELOG sekitar commit
   `9f9cb18`/`5d65188` kalau perlu detail perbandingan opsi).

**Item 24 tidak ada sisa pekerjaan.** Kalau ada permintaan lanjutan (mis.
checklist post-payment ikut sinkron lintas device, atau notifikasi
balik) — itu scope BARU, bukan kelanjutan otomatis dari desain saat ini
(desain saat ini sudah eksplisit menolak keduanya demi kesederhanaan).

## Gotcha teknis baru sesi ini (selain yang sudah ada di CLAUDE.md)

- **Double `Navigator.pop()` sinkron back-to-back bisa bikin
  `pumpAndSettle()` macet selamanya** di widget test (animasi popping
  nested-lalu-parent sheet tidak pernah konvergen). Fix: cuma pop route
  TERDEKAT/terdalam, biarkan pemanggil/pengguna tutup route luar terpisah.
- **`await someDriftTable.watch().first` langsung di dalam body
  `testWidgets` bisa HANG selamanya**, walau cuma baca sekali (bukan
  `StreamProvider`) — perluasan dari gotcha "drift StreamProvider hang 10
  menit" yang sudah ada di CLAUDE.md. Fix: pakai query one-shot
  (`await db.select(db.tabelnya).get()`), JANGAN `.watch()...first`.
- **Cara diagnosis hang widget test yang terbukti jalan**: `timeout <N>
  flutter test ...` (bash) + `tester.pump(Duration(...))` bertahap +
  `tester.takeException()` (bukan `pumpAndSettle()` buta) untuk mempersempit
  await mana yang tidak pernah selesai.
- **Menambah sheet modal baru DI ATAS `KasirScreen` otomatis aman dari
  gangguan scanner HID eksternal** — TIDAK perlu penanganan khusus. Handler
  HID global (`_onHardwareKey`) berhenti intercept begitu
  `ModalRoute.of(context)?.isCurrent` jadi false (sheet baru jadi topmost),
  KECUALI kalau sengaja di-carve-out lewat flag `_cartSheetOpen` (dipakai
  HANYA oleh `CartSheet` demi continuous-scan). Sheet baru manapun (spt
  `_VerifyOrderSheet`) TIDAK boleh reuse flag itu — biarkan HID berhenti
  intercept seperti sheet lain (`PasteOrderSheet`, dialog, dll), aman
  karena sheet tanpa text field tidak butuh input scanner sama sekali.
- Nambah konten visual baru (badge dll) ke `Column` di dalam
  `SizedBox`-constrained horizontal `ListView` item bisa overflow kalau
  tinggi container tetap tidak dinaikkan — pola berulang, ketahuan dari
  widget test (bukan cuma visual).

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
- Rencana yang didiskusikan tapi belum dieksekusi → masuk PLAN.md
  komprehensif, jangan cuma tersimpan di riwayat chat.
- Perubahan sensitif/berisiko (mis. aspek security) — tunda eksekusi
  sampai instruksi eksplisit terpisah, walau desainnya sudah disetujui
  penuh (lihat 25c).
- Untuk perubahan kecil yang jelas (tidak ambigu) — user eksplisit minta
  langsung eksekusi + merge ke main tanpa menunggu konfirmasi tambahan
  (lihat pola Item 26), TAPI kalau ada keputusan desain yang genuinely
  ambigu (banyak interpretasi valid) — tetap ajukan dulu sebelum eksekusi,
  jangan diasumsikan sepihak.
