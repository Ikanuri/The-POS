# Style UI/UX Referensi — "Gaya Landing" (v3.3.x)

Acuan WAJIB untuk setiap layar/komponen baru maupun redesain. Diturunkan dari
landing Kasir gaya Baru (`kasir_modern.dart`) yang sudah disetujui user
(9 Okt 2026), ditambah toast `AppToast`. Sumber token: `AppTheme`
(`lib/core/theme/app_theme.dart`) dan `AppStyle` (`lib/core/theme/app_style.dart`).
Dokumen lain: `DESAIN-REFERENSI-HTML.md` (asal gaya), `DESAIN-REFERENSI-TELEGRAM.md` (gerak).

## 1. Prinsip
1. **Hangat & lembut**: kanvas krem (`#EBE8E0` / gelap `#161412`), kartu putih
   (`#FFFFFF` / `#2A2623`), aksen terracotta `#C96442`. Tidak ada biru/abu dingin.
2. **Membulat**: pil (999) untuk kolom cari, chip, tombol; kartu 18; panel/dialog 22;
   sheet atas 30; lingkaran untuk tombol ikon. Radius kecil (<12) hanya untuk elemen
   di dalam kartu (thumbnail, indikator).
3. **Kartu melayang, bukan garis**: pemisah utama = kartu berbayangan hangat +
   garis tipis 1px `line`; hindari `Divider` tebal & kotak berborder keras.
4. **Satu fokus per layar**: judul serif/tegas, satu aksi utama (aksen), aksi lain
   netral/outline. Angka & nominal SELALU `AppTheme.numStyle` (Newsreader) — ukuran terkendali: hero maks 30/w600, judul layar 21/w600, nominal kartu 14.5–15.5/w600; JANGAN w700 + ukuran >30 (terasa berlebihan).
5. **Warna fungsi** (`AppTheme.*Fg/Bg`): scan biru, antrian emas, riwayat ungu, tempel
   hijau-zaitun, hutang merah, kembalian hijau, laci rose, pinjaman indigo, pre-order teal.
   Lingkaran ikon/ chip berwarna = `Bg` + ikon `Fg`.
6. **Gerak tenang** (`AppMotion`): 120/200/260/300 ms; masuk `easeOutQuint`, keluar
   `easeIn`; `easeOutBack` hanya utk yang BARU muncul. Hormati `reduced`. Tekan = `PressScale`.
7. **Performa dulu**: jangan `LayoutBuilder`/`MediaQuery.of` luas di layar yang
   menerima keyboard; bayangan blur besar hanya pada elemen melayang.

## 2. Token
| Token | Nilai |
|---|---|
| Radius | pil 999 · kartu 18 · panel/dialog 22 · sheet 30 · field form 14 · tombol 999 |
| Bayangan kartu | `0 6 22 rgba(90,60,30,.22)`-an halus (terang `0x155A3C1E`, gelap `0x40000000`) |
| Bayangan melayang (cart bar, toast) | `0 6 24 rgba(90,60,30,.12–.22)` |
| Bayangan aksen | `0 4 12 rgba(201,100,66,.35)` (tombol/logo aksen) |
| Garis | `line` 1px (`#E7E2D7` / `#383330`) |
| Jarak | 4 · 8 · 12 · 14 (gutter layar) · 16 · 24; ruang bawah daftar ≥ 24 |
| Teks | judul layar 20/700 · judul seksi 15/700 · isi 13.5–15 · keterangan 11.5–12.5 `ink2` |
| Tinggi minimum tap | 44–48dp (tombol penuh 48) |

## 3. Komponen baku
- **Layar**: latar kanvas; AppBar menyatu dengan kanvas (tanpa elevasi), judul 20/700.
- **Kartu**: `Card` tema (radius 18, bayangan hangat, garis tipis). Isi berjarak 14.
- **Tombol**: utama `FilledButton` pil aksen; sekunder `OutlinedButton` pil; teks `TextButton`.
  Dua+ tombol sebaris → override `minimumSize` sempit (lihat CLAUDE.md).
- **Kolom isian**: `InputDecoration` tema (field `#F1EEE7`, radius 14, fokus aksen 1.5).
- **Chip**: pil, terpilih = `primaryContainer`.
- **Dialog**: radius 22, latar kartu, judul 17/700; tombol pil; konfirmasi ringan → inline (Ya/Tidak).
- **Bottom sheet**: sudut atas 30, handle, latar panel; buka via `showAppSheet`.
- **Toast/notif**: `AppToast` / `showAppSnackBar` (kartu putih melayang di ATAS layar, ikon bulat
  beraksen, di atas stiker & dialog). JANGAN pakai `SnackBar` mentah. Banner inline: `InlineBanner`/`AppNoticeCard`.
- **Daftar**: `ListTile` radius 14; baris dalam kartu; lencana/pil untuk status.
- **Status kosong**: stiker (`AppSticker`) + satu kalimat + satu aksi.
- **Switch/Segmented**: aksen terracotta, bentuk pil.

- **Bilah tab bawah**: `AppNavBar` (core/widgets/app_nav_bar.dart) — pil MELAYANG ala Telegram
  (tinggi 60, margin 12/8, maks 440dp, bayangan melayang), indikator terpilih meluncur 260 ms
  easeOutQuint, ikon + label 10.5, lencana. Ikon = `AppIcon` (core/widgets/app_icons.dart):
  garis bulat 1.8 pada kisi 24, terpilih = duotone aksen. JANGAN pakai `Icons.*` untuk tab utama.
- **Layar ringkasan/dasbor**: sapaan kecil + nama toko serif di header; satu kartu hero
  bergradien terracotta untuk angka utama; kartu putih lain berisi ikon bulat warna fungsi;
  masuk berurutan (`_Reveal`, fade+naik 10dp, jeda 60ms); chip status berbentuk pil.

## 4. Aturan implementasi
- Ambil warna dari `Theme.of(context).colorScheme` / `AppTheme.*`; JANGAN hardcode warna baru
  kecuali token di atas.
- Radius & bayangan dari `AppStyle` (bukan angka liar).
- Teks UI Indonesia; nominal `formatRupiah`; tanggal manual (tanpa `DateFormat` ber-locale).
- Uji layar baru di lebar 360 dan skala font 1.3 tanpa overflow; tutup test dengan `drain()`.
