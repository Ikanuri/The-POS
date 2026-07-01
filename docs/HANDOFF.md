# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 1 Juli 2026._

---

## Di Mana Kita Sekarang

Baru menyelesaikan batch "polish" 5-item + animasi scanner, lalu merapikan
dokumentasi proyek. Kondisi: `flutter analyze` bersih, semua sudah di-commit &
push, working tree bersih.

### Selesai di sesi terakhir
- **PDF laporan:** teks legenda donut tak lagi putih (Material dibungkus di dalam
  `Theme(AppTheme.light())`); separator tanggal en-dash `–` → `-`/`s/d`.
- **Cart meta tab:** kembali _shrink-wrap_ (`mainAxisSize.min`), tombol Tahan tepat
  setelah chip Pegawai, dibungkus `Align(centerLeft)` di call-site. (Pendekatan
  `Spacer`/full-width sebelumnya **salah** menurut user — jangan diulang.)
- **Cart bar:** tombol "Lihat" & "Bayar" dihapus → buka keranjang via **swipe-up**
  (`GestureDetector.onVerticalDragEnd`). Ada hint sementara "Geser ke atas…" yang
  hilang permanen setelah dipakai 3× (disimpan di SharedPreferences).
- **Animasi scan (Opsi E):** garis pemindai menebal (2→6px) + hijau saat scan
  berhasil di mode berulang, via `ScanPulseController` (ChangeNotifier).
- **Arsip referensi:** file patokan proyek disalin ke `docs/reference/`
  (Mockup.zip, Contoh_Dataset.rar, Products.csv, products_import.csv,
  BLUEPRINT_v1.md) agar bertahan lintas sesi.
- **Dokumentasi:** dibuat `CLAUDE.md`, `CHANGELOG.md`, `PATCHNOTES.md`, file ini.

## Keputusan Penting yang Masih Berlaku
- Cart meta tab = shrink-wrap kiri, **bukan** full-width.
- Animasi scan yang dipilih = **Opsi E** (garis pulse hijau), dari 8 opsi.
- Referensi proyek tinggal di `docs/reference/` (jangan hapus).
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.

## Menggantung / Kandidat Berikutnya
- Belum ada tugas terbuka. (Proposal "Barokah Order" — sistem order pelanggan —
  masih berupa dokumen di `docs/PROPOSAL_PERTIMBANGAN_BAROKAH_ORDER.md`, belum
  diimplementasikan; tunggu keputusan user.)

## Preferensi User
- Untuk fitur bervisual (mis. animasi), **usulkan beberapa opsi desain dulu**
  sebelum implementasi.
- Bahasa komunikasi & teks UI: Indonesia.
- Hati-hati agar perubahan tidak merusak logika/alur aplikasi yang sudah ada.
