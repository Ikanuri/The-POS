# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 2 Juli 2026._

---

## Di Mana Kita Sekarang

Sesi **deep debug + stress test**. `flutter analyze` bersih, semua di-push.

**Hasil stress test (paling penting):**
- **Aritmatika AMAN untuk skala waktu tak realistis.** Uang `int64` overflow di
  ~1 miliar tahun (toko ramai); presisi Rp-satuan (2^53) di ~987 ribu tahun.
  Stok `double` running-balance: drift 0 untuk pecahan terminating (0.25 kg);
  ~0.02 gram setelah 1 juta penjualan 0.1. **Bukan faktor pembatas.**
- **Faktor pembatas = PERFORMA, bukan korektnes.** Ditemukan cacat serius:
  tidak ada indeks pada `transaction_payments(transaction_id)` → anti-join
  `backfillMissingPayments` (jalan TIAP startup) O(n²). Terukur 90k tx = 156
  detik. **Diperbaiki di `61c7455`** (indeks + schema v7): 90k=28ms,
  1,1jt=368ms. Ini yang menentukan "berapa lama data stabil".
- **Jawaban durability:** dengan fix v7 + tutup buku tahunan, praktis stabil
  tanpa batas. Tanpa tutup buku, startup melambat linear (~O(total tx)) dari
  dua backfill-scan; nyaman s/d ~1-2 juta transaksi (~beberapa tahun toko
  ramai), lalu startup mulai terasa (ratusan ms).

Sebelumnya (commit `16ad934`) 10 kelompok bug fungsional diperbaiki:

- **Tutup buku** tak lagi me-reset stok produk yang seluruh riwayat ledger-nya
  ada di tahun terarsip (saldo dibawa via entri `adjustment` baru).
- **Backup/restore/export** kini menyertakan tabel `employees` (sebelumnya
  hilang saat restore).
- **Sync LAN**: rekonsiliasi header memakai id transaksi dari item & pembayaran
  juga (cicilan/item susulan nota lama kini terkoreksi di perangkat penerima);
  `dumpSince` menyertakan item susulan via `added_at`; rename `local_id`
  tabrakan mencari suffix bebas.
- **Struk in-app & share**: `transaction_items` selalu berisi qty EFEKTIF —
  jangan pernah mengurangi qty varian lagi saat menampilkan (double-subtract
  membuat induk+varian tampil kosong). Printer sudah benar sejak awal.
- **QRIS** di layar bayar kini dirender `QrImageView` (dulu teks mentah).
- **Chart harian/per-jam** di-clamp — omzet negatif (hari didominasi retur)
  sempat bisa membuat tinggi bar negatif → crash render.
- Konversi stok rasio satuan < 1 dibetulkan; retur void tak dihitung
  `getReturnedQtyByUnit`; draft katalog tak ikut tersapu pembersihan keranjang
  24 jam; hapus induk dari modal entri ikut membersihkan varian yatim; total
  kartu pesanan ditahan pakai `cartTotalOf` (helper baru di cart_provider).

## Kandidat Optimasi Durability Berikutnya (belum dikerjakan)
- **Backfill tiap startup masih O(n) full-scan.** `backfillMissingSummaries`
  (DISTINCT-date scan: 42ms@90k, 180ms@365k) & `backfillMissingPayments`
  (kini pakai indeks, tapi tetap men-scan semua tx paid). Idealnya pakai
  watermark ('last_backfill_ts') agar hanya memproses data baru. Belum
  mendesak karena tutup buku mereset ukuran; indeks sudah menutup O(n²).
- `getReturnedQtyByUnit` scan `transactions.internal_note` tanpa indeks —
  jarang (hanya saat buka sheet retur), prioritas rendah.

## Temuan yang SENGAJA Belum Diperbaiki (kandidat diskusi)

- **Multi-satuan + varian bercampur**: invariant `storedQty induk = base +
  Σvarian` ambigu bila satu produk punya ≥2 baris satuan non-varian di
  keranjang (varian "menempel" ke produk, bukan ke baris). Efek: qty efektif
  bisa salah hitung pada kombinasi langka ini. Perbaikan butuh refactor
  atribusi varian per-baris — jangan disentuh tanpa keputusan user.
- Tombol minus di kartu produk (`_decrementProduct`) selalu mengurangi baris
  satuan PERTAMA bila produk ada di keranjang dengan >1 satuan.
- Retur atas nota tempo/kurang-bayar mencatat refund tunai penuh tanpa
  mengurangi hutang nota asal (secara akuntansi konsisten, tapi alurnya
  mungkin tak sesuai harapan kasir — keputusan bisnis).
- Sync saat ini selalu full-dump (`since` = epoch, satu-satunya caller di
  sync_screen tidak mengirim `since`) — filter incremental di `dumpSince`
  sudah dibetulkan dan siap bila kelak dibuat incremental.

## Keputusan Penting yang Masih Berlaku
- Cart meta tab = shrink-wrap kiri, **bukan** full-width.
- Animasi scan yang dipilih = **Opsi E** (garis pulse hijau), dari 8 opsi.
- Referensi proyek tinggal di `docs/reference/` (jangan hapus).
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.

## Menggantung / Kandidat Berikutnya
- Tidak ada tugas terbuka selain daftar "temuan belum diperbaiki" di atas.
- Proposal "Barokah Order" masih menunggu keputusan user
  (`docs/PROPOSAL_PERTIMBANGAN_BAROKAH_ORDER.md`).

## Preferensi User
- Untuk fitur bervisual (mis. animasi), **usulkan beberapa opsi desain dulu**
  sebelum implementasi.
- Bahasa komunikasi & teks UI: Indonesia.
- Hati-hati agar perubahan tidak merusak logika/alur aplikasi yang sudah ada.
