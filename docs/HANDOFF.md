# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 13 Juli 2026 (lanjutan sesi Item 24 — inti mekanisme QR
payment gate role Pegawai selesai diimplementasi & di-commit)._

**schemaVersion tetap 14** (tidak ada migrasi baru sesi ini — mekanisme QR
murni reuse `CartItem.itemNote`, `CartMeta`, dan payload JSON blob
`held_orders` yang sudah ada, tanpa skema DB baru). Full `flutter test`:
**260 test hijau**, `flutter analyze` bersih.

## Status Item 24 (payment gate role Pegawai) — HAMPIR SELESAI, sisa 24b

- **SELESAI & di-commit** (`4317c33`): rename kosmetik "Kasir"→"Pegawai" di
  UI + permission `terima_pembayaran` (default OFF, self-heal `beforeOpen`).
- **SELESAI & di-commit** (`1f18000`) — inti mekanisme "kirim ke
  Owner/Asisten":
  - `CartSheet`: pegawai (`deviceRole == 'kasir'`) TANPA izin
    `terima_pembayaran` melihat tombol "Kirim ke Owner/Asisten" alih-alih
    "Bayar" (gate via `_needsHandoffGateProvider`, dicek per cartId — mode
    Katalog `kCatalogCartId` TIDAK PERNAH digerbang). Tap membuka
    `_HandoffQrSheet` yang menampilkan QR (`qr_flutter`) berisi kode mesin
    `OrderParserService.encodeHandoff()` — format sama seperti `#PSN:...`
    katalog HTML, ditambah baris `Pegawai: <nama>`. "Sudah Dikirim,
    Kosongkan Keranjang" HANYA mengosongkan cart lokal pegawai — **TIDAK**
    menulis `held_orders` di device pegawai (itu tugas device OWNER saat
    scan).
  - `kasir_screen.dart`: `_handleBarcode()` deteksi prefix `#PSN:` di
    PALING AWAL (sebelum cabang `fromExternal`/`_continuousScan`) →
    `_handleOrderCode()`. Kalau ada baris `Pegawai:` → langsung
    `db.holdOrder(...)` dengan payload `awaitingPayment: true`, banner
    sukses, scanner ditutup — TIDAK masuk keranjang aktif (supaya tidak
    bentrok transaksi owner yang sedang berjalan). Kalau TIDAK ada baris
    `Pegawai:` (pesanan pelanggan biasa dari katalog HTML) → alur LAMA
    tetap jalan, buka `PasteOrderSheet` pra-diisi (`initialText`) &
    otomatis diproses. Berlaku untuk kamera MAUPUN scanner eksternal HID
    (satu titik integrasi yang sama).
  - `_HeldCard`/`_HeldInlinePanel`: badge merah "Menunggu Anda Bayar" utk
    held_order dengan `awaitingPayment: true`, beda dari pesanan ditahan
    biasa. `SizedBox` panel dinaikkan ke height 128 (dari 86) supaya badge
    muat tanpa overflow.
  - Transport: QR-lewat-scanner-kasir (bukan servis jaringan) — opsi
    servis jaringan terpisah (port 8626) sempat didesain lalu SENGAJA
    ditolak user demi kesederhanaan (baca histori di CHANGELOG sekitar
    commit `9f9cb18`/`5d65188` kalau perlu detail perbandingannya).
  - Sengaja TANPA notifikasi otomatis arah balik (owner→pegawai "transaksi
    lunas") — keputusan sadar, bukan lupa.
- **BELUM dikerjakan — 24b (checklist struk tersinkron): BUTUH KLARIFIKASI
  USER sebelum mulai coding.** Ditemukan ambiguitas desain saat mau mulai
  implementasi: checklist item struk yang SUDAH ADA (`ReceiptScreen`,
  `_checked`) itu mekanismenya POST-payment — butuh `transactionId` sungguhan
  yang baru ada SETELAH transaksi selesai dibayar & disimpan. Padahal asumsi
  awal 24b ("pegawai susun+centang sebelum kirim") itu PRE-payment (belum ada
  transactionId sama sekali, cuma held_order/QR). Dua interpretasi yang perlu
  dipilih user:
  (a) checklist BARU di sisi pre-payment (cart/handoff pegawai, sebelum QR
      dikirim) — butuh UI baru + field baru di payload `held_orders`/QR; atau
  (b) reuse checklist `ReceiptScreen` yang SUDAH ADA, tapi itu artinya
      post-payment saja (transaksi sudah lunas) — butuh transport BARU
      (beda dari held_orders/QR pre-payment) untuk kasus completed-transaction.
  **JANGAN diasumsikan sepihak — tanyakan ke user dulu** sebelum coding 24b.

## Gotcha teknis baru sesi ini (selain yang sudah ada di CLAUDE.md)

- **Double `Navigator.pop()` sinkron back-to-back bisa bikin
  `pumpAndSettle()` macet selamanya** di widget test (animasi popping
  nested-lalu-parent sheet tidak pernah konvergen) — walau pola yang sama
  mungkin baik-baik saja di produksi. Fix: cuma pop route TERDEKAT/terdalam,
  biarkan pemanggil/pengguna tutup route luar secara terpisah.
- **`await someDriftTable.watch().first` langsung di dalam body
  `testWidgets` bisa HANG selamanya**, walau cuma baca sekali (bukan
  `StreamProvider`) — perluasan dari gotcha "drift StreamProvider hang 10
  menit" yang sudah ada di CLAUDE.md, tapi ternyata trigger juga dari
  `.first` polos tanpa provider sama sekali. Fix: pakai query one-shot
  (`await db.select(db.tabelnya).get()`), JANGAN `.watch()...first`, di
  dalam widget test.
- **Cara diagnosis hang widget test yang terbukti jalan**: `timeout <N>
  flutter test ...` (bash) + `tester.pump(Duration(...))` bertahap +
  `tester.takeException()` (bukan `pumpAndSettle()` buta) untuk mempersempit
  await mana yang tidak pernah selesai.
- **Nambah konten visual baru (badge dll) ke `Column` di dalam
  `SizedBox`-constrained horizontal `ListView` item bisa overflow** kalau
  tinggi container tetap tidak dinaikkan — pola berulang di codebase ini,
  ketahuan dari widget test (bukan cuma visual).
- (Gotcha `ButtonStyle.minimumSize`/`Row` dari sesi sebelumnya — sudah
  masuk histori, tidak diulang di sini.)

## Lingkungan sesi ini
Flutter TIDAK terpasang default — dipasang manual ke `/tmp/flutter`
(versi 3.24.5 stable, samakan CI `build-apk.yml`). `/opt/flutter` yang
disebut CLAUDE.md TIDAK ADA di environment ini — selalu `which flutter`
dulu kalau command CLAUDE.md gagal. Jalankan sebagai non-root
menghasilkan warning "Woah!... trying to run as root" yang TIDAK
menggagalkan perintah (aman diabaikan).

## Menggantung / Kandidat Berikutnya
- **Item 24b** (checklist struk tersinkron) — BUTUH JAWABAN USER dulu (lihat
  di atas), baru bisa dieksekusi. Ini satu-satunya sisa Item 24.
- **Item 21+17** (sync UI persisten lintas tab + persist antrian approval)
  — masih sengaja ditunda dari sesi-sesi sebelumnya, TIDAK lagi prasyarat
  untuk Item 24 (mekanisme QR yang dipilih tidak bergantung sync/LAN).
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
  setelah instruksi eksplisit ("eksekusi semua"/konfirmasi serupa).
- Rencana yang didiskusikan tapi belum dieksekusi → masuk PLAN.md
  komprehensif, jangan cuma tersimpan di riwayat chat.
- Perubahan sensitif/berisiko (mis. aspek security) — tunda eksekusi
  sampai instruksi eksplisit terpisah, walau desainnya sudah disetujui
  penuh (lihat 25c).
- Untuk perubahan kecil yang jelas (tidak ambigu) — user eksplisit minta
  langsung eksekusi + merge ke main tanpa menunggu konfirmasi tambahan
  (lihat pola Item 26), TAPI kalau ada keputusan desain yang genuinely
  ambigu (banyak interpretasi valid, seperti 24b sekarang) — tetap ajukan
  dulu sebelum eksekusi, jangan diasumsikan sepihak.
